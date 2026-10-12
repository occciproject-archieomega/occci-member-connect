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
await db.close();console.log('PASS: repeatable Huddle migration, all five host roles, scoped code joining, host-only mic moderation, rejoin lock, private financial cards, chat, role transfers, session ending, rate limits and audit activity.');
