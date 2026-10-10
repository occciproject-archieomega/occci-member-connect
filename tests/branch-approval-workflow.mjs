import fs from 'node:fs';import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,raw_user_meta_data jsonb,raw_app_meta_data jsonb default '{}',email text,email_confirmed_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
grant usage on schema auth,storage,public to authenticated,anon;grant execute on function auth.uid(),storage.foldername(text) to authenticated,anon;grant select,insert on storage.objects to authenticated;`);
for(const path of ['supabase/setup.sql',...['002_workflow','003_staff_signup','004_activity_google','005_member_documents','006_reports','007_staff_invitations','008_staff_review_drafts'].map(n=>'supabase/migrations/'+n+'.sql')])await db.exec(fs.readFileSync(path,'utf8'));
const ids=Array.from({length:17},(_,i)=>`90000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const [admin,dm,dm2,bm,bmOther,bm2,bs,bc,bs2,member,localOther,foreign,newMember,staleMember,inviteUser,peer,transfer]=ids;
for(const id of ids){const branch=[dm2,bm2,bs2,foreign].includes(id)?'BR-11':[bmOther,localOther].includes(id)?'BR-02':'BR-01';await db.query('insert into auth.users(id,raw_user_meta_data,email) values($1,$2,$3)',[id,{first_name:'Fixture',last_name:id.slice(-3),contact_number:'09123456789',address:'Test address, Leyte',avatar:'man',branch_id:branch},id+'@example.invalid']);}
await db.query(`insert into public.occci_staff_assignments(user_id,role,branch_id,district) values($1,'Admin',null,null),($2,'DM',null,1),($3,'DM',null,2),($4,'BM','BR-01',null),($5,'BM','BR-02',null),($6,'BM','BR-11',null),($7,'Staff','BR-01',null),($8,'BC','BR-01',null),($9,'Staff','BR-11',null),($10,'Staff','BR-01',null)`,[admin,dm,dm2,bm,bmOther,bm2,bs,bc,bs2,peer]);
async function as(id,fn){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}}
async function reject(id,sql,args,pattern){await assert.rejects(as(id,()=>db.query(sql,args)),pattern);}
await db.query("update public.occci_profiles set membership_status='Active',account_number='ACC-'||right(id::text,3) where id=any($1::uuid[])",[[member,localOther,foreign]]);
const financial={savings:20000,loan_balance:12000,loan_status:'Active',annual_interest:2,source_reference:'Test ledger',as_of:'2026-10-11',schedule:[{date:'2026-11-15',amount:2000,status:'Scheduled'},{date:'2026-12-15',amount:2000,status:'Scheduled'}]};
const files=[{path:bs+'/ledger.pdf',name:'ledger.pdf',size:1024}];
await db.query("insert into storage.objects(bucket_id,name) values('occci-documents',$1),('occci-documents',$2)",[files[0].path,bs2+'/foreign.pdf']);
const old=(await db.query("insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,status,dm_reviewer,note,review_note,evidence_path,evidence_files) values($1,'BR-01','Financial sync',$2,0,$3,'DM approved',$4,'Old submission','Earlier DM review',$5,$6) returning id",[member,financial,bs,dm,files[0].path,files])).rows[0].id;
const migration=fs.readFileSync('supabase/migrations/009_branch_approval_workflow.sql','utf8');await db.exec(migration);await db.exec(migration);
assert.equal((await db.query('select status,workflow_version from public.occci_change_requests where id=$1',[old])).rows[0].status,'Pending');
assert.equal((await db.query("select count(*)::int n from public.occci_audit where action='Financial approval workflow updated' and after_data->>'request_id'=$1",[old])).rows[0].n,1,'Repeat application must not duplicate legacy workflow events');
assert.equal((await db.query('select email from public.occci_profiles where id=$1',[bs])).rows[0].email,bs+'@example.invalid');
await db.query('update auth.users set email=$1 where id=$2',['updated@example.invalid',bs]);assert.equal((await db.query('select email from public.occci_profiles where id=$1',[bs])).rows[0].email,'updated@example.invalid');
const created='90000000-0000-4000-8000-000000000099';await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[created,'new@example.invalid',{onboarding_source:'staff-invitation'}]);assert.equal((await db.query('select email from public.occci_profiles where id=$1',[created])).rows[0].email,'new@example.invalid');
// Both row policies and the activity RPC enforce the same district/branch boundaries.
for(const user of [bm,bs,bc])await as(user,async()=>{const profiles=(await db.query('select id from public.occci_profiles')).rows;assert(profiles.some(p=>p.id===member));assert(!profiles.some(p=>[foreign,localOther,dm2,bs2].includes(p.id)));});
await as(dm,async()=>{const profiles=(await db.query('select id from public.occci_profiles')).rows;assert(profiles.some(p=>p.id===localOther));assert(!profiles.some(p=>[foreign,dm2,bs2].includes(p.id)));});
for(const [branch,district,actor,role,target] of [['BR-01',1,bs,'Staff',member],['BR-02',1,bmOther,'BM',localOther],['BR-11',2,bs2,'Staff',bm],[null,1,dm,'DM',null],[null,null,admin,'Admin',null]])await db.query('insert into public.occci_audit(branch_id,district,actor,actor_role,member_id,action,note) values($1,$2,$3,$4,$5,$6,$7)',[branch,district,actor,role,target,'Scope fixture '+(branch||district||'global'),'Test scope']);
for(const user of [dm,bm,bs,bc])await as(user,async()=>{for(const sql of ['select * from public.occci_audit','select * from public.occci_activity()']){const rows=(await db.query(sql)).rows;assert(!rows.some(a=>a.action==='Scope fixture BR-11'),'Foreign district activity is hidden even when member_id equals a manager');assert(!rows.some(a=>a.action==='Scope fixture global'));if(user!==dm){assert(!rows.some(a=>a.action==='Scope fixture BR-02'));assert(!rows.some(a=>a.action==='Scope fixture 1'));}}});
assert((await as(admin,()=>db.query("select * from public.occci_activity() where action='Scope fixture BR-11'"))).rows.length);
// Team changes that used to log a null branch now retain canonical event scope.
await as(admin,()=>db.query("select public.occci_manage_record('Team',$1,$2,false,$3)",[transfer,{role:'Staff',branch_id:'BR-11'},'Assign district two employee']));
assert.equal((await db.query("select branch_id from public.occci_audit where member_id=$1 and action='Team assignment changed' order by id desc limit 1",[transfer])).rows[0].branch_id,'BR-11');
assert.equal((await as(bm,()=>db.query('select * from public.occci_activity() where member_id=$1',[transfer]))).rows.length,0);
// Scoped reports and original documents, including files owned before reassignment.
const type=(await db.query("select id from public.occci_report_types where category='Assembly' limit 1")).rows[0].id;
for(const [title,district,branch] of [['Branch one',1,'BR-01'],['Branch two',1,'BR-02'],['Other district',2,'BR-11'],['District one',1,null],['Overall',null,null]])await db.query("insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,created_by) values($1,$2,$3,$4,'2026-10-11','2026-10-11',$5)",[type,title,district,branch,admin]);
assert.deepEqual((await as(dm,()=>db.query('select title from public.occci_reports order by title'))).rows.map(r=>r.title),['Branch one','Branch two','District one']);
assert.deepEqual((await as(bm,()=>db.query('select title from public.occci_reports order by title'))).rows.map(r=>r.title),['Branch one']);
for(const [creator,branch,district] of [[bs,'BR-01',1],[peer,'BR-01',1],[bs2,'BR-11',2]])await db.query("insert into public.occci_work_reports(created_by,branch_id,district,frequency,title,period_start,period_end) values($1,$2,$3,'Daily','Test work','2026-10-11','2026-10-11')",[creator,branch,district]);
assert.equal((await as(bs,()=>db.query('select * from public.occci_work_reports'))).rows.length,1);assert.equal((await as(bm,()=>db.query('select * from public.occci_work_reports'))).rows.length,2);
await db.query("insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,note,evidence_path) values($1,'BR-11','Financial sync',$2,0,$3,'Moved original',$4)",[foreign,financial,bs,bs+'/moved.pdf']);await db.query("insert into storage.objects(bucket_id,name) values('occci-documents',$1)",[bs+'/moved.pdf']);
await as(bs,async()=>assert.equal((await db.query("select name from storage.objects where name=$1",[bs+'/moved.pdf'])).rows.length,0,'An owned file attached outside the current branch cannot bypass scope'));
// New members become active only after their BM screen and the assigned DM approves.
const approve='select public.occci_approve_member($1,$2,$3)',review='select public.occci_review_change($1,$2,$3)';
for(const user of [admin,dm,bs,bc])await reject(user,approve,[newMember,'MEM-001','Test screening'],/Only the assigned BM/);
await reject(bm2,approve,[newMember,'MEM-001','Other district'],/assigned branch/);
await as(bm,()=>db.query(approve,[newMember,'MEM-001','Screened against membership register']));
const memberRequest=(await db.query("select * from public.occci_change_requests where member_id=$1 and kind='Membership approval'",[newMember])).rows[0];assert.equal(memberRequest.status,'BM approved');
let p=(await db.query('select * from public.occci_profiles where id=$1',[newMember])).rows[0];assert.equal(p.membership_status,'Pending verification');assert.equal(p.account_number,null);
for(const user of [admin,bm,bs,dm2])await reject(user,review,[memberRequest.id,'Approve','Test decision'],/BM screening|different authorized/);
await as(dm,()=>db.query(review,[memberRequest.id,'Approve','District approval of branch membership']));p=(await db.query('select * from public.occci_profiles where id=$1',[newMember])).rows[0];assert.equal(p.membership_status,'Active');assert.equal(p.account_number,'MEM-001');
await reject(dm,review,[memberRequest.id,'Approve','Duplicate decision'],/BM screening/);
await as(bm,()=>db.query(approve,[staleMember,'MEM-002','Screened complete profile']));const stale=(await db.query("select id from public.occci_change_requests where member_id=$1 and kind='Membership approval'",[staleMember])).rows[0].id;
await as(bs,()=>db.query('select public.occci_assign_account($1,$2,$3)',[staleMember,'MEM-003','New official ID correction']));await reject(dm,review,[stale,'Approve','Approve old details'],/details changed/);
const profile={first_name:'Fixture',last_name:'Member',middle_name:'',contact_number:'09123456789',address:'Ormoc, Leyte',avatar:'man',membership_status:'Active'};await reject(bm,"select public.occci_manage_record('Member',$1,$2,false,$3)",[staleMember,profile,'Attempt direct activation'],/activation requires BM/);
// BM first, assigned DM last; balances and multi-payment schedules publish atomically.
const submit='select public.occci_submit_financial_documents($1,$2,$3,$4) id';
for(const user of [admin,dm])await reject(user,submit,[member,financial,files,'Unauthorized input'],/Request is not permitted|Branch Staff/);
await reject(dm,review,[old,'Approve','Cannot bypass BM'],/BM screening/);await reject(bmOther,review,[old,'Approve','Cannot review another branch'],/different authorized/);
await as(bm,()=>db.query(review,[old,'Approve','BM checked the original statements']));assert.equal((await as(member,()=>db.query('select * from public.occci_financials'))).rows.length,0,'No published balance after BM only');
await db.exec(migration);assert.equal((await db.query('select status from public.occci_change_requests where id=$1',[old])).rows[0].status,'BM approved','Rerunning migration preserves current screened requests');
await reject(dm2,review,[old,'Approve','Wrong district'],/different authorized/);await reject(admin,review,[old,'Approve','Admin cannot finalize'],/BM screening/);
await as(dm,()=>db.query(review,[old,'Approve','DM verified original documents']));const snapshot=(await as(member,()=>db.query('select * from public.occci_financials'))).rows[0];assert.equal(Number(snapshot.savings),20000);assert.equal(snapshot.schedule.length,2);assert.equal(snapshot.evidence_files.length,1);
const first=(await as(bs,()=>db.query(submit,[member,financial,files,'New actual balances']))).rows[0].id;const second=(await as(bs,()=>db.query(submit,[member,financial,files,'Concurrent actual balances']))).rows[0].id;
for(const id of [first,second])await as(bm,()=>db.query(review,[id,'Approve','Originals screened']));await as(dm,()=>db.query(review,[first,'Approve','Final actual verification']));await reject(dm,review,[second,'Approve','Stale verification'],/record changed/);
await reject(bs,submit,[member,{...financial,schedule:[{date:'2026-02-30',amount:10,status:'Scheduled'}]},files,'Bad calendar date'],/date|range/);
await reject(bs,submit,[member,{...financial,schedule:[{date:'2026-11-15',amount:10,status:'Unknown'}]},files,'Bad status'],/date or status/);
const bmDoc=[{path:bm+'/bm.pdf',name:'bm.pdf',size:100}];await db.query("insert into storage.objects(bucket_id,name) values('occci-documents',$1)",[bmDoc[0].path]);const bmSubmitted=(await as(bm,()=>db.query(submit,[member,financial,bmDoc,'BM screened the actual ledger']))).rows[0].id;assert.equal((await db.query('select status from public.occci_change_requests where id=$1',[bmSubmitted])).rows[0].status,'BM approved');await as(dm,()=>db.query(review,[bmSubmitted,'Approve','Independent final district approval']));
console.log('PASS: repeatable current migration, legacy review reset with audit preservation, Auth email mirroring, profile/report/activity/document isolation, no owned-file scope bypass, BM membership screening and DM activation, no Admin/BS membership approval, no direct activation bypass, BM / assigned-DM financial stages, no early published balances, private documents, multi-payment schedule persistence, stale request rejection and BM-originated screening.');await db.close();
