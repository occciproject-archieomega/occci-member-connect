import fs from 'node:fs';import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');const db=new PGlite();
const bootstrap=fs.readFileSync('tests/cashier-workflow.mjs','utf8').match(/const bootstrap=`([\s\S]*?)`;/)[1];await db.exec(bootstrap);
await db.exec("alter table storage.objects add column metadata jsonb default '{\"mimetype\":\"image/webp\",\"size\":1000}';alter table auth.users add column encrypted_password text default 'fixture-hash'");
await db.exec(fs.readFileSync('supabase/setup.sql','utf8'));for(const f of fs.readdirSync('supabase/migrations').sort().filter(f=>f<'024_'))await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8').replace('create extension if not exists pgcrypto with schema extensions;',''));
const sql=fs.readFileSync('supabase/migrations/024_occci_huddle.sql','utf8');await db.exec(sql);await db.exec(sql);
const ids=Array.from({length:8},(_,i)=>`b5000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`),[admin,dm,bm,bs,bc,member,foreign,dm2]=ids;
for(const id of ids){const branch=[foreign,dm2].includes(id)?'BR-11':'BR-01';await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,id+'@example.invalid',{first_name:'Fixture',last_name:'Test',branch_id:branch,contact_number:'09123456789',address:'Fixture address',avatar:'man'}]);await db.query("update public.occci_profiles set onboarding_complete=true,membership_status='Active',registration_kind=$2 where id=$1",[id,[member,foreign].includes(id)?'Member':'Staff']);}
for(const [id,role,branch,district] of [[admin,'Admin',null,null],[dm,'DM',null,1],[dm2,'DM',null,2],[bm,'BM','BR-01',null],[bs,'Staff','BR-01',null],[bc,'BC','BR-01',null]])await db.query('insert into public.occci_staff_assignments(user_id,role,branch_id,district) values($1,$2,$3,$4)',[id,role,branch,district]);
async function as(id,fn){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}}
async function rpc(id,name,args){return (await as(id,()=>db.query(`select public.occci_huddle_${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) data`,args))).rows[0].data;}
// Reproduce the screenshot: the old migration rejects open sessions for branch/district roles.
for(const who of [dm,bm,bs,bc])await assert.rejects(rpc(who,'create',['Open session']),/Your position cannot host this operating unit/);
await db.query("update public.occci_profiles set registration_kind='Member',membership_status='Pending verification' where id=$1",[admin]);
await assert.rejects(rpc(admin,'create',['Developer Admin session']),/Your position cannot host this operating unit/,'The developer bootstrap assignment does not change signup category');
await db.query("update public.occci_profiles set registration_kind='Staff',membership_status='Active' where id=$1",[admin]);
for(const [who,branch,dist] of [[bs,'BR-01',null],[bc,'BR-01',null],[dm,null,1],[admin,null,null]])assert((await rpc(who,'create',['Fixture hosted session',branch,dist])).id);
const room=await rpc(bm,'create',['Branch conference','BR-01',null]);assert.equal(room.join_code.length,10);
await assert.rejects(rpc(member,'create',['Member host','BR-01',null]),/cannot host/);await assert.rejects(rpc(bs,'create',['Other branch','BR-11',null]),/cannot host/);
for(const id of [admin,dm,bs,bc,member])assert.equal((await rpc(id,'join',[room.join_code])).id,room.id);
assert((await rpc(foreign,'join',[room.join_code])).error);assert((await rpc(dm2,'join',[room.join_code])).error);
await assert.rejects(rpc(bs,'command',[room.id,'mute_all',null]),/Only this Huddle host/);
await rpc(bm,'command',[room.id,'mute_all',null]);assert((await rpc(member,'context',[room.id])).mic_locked);assert(!(await rpc(bm,'context',[room.id])).mic_locked);
await rpc(member,'join',[room.join_code]);assert((await rpc(member,'context',[room.id])).mic_locked,'Rejoining does not evade host microphone lock');
await rpc(bm,'command',[room.id,'allow_all',null]);assert(!(await rpc(member,'context',[room.id])).mic_locked);
await rpc(bm,'command',[room.id,'mute',member]);assert((await rpc(member,'context',[room.id])).mic_locked);await rpc(bm,'command',[room.id,'allow',member]);
await assert.rejects(rpc(bm,'command',[room.id,'mute',foreign]),/Choose an attendee/);
await db.query("insert into public.occci_financials(member_id,savings,share_capital,loan_balance,source_reference,evidence_path,as_of) values($1,5000,1000,2500,'fixture','fixture','2026-10-13')",[member]);
const summary=await rpc(bs,'summary',[room.id,'BR-01',null]);assert.equal(summary.members,1);assert.equal(summary.savings,5000);assert.equal(summary.loans,2500);
await rpc(bs,'share',[room.id,'BR-01',null]);assert.equal((await rpc(bm,'context',[room.id])).cards.length,1);assert.equal((await rpc(member,'context',[room.id])).cards.length,0,'Members do not receive cooperative financial reports');
await assert.rejects(rpc(bc,'summary',[room.id,null,1]),/within your assignment/);await assert.rejects(rpc(dm,'summary',[room.id,'BR-11',null]),/within your assignment/);
await rpc(member,'chat',[room.id,'Fixture message']);assert((await rpc(bs,'context',[room.id])).messages.some(m=>m.body==='Fixture message'));
await assert.rejects(as(member,()=>db.query('select * from public.occci_huddle_sessions')),/permission denied/,'Codes cannot be scraped through direct table reads');
const global=await rpc(admin,'create',['Cooperative conference',null,null]);assert.equal((await rpc(foreign,'join',[global.join_code])).id,global.id);
await rpc(dm,'join',[global.join_code]);await rpc(dm,'share',[global.id,null,1]);assert.equal((await rpc(foreign,'context',[global.id])).cards.length,0);await rpc(dm2,'join',[global.join_code]);assert.equal((await rpc(dm2,'context',[global.id])).cards.length,0,'A DM cannot see another district snapshot');
await db.query("update public.occci_staff_assignments set branch_id='BR-11' where user_id=$1",[bs]);await assert.rejects(rpc(bs,'context',[room.id]),/access changed/);assert((await rpc(bm,'context',[room.id])).participants.find(p=>p.user_id===bs).blocked);
await rpc(bm,'command',[room.id,'end',null]);assert((await rpc(member,'join',[room.join_code])).error);await assert.rejects(rpc(member,'chat',[room.id,'After ending']),/ended/);
for(let i=0;i<12;i++)await rpc(foreign,'join',['BADCODE123']);assert((await rpc(foreign,'join',['BADCODE123'])).error.includes('Too many'));
assert((await db.query("select count(*)::int n from public.occci_audit where action like 'Huddle %'")).rows[0].n>10);
// The next migration changes conference access while preserving financial authorization.
const dataScope=(await db.query("select pg_get_functiondef('public.occci_huddle_data_scope(text,smallint)'::regprocedure) d")).rows[0].d;
const sessionsSql=fs.readFileSync('supabase/migrations/025_occci_huddle_sessions.sql','utf8');await db.exec(sessionsSql);await db.exec(sessionsSql);
assert.equal((await db.query("select pg_get_functiondef('public.occci_huddle_data_scope(text,smallint)'::regprocedure) d")).rows[0].d,dataScope);
await db.exec('delete from public.occci_huddle_attempts');
await db.query("update public.occci_staff_assignments set branch_id='BR-01' where user_id=$1",[bs]);
for(const who of [admin,dm,bm,bs,bc]){const created=await rpc(who,'create',['Open staff session']);assert.equal(created.branch_id,null);assert.equal(created.district,null);assert.equal((await db.query('select count(*)::int n from public.occci_huddle_attendees where session_id=$1',[created.id])).rows[0].n,0,'Creation does not count as joining');}
const open=await rpc(bm,'create',['First panel session','BR-11',2]),second=await rpc(bm,'create',['Second panel session']);assert.notEqual(open.join_code,second.join_code);assert.equal(open.branch_id,null);assert.equal(open.district,null);
await assert.rejects(rpc(member,'create',['Member hosting']),/Only assigned OCCCI staff/);
const directory=await rpc(foreign,'list',[]);assert(directory.some(s=>s.id===open.id));assert(directory.some(s=>s.id===second.id));assert(directory.every(s=>!('join_code' in s)),'The public authenticated session panel never exposes other hosts codes');
const own=await rpc(bm,'list',[]);assert.equal(own.find(s=>s.id===open.id).join_code,open.join_code);assert(own.filter(s=>s.host_id!==bm).every(s=>!('join_code' in s)));
await assert.rejects(rpc(foreign,'context',[open.id]),/access changed/,'A listed session alone does not grant attendance or chat access');
const wrong=await rpc(foreign,'join',[second.join_code,open.id]);assert(wrong.error);assert.equal((await db.query('select count(*)::int n from public.occci_huddle_attendees where user_id=$1 and session_id in ($2,$3)',[foreign,open.id,second.id])).rows[0].n,0,'A code from another selected session grants no attendance');
for(const who of [foreign,dm2,member,bm,dm,bs,bc])assert.equal((await rpc(who,'join',[open.join_code,open.id])).id,open.id,'Any active account can join across districts with the correct code');
assert(!('join_code' in (await rpc(foreign,'context',[open.id])).session));assert.equal((await rpc(bm,'context',[open.id])).session.join_code,open.join_code);
assert((await rpc(bm,'context',[open.id])).is_host);await assert.rejects(rpc(dm2,'command',[open.id,'end',null]),/Only this Huddle host/);
await rpc(bm,'command',[open.id,'mute_all',null]);assert((await rpc(foreign,'context',[open.id])).mic_locked);await rpc(bm,'command',[open.id,'allow_all',null]);
await rpc(bs,'share',[open.id,'BR-01',null]);assert.equal((await rpc(bm,'context',[open.id])).cards.length,1);assert.equal((await rpc(dm2,'context',[open.id])).cards.length,0);assert.equal((await rpc(foreign,'context',[open.id])).cards.length,0);
await assert.rejects(rpc(dm2,'summary',[open.id,'BR-01',null]),/within your assignment/);await assert.rejects(rpc(bm,'summary',[open.id,'BR-11',null]),/within your assignment/);await assert.rejects(rpc(member,'summary',[open.id,'BR-01',null]),/within your assignment/);
await db.query("update public.occci_staff_assignments set branch_id='BR-11' where user_id=$1",[bs]);const transferred=await rpc(bs,'context',[open.id]);assert.equal(transferred.cards.length,0,'Transferred staff lose access to their old branch cards');assert(!transferred.participants.find(p=>p.user_id===bs).blocked,'Transfer does not restrict open conference participation');
await rpc(foreign,'command',[open.id,'leave',null]);await assert.rejects(rpc(foreign,'context',[open.id]),/access changed/,'Leaving revokes attendee reads until code-based rejoining');
await rpc(foreign,'join',[open.join_code,open.id]);await rpc(foreign,'chat',[open.id,'Cross-district meeting chat']);assert((await rpc(bm,'context',[open.id])).messages.some(m=>m.body==='Cross-district meeting chat'));
await assert.rejects(as(foreign,()=>db.query('select * from public.occci_huddle_sessions')),/permission denied/);
await assert.rejects(as(foreign,()=>db.query('select public.occci_huddle_host_scope(null,null)')),/permission denied/);
await db.exec('set role anon');try{await assert.rejects(db.query('select public.occci_huddle_list()'),/permission denied/);}finally{await db.exec('reset role');}
await rpc(bm,'command',[second.id,'end',null]);assert(!(await rpc(foreign,'list',[])).some(s=>s.id===second.id));assert((await rpc(foreign,'join',[second.join_code,second.id])).error);assert((await rpc(bm,'context',[open.id])).is_host,'Ending a second session leaves the first one active');
const expired=await rpc(bc,'create',['Expired session']);await db.query("update public.occci_huddle_sessions set expires_at=now()-interval '1 second' where id=$1",[expired.id]);assert(!(await rpc(member,'list',[])).some(s=>s.id===expired.id));assert((await rpc(member,'join',[expired.join_code,expired.id])).error);
await db.query("update public.occci_profiles set membership_status='Pending verification' where id=$1",[foreign]);assert.deepEqual(await rpc(foreign,'list',[]),[]);await assert.rejects(rpc(foreign,'join',[open.join_code,open.id]),/active OCCCI account/);
await db.query("update public.occci_profiles set membership_status='Active',archived_at=now() where id=$1",[foreign]);await assert.rejects(rpc(foreign,'join',[open.join_code,open.id]),/active OCCCI account/);
await db.query('delete from public.occci_staff_assignments where user_id=$1',[bc]);assert.deepEqual(await rpc(bc,'list',[]),[]);await assert.rejects(rpc(bc,'join',[open.join_code,open.id]),/active OCCCI account/);
// Approved positions must work even when their original registration was as a member.
await db.query("insert into public.occci_staff_assignments(user_id,role,branch_id) values($1,'BC','BR-01')",[bc]);
for(const who of [admin,dm,bm,bs,bc])await db.query("update public.occci_profiles set registration_kind='Member',membership_status='Pending verification' where id=$1",[who]);
for(const who of [admin,dm,bm,bs,bc])await assert.rejects(rpc(who,'create',['Legacy approved official']),/Only assigned OCCCI staff/);
const before=(await db.query('select id,registration_kind,membership_status from public.occci_profiles order by id')).rows;
const fix=fs.readFileSync('supabase/migrations/026_occci_huddle_staff_permissions.sql','utf8');await db.exec(fix);await db.exec(fix);
assert.deepEqual((await db.query('select id,registration_kind,membership_status from public.occci_profiles order by id')).rows,before,'The repair never promotes or modifies profiles');
assert.equal((await db.query("select pg_get_functiondef('public.occci_huddle_data_scope(text,smallint)'::regprocedure) d")).rows[0].d,dataScope);
for(const [who,role] of [[admin,'Admin'],[dm,'DM'],[bm,'BM'],[bs,'Staff'],[bc,'BC']]){const p=await rpc(who,'permissions',[]);assert.equal(p.role,role);assert(p.database_ready&&p.can_host&&p.can_join);const created=await rpc(who,'create',['Approved '+role+' session']);assert(created.id);assert.equal(created.branch_id,null);assert.equal(created.district,null);assert.equal((await rpc(who,'list',[])).find(s=>s.id===created.id).join_code,created.join_code);}
await assert.rejects(rpc(member,'create',['Member attempting to host']),/Only assigned OCCCI staff/);assert.equal((await rpc(member,'permissions',[])).can_host,false);
await assert.rejects(rpc(bs,'summary',[open.id,'BR-01',null]),/within your assignment/,'The transferred BS cannot use the permission fix to read another branch');
await assert.rejects(rpc(dm2,'summary',[open.id,'BR-01',null]),/within your assignment/,'DM financial data is still limited to the assigned district');
await db.query("update public.occci_profiles set archived_at=null,registration_kind='Staff',onboarding_complete=true,membership_status='Active' where id=$1",[foreign]);
assert.equal((await rpc(foreign,'permissions',[])).can_host,false);await assert.rejects(rpc(foreign,'create',['Unassigned applicant']),/Only assigned OCCCI staff/);await assert.rejects(rpc(foreign,'join',[open.join_code,open.id]),/active OCCCI account/);
await db.query('delete from public.occci_staff_assignments where user_id=$1',[bc]);assert.equal((await rpc(bc,'permissions',[])).can_host,false);await assert.rejects(rpc(bc,'create',['Revoked staff position']),/Only assigned OCCCI staff/);
await db.query("update public.occci_profiles set archived_at=now() where id=$1",[bm]);assert.equal((await rpc(bm,'permissions',[])).can_host,false);await assert.rejects(rpc(bm,'create',['Archived BM']),/Only assigned OCCCI staff/);
await db.query('update public.occci_profiles set onboarding_complete=false where id=$1',[dm]);assert.equal((await rpc(dm,'permissions',[])).can_host,false);
await db.exec('set role anon');try{await assert.rejects(db.query('select public.occci_huddle_permissions()'),/permission denied/);}finally{await db.exec('reset role');}

