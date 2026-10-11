import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const bootstrap=`create role anon;create role authenticated;create schema auth;create schema storage;
create table auth.users(id uuid primary key,raw_user_meta_data jsonb,raw_app_meta_data jsonb default '{}',email text,email_confirmed_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
grant usage on schema auth,storage,public to authenticated,anon;grant execute on function auth.uid(),storage.foldername(text) to authenticated,anon;grant select,insert on storage.objects to authenticated;`;
const db=new PGlite();await db.exec(bootstrap);
const prior=['supabase/setup.sql',...fs.readdirSync('supabase/migrations').filter(n=>/^0(0[2-9]|1[0-3])_/.test(n)).sort().map(n=>'supabase/migrations/'+n)];
for(const path of prior)await db.exec(fs.readFileSync(path,'utf8'));
const ids=Array.from({length:13},(_,i)=>`a0000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const [admin,dm,bm,bs,bc,bc2,member,unknown,foreign,newMember,noRecord,archived,otherMember]=ids;
for(const id of ids){const branch=[bc2,foreign].includes(id)?'BR-11':'BR-01';await db.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,id+'@example.invalid',{first_name:'Fixture',last_name:id.slice(-3),contact_number:'09123456789',address:'Fixture address, Leyte',avatar:'man',branch_id:branch}]);}
await db.query(`insert into public.occci_staff_assignments(user_id,role,branch_id,district) values($1,'Admin',null,null),($2,'DM',null,1),($3,'BM','BR-01',null),($4,'Staff','BR-01',null),($5,'BC','BR-01',null),($6,'BC','BR-11',null)`,[admin,dm,bm,bs,bc,bc2]);
await db.query("update public.occci_profiles set membership_status='Active',account_number='ACC-'||right(id::text,3),onboarding_complete=true where id<>$1",[newMember]);
await db.query("insert into public.occci_financials(member_id,savings,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision) values($1,10000,5000,'Active',12,'[]','Legacy ledger','fixture/original.pdf','[]','2026-10-11',1),($2,2000,600,'Active',12,'[]','Legacy unknown capital','fixture/original.pdf','[]','2026-10-11',1)",[member,unknown]);
const migration=fs.readFileSync('supabase/migrations/014_member_dashboard_cashier.sql','utf8');await db.exec(migration);await db.exec(migration);
assert.equal((await db.query('select share_capital from public.occci_financials where member_id=$1',[member])).rows[0].share_capital,null,'Legacy capital must remain unknown, not fabricated zero');
async function as(id,fn){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,session_id:'11111111-1111-4111-8111-111111111111',amr:[{method:'oauth',timestamp:0}]})]);await db.exec('set role authenticated');try{return await fn();}finally{await db.exec('reset role');}}
const review='select public.occci_review_change($1,$2,$3)',submit='select public.occci_submit_financial_documents($1,$2,$3,$4) id',post='select public.occci_record_cashier_payment($1,$2,$3,$4,$5) receipt';
const docs=[{path:bs+'/ledger.pdf',name:'ledger.pdf',size:1024}];await db.query("insert into storage.objects(bucket_id,name) values('occci-documents',$1)",[docs[0].path]);
const financial={savings:10000,share_capital:2000,loan_balance:5000,loan_status:'Active',annual_interest:12,source_reference:'Verified fixture ledger',as_of:'2026-10-11',schedule:[{date:'2026-11-15',amount:1100,status:'Scheduled'},{date:'2026-12-15',amount:1100,status:'Scheduled'}]};
async function submitAndScreen(values,target=member){const id=(await as(bs,()=>db.query(submit,[target,values,docs,'Original balance verification']))).rows[0].id;await as(bm,()=>db.query(review,[id,'Approve','Branch document screening']));return id;}
const initial=await submitAndScreen(financial);assert.equal((await db.query('select share_capital from public.occci_financials where member_id=$1',[member])).rows[0].share_capital,null);await as(dm,()=>db.query(review,[initial,'Approve','District document verification']));
let f=(await db.query('select * from public.occci_financials where member_id=$1',[member])).rows[0];assert.equal(Number(f.share_capital),2000);assert.equal(f.revision,2);assert.equal(f.evidence_files[0].name,'ledger.pdf');
let sequence=100;const reference=()=>`b0000000-0000-4000-8000-${String(sequence++).padStart(12,'0')}`;
const value=(receipt,extra={})=>({receipt_number:receipt,payment_date:'2026-10-11',principal_amount:0,interest_amount:0,fees_amount:0,savings_amount:0,share_capital_amount:0,schedule_index:null,...extra});
const balance=async(target=member)=>(await db.query('select * from public.occci_financials where member_id=$1',[target])).rows[0];
const count=async()=>(await db.query('select count(*)::int n from public.occci_cashier_payments')).rows[0].n;
const note='Receipt checked against branch cashbook';
const record=async(user,target,values,rev,ref=reference())=>(await as(user,()=>db.query(post,[target,values,rev,ref,note]))).rows[0].receipt;
async function reject(user,target,values,rev,pattern,ref=reference()){const before=await count(),previous=JSON.stringify(await balance(target));await assert.rejects(record(user,target,values,rev,ref),pattern);assert.equal(await count(),before);assert.equal(JSON.stringify(await balance(target)),previous,'Rejected posting must leave balances unchanged');}
const firstValues=value('OR-001',{principal_amount:1000,interest_amount:100,fees_amount:20,savings_amount:500,share_capital_amount:100,schedule_index:0}),firstReference=reference();
const first=await record(bc,member,firstValues,2,firstReference);assert.equal(Number(first.total_amount),1720);assert.equal(first.cashier_id,bc);assert.equal(Number(first.loan_balance_before),5000);assert.equal(Number(first.loan_balance_after),4000);
f=await balance();assert.equal(Number(f.loan_balance),4000);assert.equal(Number(f.savings),10500);assert.equal(Number(f.share_capital),2100);assert.equal(f.revision,3);assert.equal(f.schedule[0].status,'Paid');assert.equal(f.schedule[0].paid_amount,1100);assert.equal(f.evidence_files[0].name,'ledger.pdf');
const audits=(await db.query("select * from public.occci_audit where action='Cashier payment posted'")).rows;assert.equal(audits.length,1);assert.equal(audits[0].actor_role,'BC');assert(audits[0].subject_name);assert.equal(audits[0].after_data.receipt_number,'OR-001');assert.equal(audits[0].after_data.principal_amount,1000);
const again=await record(bc,member,firstValues,2,firstReference);assert.equal(again.id,first.id);assert.equal(await count(),1);assert.equal((await balance()).revision,3);assert.equal((await db.query("select count(*)::int n from public.occci_audit where action='Cashier payment posted'")).rows[0].n,1);
await reject(bc,member,{...firstValues,principal_amount:900},3,/different details/,firstReference);
await reject(bc,member,value('or-001',{principal_amount:10}),3,/already recorded/);
await reject(bc,member,value('OR-stale',{principal_amount:10}),2,/balance changed/);
await reject(bc,member,value('OR-over',{principal_amount:4000.01}),3,/outstanding loan/);
await reject(bc,member,value('OR-paid',{principal_amount:1,schedule_index:0}),3,/already paid/);
await reject(bc,member,value('OR-installment',{principal_amount:1000,interest_amount:101,schedule_index:1}),3,/remaining installment/);
const partial=await record(bc,member,value('OR-002',{principal_amount:500,interest_amount:50,schedule_index:1}),3);assert.equal(Number(partial.total_amount),550);f=await balance();assert.equal(Number(f.loan_balance),3500);assert.equal(f.schedule[1].paid_amount,550);assert.equal(f.schedule[1].status,'Scheduled');assert.equal(f.revision,4);
const interestOnly=await record(bc,member,value('OR-interest',{interest_amount:25,fees_amount:5}),4);assert.equal(Number(interestOnly.loan_balance_after),3500);assert.equal((await balance()).revision,5);
await reject(bc,unknown,value('OR-unknown-capital',{share_capital_amount:100}),1,/opening share capital/);
const unknownReceipt=await record(bc,unknown,value('OR-unknown-principal',{principal_amount:100}),1);assert.equal(unknownReceipt.share_capital_after,null);assert.equal((await balance(unknown)).share_capital,null);assert.equal(Number((await balance(unknown)).loan_balance),500);
for(const roleUser of [admin,dm,bm,bs,member])await reject(roleUser,member,value('OR-role-'+roleUser.slice(-3),{principal_amount:1}),5,/Only the assigned Branch Cashier/);
await reject(bc2,member,value('OR-foreign',{principal_amount:1}),5,/assigned branch/);
await reject(bc,newMember,value('OR-new',{savings_amount:1}),0,/approved cooperative member/);
await reject(bc,bc,value('OR-staff',{savings_amount:1}),0,/approved cooperative member/);
await reject(bc,noRecord,value('OR-no-record',{savings_amount:1}),0,/DM-verified/);
await db.query('update public.occci_profiles set archived_at=now() where id=$1',[archived]);await reject(bc,archived,value('OR-archived',{savings_amount:1}),0,/approved cooperative member/);
for(const [label,extra,pattern] of [['negative',{principal_amount:-1},/nonnegative/],['nan',{principal_amount:'NaN'},/nonnegative/],['infinite',{interest_amount:'Infinity'},/nonnegative/],['decimals',{principal_amount:1.234},/two decimal/],['zero',{},/positive/],['invalid-index',{principal_amount:1,schedule_index:99},/unpaid installment/],['no-loan-schedule',{savings_amount:10,schedule_index:1},/unpaid installment/],['future',{principal_amount:1,payment_date:'2999-01-01'},/future/],['invalid-date',{principal_amount:1,payment_date:'2026-13-01'},/date/]])await reject(bc,member,value('OR-invalid-'+label,extra),5,pattern);
await reject(bc,member,value('OR-null-revision',{principal_amount:1}),null,/balance changed/);
// A pending document snapshot cannot overwrite a newer cashier transaction.
const stale=await submitAndScreen({...financial,share_capital:2100,savings:10500,loan_balance:3500,schedule:f.schedule});
await record(bc,member,value('OR-extra-principal',{principal_amount:250}),5);
await assert.rejects(as(dm,()=>db.query(review,[stale,'Approve','Reject stale financial snapshot'])),/Financial record changed/);assert.equal(Number((await balance()).loan_balance),3250);assert.equal((await db.query('select status from public.occci_change_requests where id=$1',[stale])).rows[0].status,'BM approved');
// Leaving capital blank preserves the verified balance; invalid additions fail before creating requests.
const refreshed={...financial,savings:10500,loan_balance:3250,schedule:(await balance()).schedule};delete refreshed.share_capital;
const replacement=await submitAndScreen(refreshed);await as(dm,()=>db.query(review,[replacement,'Approve','Verified current cashbook and ledger']));assert.equal(Number((await balance()).share_capital),2100);
for(const bad of [{...financial,share_capital:-1},{...financial,share_capital:'NaN'},{...financial,share_capital:0.123},{...financial,schedule:[{date:'2026-11-15',amount:100,paid_amount:101,status:'Scheduled'}]}])await assert.rejects(as(bs,()=>db.query(submit,[member,bad,docs,'Invalid balance rejected'])),/nonnegative|decimal|cannot exceed/);
// Final principal payoff, deposits and new capital contributions remain separate.
f=await balance();await record(bc,member,value('OR-payoff',{principal_amount:3250}),f.revision);f=await balance();assert.equal(Number(f.loan_balance),0);assert.equal(f.loan_status,'Paid');assert.equal(Number(f.share_capital),2100);
await record(bc,member,value('OR-deposit',{savings_amount:10,share_capital_amount:5}),f.revision);assert.equal(Number((await balance()).loan_balance),0);assert.equal(Number((await balance()).savings),10510);assert.equal(Number((await balance()).share_capital),2105);
// Seed a genuine foreign-branch cashier receipt to exercise all read scopes.
await db.query("insert into public.occci_financials(member_id,savings,share_capital,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,as_of,revision) values($1,100,50,10,'Active',0,'[]','Foreign verified ledger','fixture/original.pdf','2026-10-11',1)",[foreign]);await record(bc2,foreign,value('OR-foreign-valid',{principal_amount:1}),1);
for(const user of [dm,bm,bs,bc]){const rows=(await as(user,()=>db.query('select * from public.occci_cashier_payments'))).rows;assert(rows.length);assert(!rows.some(p=>p.member_id===foreign));}
const own=(await as(member,()=>db.query('select * from public.occci_cashier_payments'))).rows;assert(own.length);assert(own.every(p=>p.member_id===member));assert((await as(admin,()=>db.query('select * from public.occci_cashier_payments'))).rows.some(p=>p.member_id===foreign));
for(const command of ['update public.occci_cashier_payments set note=\'Tampered\'','delete from public.occci_cashier_payments','update public.occci_financials set loan_balance=0'])await assert.rejects(as(bc,()=>db.query(command)),/permission denied/);
for(const sql of ["select public.occci_cashier_amount('{}','principal_amount')","select public.occci_validate_financial_additions('{}')"])await assert.rejects(as(bc,()=>db.query(sql)),/permission denied/);
await db.exec('set role anon');await assert.rejects(db.query(post,[member,value('OR-anon',{savings_amount:1}),1,reference(),note]),/permission denied/);await db.exec('reset role');
const preserved=await count();await db.exec(migration);assert.equal(await count(),preserved);assert.equal((await db.query("select count(*)::int n from public.occci_schema_versions where version='014_member_dashboard_cashier'")).rows[0].n,1);
const fresh=new PGlite();await fresh.exec(bootstrap);await fresh.exec(fs.readFileSync('supabase/install.sql','utf8'));assert.equal((await fresh.query("select to_regclass('public.occci_cashier_payments') is not null ready")).rows[0].ready,true);assert.equal((await fresh.query("select count(*)::int n from public.occci_schema_versions where version='014_member_dashboard_cashier'")).rows[0].n,1);
await fresh.close();await db.close();
console.log('PASS: upgrade and fresh installer, verified/unknown capital, BM/DM baseline approval, principal-only deduction, separate interest/fees/deposits/capital, paid/partial schedules, exact retry idempotency, receipt uniqueness, stale/overpayment rejection, role and RLS isolation, retained documents/audit identity, stale sync protection, payoff and private helper permissions.');
