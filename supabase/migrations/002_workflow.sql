-- Apply AFTER supabase/setup.sql. Supabase SQL Editor; transactional and repeatable.
begin;
alter table public.occci_branches add column if not exists active boolean not null default true;
alter table public.occci_profiles add column if not exists last_name text not null default '';
alter table public.occci_profiles add column if not exists first_name text not null default '';
alter table public.occci_profiles add column if not exists middle_name text not null default '';
alter table public.occci_profiles add column if not exists contact_number text not null default '';
alter table public.occci_profiles add column if not exists address text not null default '';
alter table public.occci_profiles add column if not exists account_number text unique;
alter table public.occci_profiles add column if not exists photo_path text;
alter table public.occci_profiles add column if not exists revision integer not null default 0;
alter table public.occci_profiles add column if not exists archived_at timestamptz;
alter table public.occci_staff_assignments add column if not exists district smallint;
alter table public.occci_staff_assignments alter column branch_id drop not null;
alter table public.occci_staff_assignments drop constraint if exists occci_staff_assignments_role_check;
-- Preserve least privilege: old branch Admin -> BM; old network Admin Head -> Admin.
create table if not exists public.occci_schema_versions(version text primary key);
alter table public.occci_schema_versions enable row level security;
revoke all on public.occci_schema_versions from public,anon,authenticated;
do $$ begin
 if not exists(select 1 from public.occci_schema_versions where version='002_workflow') then
 update public.occci_staff_assignments set role=case role when 'Admin' then 'BM' when 'Admin Head' then 'Admin' else role end where role in ('Admin','Admin Head');
 insert into public.occci_schema_versions values('002_workflow');
 end if;
end;$$;
alter table public.occci_staff_assignments add constraint occci_staff_assignments_role_check check(role in ('Admin','DM','BM','Staff'));
alter table public.occci_staff_assignments drop constraint if exists occci_assignment_scope;
alter table public.occci_staff_assignments add constraint occci_assignment_scope check((role='Admin') or (role='DM' and district is not null and district between 1 and 6) or (role in ('BM','Staff') and branch_id is not null));
create table if not exists public.occci_audit(
 id bigint generated always as identity primary key, actor uuid references auth.users(id), member_id uuid references public.occci_profiles(id), branch_id text references public.occci_branches(id),
 action text not null, before_data jsonb, after_data jsonb, note text not null default '', created_at timestamptz not null default now());
create table if not exists public.occci_financials(
 member_id uuid primary key references public.occci_profiles(id), savings numeric(16,2) not null default 0 check(savings>=0), loan_balance numeric(16,2) not null default 0 check(loan_balance>=0),
 loan_status text not null default 'No active loan' check(loan_status in ('No active loan','Active','Paid','Overdue','Restructured')), annual_interest numeric(6,3) not null default 0 check(annual_interest between 0 and 100),
 schedule jsonb not null default '[]' check(jsonb_typeof(schedule)='array'), source_reference text not null, evidence_path text not null, as_of date not null, revision integer not null default 1, updated_at timestamptz not null default now());
create table if not exists public.occci_change_requests(
 id uuid primary key default gen_random_uuid(), member_id uuid not null references public.occci_profiles(id), branch_id text not null references public.occci_branches(id), kind text not null check(kind in ('Profile edit','Financial sync')),
 proposed jsonb not null, base_revision integer not null, submitted_by uuid not null references auth.users(id), status text not null default 'Pending' check(status in ('Pending','BM approved','DM approved','Applied','Rejected','Cancelled')),
 bm_reviewer uuid references auth.users(id), dm_reviewer uuid references auth.users(id), admin_reviewer uuid references auth.users(id), evidence_path text, note text not null, review_note text, created_at timestamptz not null default now(), reviewed_at timestamptz);
create table if not exists public.occci_content(
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('Announcement','Event','Service')), title text not null check(length(title) between 1 and 150), body text not null,
 branch_id text references public.occci_branches(id), district smallint check(district between 1 and 6), event_date date, published boolean not null default true, created_by uuid references auth.users(id), updated_at timestamptz not null default now(), archived_at timestamptz);