// Studio migration runs safely twice on an established database.
const studioSql=fs.readFileSync('supabase/migrations/027_occci_huddle_studio.sql','utf8');await db.exec(studioSql);await db.exec(studioSql);
await db.query("update public.occci_profiles set archived_at=null,onboarding_complete=true,registration_kind='Member',membership_status='Active' where id=any($1::uuid[])",[[admin,dm,bm,bs,member,dm2]]);
const studioRoom=await rpc(admin,'create',['Studio permissions fixture']);
for(const who of [admin,dm,bm,bs,member,dm2])await rpc(who,'join',[studioRoom.join_code,studioRoom.id]);
assert((await rpc(member,'list',[])).find(s=>s.id===studioRoom.id).can_resume);
assert.equal((await rpc(member,'resume',[studioRoom.id])).id,studioRoom.id);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'camera',admin,{}]),/Only the host/);
let studio=await rpc(admin,'studio',[studioRoom.id,'camera',admin,{}]);assert.equal(studio.presentation.target,admin);assert(studio.studio_ready);
const stroke={revision:studio.presentation.revision,tool:'arrow',color:'cyan',points:[[.1,.2],[.8,.9]]};
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,stroke]),/host must allow/);
await rpc(admin,'studio',[studioRoom.id,'grant_pen',member,{}]);
studio=await rpc(member,'studio',[studioRoom.id,'stroke',null,stroke]);assert.equal(studio.strokes.length,1);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,{...stroke,points:[[2,.2],[.8,.9]]}]),/inside the stage/);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,{...stroke,color:'purple'}]),/Invalid drawing/);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'clear',null,{}]),/Only the host/);
studio=await rpc(admin,'studio',[studioRoom.id,'clear',null,{}]);assert.equal(studio.strokes.length,0);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,stroke]),/presentation changed/);
await rpc(admin,'studio',[studioRoom.id,'revoke_pen',member,{}]);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,{...stroke,revision:studio.presentation.revision}]),/host must allow/);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'record_start',null,{}]),/Only the host/);
studio=await rpc(admin,'studio',[studioRoom.id,'record_start',null,{}]);assert(studio.recording);
assert((await rpc(member,'context',[studioRoom.id])).recording);
await db.query("update public.occci_huddle_stage set record_expires_at=now()-interval '1 second' where session_id=$1",[studioRoom.id]);assert.equal((await rpc(member,'context',[studioRoom.id])).recording,false,'An expired recording lease clears its indicator');
await rpc(admin,'studio',[studioRoom.id,'record_ping',null,{}]);assert((await rpc(member,'context',[studioRoom.id])).recording);
await rpc(admin,'studio',[studioRoom.id,'record_stop',null,{}]);assert.equal((await rpc(member,'context',[studioRoom.id])).recording,false);
// Mute all and then open one mic leaves everyone else locked and never starts a device.
await rpc(admin,'command',[studioRoom.id,'mute_all',null]);await rpc(admin,'command',[studioRoom.id,'allow',member]);
studio=await rpc(member,'context',[studioRoom.id]);assert.equal(studio.mic_locked,false);
assert.equal((await rpc(dm,'context',[studioRoom.id])).mic_locked,true);
await rpc(member,'command',[studioRoom.id,'leave',null]);await rpc(member,'join',[studioRoom.join_code,studioRoom.id]);assert.equal((await rpc(member,'context',[studioRoom.id])).mic_locked,true,'New/rejoining attendees inherit Mute all');

