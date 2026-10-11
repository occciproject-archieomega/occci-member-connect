import fs from 'node:fs';import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');const db=new PGlite();
const bootstrap=`create role anon;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,raw_user_meta_data jsonb,raw_app_meta_data jsonb default '{}',email text,email_confirmed_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
grant usage on schema auth,storage,public to authenticated,anon;grant execute on function auth.uid(),storage.foldername(text) to authenticated,anon;grant select,insert on storage.objects to authenticated;`;
await db.exec(bootstrap);
for(const path of ['supabase/setup.sql',...['002_workflow','003_staff_signup','004_activity_google','005_member_documents','006_reports','007_staff_invitations','008_staff_review_drafts','009_branch_approval_workflow','010_audit_subject_identity','011_admin_position_confirmation','012_all_staff_password_confirmation'].map(n=>'supabase/migrations/'+n+'.sql')])await db.exec(fs.readFileSync(path,'utf8'));
const ids=Array.from({length:16},(_,i)=>`83000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const [admin,dm,foreignDM,bm,otherBM,foreignBM,bs,bc,member,ownMember,foreignMember,applicant,extra,duplicateDM,duplicateBM,newMember]=ids;
for(const id of ids){const branch=[foreignDM,foreignBM,foreignMember].includes(id)?'BR-11':'BR-01';await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,id+'@example.invalid',{first_name:'Fixture',last_name:id.slice(-3),contact_number:'09123456789',address:'Test address, Leyte',avatar:'man',branch_id:branch}]);}
await db.query(`insert into public.occci_staff_assignments(user_id,role,branch_id,district) values($1,'Admin',null,null),($2,'DM',null,1),($3,'DM',null,2),($4,'BM','BR-01',null),($5,'BM','BR-02',null),($6,'BM','BR-11',null),($7,'Staff','BR-01',null),($8,'BC','BR-01',null),($9,'Staff','BR-02',null)`,[admin,dm,foreignDM,bm,otherBM,foreignBM,bs,bc,extra]);
const migration=fs.readFileSync('supabase/migrations/013_single_managers_financial_review.sql','utf8');
// An upgrade cannot silently remove, demote or choose between conflicting managers.
await db.query("insert into public.occci_staff_assignments(user_id,role,district) values($1,'DM',1)",[duplicateDM]);
await assert.rejects(db.exec(migration),/Resolve duplicate District Manager/);await db.exec('rollback');
assert.equal((await db.query("select count(*)::int n from public.occci_staff_assignments where role='DM' and district=1")).rows[0].n,2);
assert.equal((await db.query("select to_regclass('public.occci_one_dm_per_district') idx")).rows[0].idx,null);
await db.query('delete from public.occci_staff_assignments where user_id=$1',[duplicateDM]);
await db.query("insert into public.occci_staff_assignments(user_id,role,branch_id) values($1,'BM','BR-01')",[duplicateBM]);
await assert.rejects(db.exec(migration),/Resolve duplicate Branch Manager/);await db.exec('rollback');
assert.equal((await db.query("select count(*)::int n from public.occci_staff_assignments where role='BM' and branch_id='BR-01'")).rows[0].n,2);
await db.query('delete from public.occci_staff_assignments where user_id=$1',[duplicateBM]);
await db.exec(migration);await db.exec(migration);
async function as(id,fn,claims={sub:id,session_id:'11111111-1111-4111-8111-111111111111',amr:[{method:'oauth',timestamp:0}]}){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}}
async function reject(id,sql,args,pattern){await assert.rejects(as(id,()=>db.query(sql,args)),pattern);}
let sessionCounter=0;async function passwordClaims(){const time=Number((await db.query('select floor(extract(epoch from clock_timestamp()))::bigint t')).rows[0].t);return{sub:admin,session_id:`44000000-0000-4000-8000-${String(++sessionCounter).padStart(12,'0')}`,amr:[{method:'password',timestamp:time}]};}
const begin='select public.occci_begin_position_confirmation($1,$2,$3) id',manage="select public.occci_manage_record('Team',$1,$2,$3,$4)";
async function start(target,values,kind='Team'){return(await as(admin,()=>db.query(begin,[kind,target,values]))).rows[0].id;}
async function assign(target,values,remove=false){const proof=await start(target,values,remove?'Team removal':'Team');return as(admin,()=>db.query(manage,[target,{...values,position_confirmation:proof},remove,'Verified fixture manager assignment']),await passwordClaims());}
for(const kind of ['Team','Staff application']){
 await reject(admin,begin,[kind,extra,{role:'DM',district:1}],/District 1 already has a DM/);
 await reject(admin,begin,[kind,extra,{role:'BM',branch_id:'BR-01'}],/branch already has a BM/);
}
await assert.rejects(db.query("insert into public.occci_staff_assignments(user_id,role,district) values($1,'DM',1)",[duplicateDM]),/occci_one_dm_per_district/);
await assert.rejects(db.query("insert into public.occci_staff_assignments(user_id,role,branch_id) values($1,'BM','BR-01')",[duplicateBM]),/occci_one_bm_per_branch/);
await assert.rejects(db.query("update public.occci_staff_assignments set branch_id='BR-01' where user_id=$1",[otherBM]),/occci_one_bm_per_branch/);
await assert.rejects(db.query("update public.occci_staff_assignments set district=1 where user_id=$1",[foreignDM]),/occci_one_dm_per_district/);
await assign(dm,{role:'DM',district:1});await assign(bm,{role:'BM',branch_id:'BR-01'});
await reject(admin,manage,[extra,{role:'Staff',branch_id:'BR-01'},false,'Missing password'],/password/);
for(const role of ['authenticated','anon'])assert.equal((await db.query("select has_function_privilege($1,'public.occci_require_manager_slot(uuid,jsonb)','execute') allowed",[role])).rows[0].allowed,false);
// An occupied position arising after the password challenge must still be blocked atomically.
await db.query("update public.occci_profiles set registration_kind='Staff',employee_id='EMP-013' where id=$1",[applicant]);await db.query('insert into public.occci_staff_applications(user_id) values($1)',[applicant]);
const staffValues={role:'BM',branch_id:'BR-16',employee_id:'EMP-013'},appProof=await start(applicant,staffValues,'Staff application');
await db.query("insert into public.occci_staff_assignments(user_id,role,branch_id) values($1,'BM','BR-16')",[duplicateBM]);
const reviewStaff="select public.occci_review_staff($1,'Approve',$2,$3)";
await assert.rejects(as(admin,()=>db.query(reviewStaff,[applicant,{...staffValues,position_confirmation:appProof},'Manager slot changed before approval']),await passwordClaims()),/occci_one_bm_per_branch/);
assert.equal((await db.query('select used_at from public.occci_position_confirmations where id=$1',[appProof])).rows[0].used_at,null);
assert.equal((await db.query('select status from public.occci_staff_applications where user_id=$1',[applicant])).rows[0].status,'Pending');
assert.equal((await db.query('select count(*)::int n from public.occci_staff_assignments where user_id=$1',[applicant])).rows[0].n,0);
await assign(duplicateBM,{},true);
await as(admin,()=>db.query(reviewStaff,[applicant,{...staffValues,position_confirmation:appProof},'Approve manager after vacancy']),await passwordClaims());
await reject(admin,begin,['Team',otherBM,{role:'BM',branch_id:'BR-16'}],/already has a BM/);
assert.equal((await db.query('select branch_id from public.occci_staff_assignments where user_id=$1',[otherBM])).rows[0].branch_id,'BR-02');
await db.query("update public.occci_profiles set membership_status='Active',account_number='ACC-'||right(id::text,3) where id=any($1::uuid[])",[[member,ownMember,foreignMember]]);
const proposal={savings:20000,loan_balance:12000,loan_status:'Active',annual_interest:2,source_reference:'Fixture ledger',as_of:'2026-10-11',schedule:[{date:'2026-11-15',amount:2000,status:'Scheduled'}]};
for(const id of [bs,bm])await db.query("insert into storage.objects(bucket_id,name) values('occci-documents',$1)",[id+'/ledger.pdf']);
async function submit(who,target,values=proposal){return(await as(who,()=>db.query('select public.occci_submit_financial_documents($1,$2,$3,$4) id',[target,values,[{path:who+'/ledger.pdf',name:'ledger.pdf',size:1024}],'Original fixture ledger']))).rows[0].id;}
const review='select public.occci_review_change($1,$2,$3)',staffRequest=await submit(bs,member),ownRequest=await submit(bm,ownMember),ownReject=await submit(bm,ownMember,{...proposal,savings:999});
await as(bm,()=>db.query(review,[staffRequest,'Approve','Verified against original ledger as BM']));
assert.equal((await db.query('select count(*)::int n from public.occci_financials where member_id=any($1::uuid[])',[[member,ownMember]])).rows[0].n,0,'Nothing is published at BM screening');
for(const id of [admin,bs,bc,bm,foreignDM])await reject(id,review,[staffRequest,'Approve','Unauthorized final review'],/assigned branch|BM screening/);
// The same recorded BM is now the only DM for this district.
await assign(dm,{role:'Staff',branch_id:'BR-02'});await assign(bm,{role:'DM',district:1});
assert.equal((await db.query("select count(*)::int n from public.occci_staff_assignments where role='DM' and district=1")).rows[0].n,1);
await reject(dm,review,[staffRequest,'Approve','Former DM account no longer authorized'],/assigned branch|BM screening/);
await as(bm,()=>db.query(review,[staffRequest,'Approve','Final approval as current district DM']));
await as(bm,()=>db.query(review,[ownRequest,'Approve','Final approval of own historical BM submission']));
for(const [request,target] of [[staffRequest,member],[ownRequest,ownMember]]){
 const q=(await db.query('select * from public.occci_change_requests where id=$1',[request])).rows[0],f=(await db.query('select * from public.occci_financials where member_id=$1',[target])).rows[0];
 assert.equal(q.status,'Applied');assert.equal(q.bm_reviewer,bm);assert.equal(q.dm_reviewer,bm);assert.equal(q.admin_reviewer,null);assert.equal(Number(f.savings),20000);assert.equal(f.revision,1);assert.equal(f.evidence_files.length,1);
}
const history=(await db.query("select actor,actor_role,action from public.occci_audit where after_data->>'request_id'=$1 order by created_at",[staffRequest])).rows;
assert(history.some(a=>a.actor===bm&&a.actor_role==='BM'&&a.action==='Request reviewed'));
assert(history.some(a=>a.actor===bm&&a.actor_role==='DM'&&a.action==='Request reviewed'));
assert(history.some(a=>a.actor===bs&&a.action==='Request submitted'));
await as(bm,()=>db.query(review,[ownReject,'Reject','Reject historical submission after final district review']));assert.equal((await db.query('select status from public.occci_change_requests where id=$1',[ownReject])).rows[0].status,'Rejected');
assert.equal(Number((await db.query('select savings from public.occci_financials where member_id=$1',[ownMember])).rows[0].savings),20000);
await reject(bm,review,[staffRequest,'Approve','Duplicate final review'],/BM screening/);
const pending=await submit(bs,member);
await reject(bm,review,[pending,'Approve','DM cannot skip BM screening'],/BM screening/);
await db.query("update public.occci_change_requests set status='BM approved',bm_reviewer=null where id=$1",[pending]);
await reject(bm,review,[pending,'Approve','Missing recorded screening'],/BM screening/);
assert.equal((await db.query('select revision from public.occci_financials where member_id=$1',[member])).rows[0].revision,1);
// Branch restrictions, unchanged records, and separate profile/member reviewers still apply.
await db.query("update public.occci_change_requests set status='Pending' where id=$1",[pending]);await assign(extra,{role:'BM',branch_id:'BR-01'});
await as(extra,()=>db.query(review,[pending,'Approve','New branch manager screens the update']));await db.query('update public.occci_financials set revision=revision+1 where member_id=$1',[member]);
await reject(bm,review,[pending,'Approve','Stale finance update'],/Financial record changed/);assert.equal((await db.query('select status from public.occci_change_requests where id=$1',[pending])).rows[0].status,'BM approved');
const edit=(await as(bm,()=>db.query("select public.occci_submit_change($1,'Profile edit',$2,null,$3) id",[member,{permission_only:true},'Profile correction request as DM']))).rows[0].id;
await reject(bm,review,[edit,'Approve','Self profile review remains blocked'],/different authorized/);
await as(extra,()=>db.query('select public.occci_approve_member($1,$2,$3)',[newMember,'MEM-013','Branch screening of new member']));
const memberRequest=(await db.query("select id from public.occci_change_requests where member_id=$1 and kind='Membership approval'",[newMember])).rows[0].id;
await as(bm,()=>db.query(review,[memberRequest,'Approve','Current DM approves separate BM screening']));assert.equal((await db.query('select membership_status from public.occci_profiles where id=$1',[newMember])).rows[0].membership_status,'Active');
await db.query("insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,status,bm_reviewer,note) values($1,'BR-01','Membership approval',$2,0,$3,'BM approved',$3,'Historic same-user membership screening')",[newMember,{account_number:'MEM-OTHER'},bm]);
const sameMember=(await db.query("select id from public.occci_change_requests where member_id=$1 and note='Historic same-user membership screening'",[newMember])).rows[0].id;await reject(bm,review,[sameMember,'Approve','Membership self review remains blocked'],/different authorized/);
assert.equal((await as(foreignDM,()=>db.query('select count(*)::int n from public.occci_financials where member_id=$1',[member]))).rows[0].n,0);
assert.equal((await as(bs,()=>db.query('select count(*)::int n from public.occci_financials where member_id=$1',[foreignMember]))).rows[0].n,0);
const before=(await db.query('select count(*)::int n from public.occci_audit')).rows[0].n;await db.exec(migration);assert.equal((await db.query('select count(*)::int n from public.occci_audit')).rows[0].n,before);
const fresh=new PGlite();await fresh.exec(bootstrap);await fresh.exec(fs.readFileSync('supabase/install.sql','utf8'));
const indexes=(await fresh.query("select count(*)::int n from pg_index where indexrelid in ('public.occci_one_dm_per_district'::regclass,'public.occci_one_bm_per_branch'::regclass) and indisunique and indisvalid")).rows[0].n;assert.equal(indexes,2,'Fresh installer creates both manager limits');
await db.exec(fs.readFileSync('supabase/migrations/014_member_dashboard_cashier.sql','utf8'));
const procedures="select proname,prosrc from pg_proc where oid in ('public.occci_review_change(uuid,text,text)'::regprocedure,'public.occci_begin_position_confirmation(text,uuid,jsonb)'::regprocedure,'public.occci_require_manager_slot(uuid,jsonb)'::regprocedure) order by proname";assert.deepEqual((await fresh.query(procedures)).rows,(await db.query(procedures)).rows,'Fresh install and upgraded database use the same current procedures');
assert.equal((await fresh.query("select has_function_privilege('authenticated','public.occci_require_manager_slot(uuid,jsonb)','execute') allowed")).rows[0].allowed,false);await fresh.close();
console.log('PASS: duplicate-manager upgrade safety, unique positions across all writes, vacancy and same-account assignment, password-gated transfers, staff-approval race rollback, one assigned DM finalizing its historical BM screening/submission, retained stage audits and documents, no premature financial publication, role/district checks, replay/stale/missing-screening denial, separate profile and membership reviewers, idempotent migration and executed fresh installer.');await db.close();