create index if not exists occci_profile_branch_idx on public.occci_profiles(branch_id);
create index if not exists occci_request_branch_idx on public.occci_change_requests(branch_id,status);
create index if not exists occci_audit_member_idx on public.occci_audit(member_id,created_at);
create or replace function public.occci_role() returns text language sql stable security definer set search_path='' as $$ select coalesce((select role from public.occci_staff_assignments where user_id=auth.uid()),'Member'); $$;
create or replace function public.occci_district() returns smallint language sql stable security definer set search_path='' as $$ select district from public.occci_staff_assignments where user_id=auth.uid(); $$;
create or replace function public.occci_can_read_branch(target_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s left join public.occci_branches b on b.id=target_branch where s.user_id=auth.uid() and (s.role='Admin' or (s.role='DM' and s.district=b.district) or (s.role in ('BM','Staff') and s.branch_id=target_branch)));
$$;
create or replace function public.occci_log(target uuid,branch text,action_name text,previous jsonb,new_data jsonb,reason text) returns void language sql security definer set search_path='' as $$
 insert into public.occci_audit(actor,member_id,branch_id,action,before_data,after_data,note) values(auth.uid(),target,branch,action_name,previous,new_data,reason);
$$;
create or replace function public.occci_handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; fullname_value text;
begin
 if not exists(select 1 from public.occci_branches where id=meta->>'branch_id' and active) or coalesce(length(trim(meta->>'first_name')),0) not between 1 and 50 or coalesce(length(trim(meta->>'last_name')),0) not between 1 and 50 or coalesce(length(meta->>'middle_name'),0)>50 or coalesce(length(trim(meta->>'contact_number')),0) not between 7 and 30 or coalesce(length(trim(meta->>'address')),0) not between 5 and 500 then raise exception 'Complete the required member details and choose an active branch';end if;
 fullname_value:=trim(concat_ws(' ',nullif(meta->>'first_name',''),nullif(meta->>'middle_name',''),nullif(meta->>'last_name','')));
 insert into public.occci_profiles(id,full_name,branch_id,avatar,last_name,first_name,middle_name,contact_number,address)
 values(new.id,coalesce(nullif(left(fullname_value,100),''),nullif(left(meta->>'full_name',100),''),'Member'),
 meta->>'branch_id',
 case when meta->>'avatar' in ('man','farmer','lady','lola','boy','girl') then meta->>'avatar' else 'lady' end,
 left(coalesce(meta->>'last_name',''),50),left(coalesce(meta->>'first_name',''),50),left(coalesce(meta->>'middle_name',''),50),left(coalesce(meta->>'contact_number',''),30),left(coalesce(meta->>'address',''),500));
 return new;
end;$$;
-- Restrict all table writes to validated RPCs below.
revoke all on public.occci_profiles,public.occci_staff_assignments,public.occci_financials,public.occci_change_requests,public.occci_content,public.occci_audit from anon,authenticated;
grant select on public.occci_profiles,public.occci_staff_assignments,public.occci_financials,public.occci_change_requests,public.occci_content,public.occci_audit to authenticated;
alter table public.occci_financials enable row level security;
alter table public.occci_change_requests enable row level security;
alter table public.occci_content enable row level security;
alter table public.occci_audit enable row level security;
drop policy if exists occci_fin_read on public.occci_financials;
create policy occci_fin_read on public.occci_financials for select to authenticated using(member_id=auth.uid() or exists(select 1 from public.occci_profiles p where p.id=member_id and public.occci_can_read_branch(p.branch_id)));
drop policy if exists occci_request_read on public.occci_change_requests;
create policy occci_request_read on public.occci_change_requests for select to authenticated using(member_id=auth.uid() or public.occci_can_read_branch(branch_id));
drop policy if exists occci_audit_read on public.occci_audit;
create policy occci_audit_read on public.occci_audit for select to authenticated using(member_id=auth.uid() or public.occci_role()='Admin' or public.occci_can_read_branch(branch_id));
drop policy if exists occci_content_read on public.occci_content;
create policy occci_content_read on public.occci_content for select to authenticated using(public.occci_role()='Admin' or public.occci_can_read_branch(branch_id) or (published and archived_at is null and exists(select 1 from public.occci_profiles p join public.occci_branches b on b.id=p.branch_id where p.id=auth.uid() and (occci_content.branch_id is null or occci_content.branch_id=p.branch_id) and (occci_content.district is null or occci_content.district=b.district))) or (public.occci_role()='DM' and branch_id is null and district=public.occci_district()));
drop policy if exists occci_staff_self_read on public.occci_staff_assignments;
create policy occci_staff_self_read on public.occci_staff_assignments for select to authenticated using(user_id=auth.uid() or public.occci_role()='Admin' or public.occci_can_read_branch(branch_id) or (public.occci_role()='DM' and district=public.occci_district()));
create or replace function public.occci_approve_member(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role();
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','BM','Staff') then raise exception 'Membership approval is not permitted in this branch'; end if;
 if p.membership_status<>'Pending verification' or p.archived_at is not null then raise exception 'This membership is not pending'; end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid unique account number and approval note'; end if;
 update public.occci_profiles set membership_status='Active',account_number=trim(account),revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Membership approved',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',trim(account)),reason);