await rpc(admin,'command',[studioRoom.id,'allow_all',null]);
const monthly=(await db.query("insert into public.occci_work_reports(created_by,branch_id,district,frequency,title,period_start,period_end,status,summary,metrics) values($1,'BR-01',1,'Monthly','October branch totals','2026-10-01','2026-10-31','Approved','Approved fixture totals','{\"collections\":12500}') returning id",[bm])).rows[0].id;
const project=(await db.query("insert into public.occci_reports(type_id,title,branch_id,district,period_start,period_end,status,summary,details,created_by) values('special-project','Branch project','BR-01',1,'2026-10-01','2026-10-31','Approved','Fixture project','{\"budget\":3000}',$1) returning id",[admin])).rows[0].id;
assert((await rpc(admin,'reports',[studioRoom.id,null,null,'2026-10-01','monthly'])).some(r=>r.id===monthly));
assert((await rpc(dm,'reports',[studioRoom.id,null,1,'2026-10-01','project'])).some(r=>r.id===project));
await assert.rejects(rpc(dm2,'reports',[studioRoom.id,'BR-01',null,'2026-10-01','monthly']),/authorized operating unit/);
await assert.rejects(rpc(member,'reports',[studioRoom.id,'BR-01',null,'2026-10-01','monthly']),/authorized operating unit/);
studio=await rpc(admin,'studio',[studioRoom.id,'report',null,{report_id:monthly,source:'work'}]);assert.equal(studio.presentation.report.metrics.collections,12500);
for(const who of [member,dm2,bs]){const privateContext=await rpc(who,'context',[studioRoom.id]);assert(privateContext.presentation.restricted);assert(!privateContext.presentation.report);assert(!JSON.stringify(privateContext.presentation).includes('12500'));assert.deepEqual(privateContext.strokes,[]);}
assert.equal((await rpc(dm,'context',[studioRoom.id])).presentation.report.id,monthly);
assert.equal((await rpc(bm,'context',[studioRoom.id])).presentation.report.id,monthly);
await assert.rejects(rpc(dm2,'studio',[studioRoom.id,'report',null,{report_id:monthly,source:'work'}]),/outside your authorized units/);
await rpc(admin,'studio',[studioRoom.id,'grant_pen',member,{}]);studio=await rpc(member,'context',[studioRoom.id]);
await assert.rejects(rpc(member,'studio',[studioRoom.id,'stroke',null,{...stroke,revision:studio.presentation.revision}]),/host must allow/);
await as(member,async()=>{await assert.rejects(db.query('select * from public.occci_huddle_stage'),/permission denied/);await assert.rejects(db.query('select * from public.occci_huddle_strokes'),/permission denied/);});
await rpc(member,'command',[studioRoom.id,'leave',null]);assert.equal((await rpc(member,'list',[])).find(s=>s.id===studioRoom.id).can_resume,false);await assert.rejects(rpc(member,'resume',[studioRoom.id]),/access changed|code to join/);
await rpc(admin,'command',[studioRoom.id,'end',null]);await assert.rejects(rpc(dm,'resume',[studioRoom.id]),/ended|access changed/);
assert.equal((await db.query("select pg_get_functiondef('public.occci_huddle_data_scope(text,smallint)'::regprocedure) d")).rows[0].d,dataScope);

