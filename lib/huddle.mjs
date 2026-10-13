import {AccessToken,RoomServiceClient,TrackSource,DataPacket_Kind} from 'livekit-server-sdk';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers={'Cache-Control':'no-store','Content-Type':'application/json','X-Content-Type-Options':'nosniff'};
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
class HuddleError extends Error{constructor(message,status=400,setupRequired=false){super(message);this.status=status;this.setupRequired=setupRequired;}}
const setupError=()=>new HuddleError('Huddle database update is required. Run huddle-update.sql in Supabase SQL Editor, then refresh Sessions.',503,true);
export function createHuddleHandler({env=process.env,fetcher=fetch,Token=AccessToken,Rooms=RoomServiceClient,logger=console}={}){
 const config=()=>({supabase:env.SUPABASE_URL||env.NEXT_PUBLIC_SUPABASE_URL,key:env.SUPABASE_PUBLISHABLE_KEY||env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,url:env.LIVEKIT_URL,apiKey:env.LIVEKIT_API_KEY,secret:env.LIVEKIT_API_SECRET});
 const missing=c=>[['SUPABASE_URL',c.supabase],['SUPABASE_PUBLISHABLE_KEY',c.key],['LIVEKIT_URL',c.url],['LIVEKIT_API_KEY',c.apiKey],['LIVEKIT_API_SECRET',c.secret]].filter(([,value])=>!value).map(([name])=>name);
 async function call(c,bearer,path,body){
  const response=await fetcher(c.supabase+path,{method:body===undefined?'GET':'POST',headers:{apikey:c.key,Authorization:'Bearer '+bearer,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
  const data=await response.json().catch(()=>({}));
  if(!response.ok){if(['PGRST202','PGRST203','PGRST205','42883','42703'].includes(data.code)||data.message==='Your position cannot host this operating unit.')throw setupError();throw new HuddleError(data.message||'Huddle access denied.',response.status===401||data.code==='42501'?403:400);}
  return data;
 }
 return async function handle(request){
  const c=config();
  if(request.method==='GET')return reply({configured:missing(c).length===0,missing:missing(c)});
  if(request.method!=='POST')return reply({error:'Use POST for Huddle actions.'},405);
  try{
   const origin=request.headers.get('origin');if(origin&&origin!==new URL(request.url).origin)throw new HuddleError('This origin is not allowed.',403);
   const bearer=request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]+)$/)?.[1];if(!bearer)throw new HuddleError('Sign in to OCCCI before joining Huddle.',401);
   if(!c.supabase||!c.key)throw new HuddleError('Huddle server authentication setup is pending.',503);
   const user=await call(c,bearer,'/auth/v1/user');if(!UUID.test(user.id||''))throw new HuddleError('Sign in to OCCCI before joining Huddle.',401);
   if(!request.headers.get('content-type')?.startsWith('application/json'))throw new HuddleError('Send a JSON request.',415);
   const text=await request.text();if(text.length>12000)throw new HuddleError('The request is too large.',413);
   let body;try{body=JSON.parse(text);}catch{throw new HuddleError('Invalid request.',400);}if(!body||Array.isArray(body)||typeof body!=='object')throw new HuddleError('Invalid request.');
   const rpc=(name,args={})=>call(c,bearer,'/rest/v1/rpc/occci_huddle_'+name,args);
   async function permissions(){const result=await rpc('permissions');if(result.database_ready!==true)throw setupError();return result;}
   if(body.action==='list')return reply({permissions:await permissions(),sessions:await rpc('list')});
   if(body.action==='create'){
    if(typeof body.title!=='string'||!body.title.trim()||body.title.length>150)throw new HuddleError('Enter a session title.');
    if((await permissions()).can_host!==true)throw new HuddleError('Only approved OCCCI staff (Admin, DM, BM, BS or BC) can create a session.',403);
    return reply({session:await rpc('create',{label:body.title.trim()})});
   }
   if(body.action==='leave'){if(!UUID.test(body.sessionId||''))throw new HuddleError('Choose a valid Huddle.');await rpc('command',{sid:body.sessionId,command:'leave',target:null});return reply({ok:true});}
   const roomName=sid=>'occci-huddle-'+sid;
   async function context(sid){return rpc('context',{sid});}
   if(body.action==='end'){
    if(!UUID.test(body.sessionId||''))throw new HuddleError('Choose a valid Huddle.');
    const ctx=await context(body.sessionId);if(!ctx.is_host)throw new HuddleError('Only this Huddle host can manage attendees.',403);
    await rpc('command',{sid:body.sessionId,command:'end',target:null});
    let mediaCleanupPending=false;
    if(!missing(c).length)try{await new Rooms(c.url.replace(/^wss:/,'https:'),c.apiKey,c.secret).deleteRoom(roomName(body.sessionId));}catch(error){mediaCleanupPending=true;logger.error('OCCCI Huddle media cleanup pending',{type:error.name});}
    return reply({ok:true,mediaCleanupPending});
   }
   const unit={branch:typeof body.branch==='string'&&body.branch?body.branch:null,dist:body.district==null||body.district===''?null:Number(body.district)};
   if(unit.branch&&unit.branch.length>100||unit.dist!==null&&(!Number.isInteger(unit.dist)||unit.dist<1||unit.dist>6))throw new HuddleError('Choose a valid operating unit.');
   if(missing(c).length)throw new HuddleError('OCCCI Huddle is awaiting its LiveKit connection. Configure the server credentials in Vercel.',503);
   if(!/^wss:\/\//.test(c.url)&&!/^https:\/\//.test(c.url))throw new HuddleError('LiveKit must use a secure connection URL.',503);
   const service=new Rooms(c.url.replace(/^wss:/,'https:'),c.apiKey,c.secret);
   async function reconcile(ctx){
    const live=await service.listParticipants(roomName(ctx.session.id));
    async function apply(participant){
     const allowed=ctx.participants.find(p=>p.user_id===participant.identity);
     if(!allowed||allowed.blocked){await service.removeParticipant(roomName(ctx.session.id),participant.identity);return;}
     const sources=[TrackSource.CAMERA,TrackSource.SCREEN_SHARE,TrackSource.SCREEN_SHARE_AUDIO,...(allowed.mic_locked?[]:[TrackSource.MICROPHONE])];
     const current=participant.permission?.canPublishSources||[];
     if(current.length!==sources.length||sources.some(source=>!current.includes(source)))await service.updateParticipant(roomName(ctx.session.id),participant.identity,{permission:{canSubscribe:true,canPublish:true,canPublishData:true,canPublishSources:sources}});
     if(allowed.mic_locked)for(const track of participant.tracks||[])if(track.source===TrackSource.MICROPHONE&&!track.muted)await service.mutePublishedTrack(roomName(ctx.session.id),participant.identity,track.sid,true);
    }
    for(let i=0;i<live.length;i+=10)await Promise.all(live.slice(i,i+10).map(apply));
   }
   async function notify(sid,kind){try{await service.sendData(roomName(sid),new TextEncoder().encode(JSON.stringify({kind})),DataPacket_Kind.RELIABLE,{topic:'occci.huddle.changed'});}catch{/* DB remains the source of truth; clients also refresh periodically. */}}
   if(body.action==='join'||body.action==='resume'){
    if(body.action==='join'&&(typeof body.code!=='string'||!/^[a-z0-9 -]{8,24}$/i.test(body.code)))throw new HuddleError('Enter the special session code.');
    if(body.sessionId!=null&&!UUID.test(body.sessionId))throw new HuddleError('Choose a valid Huddle.');
    if(body.action==='resume'&&!UUID.test(body.sessionId||''))throw new HuddleError('Choose a valid Huddle.');
    const session=body.action==='resume'?await rpc('resume',{sid:body.sessionId}):await rpc('join',{code:body.code,expected_session:body.sessionId||null});if(session.error)throw new HuddleError(session.error,/Too many/.test(session.error)?429:404);
    try{await service.createRoom({name:roomName(session.id),emptyTimeout:300,departureTimeout:60,maxParticipants:100});const ctx=await context(session.id);await reconcile(ctx);
     const token=new Token(c.apiKey,c.secret,{identity:user.id,name:ctx.name,ttl:'60s',metadata:JSON.stringify({role:ctx.role,host:ctx.is_host})});
     token.addGrant({roomJoin:true,room:roomName(session.id),canSubscribe:true,canPublish:true,canPublishData:true,canPublishSources:[TrackSource.CAMERA,TrackSource.SCREEN_SHARE,TrackSource.SCREEN_SHARE_AUDIO,...(ctx.mic_locked?[]:[TrackSource.MICROPHONE])]});
     return reply({url:c.url,token:await token.toJwt(),context:ctx});
    }catch(error){await rpc('command',{sid:session.id,command:'leave',target:null}).catch(()=>{});throw error;}
   }
   if(!UUID.test(body.sessionId||''))throw new HuddleError('Choose a valid Huddle.');
   let ctx=await context(body.sessionId);
   if(!ctx.participants.some(p=>p.user_id===user.id&&!p.blocked))throw new HuddleError('Join this Huddle with its special code first.',403);
   if(body.action==='context'){await reconcile(ctx);return reply({context:ctx});}
   if(body.action==='moderate'){
    if(!ctx.is_host)throw new HuddleError('Only this Huddle host can manage attendees.',403);
    const command=body.command;
    if(!['mute','allow','mute_all','allow_all'].includes(command))throw new HuddleError('Invalid host action.');
    if(['mute','allow'].includes(command)&&!UUID.test(body.target||''))throw new HuddleError('Choose an attendee.');
    await rpc('command',{sid:body.sessionId,command,target:['mute','allow'].includes(command)?body.target:null});
    ctx=await context(body.sessionId);await reconcile(ctx);await notify(body.sessionId,'moderation');return reply({context:ctx});
   }
   if(body.action==='delete_card'){
    if(!UUID.test(body.cardId||''))throw new HuddleError('Choose a valid snapshot.');
    try{await rpc('delete_card',{sid:body.sessionId,cid:body.cardId});}catch(error){if(error.setupRequired)throw new HuddleError('Apply Huddle snapshot update 028 in Supabase SQL Editor to delete shared snapshots.',503);throw error;}
    await notify(body.sessionId,'data');return reply({context:await context(body.sessionId)});
   }
   if(body.action==='reports'){
    if(ctx.studio_ready!==true)throw new HuddleError('Apply Huddle studio update 027 in Supabase SQL Editor.',503);
    if(typeof body.month!=='string'||!/^\d{4}-\d{2}-01$/.test(body.month)||!['monthly','project'].includes(body.kind))throw new HuddleError('Choose a month and report type.');
    const page=body.page??0;if(!Number.isInteger(page)||page<0||page>9999)throw new HuddleError('Choose a valid report page.');
    return reply({reports:await rpc('reports',{sid:body.sessionId,...unit,month:body.month,kind:body.kind,page})});
   }
   if(body.action==='studio'){
    if(ctx.studio_ready!==true)throw new HuddleError('Apply Huddle studio update 027 in Supabase SQL Editor.',503);
    if(!['grant_pen','revoke_pen','camera','screen','report','record_start','record_stop','record_ping','clear','stroke'].includes(body.command))throw new HuddleError('Invalid stage action.');
    if(!['report','stroke'].includes(body.command)&&!ctx.is_host)throw new HuddleError('Only this Huddle host can control the stage.',403);
    if(body.target!=null&&!UUID.test(body.target))throw new HuddleError('Choose an attendee.');
    if(body.command==='report'&&(!UUID.test(body.reportId||'')||!['work','register'].includes(body.source)))throw new HuddleError('Choose a valid report.');
    const values=body.command==='report'?{report_id:body.reportId,source:body.source}:body.command==='stroke'?body.stroke:{};
    if(!values||typeof values!=='object'||Array.isArray(values))throw new HuddleError('Invalid drawing.');
    ctx=await rpc('studio',{sid:body.sessionId,command:body.command,target:body.target||null,values_json:values});
    if(body.command!=='record_ping')await notify(body.sessionId,'studio');return reply({context:ctx});
   }
   if(body.action==='chat'){if(typeof body.message!=='string'||!body.message.trim()||body.message.length>2000)throw new HuddleError('Enter a message up to 2000 characters.');await rpc('chat',{sid:body.sessionId,message:body.message});await notify(body.sessionId,'chat');return reply({context:await context(body.sessionId)});}
   if(body.action==='summary')return reply({summary:await rpc('summary',{sid:body.sessionId,...unit})});
   if(body.action==='share'){await rpc('share',{sid:body.sessionId,...unit});await notify(body.sessionId,'data');return reply({context:await context(body.sessionId)});}
   throw new HuddleError('Unknown Huddle action.');
  }catch(error){if(error instanceof HuddleError)return reply({error:error.message,...(error.setupRequired?{setupRequired:true}:{})},error.status);logger.error('OCCCI Huddle action failed',{type:error.name});return reply({error:'The conference service could not complete this action. Please try again.'},502);}
 };
}