end;$$;
create or replace function public.occci_profile_values(target uuid,values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare fn text; ln text; mn text; contact text; addr text; status_value text; avatar_value text;
begin
 fn:=trim(values_json->>'first_name'); ln:=trim(values_json->>'last_name');mn:=trim(coalesce(values_json->>'middle_name',''));contact:=trim(values_json->>'contact_number');addr:=trim(values_json->>'address');status_value:=values_json->>'membership_status';avatar_value:=values_json->>'avatar';
 if coalesce(length(fn),0) not between 1 and 50 or coalesce(length(ln),0) not between 1 and 50 or length(mn)>50 or coalesce(length(contact),0) not between 7 and 30 or coalesce(length(addr),0) not between 5 and 500 or status_value is null or status_value not in ('Active','Suspended','Pending verification') or avatar_value is null or avatar_value not in ('man','farmer','lady','lola','boy','girl') then raise exception 'Invalid member details'; end if;
 if status_value='Active' and not exists(select 1 from public.occci_profiles where id=target and account_number is not null) then raise exception 'Approve membership and assign an account number first';end if;
 update public.occci_profiles set first_name=fn,last_name=ln,middle_name=mn,full_name=left(trim(concat_ws(' ',fn,nullif(mn,''),ln)),100),contact_number=contact,address=addr,membership_status=status_value,avatar=avatar_value,revision=revision+1 where id=target;
end;$$;
create or replace function public.occci_submit_change(target uuid,request_kind text,values_json jsonb,evidence text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role(); request_id uuid; rev integer; item jsonb;
begin
 select * into p from public.occci_profiles where id=target;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM','Staff') or p.archived_at is not null then raise exception 'Request is not permitted';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a request note';end if;
 if request_kind='Profile edit' then rev:=p.revision;
 elsif request_kind='Financial sync' then
 if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates'; end if;
 if coalesce(evidence,'') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-documents' and name=evidence) then raise exception 'Upload a source document first';end if;
 if lower(coalesce(values_json->>'savings','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'loan_balance','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'annual_interest','')) in ('nan','infinity','-infinity') then raise exception 'Finite financial amounts are required';end if;
 if coalesce(values_json->>'source_reference','')='' or (values_json->>'as_of')::date is null or (values_json->>'savings')::numeric<0 or (values_json->>'loan_balance')::numeric<0 or (values_json->>'annual_interest')::numeric not between 0 and 100 or values_json->>'loan_status' is null or values_json->>'loan_status' not in ('No active loan','Active','Paid','Overdue','Restructured') or coalesce(jsonb_typeof(values_json->'schedule'),'')<>'array' then raise exception 'Invalid financial details'; end if;
 if values_json->>'savings' is null or values_json->>'loan_balance' is null or values_json->>'annual_interest' is null then raise exception 'Financial amounts are required';end if;
 for item in select * from jsonb_array_elements(values_json->'schedule') loop
 if lower(coalesce(item->>'amount','')) in ('nan','infinity','-infinity') then raise exception 'Invalid payment schedule';end if;
 if (item->>'date')::date is null or item->>'amount' is null or (item->>'amount')::numeric<0 then raise exception 'Invalid payment schedule';end if;
 end loop;
 select coalesce((select revision from public.occci_financials where member_id=target),0) into rev;
 else raise exception 'Invalid request type';end if;
 insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,evidence_path,note) values(target,p.branch_id,request_kind,values_json,rev,auth.uid(),evidence,reason) returning id into request_id;
 perform public.occci_log(target,p.branch_id,'Request submitted',null,jsonb_build_object('request_id',request_id,'kind',request_kind,'proposed',values_json),reason);
 return request_id;
end;$$;
create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) or q.submitted_by=auth.uid() then raise exception 'Review requires a different authorized reviewer';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a review note';end if;
 if q.kind='Profile edit' then
 if r not in ('BM','Admin') or q.status<>'Pending' then raise exception 'Profile edits require branch manager approval';end if;
 if decision is null or decision not in ('Approve','Reject') then raise exception 'Invalid decision';end if;
 target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
 update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=reason,reviewed_at=now() where id=request_id;
 else
 if decision is null or decision not in ('Approve','Reject') then raise exception 'Invalid decision';end if;
 if q.status='Pending' and r='DM' then
 target_status:=case decision when 'Approve' then 'DM approved' else 'Rejected' end;
 update public.occci_change_requests set status=target_status,dm_reviewer=auth.uid(),review_note=reason,reviewed_at=now() where id=request_id;
 elsif q.status='DM approved' and r='Admin' then
 if q.dm_reviewer=auth.uid() then raise exception 'DM and Admin approvals must be separate';end if;
 target_status:=case decision when 'Approve' then 'Applied' else 'Rejected' end;
 if decision='Approve' then
 -- Serialize on member row, including first-ever snapshot (no financial row yet).
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.membership_status<>'Active' or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member scope/status changed; submit a new request';end if;
 select * into f from public.occci_financials where member_id=q.member_id;
 if coalesce(f.revision,0)<>q.base_revision then raise exception 'Financial record changed; submit a new request';end if;
 v:=q.proposed;
 insert into public.occci_financials(member_id,savings,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,as_of,revision)
 values(q.member_id,(v->>'savings')::numeric,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,(v->>'as_of')::date,q.base_revision+1)
 on conflict(member_id) do update set savings=excluded.savings,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
 perform public.occci_log(q.member_id,q.branch_id,'Financial record synchronized',to_jsonb(f),v,reason);
 end if;
 update public.occci_change_requests set status=target_status,admin_reviewer=auth.uid(),review_note=reason,reviewed_at=now() where id=request_id;
 else raise exception 'Financial sync requires DM review, then Admin approval';end if;
 end if;
 perform public.occci_log(q.member_id,q.branch_id,'Request reviewed',jsonb_build_object('status',q.status),jsonb_build_object('request_id',request_id,'status',target_status),reason);