// Snapshot deletion preserves author/host permissions and never touches financial records.
const snapshotSql=fs.readFileSync('supabase/migrations/028_occci_huddle_snapshot_delete.sql','utf8');await db.exec(snapshotSql);await db.exec(snapshotSql);
const snapshotRoom=await rpc(admin,'create',['Snapshot lifecycle']);
for(const who of [admin,dm,bm,member,dm2])await rpc(who,'join',[snapshotRoom.join_code,snapshotRoom.id]);
const financialBefore=(await db.query('select * from public.occci_financials order by member_id')).rows;
const ownCard=await rpc(bm,'share',[snapshotRoom.id,'BR-01',null]);
await assert.rejects(rpc(dm,'delete_card',[snapshotRoom.id,ownCard.id]),/own snapshots/,'An authorized reader cannot delete another attendee snapshot');
await assert.rejects(rpc(dm2,'delete_card',[snapshotRoom.id,ownCard.id]),/own snapshots/,'Cross-district deletion is denied');
await assert.rejects(rpc(member,'delete_card',[snapshotRoom.id,ownCard.id]),/own snapshots/,'A member cannot erase financial snapshots');
assert((await rpc(bm,'delete_card',[snapshotRoom.id,ownCard.id])).ok);
assert(!(await rpc(admin,'context',[snapshotRoom.id])).cards.some(c=>c.id===ownCard.id));
assert((await rpc(bm,'delete_card',[snapshotRoom.id,ownCard.id])).ok,'Deletion is idempotent');
const hostCard=await rpc(bm,'share',[snapshotRoom.id,'BR-01',null]);assert((await rpc(admin,'delete_card',[snapshotRoom.id,hostCard.id])).ok);
const otherSession=await rpc(admin,'create',['Other snapshot session']);await rpc(admin,'join',[otherSession.join_code,otherSession.id]);const separateCard=await rpc(admin,'share',[otherSession.id,'BR-01',null]);
await rpc(admin,'delete_card',[snapshotRoom.id,separateCard.id]);assert((await rpc(admin,'context',[otherSession.id])).cards.some(c=>c.id===separateCard.id),'A card ID from another session is never deleted');
assert.deepEqual((await db.query('select * from public.occci_financials order by member_id')).rows,financialBefore);
assert((await db.query("select count(*) n from public.occci_audit where action='Huddle snapshot deleted'")).rows[0].n>=2);
await rpc(bm,'command',[snapshotRoom.id,'leave',null]);await assert.rejects(rpc(bm,'delete_card',[snapshotRoom.id,hostCard.id]),/access changed|Join/);
await db.close();console.log('PASS: snapshot deletion author/host/scope/audit/source preservation; migrations 024–028 repeat safely; studio host permissions, scoped monthly/project reports, report redaction, drawing grants/revocation/stale revision, individual mic unlock, recording notices, resume/leave/end and existing financial boundaries.');