end;$$;
create or replace function public.occci_apply_edit(request_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; p public.occci_profiles;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or q.kind<>'Profile edit' or q.status<>'BM approved' or q.submitted_by<>auth.uid() or not public.occci_can_read_branch(q.branch_id) or public.occci_role() not in ('Staff','BM','DM','Admin') then raise exception 'Only the requesting staff member can apply this approved edit';end if;
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.revision<>q.base_revision or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member details changed; submit a new edit request';end if;
 perform public.occci_profile_values(q.member_id,q.proposed);
 update public.occci_change_requests set status='Applied',reviewed_at=now() where id=request_id;
 perform public.occci_log(q.member_id,q.branch_id,'Approved member edit applied',to_jsonb(p),q.proposed,q.note);
end;$$;
create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
declare r text:=public.occci_role(); p public.occci_profiles; c public.occci_content; b public.occci_branches; target_branch text; target_district smallint; previous jsonb; uid uuid;
begin
 if coalesce(length(trim(reason)),0)<3 then raise exception 'A reason is required for every change';end if;
 if record_kind='Member' then
 select * into p from public.occci_profiles where id=record_id::uuid for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','BM') then raise exception 'Staff must request BM approval before changing member details';end if;
 if remove_record then
 if r<>'Admin' then raise exception 'Only Admin can archive a member';end if;
 update public.occci_profiles set archived_at=now(),revision=revision+1 where id=p.id;
 else perform public.occci_profile_values(p.id,values_json);end if;
 perform public.occci_log(p.id,p.branch_id,case when remove_record then 'Member archived' else 'Member edited' end,to_jsonb(p),values_json,reason);
 elsif record_kind='Content' then
 if r not in ('Admin','DM','BM') then raise exception 'Content management is not permitted';end if;
 if record_id<>'' then select * into c from public.occci_content where id=record_id::uuid for update; if not found then raise exception 'Content not found';end if;previous:=to_jsonb(c);end if;
 target_branch:=nullif(values_json->>'branch_id','');target_district:=nullif(values_json->>'district','')::smallint;
 if r<>'Admin' then
 if record_id<>'' and not ((c.branch_id is not null and public.occci_can_read_branch(c.branch_id)) or (r='DM' and c.branch_id is null and c.district=(select district from public.occci_staff_assignments where user_id=auth.uid()))) then raise exception 'Content is outside your scope';end if;
 if not ((target_branch is not null and public.occci_can_read_branch(target_branch)) or (r='DM' and target_branch is null and target_district=(select district from public.occci_staff_assignments where user_id=auth.uid()))) then raise exception 'Choose content scope within your assignment';end if;
 end if;
 if remove_record then update public.occci_content set archived_at=now(),updated_at=now() where id=c.id;
 else
 if coalesce(length(trim(values_json->>'title')),0) not between 1 and 150 or coalesce(length(trim(values_json->>'body')),0)=0 then raise exception 'Title and content are required';end if;
 insert into public.occci_content(id,kind,title,body,branch_id,district,event_date,published,created_by)
 values(coalesce(c.id,gen_random_uuid()),values_json->>'kind',trim(values_json->>'title'),values_json->>'body',target_branch,target_district,nullif(values_json->>'event_date','')::date,(values_json->>'published')::boolean,auth.uid())
 on conflict(id) do update set kind=excluded.kind,title=excluded.title,body=excluded.body,branch_id=excluded.branch_id,district=excluded.district,event_date=excluded.event_date,published=excluded.published,updated_at=now() returning id into uid;
 end if;
 perform public.occci_log(null,coalesce(target_branch,c.branch_id),'Content changed',previous,values_json,reason);
 elsif record_kind='Branch' then
 if r<>'Admin' then raise exception 'Only Admin can manage branches';end if;
 if record_id is null or record_id !~ '^[A-Za-z0-9_-]{2,40}$' then raise exception 'Invalid branch reference';end if;
 select * into b from public.occci_branches where id=record_id for update;
 if remove_record then update public.occci_branches set active=false where id=record_id;
 else insert into public.occci_branches(id,name,district,active) values(record_id,trim(values_json->>'name'),(values_json->>'district')::smallint,true) on conflict(id) do update set name=excluded.name,district=excluded.district,active=true;end if;
 perform public.occci_log(null,record_id,'Branch changed',to_jsonb(b),values_json,reason);
 elsif record_kind='Team' then
 if r<>'Admin' then raise exception 'Only Admin can assign roles';end if;
 if record_id=auth.uid()::text then raise exception 'An administrator cannot change their own assignment';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=record_id::uuid;
 if remove_record then delete from public.occci_staff_assignments where user_id=record_id::uuid;
 else
 if not exists(select 1 from public.occci_profiles where id=record_id::uuid and archived_at is null) then raise exception 'Choose an existing member account';end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(record_id::uuid,values_json->>'role',nullif(values_json->>'branch_id',''),nullif(values_json->>'district','')::smallint) on conflict(user_id) do update set role=excluded.role,branch_id=excluded.branch_id,district=excluded.district;
 end if;
 perform public.occci_log(record_id::uuid,null,'Team assignment changed',previous,values_json,reason);
 else raise exception 'Unknown record type';end if;
end;$$;
create or replace function public.occci_set_photo(photo text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles;
begin
 if photo is not null and (photo not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-avatars' and name=photo)) then raise exception 'Photo must belong to your account';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found then raise exception 'Profile not found';end if;
 update public.occci_profiles set photo_path=photo,revision=revision+1 where id=auth.uid();
 perform public.occci_log(auth.uid(),p.branch_id,'Profile photo updated',jsonb_build_object('photo_path',p.photo_path),jsonb_build_object('photo_path',photo),'Member profile photo');
end;$$;
-- Private storage: immutable source documents, owner-controlled profile photos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('occci-documents','occci-documents',false,10485760,array['application/pdf','image/jpeg','image/png']),('occci-avatars','occci-avatars',false,5242880,array['image/jpeg','image/png']) on conflict(id) do nothing;
drop policy if exists occci_document_insert on storage.objects;
create policy occci_document_insert on storage.objects for insert to authenticated with check(bucket_id='occci-documents' and (storage.foldername(name))[1]=auth.uid()::text and public.occci_role() in ('Staff','BM','DM','Admin'));
drop policy if exists occci_document_read on storage.objects;
create policy occci_document_read on storage.objects for select to authenticated using(bucket_id='occci-documents' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_change_requests q where q.evidence_path=name and public.occci_can_read_branch(q.branch_id))));
drop policy if exists occci_avatar_insert on storage.objects;
create policy occci_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='occci-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists occci_avatar_read on storage.objects;
create policy occci_avatar_read on storage.objects for select to authenticated using(bucket_id='occci-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_profiles p where p.photo_path=name and public.occci_can_read_branch(p.branch_id))));
-- Explicit RPC allowlist; internal mutators are not callable by clients.
revoke all on function public.occci_log(uuid,text,text,jsonb,jsonb,text),public.occci_profile_values(uuid,jsonb),public.occci_handle_signup() from public,anon,authenticated;
revoke all on function public.occci_role(),public.occci_district(),public.occci_approve_member(uuid,text,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text),public.occci_apply_edit(uuid),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_set_photo(text) from public,anon,authenticated;
grant execute on function public.occci_role(),public.occci_district(),public.occci_approve_member(uuid,text,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text),public.occci_apply_edit(uuid),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_set_photo(text) to authenticated;
commit;
