-- Run in the Supabase SQL Editor for project hlxcltqnlypptbykirzi.
begin;
create table if not exists public.occci_branches(id text primary key,name text not null,district smallint not null check(district between 1 and 6));
insert into public.occci_branches(id,name,district) values
('BR-02','Abuyog',1),
('BR-03','Albuera',1),
('BR-04','Bacolod',1),
('BR-05','Baybay',1),
('BR-06','Cebu',1),
('BR-07','Isabel',1),
('BR-08','Merida',1),
('BR-01','Ormoc',1),
('BR-09','Talisay',1),
('BR-10','San Francisco',1),
('BR-11','Alang-Alang',2),
('BR-12','Babatngon',2),
('BR-13','Calamba',2),
('BR-14','Lucena',2),
('BR-15','Pasay',2),
('BR-16','Tacloban',2),
('BR-17','Hilongos',3),
('BR-18','Inopacan',3),
('BR-19','Liloan',3),
('BR-20','Maasin',3),
('BR-21','San Juan',3),
('BR-22','Sogod',3),
('BR-23','Surigao',3),
('BR-24','Talibon',3),
('BR-25','Ubay',3),
('BR-26','Brooke''s Point',4),
('BR-27','Carigara',4),
('BR-28','Kananga',4),
('BR-29','Palompon',4),
('BR-30','Puerto Princesa',4),
('BR-31','Rio Tuba',4),
('BR-32','San Isidro',4),
('BR-33','Tabango',4),
('BR-34','Villaba',4),
('BR-35','Biliran',5),
('BR-36','Cabucgayan',5),
('BR-37','Caibiran',5),
('BR-38','Calubian',5),
('BR-39','Culaba',5),
('BR-40','Kalibo',5),
('BR-41','Kawayan',5),
('BR-42','Leyte',5),
('BR-43','Naval',5),
('BR-44','Allen',6),
('BR-45','Balangiga',6),
('BR-46','Borongan',6),
('BR-47','Calbayog',6),
('BR-48','Calbiga',6),
('BR-49','Catarman',6),
('BR-50','Catbalogan',6),
('BR-51','Dolores',6),
('BR-52','Guiuan',6) on conflict(id) do update set name=excluded.name,district=excluded.district;
create table if not exists public.occci_profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check(length(full_name) between 1 and 100),
 branch_id text not null references public.occci_branches(id),
 avatar text not null default 'lady' check(avatar in ('man','farmer','lady','lola','boy','girl')),
 membership_status text not null default 'Pending verification' check(membership_status in ('Pending verification','Active','Suspended')),
 created_at timestamptz not null default now()
);
create table if not exists public.occci_staff_assignments(
 user_id uuid primary key references auth.users(id) on delete cascade,
 branch_id text not null references public.occci_branches(id),
 role text not null check(role in ('Admin Head','Admin','Staff'))
);
alter table public.occci_branches enable row level security;
alter table public.occci_profiles enable row level security;
alter table public.occci_staff_assignments enable row level security;
create or replace function public.occci_can_read_branch(target_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s where s.user_id=(select auth.uid()) and (s.role='Admin Head' or s.branch_id=target_branch));
$$;
revoke all on function public.occci_can_read_branch(text) from public;
grant execute on function public.occci_can_read_branch(text) to authenticated;
drop policy if exists occci_branch_read on public.occci_branches;
create policy occci_branch_read on public.occci_branches for select to anon,authenticated using(true);
drop policy if exists occci_profile_read on public.occci_profiles;
create policy occci_profile_read on public.occci_profiles for select to authenticated using(id=(select auth.uid()) or public.occci_can_read_branch(branch_id));
drop policy if exists occci_profile_update on public.occci_profiles;
create policy occci_profile_update on public.occci_profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
drop policy if exists occci_staff_self_read on public.occci_staff_assignments;
create policy occci_staff_self_read on public.occci_staff_assignments for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.occci_profiles,public.occci_staff_assignments,public.occci_branches from anon,authenticated;
grant select on public.occci_branches to anon,authenticated;
grant select on public.occci_profiles,public.occci_staff_assignments to authenticated;
grant update(full_name,avatar) on public.occci_profiles to authenticated;
-- Role, membership status and branch cannot be changed by a member.
create or replace function public.occci_handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.occci_profiles(id,full_name,branch_id,avatar)
 values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'full_name',100),''),'Member'),
 case when exists(select 1 from public.occci_branches where id=new.raw_user_meta_data->>'branch_id') then new.raw_user_meta_data->>'branch_id' else 'BR-01' end,
 case when new.raw_user_meta_data->>'avatar' in ('man','farmer','lady','lola','boy','girl') then new.raw_user_meta_data->>'avatar' else 'lady' end);
 return new;
end;$$;
revoke all on function public.occci_handle_signup() from public,anon,authenticated;
drop trigger if exists occci_on_signup on auth.users;
create trigger occci_on_signup after insert on auth.users for each row execute function public.occci_handle_signup();
-- Backfill existing accounts conservatively: pending verification, default Ormoc.
insert into public.occci_profiles(id,full_name,branch_id,avatar)
select id,coalesce(nullif(left(raw_user_meta_data->>'full_name',100),''),'Member'),
case when exists(select 1 from public.occci_branches where id=raw_user_meta_data->>'branch_id') then raw_user_meta_data->>'branch_id' else 'BR-01' end,
case when raw_user_meta_data->>'avatar' in ('man','farmer','lady','lola','boy','girl') then raw_user_meta_data->>'avatar' else 'lady' end
from auth.users on conflict(id) do nothing;
commit;
-- Assign staff only through an administrator's SQL Editor or trusted server.
-- insert into public.occci_staff_assignments(user_id,branch_id,role)
-- values ('VERIFIED-AUTH-USER-UUID','BR-01','Admin Head');

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

-- Apply after 002_workflow.sql. One-time developer bootstrap and reviewed staff signup.
begin;
alter table public.occci_profiles add column if not exists registration_kind text not null default 'Member' check(registration_kind in ('Member','Staff'));
create table if not exists public.occci_staff_applications(
 user_id uuid primary key references public.occci_profiles(id), requested_role text not null check(requested_role in ('DM','BM','Staff')),
 district smallint not null check(district between 1 and 6), branch_id text not null references public.occci_branches(id),
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected')), reviewed_by uuid references auth.users(id),
 review_note text, created_at timestamptz not null default now(), reviewed_at timestamptz);
alter table public.occci_staff_applications enable row level security;
revoke all on public.occci_staff_applications from public,anon,authenticated;
grant select on public.occci_staff_applications to authenticated;
drop policy if exists occci_application_read on public.occci_staff_applications;
create policy occci_application_read on public.occci_staff_applications for select to authenticated using(user_id=auth.uid() or public.occci_role()='Admin');
create or replace function public.occci_staff_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; d smallint;
begin
 if coalesce(meta->>'registration_kind','Member') not in ('Member','Staff') then raise exception 'Choose Member or OCCCI Staff signup';end if;
 if meta->>'registration_kind'='Staff' then
 if meta->>'requested_role' is null or meta->>'requested_role' not in ('DM','BM','Staff') then raise exception 'Select a valid requested staff position';end if;
 select district into d from public.occci_branches where id=meta->>'branch_id' and active;
 if d is null or coalesce(meta->>'district','')<>d::text then raise exception 'Choose a branch within the selected district';end if;
 update public.occci_profiles set registration_kind='Staff' where id=new.id;
 insert into public.occci_staff_applications(user_id,requested_role,district,branch_id) values(new.id,meta->>'requested_role',d,meta->>'branch_id');
 perform public.occci_log(new.id,meta->>'branch_id','Staff application submitted',null,jsonb_build_object('requested_role',meta->>'requested_role','district',d),'Staff access requires cooperative Admin approval');
 end if;
 return new;
end;$$;
-- Alphabetical trigger order: profile creation runs before staff application creation.
drop trigger if exists occci_staff_signup on auth.users;
create trigger occci_staff_signup after insert on auth.users for each row execute function public.occci_staff_signup();
create or replace function public.occci_review_staff(target uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare a public.occci_staff_applications; p public.occci_profiles; previous jsonb;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only cooperative Admin can approve staff positions';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0)<3 then raise exception 'Choose a decision and provide a review note';end if;
 select * into a from public.occci_staff_applications where user_id=target for update;
 if not found or a.status<>'Pending' or target=auth.uid() then raise exception 'Choose another pending staff applicant';end if;
 select * into p from public.occci_profiles where id=target for update;
 if p.archived_at is not null then raise exception 'Applicant is archived';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=target;
 if decision='Approve' then
 if not exists(select 1 from auth.users where id=target and email_confirmed_at is not null) then raise exception 'Applicant must confirm their email before approval';end if;
 if not exists(select 1 from public.occci_branches where id=a.branch_id and active and district=a.district) then raise exception 'Requested branch/district changed; correct the directory before approval';end if;
 if previous is not null then raise exception 'Applicant already has a team assignment; manage it in Team';end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(target,a.requested_role,case when a.requested_role='DM' then null else a.branch_id end,case when a.requested_role='DM' then a.district else null end);
 end if;
 update public.occci_staff_applications set status=case decision when 'Approve' then 'Approved' else 'Rejected' end,reviewed_by=auth.uid(),review_note=reason,reviewed_at=now() where user_id=target;
 perform public.occci_log(target,a.branch_id,'Staff application reviewed',to_jsonb(a),jsonb_build_object('decision',decision,'role',a.requested_role,'district',a.district,'branch_id',a.branch_id),reason);
 if decision='Approve' then perform public.occci_log(target,a.branch_id,'Team assignment approved',previous,jsonb_build_object('role',a.requested_role,'district',a.district,'branch_id',a.branch_id),reason);end if;
end;$$;
-- Private, one-use bootstrap. Email comes from trusted auth.users, never client metadata.
create table if not exists public.occci_developer_bootstrap(
 singleton boolean primary key default true check(singleton), email text not null, consumed_by uuid references auth.users(id), consumed_at timestamptz);
alter table public.occci_developer_bootstrap enable row level security;
revoke all on public.occci_developer_bootstrap from public,anon,authenticated;
-- Configure the private target in SQL Editor before running this migration:
-- select set_config('occci.bootstrap_email','REPLACE_WITH_VERIFIED_DEVELOPER_EMAIL',false);
insert into public.occci_developer_bootstrap(singleton,email) values(true,coalesce(current_setting('occci.bootstrap_email',true),''))
on conflict(singleton) do update set email=excluded.email where occci_developer_bootstrap.consumed_at is null and occci_developer_bootstrap.email='' and excluded.email<>'';
create or replace function public.occci_bootstrap_developer(target uuid) returns void language plpgsql security definer set search_path='' as $$
declare config public.occci_developer_bootstrap; previous jsonb;
begin
 select * into config from public.occci_developer_bootstrap where singleton for update;
 if config.consumed_at is not null then return;end if;
 if not exists(select 1 from auth.users u join public.occci_profiles p on p.id=u.id where u.id=target and lower(u.email)=lower(config.email) and u.email_confirmed_at is not null and p.archived_at is null) then return;end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=target;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(target,'Admin',null,null) on conflict(user_id) do update set role='Admin',branch_id=null,district=null;
 update public.occci_developer_bootstrap set consumed_by=target,consumed_at=now() where singleton;
 perform public.occci_log(target,null,'Temporary developer Admin activated',previous,jsonb_build_object('role','Admin'),'One-time verified developer bootstrap; transfer to cooperative Admin and remove this assignment after setup');
end;$$;
create or replace function public.occci_developer_confirmed() returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.occci_bootstrap_developer(new.id);return new;end;$$;
drop trigger if exists occci_z_developer_confirmed on auth.users;
create trigger occci_z_developer_confirmed after insert or update of email,email_confirmed_at on auth.users for each row execute function public.occci_developer_confirmed();
-- Activate an already registered/confirmed developer, or wait for signup + confirmation.
select public.occci_bootstrap_developer(id) from auth.users where lower(email)=(select lower(email) from public.occci_developer_bootstrap where singleton) and email_confirmed_at is not null;
revoke all on function public.occci_staff_signup(),public.occci_bootstrap_developer(uuid),public.occci_developer_confirmed(),public.occci_review_staff(uuid,text,text) from public,anon,authenticated;
grant execute on function public.occci_review_staff(uuid,text,text) to authenticated;
commit;

-- Apply after 003_staff_signup.sql. Safe to rerun; no provider secrets or user grants.
begin;
alter table public.occci_profiles add column if not exists onboarding_complete boolean not null default true;
alter table public.occci_profiles alter column branch_id drop not null;
alter table public.occci_audit add column if not exists actor_name text;
alter table public.occci_audit add column if not exists actor_role text;
create or replace function public.occci_log(target uuid,branch text,action_name text,previous jsonb,new_data jsonb,reason text) returns void language sql security definer set search_path='' as $$
 insert into public.occci_audit(actor,member_id,branch_id,action,before_data,after_data,note,actor_name,actor_role)
 values(auth.uid(),target,branch,action_name,previous,new_data,reason,(select full_name from public.occci_profiles where id=auth.uid()),case when auth.uid() is not null then public.occci_role() end);
$$;
drop policy if exists occci_audit_read on public.occci_audit;
create policy occci_audit_read on public.occci_audit for select to authenticated using(member_id=auth.uid() or public.occci_role() in ('Admin','DM','BM') or public.occci_can_read_branch(branch_id));
-- Name resolution is limited to actors in already-authorized audit rows, not profile access.
create or replace function public.occci_activity() returns setof public.occci_audit language sql stable security definer set search_path='' as $$
 select jsonb_populate_record(null::public.occci_audit,to_jsonb(a)||jsonb_build_object('actor_name',coalesce(a.actor_name,p.full_name,case when a.actor is null then 'System' else 'Cooperative user' end)))
 from public.occci_audit a left join public.occci_profiles p on p.id=a.actor
 where auth.uid() is not null and (a.member_id=auth.uid() or public.occci_role() in ('Admin','DM','BM') or public.occci_can_read_branch(a.branch_id))
 order by a.created_at desc,a.id desc;
$$;
create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
declare r text:=public.occci_role(); p public.occci_profiles; c public.occci_content; b public.occci_branches; target_branch text; target_district smallint; previous jsonb; uid uuid;
begin
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Enter reason, comments or notes (at least 3 characters)';end if;
 if record_kind='Member' then
 select * into p from public.occci_profiles where id=record_id::uuid for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','BM') then raise exception 'Staff must request BM approval before changing member details';end if;
 if remove_record then
 if r<>'Admin' then raise exception 'Only Admin can archive a member';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if exists(select 1 from public.occci_staff_assignments where user_id=p.id and role='Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles active_profile on active_profile.id=s.user_id where s.role='Admin' and s.user_id<>p.id and active_profile.archived_at is null) then raise exception 'Keep at least one Admin before archiving this account';end if;
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
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=record_id::uuid;
 if previous->>'role'='Admin' and (remove_record or coalesce(values_json->>'role','')<>'Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles other_profile on other_profile.id=s.user_id where s.role='Admin' and s.user_id<>record_id::uuid and other_profile.archived_at is null) then raise exception 'Keep at least one Admin. Assign another Admin before changing or removing this assignment';end if;
 if remove_record then delete from public.occci_staff_assignments where user_id=record_id::uuid;
 else
 if not exists(select 1 from public.occci_profiles target_profile join auth.users u on u.id=target_profile.id where target_profile.id=record_id::uuid and target_profile.archived_at is null and target_profile.onboarding_complete and u.email_confirmed_at is not null) then raise exception 'Choose an account with confirmed email and completed profile';end if;
 if coalesce(values_json->>'role','') not in ('Admin','DM','BM','Staff') then raise exception 'Choose a valid role';end if;
 if values_json->>'role'='Admin' then values_json:=jsonb_build_object('role','Admin','branch_id',null,'district',null);
 elsif values_json->>'role'='DM' then
 if not exists(select 1 from public.occci_branches where active and district=nullif(values_json->>'district','')::smallint) then raise exception 'Choose a district with active branches';end if;
 values_json:=jsonb_build_object('role','DM','branch_id',null,'district',(values_json->>'district')::smallint);
 else
 if not exists(select 1 from public.occci_branches where id=values_json->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
 values_json:=jsonb_build_object('role',values_json->>'role','branch_id',values_json->>'branch_id','district',null);
 end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(record_id::uuid,values_json->>'role',nullif(values_json->>'branch_id',''),nullif(values_json->>'district','')::smallint) on conflict(user_id) do update set role=excluded.role,branch_id=excluded.branch_id,district=excluded.district;
 end if;
 insert into public.occci_audit(actor,member_id,branch_id,action,before_data,after_data,note,actor_name,actor_role) values(auth.uid(),record_id::uuid,null,'Team assignment changed',previous,case when remove_record then jsonb_build_object('role','Member') else values_json end,reason,(select full_name from public.occci_profiles where id=auth.uid()),r);
 else raise exception 'Unknown record type';end if;
end;$$;
create or replace function public.occci_handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; fullname_value text;
begin
 if new.raw_app_meta_data->>'provider'='google' then
 insert into public.occci_profiles(id,full_name,branch_id,avatar,onboarding_complete)
 values(new.id,coalesce(nullif(left(meta->>'full_name',100),''),'New member'),null,'lady',false);
 return new;
 end if;
 if not exists(select 1 from public.occci_branches where id=meta->>'branch_id' and active) or coalesce(length(trim(meta->>'first_name')),0) not between 1 and 50 or coalesce(length(trim(meta->>'last_name')),0) not between 1 and 50 or coalesce(length(meta->>'middle_name'),0)>50 or coalesce(length(trim(meta->>'contact_number')),0) not between 7 and 30 or coalesce(length(trim(meta->>'address')),0) not between 5 and 500 then raise exception 'Complete the required member details and choose an active branch';end if;
 fullname_value:=trim(concat_ws(' ',nullif(meta->>'first_name',''),nullif(meta->>'middle_name',''),nullif(meta->>'last_name','')));
 insert into public.occci_profiles(id,full_name,branch_id,avatar,last_name,first_name,middle_name,contact_number,address)
 values(new.id,coalesce(nullif(left(fullname_value,100),''),nullif(left(meta->>'full_name',100),''),'Member'),
 meta->>'branch_id',
 case when meta->>'avatar' in ('man','farmer','lady','lola','boy','girl') then meta->>'avatar' else 'lady' end,
 left(coalesce(meta->>'last_name',''),50),left(coalesce(meta->>'first_name',''),50),left(coalesce(meta->>'middle_name',''),50),left(coalesce(meta->>'contact_number',''),30),left(coalesce(meta->>'address',''),500));
 return new;
end;$$;
create or replace function public.occci_staff_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; d smallint;
begin
 if exists(select 1 from public.occci_profiles where id=new.id and not onboarding_complete) then return new;end if;
 if coalesce(meta->>'registration_kind','Member') not in ('Member','Staff') then raise exception 'Choose Member or OCCCI Staff signup';end if;
 if meta->>'registration_kind'='Staff' then
 if meta->>'requested_role' is null or meta->>'requested_role' not in ('DM','BM','Staff') then raise exception 'Select a valid requested staff position';end if;
 select district into d from public.occci_branches where id=meta->>'branch_id' and active;
 if d is null or coalesce(meta->>'district','')<>d::text then raise exception 'Choose a branch within the selected district';end if;
 update public.occci_profiles set registration_kind='Staff' where id=new.id;
 insert into public.occci_staff_applications(user_id,requested_role,district,branch_id) values(new.id,meta->>'requested_role',d,meta->>'branch_id');
 perform public.occci_log(new.id,meta->>'branch_id','Staff application submitted',null,jsonb_build_object('requested_role',meta->>'requested_role','district',d),'Staff access requires cooperative Admin approval');
 end if;
 return new;
end;$$;
create or replace function public.occci_approve_member(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role();
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','BM','Staff') then raise exception 'Membership approval is not permitted in this branch'; end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before approval';end if;
 if p.membership_status<>'Pending verification' or p.archived_at is not null then raise exception 'This membership is not pending'; end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid unique account number and approval note'; end if;
 update public.occci_profiles set membership_status='Active',account_number=trim(account),revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Membership approved',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',trim(account)),reason);
end;$$;

create or replace function public.occci_complete_onboarding(values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; b public.occci_branches; kind text:=coalesce(values_json->>'registration_kind','Member'); requested text:=values_json->>'requested_role';
begin
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is not null or p.onboarding_complete then raise exception 'This account is not awaiting profile completion';end if;
 select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
 if not found or b.district::text<>coalesce(values_json->>'district','') then raise exception 'Choose an active branch in the selected district';end if;
 if kind not in ('Member','Staff') or (kind='Staff' and coalesce(requested,'') not in ('DM','BM','Staff')) then raise exception 'Choose Member or a valid requested staff position';end if;
 -- Reuse strict field validation; a new account cannot become Active or assign roles.
 perform public.occci_profile_values(p.id,values_json||jsonb_build_object('membership_status','Pending verification'));
 update public.occci_profiles set branch_id=b.id,onboarding_complete=true,registration_kind=kind where id=p.id;
 if kind='Staff' then insert into public.occci_staff_applications(user_id,requested_role,district,branch_id) values(p.id,requested,b.district,b.id);end if;
 perform public.occci_log(p.id,b.id,'Registration profile completed',null,jsonb_build_object('registration_kind',kind,'requested_role',case when kind='Staff' then requested end,'branch_id',b.id,'district',b.district),'Profile completed after Google sign-in; approval remains required');
end;$$;
revoke all on function public.occci_activity(),public.occci_complete_onboarding(jsonb) from public,anon,authenticated;
grant execute on function public.occci_activity(),public.occci_complete_onboarding(jsonb) to authenticated;
insert into public.occci_schema_versions values('004_activity_google') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 004_activity_google.sql. Preserves all existing records and single-file references.
begin;
alter table public.occci_change_requests add column if not exists evidence_files jsonb not null default '[]';
alter table public.occci_financials add column if not exists evidence_files jsonb not null default '[]';
-- Private originals may be PDF, Office documents, scans or other file formats.
update storage.buckets set public=false,file_size_limit=10485760,allowed_mime_types=null where id='occci-documents';
create or replace function public.occci_assign_account(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles;
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or not public.occci_can_read_branch(p.branch_id) or public.occci_role() not in ('Admin','DM','BM','Staff') then raise exception 'Account assignment is not permitted in this branch';end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before assigning an ID';end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid official ID and reason, comments or notes';end if;
 perform pg_catalog.pg_advisory_xact_lock(771005);
 if exists(select 1 from public.occci_profiles where lower(account_number)=lower(trim(account)) and id<>target) then raise exception 'This account number is already assigned to another member';end if;
 update public.occci_profiles set account_number=trim(account),revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Official ID assigned',jsonb_build_object('account_number',p.account_number),jsonb_build_object('account_number',trim(account)),reason);
end;$$;
create or replace function public.occci_apply_authorized_edit(request_id uuid,values_json jsonb,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; p public.occci_profiles;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or q.kind<>'Profile edit' or q.status<>'BM approved' or coalesce(q.proposed->>'permission_only','false')<>'true' or q.submitted_by<>auth.uid() or public.occci_role()<>'Staff' or not public.occci_can_read_branch(q.branch_id) then raise exception 'Wait for BM or DM approval before editing this member';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide reason, comments or notes for the edit';end if;
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.revision<>q.base_revision or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member details changed; request new approval';end if;
 perform public.occci_profile_values(q.member_id,values_json);
 update public.occci_change_requests set status='Applied',proposed=values_json,reviewed_at=now() where id=request_id;
 perform public.occci_log(q.member_id,q.branch_id,'Approved member edit applied',to_jsonb(p),values_json||jsonb_build_object('request_id',request_id),reason);
end;$$;
create or replace function public.occci_submit_financial_documents(target uuid,values_json jsonb,documents jsonb,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare d jsonb; request_id uuid; total bigint:=0; paths text[]:='{}';
begin
 if jsonb_typeof(documents) is distinct from 'array' then raise exception 'Attach original supporting documents';end if;
 if jsonb_array_length(documents) not between 1 and 10 then raise exception 'Attach 1 to 10 original supporting documents';end if;
 for d in select * from jsonb_array_elements(documents) loop
 if coalesce(d->>'path','') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-documents' and name=d->>'path') then raise exception 'Upload every supporting document to your private folder first';end if;
 if coalesce(length(d->>'name'),0) not between 1 and 255 or coalesce((d->>'size')::bigint,0) not between 1 and 10485760 or (d->>'path')=any(paths) then raise exception 'Invalid document name, size or duplicate attachment';end if;
 paths:=array_append(paths,d->>'path');total:=total+(d->>'size')::bigint;
 end loop;
 if total>52428800 then raise exception 'Supporting documents exceed 50 MB in total';end if;
 request_id:=public.occci_submit_change(target,'Financial sync',values_json,documents->0->>'path',reason);
 update public.occci_change_requests set evidence_files=documents where id=request_id;
 perform public.occci_log(target,(select branch_id from public.occci_profiles where id=target),'Original documents attached',null,jsonb_build_object('request_id',request_id,'documents',documents),reason);
 return request_id;
end;$$;
create or replace function public.occci_approve_member(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role();
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM','Staff') then raise exception 'Membership approval is not permitted in this branch'; end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before approval';end if;
 if p.membership_status<>'Pending verification' or p.archived_at is not null then raise exception 'This membership is not pending'; end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid unique account number and approval note'; end if;
 perform public.occci_assign_account(target,account,reason);
 update public.occci_profiles set membership_status='Active',revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Membership approved',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',trim(account)),reason);
end;$$;
create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
declare r text:=public.occci_role(); p public.occci_profiles; c public.occci_content; b public.occci_branches; target_branch text; target_district smallint; previous jsonb; uid uuid;
begin
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Enter reason, comments or notes (at least 3 characters)';end if;
 if record_kind='Member' then
 select * into p from public.occci_profiles where id=record_id::uuid for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM') then raise exception 'Staff must request BM approval before changing member details';end if;
 if p.archived_at is not null then raise exception 'This member is already archived';end if;
 if remove_record then
 if r<>'Admin' then raise exception 'Only Admin can archive a member';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if exists(select 1 from public.occci_staff_assignments where user_id=p.id and role='Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles active_profile on active_profile.id=s.user_id where s.role='Admin' and s.user_id<>p.id and active_profile.archived_at is null) then raise exception 'Keep at least one Admin before archiving this account';end if;
 update public.occci_profiles set archived_at=now(),revision=revision+1 where id=p.id;
 delete from public.occci_staff_assignments where user_id=p.id;
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
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=record_id::uuid;
 if previous->>'role'='Admin' and (remove_record or coalesce(values_json->>'role','')<>'Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles other_profile on other_profile.id=s.user_id where s.role='Admin' and s.user_id<>record_id::uuid and other_profile.archived_at is null) then raise exception 'Keep at least one Admin. Assign another Admin before changing or removing this assignment';end if;
 if remove_record then delete from public.occci_staff_assignments where user_id=record_id::uuid;
 else
 if not exists(select 1 from public.occci_profiles target_profile join auth.users u on u.id=target_profile.id where target_profile.id=record_id::uuid and target_profile.archived_at is null and target_profile.onboarding_complete and u.email_confirmed_at is not null) then raise exception 'Choose an account with confirmed email and completed profile';end if;
 if coalesce(values_json->>'role','') not in ('Admin','DM','BM','Staff') then raise exception 'Choose a valid role';end if;
 if values_json->>'role'='Admin' then values_json:=jsonb_build_object('role','Admin','branch_id',null,'district',null);
 elsif values_json->>'role'='DM' then
 if not exists(select 1 from public.occci_branches where active and district=nullif(values_json->>'district','')::smallint) then raise exception 'Choose a district with active branches';end if;
 values_json:=jsonb_build_object('role','DM','branch_id',null,'district',(values_json->>'district')::smallint);
 else
 if not exists(select 1 from public.occci_branches where id=values_json->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
 values_json:=jsonb_build_object('role',values_json->>'role','branch_id',values_json->>'branch_id','district',null);
 end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(record_id::uuid,values_json->>'role',nullif(values_json->>'branch_id',''),nullif(values_json->>'district','')::smallint) on conflict(user_id) do update set role=excluded.role,branch_id=excluded.branch_id,district=excluded.district;
 end if;
 insert into public.occci_audit(actor,member_id,branch_id,action,before_data,after_data,note,actor_name,actor_role) values(auth.uid(),record_id::uuid,null,'Team assignment changed',previous,case when remove_record then jsonb_build_object('role','Member') else values_json end,reason,(select full_name from public.occci_profiles where id=auth.uid()),r);
 else raise exception 'Unknown record type';end if;
end;$$;
create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) or q.submitted_by=auth.uid() then raise exception 'Review requires a different authorized reviewer';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a review note';end if;
 if q.kind='Profile edit' then
 if r not in ('BM','DM','Admin') or q.status<>'Pending' then raise exception 'Profile edits require BM or DM approval';end if;
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
 insert into public.occci_financials(member_id,savings,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision)
 values(q.member_id,(v->>'savings')::numeric,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,q.evidence_files,(v->>'as_of')::date,q.base_revision+1)
 on conflict(member_id) do update set savings=excluded.savings,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,evidence_files=excluded.evidence_files,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
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
 if not found or q.kind<>'Profile edit' or coalesce(q.proposed->>'permission_only','false')='true' or q.status<>'BM approved' or q.submitted_by<>auth.uid() or not public.occci_can_read_branch(q.branch_id) or public.occci_role() not in ('Staff','BM','DM','Admin') then raise exception 'Only the requesting staff member can apply this approved edit';end if;
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.revision<>q.base_revision or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member details changed; submit a new edit request';end if;
 perform public.occci_profile_values(q.member_id,q.proposed);
 update public.occci_change_requests set status='Applied',reviewed_at=now() where id=request_id;
 perform public.occci_log(q.member_id,q.branch_id,'Approved member edit applied',to_jsonb(p),q.proposed,q.note);
end;$$;
-- Reviewers can read every attachment in their assigned branch/district; audit access alone does not grant document access.
drop policy if exists occci_document_read on storage.objects;
create policy occci_document_read on storage.objects for select to authenticated using(bucket_id='occci-documents' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_change_requests q where public.occci_can_read_branch(q.branch_id) and (q.evidence_path=name or q.evidence_files @> jsonb_build_array(jsonb_build_object('path',name))))));
revoke all on function public.occci_assign_account(uuid,text,text),public.occci_apply_authorized_edit(uuid,jsonb,text),public.occci_submit_financial_documents(uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_assign_account(uuid,text,text),public.occci_apply_authorized_edit(uuid,jsonb,text),public.occci_submit_financial_documents(uuid,jsonb,jsonb,text) to authenticated;
insert into public.occci_schema_versions values('005_member_documents') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Reporting workspace and Staff work workflow
-- Apply after 005_member_documents.sql. Private managerial reports; no member data is copied.
begin;
create table if not exists public.occci_report_types(
 id text primary key, category text not null check(category in ('Assembly','Compliance','District','Cluster','Work')),
 name text not null, guidance text not null default '', active boolean not null default true);
insert into public.occci_report_types(id,category,name,guidance) values
('staff-daily','Work','Daily staff work report','Daily branch work, source documents and actual transaction totals.'),
('staff-weekly','Work','Weekly staff work report','Seven-day summary of branch work and actual transaction totals.'),
('staff-monthly','Work','Monthly staff work report','Calendar-month summary of branch work and actual transaction totals.'),
('assembly-minutes','Assembly','Minutes of the last general assembly','Proceedings, attendance, resolutions and approvals.'),
('board-report','Assembly','Consolidated Board of Directors report','Management performance, operations, achievements and strategic updates.'),
('committee-report','Assembly','Committee report','Audit, Election, Ethics or another committee. Identify the committee in the title.'),
('assembly-afs','Assembly','Audited financial statements','Attach the signed statements and auditor report; identify the external auditor.'),
('budget-program','Assembly','Proposed budget and program of activities','Plans and financial projections for assembly consideration.'),
('capr','Compliance','Cooperative Annual Progress Report (CAPR)','Record the prepared report and submission acknowledgement.'),
('compliance-afs','Compliance','Audited financial statements package','Statements, management responsibility, auditor opinion, representation and notes.'),
('social-audit','Compliance','Social audit report','Socio-civic programs and related activities.'),
('performance-audit','Compliance','Performance audit report','Governance, management and financial performance.'),
('officers-training','Compliance','List of officers and mandatory training','Officers and completed or undertaken training.'),
('mediation','Compliance','Semi-annual mediation and conciliation report','Specify the reporting half-year in the period.'),
('sworn-statement','Compliance','Sworn statement of cooperative officers','Attach the signed prescribed statement.'),
('atir-abr','Compliance','Annual tax incentives / benefits reports','Applicable to cooperatives with a certificate of tax exemption.'),
('coc-record','Compliance','Certificate of Compliance and payment record','Receipt, acknowledgement and certificate tracking.'),
('district-management','District','Consolidated district management report','Branch operations, membership and verified financial growth.'),
('district-credit','District','District financial and credit performance','Approved balances; attach source documents for assets, provisions and surplus.'),
('district-resolutions','District','District resolutions and proposals','Policy proposals, regional budgets and recorded decisions.'),
('district-election','District','District Election Committee report','Candidate screening, election returns and delegates.'),
('cluster-performance','Cluster','Branch performance and local updates','Membership recruitment, verified savings and branch programs.'),
('cluster-credit','Cluster','Loan portfolio and delinquency review','Approved loan balances and overdue status; attach collection records.'),
('cluster-welfare','Cluster','Member benefit and welfare report','Scholarships, insurance, calamity aid and other branch programs.'),
('cluster-election','Cluster','Cluster minutes and delegate election report','Attendance, resolutions, elected delegates and election results.')
on conflict(id) do nothing;
create table if not exists public.occci_reports(
 id uuid primary key default gen_random_uuid(), type_id text not null references public.occci_report_types(id), title text not null,
 district smallint check(district between 1 and 6), branch_id text references public.occci_branches(id),
 period_start date not null, period_end date not null, meeting_date date, due_date date,
 status text not null default 'Draft' check(status in ('Draft','For review','Approved','Returned','Filed')),
 summary text not null default '', details jsonb not null default '{}', documents jsonb not null default '[]',
 created_by uuid not null references auth.users(id), reviewer uuid references auth.users(id), review_note text,
 filed_on date, filing_reference text, revision integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), archived_at timestamptz,
 check(period_end>=period_start), check(jsonb_typeof(documents)='array'), check(jsonb_typeof(details)='object'));
create table if not exists public.occci_report_events(
 id bigint generated always as identity primary key, report_id uuid not null references public.occci_reports(id),
 actor uuid not null references auth.users(id), actor_name text, actor_role text,
 action text not null, before_data jsonb, after_data jsonb, note text not null, created_at timestamptz not null default now());
create index if not exists occci_report_scope_idx on public.occci_reports(district,branch_id,period_start);
create index if not exists occci_report_event_idx on public.occci_report_events(report_id,created_at);
create or replace function public.occci_report_access(d smallint,b text,write_access boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce((public.occci_role()='Admin' or (public.occci_role()='DM' and d=public.occci_district()) or (public.occci_role()='BM' and b is not null and public.occci_can_read_branch(b)) or (not write_access and public.occci_role() in ('DM','BM') and d is null and b is null)),false);
$$;
alter table public.occci_report_types enable row level security;
alter table public.occci_reports enable row level security;
alter table public.occci_report_events enable row level security;
revoke all on public.occci_report_types,public.occci_reports,public.occci_report_events from public,anon,authenticated;
grant select on public.occci_report_types,public.occci_reports,public.occci_report_events to authenticated;
drop policy if exists occci_report_types_read on public.occci_report_types;
create policy occci_report_types_read on public.occci_report_types for select to authenticated using((public.occci_role() in ('Admin','DM','BM') or public.occci_role()='Staff' and category='Work'));
drop policy if exists occci_reports_read on public.occci_reports;
create policy occci_reports_read on public.occci_reports for select to authenticated using(public.occci_report_access(district,branch_id,false));
drop policy if exists occci_report_events_read on public.occci_report_events;
create policy occci_report_events_read on public.occci_report_events for select to authenticated using(exists(select 1 from public.occci_reports r where r.id=report_id and public.occci_report_access(r.district,r.branch_id,false)));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('occci-reports','occci-reports',false,10485760,null) on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=null;
drop policy if exists occci_report_upload on storage.objects;
create policy occci_report_upload on storage.objects for insert to authenticated with check(bucket_id='occci-reports' and public.occci_role() in ('Admin','DM','BM','Staff') and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and public.occci_role() in ('Admin','DM','BM') and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',name)))));
create or replace function public.occci_save_report(target uuid,values_json jsonb,expected_revision integer,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.occci_reports; result_id uuid; d smallint; b text; category_value text; doc jsonb; docs jsonb; total bigint:=0; seen text[]:='{}';
begin
 if public.occci_role() not in ('Admin','DM','BM') or coalesce(length(trim(reason)),0)<3 then raise exception 'Manager access and reason / comments / notes are required';end if;
 if target is not null then
  select * into old from public.occci_reports where id=target for update;
  if not found or old.archived_at is not null or not public.occci_report_access(old.district,old.branch_id,true) then raise exception 'Report editing is not permitted';end if;
  if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before saving';end if;
  if old.status not in ('Draft','Returned') then raise exception 'Only draft or returned reports can be edited';end if;
 end if;
 b:=nullif(values_json->>'branch_id','');d:=nullif(values_json->>'district','')::smallint;
 if b is not null then select district into d from public.occci_branches where id=b and active;if not found then raise exception 'Choose an active branch';end if;end if;
 if not public.occci_report_access(d,b,true) then raise exception 'Report scope is outside your assignment';end if;
 select category into category_value from public.occci_report_types where id=values_json->>'type_id' and active;
 if not found then raise exception 'Choose an active report type';end if;
 if category_value='Work' then raise exception 'Staff work reports require the BM approval workflow';end if;
 if category_value='Compliance' and (d is not null or b is not null) then raise exception 'Annual compliance records use cooperative scope';end if;
 if category_value='District' and (d is null or b is not null) then raise exception 'District assembly reports need a district scope';end if;
 if category_value='Cluster' and b is null then raise exception 'Cluster meeting reports need a branch';end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 3 and 150 or coalesce(length(values_json->>'summary'),0)>10000 or coalesce(values_json->>'period_start','')='' or coalesce(values_json->>'period_end','')='' or (values_json->>'period_end')::date<(values_json->>'period_start')::date then raise exception 'Provide title and a valid reporting period';end if;
 if jsonb_typeof(coalesce(values_json->'details','{}')) is distinct from 'object' or length(coalesce(values_json->'details','{}')::text)>30000 then raise exception 'Invalid report details';end if;
 if coalesce((values_json->'details'->>'attended')::integer,0)<0 or coalesce((values_json->'details'->>'eligible')::integer,0)<0 or (values_json->'details'->>'attended')::integer>(values_json->'details'->>'eligible')::integer then raise exception 'Attendance must be non-negative and cannot exceed eligible participants';end if;
 docs:=coalesce(values_json->'documents','[]');
 if jsonb_typeof(docs) is distinct from 'array' or jsonb_array_length(docs)>10 then raise exception 'Attach at most 10 original documents';end if;
 for doc in select * from jsonb_array_elements(docs) loop
  if not exists(select 1 from storage.objects where bucket_id='occci-reports' and name=doc->>'path') or (coalesce(doc->>'path','') not like auth.uid()::text||'/%' and not coalesce(old.documents,'[]') @> jsonb_build_array(jsonb_build_object('path',doc->>'path'))) then raise exception 'Upload new files to your own private folder';end if;
  if coalesce(length(doc->>'name'),0) not between 1 and 255 or coalesce((doc->>'size')::bigint,0) not between 1 and 10485760 or (doc->>'path')=any(seen) then raise exception 'Invalid document name, size or duplicate attachment';end if;
  total:=total+(doc->>'size')::bigint;seen:=array_append(seen,doc->>'path');
 end loop;
 if total>52428800 then raise exception 'Attachments exceed 50 MB total';end if;
 if target is null then
  insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,meeting_date,due_date,summary,details,documents,created_by)
  values(values_json->>'type_id',trim(values_json->>'title'),d,b,(values_json->>'period_start')::date,(values_json->>'period_end')::date,nullif(values_json->>'meeting_date','')::date,nullif(values_json->>'due_date','')::date,coalesce(values_json->>'summary',''),coalesce(values_json->'details','{}'),docs,auth.uid()) returning id into result_id;
 else
  update public.occci_reports set type_id=values_json->>'type_id',title=trim(values_json->>'title'),district=d,branch_id=b,period_start=(values_json->>'period_start')::date,period_end=(values_json->>'period_end')::date,meeting_date=nullif(values_json->>'meeting_date','')::date,due_date=nullif(values_json->>'due_date','')::date,summary=coalesce(values_json->>'summary',''),details=coalesce(values_json->'details','{}'),documents=docs,revision=revision+1,updated_at=now() where id=target;result_id:=target;
 end if;
 insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(result_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),case when target is null then 'Report created' else 'Report updated' end,to_jsonb(old),(select to_jsonb(r) from public.occci_reports r where id=result_id),reason);
 return result_id;
end;$$;
create or replace function public.occci_report_transition(target uuid,decision text,expected_revision integer,reason text,filed_date date default null,reference text default null) returns void language plpgsql security definer set search_path='' as $$
declare old public.occci_reports; new_status text;
begin
 select * into old from public.occci_reports where id=target for update;
 if not found or not public.occci_report_access(old.district,old.branch_id,true) or coalesce(length(trim(reason)),0)<3 then raise exception 'Report action is not permitted; provide reason / comments / notes';end if;
 if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before continuing';end if;
 if decision='Restore' then
  if old.archived_at is null then raise exception 'Report is not archived';end if;
  update public.occci_reports set archived_at=null,revision=revision+1,updated_at=now() where id=target;
 else
  if old.archived_at is not null then raise exception 'Restore the archived report first';end if;
  if decision='Archive' then update public.occci_reports set archived_at=now(),revision=revision+1,updated_at=now() where id=target;
  else
   if decision='Submit' and old.status in ('Draft','Returned') then
    if length(trim(old.summary))<3 or jsonb_array_length(old.documents)=0 then raise exception 'Add a summary and source documents before review';end if;new_status:='For review';
   elsif decision in ('Approve','Return') and old.status='For review' then
    if old.created_by=auth.uid() and not (public.occci_role()='Admin' and old.district is null and old.branch_id is null) then raise exception 'A different authorized manager must review this report';end if;
    new_status:=case decision when 'Approve' then 'Approved' else 'Returned' end;
   elsif decision='File' and old.status='Approved' then
    if filed_date is null or filed_date>current_date or coalesce(length(trim(reference)),0)<3 then raise exception 'Record a valid filing date and acknowledgement reference';end if;new_status:='Filed';
   else raise exception 'This action does not match the current report status';end if;
   update public.occci_reports set status=new_status,reviewer=case when decision in ('Approve','Return') then auth.uid() else reviewer end,review_note=case when decision in ('Approve','Return') then reason else review_note end,filed_on=case when decision='File' then filed_date else filed_on end,filing_reference=case when decision='File' then trim(reference) else filing_reference end,revision=revision+1,updated_at=now() where id=target;
  end if;
 end if;
 insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(target,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Report '||lower(decision),to_jsonb(old),(select to_jsonb(r) from public.occci_reports r where id=target),reason);
end;$$;
-- Staff prepares work reports privately; a branch manager publishes the approved record.
create table if not exists public.occci_work_reports(
 id uuid primary key default gen_random_uuid(), created_by uuid not null references auth.users(id),
 branch_id text not null references public.occci_branches(id), district smallint not null,
 frequency text not null check(frequency in ('Daily','Weekly','Monthly')), title text not null,
 period_start date not null,period_end date not null, summary text not null default '', metrics jsonb not null default '{}',
 documents jsonb not null default '[]',status text not null default 'Draft' check(status in ('Draft','For review','Approved','Returned')),
 review_note text,reviewer uuid references auth.users(id), published_report uuid references public.occci_reports(id),
 revision integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(period_end>=period_start),check(jsonb_typeof(metrics)='object'),check(jsonb_typeof(documents)='array'));
create unique index if not exists occci_work_approved_period on public.occci_work_reports(created_by,frequency,period_start,period_end) where status='Approved';
create table if not exists public.occci_work_report_events(
 id bigint generated always as identity primary key,work_report_id uuid not null references public.occci_work_reports(id),
 actor uuid not null references auth.users(id),actor_name text,actor_role text,action text not null,
 before_data jsonb,after_data jsonb,note text not null,created_at timestamptz not null default now());
create or replace function public.occci_work_access(owner_id uuid,b text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (owner_id=auth.uid() or public.occci_role() in ('Admin','DM','BM') and public.occci_can_read_branch(b));
$$;
alter table public.occci_work_reports enable row level security;
alter table public.occci_work_report_events enable row level security;
revoke all on public.occci_work_reports,public.occci_work_report_events from public,anon,authenticated;
grant select on public.occci_work_reports,public.occci_work_report_events to authenticated;
drop policy if exists occci_work_reports_read on public.occci_work_reports;
create policy occci_work_reports_read on public.occci_work_reports for select to authenticated using(public.occci_work_access(created_by,branch_id));
drop policy if exists occci_work_events_read on public.occci_work_report_events;
create policy occci_work_events_read on public.occci_work_report_events for select to authenticated using(exists(select 1 from public.occci_work_reports w where w.id=work_report_id and public.occci_work_access(w.created_by,w.branch_id)));
-- Managers retain branch-scoped documents; staff sees only their own staged work.
drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and ((public.occci_role() in ('Admin','DM','BM','Staff') and (storage.foldername(name))[1]=auth.uid()::text) or exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',name))) or exists(select 1 from public.occci_work_reports w where public.occci_work_access(w.created_by,w.branch_id) and w.documents @> jsonb_build_array(jsonb_build_object('path',name)))));
create or replace function public.occci_save_work_report(target uuid,values_json jsonb,expected_revision integer,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;assignment public.occci_staff_assignments;result_id uuid;start_date date;end_date date;freq text;doc jsonb;docs jsonb;total bigint:=0;seen text[]:='{}';entry record;metrics_value jsonb;
begin
 select * into assignment from public.occci_staff_assignments where user_id=auth.uid() and role='Staff';
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Staff assignment and reason / comments / notes are required';end if;
 if target is not null then
  select * into old from public.occci_work_reports where id=target for update;
  if not found or old.created_by<>auth.uid() or old.branch_id<>assignment.branch_id or old.status not in ('Draft','Returned') then raise exception 'Only your draft or returned work report can be edited';end if;
  if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before saving';end if;
 end if;
 freq:=values_json->>'frequency';start_date:=(values_json->>'period_start')::date;end_date:=(values_json->>'period_end')::date;
 if freq is null or freq not in ('Daily','Weekly','Monthly') or start_date is null or end_date is null or (freq='Daily' and end_date<>start_date) or (freq='Weekly' and (end_date<>start_date+6 or extract(isodow from start_date)<>1)) or (freq='Monthly' and (extract(day from start_date)<>1 or end_date<>(date_trunc('month',start_date)+interval '1 month - 1 day')::date)) then raise exception 'Use one day, seven days, or a complete calendar month for the report period';end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 3 and 150 or coalesce(length(values_json->>'summary'),0)>10000 then raise exception 'Provide a valid title and work summary';end if;
 metrics_value:=coalesce(values_json->'metrics','{}');
 if jsonb_typeof(metrics_value) is distinct from 'object' then raise exception 'Invalid work totals';end if;
 for entry in select * from jsonb_each_text(metrics_value) loop
  if entry.key not in ('registrations','account_updates','savings_collections','loan_releases','loan_repayments','followups') or entry.value is null or entry.value::numeric<0 or entry.value::numeric>99999999999999 then raise exception 'Invalid work totals';end if;
  if entry.key in ('registrations','account_updates','followups') and entry.value::numeric<>trunc(entry.value::numeric) then raise exception 'Work counts must be whole numbers';end if;
 end loop;
 docs:=coalesce(values_json->'documents','[]');
 if jsonb_typeof(docs) is distinct from 'array' or jsonb_array_length(docs)>10 then raise exception 'Attach at most 10 source documents';end if;
 for doc in select * from jsonb_array_elements(docs) loop
  if coalesce(doc->>'path','') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-reports' and name=doc->>'path') or coalesce(length(doc->>'name'),0) not between 1 and 255 or coalesce((doc->>'size')::bigint,0) not between 1 and 10485760 or (doc->>'path')=any(seen) then raise exception 'Invalid private source attachment';end if;
  total:=total+(doc->>'size')::bigint;seen:=array_append(seen,doc->>'path');
 end loop;
 if total>52428800 then raise exception 'Source documents exceed 50 MB';end if;
 if target is null then
  insert into public.occci_work_reports(created_by,branch_id,district,frequency,title,period_start,period_end,summary,metrics,documents)
  values(auth.uid(),assignment.branch_id,(select district from public.occci_branches where id=assignment.branch_id),freq,trim(values_json->>'title'),start_date,end_date,coalesce(values_json->>'summary',''),metrics_value,docs) returning id into result_id;
 else
  update public.occci_work_reports set frequency=freq,title=trim(values_json->>'title'),period_start=start_date,period_end=end_date,summary=coalesce(values_json->>'summary',''),metrics=metrics_value,documents=docs,revision=revision+1,updated_at=now() where id=target;result_id:=target;
 end if;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(result_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),case when target is null then 'Work report created' else 'Work report updated' end,to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=result_id),reason);
 return result_id;
end;$$;
create or replace function public.occci_work_report_transition(target uuid,decision text,expected_revision integer,reason text) returns void language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;report_id uuid;state text;
begin
 select * into old from public.occci_work_reports where id=target for update;
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid work report and reason / comments / notes';end if;
 if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before continuing';end if;
 if decision='Submit' then
  if public.occci_role()<>'Staff' or old.created_by<>auth.uid() or not public.occci_can_read_branch(old.branch_id) or old.status not in ('Draft','Returned') then raise exception 'Only Staff can submit their own draft or returned report';end if;
  if length(trim(old.summary))<3 or jsonb_array_length(old.documents)=0 then raise exception 'Add a work summary and original documents before BM review';end if;state:='For review';
 elsif decision in ('Approve','Return') then
  if public.occci_role()<>'BM' or not public.occci_can_read_branch(old.branch_id) or old.created_by=auth.uid() or old.status<>'For review' then raise exception 'Only the assigned BM can review submitted branch staff work';end if;
  state:=case decision when 'Approve' then 'Approved' else 'Returned' end;
  if decision='Approve' then
   if exists(select 1 from public.occci_work_reports w where w.created_by=old.created_by and w.frequency=old.frequency and w.period_start=old.period_start and w.period_end=old.period_end and w.status='Approved') then raise exception 'An approved report already exists for this staff member and period';end if;
   insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,status,summary,details,documents,created_by,reviewer,review_note)
   values('staff-'||lower(old.frequency),old.title,old.district,old.branch_id,old.period_start,old.period_end,'Approved',old.summary,old.metrics||jsonb_build_object('frequency',old.frequency,'staff_work_id',old.id),old.documents,old.created_by,auth.uid(),reason) returning id into report_id;
   insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,after_data,note)
   values(report_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Staff work approved and published',(select to_jsonb(r) from public.occci_reports r where id=report_id),reason);
  end if;
 else raise exception 'Choose submit, approve or return';end if;
 update public.occci_work_reports set status=state,reviewer=case when decision in ('Approve','Return') then auth.uid() else reviewer end,review_note=case when decision in ('Approve','Return') then reason else review_note end,published_report=coalesce(report_id,published_report),revision=revision+1,updated_at=now() where id=target;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(target,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Work report '||lower(decision),to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=target),reason);
end;$$;
revoke all on function public.occci_work_access(uuid,text),public.occci_save_work_report(uuid,jsonb,integer,text),public.occci_work_report_transition(uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.occci_work_access(uuid,text),public.occci_save_work_report(uuid,jsonb,integer,text),public.occci_work_report_transition(uuid,text,integer,text) to authenticated;
revoke all on function public.occci_report_access(smallint,text,boolean),public.occci_save_report(uuid,jsonb,integer,text),public.occci_report_transition(uuid,text,integer,text,date,text) from public,anon,authenticated;
grant execute on function public.occci_report_access(smallint,text,boolean),public.occci_save_report(uuid,jsonb,integer,text),public.occci_report_transition(uuid,text,integer,text,date,text) to authenticated;
insert into public.occci_schema_versions values('006_reports') on conflict do nothing;
notify pgrst,'reload schema';
commit;


-- 007_staff_invitations.sql
-- Apply after 006_reports.sql. Invitations do not grant roles; only Admin review does.
begin;
do $$ begin
 if to_regclass('public.occci_work_reports') is null then raise exception 'Apply 006_reports.sql first';end if;
end;$$;
alter table public.occci_profiles add column if not exists employee_id text;
alter table public.occci_profiles drop constraint if exists occci_employee_id_format;
alter table public.occci_profiles add constraint occci_employee_id_format check(employee_id is null or employee_id ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,49}$');
create unique index if not exists occci_employee_id_unique on public.occci_profiles(lower(employee_id)) where employee_id is not null;
alter table public.occci_staff_assignments drop constraint if exists occci_staff_assignments_role_check;
alter table public.occci_staff_assignments add constraint occci_staff_assignments_role_check check(role in ('Admin','DM','BM','Staff','BC'));
alter table public.occci_staff_assignments drop constraint if exists occci_assignment_scope;
alter table public.occci_staff_assignments add constraint occci_assignment_scope check((role='Admin') or (role='DM' and district is not null and district between 1 and 6) or (role in ('BM','Staff','BC') and branch_id is not null));

create table if not exists public.occci_staff_invites(
 id uuid primary key default gen_random_uuid(), code_hash bytea not null,
 label text not null check(length(label) between 1 and 150), created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), expires_at timestamptz not null,
 revoked_at timestamptz, redeemed_at timestamptz, redeemed_by uuid references auth.users(id),
 check(expires_at>created_at), check((redeemed_at is null)=(redeemed_by is null))
);
alter table public.occci_staff_invites enable row level security;
revoke all on public.occci_staff_invites from public,anon,authenticated;
-- Never expose the hash or reusable secret through REST. Only Admin may list metadata.
grant select(id,label,created_by,created_at,expires_at,revoked_at,redeemed_at,redeemed_by) on public.occci_staff_invites to authenticated;
drop policy if exists occci_staff_invites_read on public.occci_staff_invites;
create policy occci_staff_invites_read on public.occci_staff_invites for select to authenticated using(public.occci_role()='Admin');
alter table public.occci_staff_applications alter column requested_role drop not null;
alter table public.occci_staff_applications alter column district drop not null;
alter table public.occci_staff_applications alter column branch_id drop not null;
alter table public.occci_staff_applications add column if not exists invite_id uuid references public.occci_staff_invites(id);
alter table public.occci_staff_applications add column if not exists assigned_role text check(assigned_role in ('Admin','DM','BM','Staff','BC'));

create or replace function public.occci_invite_digest(invite uuid,code text) returns bytea language sql immutable set search_path='' as $$
 select sha256(convert_to(invite::text||':'||upper(regexp_replace(coalesce(code,''),'[[:space:]-]','','g')),'UTF8'));
$$;
create or replace function public.occci_verify_staff_invite(invite_id uuid,code text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_invites i where i.id=invite_id and i.code_hash=public.occci_invite_digest(invite_id,code) and i.expires_at>now() and i.revoked_at is null and i.redeemed_at is null);
$$;
create or replace function public.occci_create_staff_invite(label text,valid_days integer,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare invite uuid:=gen_random_uuid(); secret text:=upper(left(replace(gen_random_uuid()::text,'-',''),24)); expiry timestamptz;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only Admin can generate staff invitations';end if;
 if coalesce(length(trim(label)),0) not between 1 and 150 or valid_days is null or valid_days not between 1 and 30 or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a label, 1–30 days validity and reason / comments / notes';end if;
 expiry:=now()+make_interval(days=>valid_days);
 insert into public.occci_staff_invites(id,code_hash,label,created_by,expires_at) values(invite,public.occci_invite_digest(invite,secret),trim(label),auth.uid(),expiry);
 perform public.occci_log(null,null,'Staff invitation created',null,jsonb_build_object('invite_id',invite,'label',trim(label),'expires_at',expiry),reason);
 return jsonb_build_object('id',invite,'code',regexp_replace(secret,'(.{4})(.{4})(.{4})(.{4})(.{4})(.{4})','\1-\2-\3-\4-\5-\6'),'expires_at',expiry);
end;$$;
create or replace function public.occci_revoke_staff_invite(invite_id uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
declare i public.occci_staff_invites;
begin
 if public.occci_role()<>'Admin' or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Admin access and reason / comments / notes are required';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or i.redeemed_at is not null or i.revoked_at is not null then raise exception 'Choose an unused active invitation';end if;
 update public.occci_staff_invites set revoked_at=now() where id=invite_id;
 perform public.occci_log(null,null,'Staff invitation revoked',jsonb_build_object('invite_id',i.id,'label',i.label),jsonb_build_object('revoked_at',now()),reason);
end;$$;

-- User-editable auth metadata may create a placeholder, never a staff application or role.
create or replace function public.occci_handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; fullname_value text;
begin
 if coalesce(meta->>'registration_kind','Member')<>'Member' then raise exception 'Staff registration requires an Admin invitation';end if;
 if new.raw_app_meta_data->>'provider'='google' or meta->>'onboarding_source'='staff-invitation' then
  insert into public.occci_profiles(id,full_name,branch_id,avatar,onboarding_complete)
  values(new.id,coalesce(nullif(left(meta->>'full_name',100),''),'New member'),null,'lady',false);
  return new;
 end if;
 if not exists(select 1 from public.occci_branches where id=meta->>'branch_id' and active) or coalesce(length(trim(meta->>'first_name')),0) not between 1 and 50 or coalesce(length(trim(meta->>'last_name')),0) not between 1 and 50 or coalesce(length(meta->>'middle_name'),0)>50 or coalesce(length(trim(meta->>'contact_number')),0) not between 7 and 30 or coalesce(length(trim(meta->>'address')),0) not between 5 and 500 then raise exception 'Complete the required member details and choose an active branch';end if;
 fullname_value:=trim(concat_ws(' ',nullif(meta->>'first_name',''),nullif(meta->>'middle_name',''),nullif(meta->>'last_name','')));
 insert into public.occci_profiles(id,full_name,branch_id,avatar,last_name,first_name,middle_name,contact_number,address)
 values(new.id,coalesce(nullif(left(fullname_value,100),''),'Member'),meta->>'branch_id',case when meta->>'avatar' in ('man','farmer','lady','lola','boy','girl') then meta->>'avatar' else 'lady' end,left(coalesce(meta->>'last_name',''),50),left(coalesce(meta->>'first_name',''),50),left(coalesce(meta->>'middle_name',''),50),left(coalesce(meta->>'contact_number',''),30),left(coalesce(meta->>'address',''),500));
 return new;
end;$$;
create or replace function public.occci_staff_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if coalesce(new.raw_user_meta_data->>'registration_kind','Member')<>'Member' then raise exception 'Staff registration requires an Admin invitation';end if;
 return new;
end;$$;
create or replace function public.occci_complete_onboarding(values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; b public.occci_branches;
begin
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is not null or p.onboarding_complete then raise exception 'This account is not awaiting profile completion';end if;
 if coalesce(values_json->>'registration_kind','Member')<>'Member' then raise exception 'Staff registration requires an Admin invitation';end if;
 select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
 if not found or b.district::text<>coalesce(values_json->>'district','') then raise exception 'Choose an active branch in the selected district';end if;
 perform public.occci_profile_values(p.id,values_json||jsonb_build_object('membership_status','Pending verification'));
 update public.occci_profiles set branch_id=b.id,onboarding_complete=true,registration_kind='Member' where id=p.id;
 perform public.occci_log(p.id,b.id,'Registration profile completed',null,jsonb_build_object('registration_kind','Member','branch_id',b.id,'district',b.district),'Member profile completed; approval remains required');
end;$$;

create or replace function public.occci_submit_staff_application(invite_id uuid,code text,values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare i public.occci_staff_invites; p public.occci_profiles; fullname_value text; employee text:=trim(values_json->>'employee_id');
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Sign in with a verified email before sending your application';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is not null or p.membership_status='Active' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) or exists(select 1 from public.occci_staff_applications where user_id=p.id and status in ('Pending','Approved')) then raise exception 'This account already has membership, staff access or an application awaiting review';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or i.code_hash is distinct from public.occci_invite_digest(invite_id,code) or i.expires_at<=now() or i.revoked_at is not null or i.redeemed_at is not null then raise exception 'Invitation or code is invalid, expired or already used';end if;
 if values_json ?| array['role','requested_role','branch_id','district','membership_status'] then raise exception 'Admin assigns the position and scope after reviewing the application';end if;
 if coalesce(length(trim(values_json->>'first_name')),0) not between 1 and 50 or coalesce(length(trim(values_json->>'last_name')),0) not between 1 and 50 or coalesce(length(values_json->>'middle_name'),0)>50 or coalesce(length(trim(values_json->>'contact_number')),0) not between 7 and 30 or employee is null or employee !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,49}$' or coalesce(values_json->>'avatar','') not in ('man','farmer','lady','lola','boy','girl') then raise exception 'Enter your complete name, employee ID, contact number and choose a photo or avatar';end if;
 fullname_value:=trim(concat_ws(' ',nullif(trim(values_json->>'first_name'),''),nullif(trim(values_json->>'middle_name'),''),nullif(trim(values_json->>'last_name'),'')));
 if length(fullname_value)>100 then raise exception 'Complete name must be at most 100 characters';end if;
 if exists(select 1 from public.occci_profiles where lower(employee_id)=lower(employee) and id<>p.id) then raise exception 'Employee ID is already registered';end if;
 update public.occci_profiles set full_name=fullname_value,first_name=trim(values_json->>'first_name'),last_name=trim(values_json->>'last_name'),middle_name=coalesce(trim(values_json->>'middle_name'),''),contact_number=trim(values_json->>'contact_number'),employee_id=employee,avatar=values_json->>'avatar',registration_kind='Staff',onboarding_complete=true,branch_id=null,revision=revision+1 where id=p.id;
 insert into public.occci_staff_applications(user_id,requested_role,district,branch_id,invite_id)
 values(p.id,null,null,null,i.id) on conflict(user_id) do update set requested_role=null,district=null,branch_id=null,assigned_role=null,invite_id=excluded.invite_id,status='Pending',reviewed_by=null,review_note=null,reviewed_at=null,created_at=now();
 update public.occci_staff_invites set redeemed_by=p.id,redeemed_at=now() where id=i.id;
 perform public.occci_log(p.id,null,'Staff application submitted',null,jsonb_build_object('invite_id',i.id,'employee_id',employee,'status','Pending'),'Qualified invitation redeemed; Admin will assign position and scope');
end;$$;

-- The previous endpoint is intentionally disabled, including for older cached clients.
create or replace function public.occci_review_staff(target uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
begin raise exception 'Refresh the app and select an Admin-assigned position before approving staff';end;$$;
create or replace function public.occci_review_staff(target uuid,decision text,values_json jsonb,reason text) returns void language plpgsql security definer set search_path='' as $$
declare a public.occci_staff_applications; p public.occci_profiles; assigned text:=values_json->>'role'; b public.occci_branches; d smallint; employee text;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only cooperative Admin can approve staff positions';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Choose a decision and provide reason / comments / notes';end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or target=auth.uid() then raise exception 'Choose another pending staff applicant';end if;
 select * into a from public.occci_staff_applications where user_id=target for update;
 if not found or a.status<>'Pending' then raise exception 'Choose a pending staff applicant';end if;
 if decision='Approve' then
  if not exists(select 1 from auth.users where id=target and email_confirmed_at is not null) then raise exception 'Applicant must confirm their email before approval';end if;
  if exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Applicant already has a team assignment';end if;
  if assigned is null or assigned not in ('Admin','DM','BM','Staff','BC') then raise exception 'Select the position to assign';end if;
  employee:=coalesce(nullif(trim(values_json->>'employee_id'),''),p.employee_id);
  if employee is null or employee !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,49}$' then raise exception 'Record a valid employee ID before approval';end if;
  if exists(select 1 from public.occci_profiles where lower(employee_id)=lower(employee) and id<>target) then raise exception 'Employee ID is already registered';end if;
  if assigned='DM' then
   d:=(values_json->>'district')::smallint;
   if d is null or not exists(select 1 from public.occci_branches where active and district=d) then raise exception 'Choose an active district';end if;
  elsif assigned in ('BM','Staff','BC') then
   select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
   if not found then raise exception 'Choose an active branch';end if;
   d:=b.district;
  end if;
  insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(target,assigned,case when assigned in ('BM','Staff','BC') then b.id end,case when assigned='DM' then d end);
  update public.occci_profiles set employee_id=employee,branch_id=case when assigned in ('BM','Staff','BC') then b.id end,revision=revision+1 where id=target;
 end if;
 update public.occci_staff_applications set status=case decision when 'Approve' then 'Approved' else 'Rejected' end,assigned_role=case when decision='Approve' then assigned end,requested_role=null,district=case when decision='Approve' then d else a.district end,branch_id=case when decision='Approve' then b.id else a.branch_id end,reviewed_by=auth.uid(),review_note=reason,reviewed_at=now() where user_id=target;
 perform public.occci_log(target,case when decision='Approve' then b.id else a.branch_id end,'Staff application reviewed',to_jsonb(a),jsonb_build_object('decision',decision,'role',case when decision='Approve' then assigned end,'district',d,'branch_id',b.id,'employee_id',employee),reason);
 if decision='Approve' then perform public.occci_log(target,b.id,'Team assignment approved',null,jsonb_build_object('role',assigned,'district',case when assigned='DM' then d end,'branch_id',b.id),reason);end if;
end;$$;

revoke all on function public.occci_invite_digest(uuid,text),public.occci_verify_staff_invite(uuid,text),public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text),public.occci_submit_staff_application(uuid,text,jsonb),public.occci_review_staff(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_verify_staff_invite(uuid,text) to anon,authenticated;
grant execute on function public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text),public.occci_submit_staff_application(uuid,text,jsonb),public.occci_review_staff(uuid,text,jsonb,text) to authenticated;
-- Branch Cashier extensions follow. Existing manager approval gates remain unchanged.
create or replace function public.occci_can_read_branch(target_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s left join public.occci_branches b on b.id=target_branch where s.user_id=auth.uid() and (s.role='Admin' or (s.role='DM' and s.district=b.district) or (s.role in ('BM','Staff','BC') and s.branch_id=target_branch)));
$$;

create or replace function public.occci_submit_change(target uuid,request_kind text,values_json jsonb,evidence text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role(); request_id uuid; rev integer; item jsonb;
begin
 select * into p from public.occci_profiles where id=target;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM','Staff','BC') or p.archived_at is not null then raise exception 'Request is not permitted';end if;
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

create or replace function public.occci_assign_account(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles;
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or not public.occci_can_read_branch(p.branch_id) or public.occci_role() not in ('Admin','DM','BM','Staff','BC') then raise exception 'Account assignment is not permitted in this branch';end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before assigning an ID';end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid official ID and reason, comments or notes';end if;
 perform pg_catalog.pg_advisory_xact_lock(771005);
 if exists(select 1 from public.occci_profiles where lower(account_number)=lower(trim(account)) and id<>target) then raise exception 'This account number is already assigned to another member';end if;
 update public.occci_profiles set account_number=trim(account),revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Official ID assigned',jsonb_build_object('account_number',p.account_number),jsonb_build_object('account_number',trim(account)),reason);
end;$$;

create or replace function public.occci_apply_authorized_edit(request_id uuid,values_json jsonb,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; p public.occci_profiles;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or q.kind<>'Profile edit' or q.status<>'BM approved' or coalesce(q.proposed->>'permission_only','false')<>'true' or q.submitted_by<>auth.uid() or public.occci_role() not in ('Staff','BC') or not public.occci_can_read_branch(q.branch_id) then raise exception 'Wait for BM or DM approval before editing this member';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide reason, comments or notes for the edit';end if;
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.revision<>q.base_revision or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member details changed; request new approval';end if;
 perform public.occci_profile_values(q.member_id,values_json);
 update public.occci_change_requests set status='Applied',proposed=values_json,reviewed_at=now() where id=request_id;
 perform public.occci_log(q.member_id,q.branch_id,'Approved member edit applied',to_jsonb(p),values_json||jsonb_build_object('request_id',request_id),reason);
end;$$;

create or replace function public.occci_approve_member(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role();
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM','Staff','BC') then raise exception 'Membership approval is not permitted in this branch'; end if;
 if p.registration_kind='Staff' then raise exception 'Use Staff Applications to approve and assign this employee';end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before approval';end if;
 if p.membership_status<>'Pending verification' or p.archived_at is not null then raise exception 'This membership is not pending'; end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid unique account number and approval note'; end if;
 perform public.occci_assign_account(target,account,reason);
 update public.occci_profiles set membership_status='Active',revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Membership approved',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',trim(account)),reason);
end;$$;

create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
declare r text:=public.occci_role(); p public.occci_profiles; c public.occci_content; b public.occci_branches; target_branch text; target_district smallint; previous jsonb; uid uuid;
begin
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Enter reason, comments or notes (at least 3 characters)';end if;
 if record_kind='Member' then
 select * into p from public.occci_profiles where id=record_id::uuid for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('Admin','DM','BM') then raise exception 'Staff must request BM approval before changing member details';end if;
 if p.archived_at is not null then raise exception 'This member is already archived';end if;
 if remove_record then
 if r<>'Admin' then raise exception 'Only Admin can archive a member';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if exists(select 1 from public.occci_staff_assignments where user_id=p.id and role='Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles active_profile on active_profile.id=s.user_id where s.role='Admin' and s.user_id<>p.id and active_profile.archived_at is null) then raise exception 'Keep at least one Admin before archiving this account';end if;
 update public.occci_profiles set archived_at=now(),revision=revision+1 where id=p.id;
 delete from public.occci_staff_assignments where user_id=p.id;
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
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=record_id::uuid;
 if previous->>'role'='Admin' and (remove_record or coalesce(values_json->>'role','')<>'Admin') and not exists(select 1 from public.occci_staff_assignments s join public.occci_profiles other_profile on other_profile.id=s.user_id where s.role='Admin' and s.user_id<>record_id::uuid and other_profile.archived_at is null) then raise exception 'Keep at least one Admin. Assign another Admin before changing or removing this assignment';end if;
 if remove_record then delete from public.occci_staff_assignments where user_id=record_id::uuid;
 else
 if not exists(select 1 from public.occci_profiles target_profile join auth.users u on u.id=target_profile.id where target_profile.id=record_id::uuid and target_profile.archived_at is null and target_profile.onboarding_complete and u.email_confirmed_at is not null) then raise exception 'Choose an account with confirmed email and completed profile';end if;
 if exists(select 1 from public.occci_staff_applications where user_id=record_id::uuid and status='Pending') then raise exception 'Review the pending applicant in Staff Applications first';end if;
 if coalesce(values_json->>'role','') not in ('Admin','DM','BM','Staff','BC') then raise exception 'Choose a valid role';end if;
 if values_json->>'role'='Admin' then values_json:=jsonb_build_object('role','Admin','branch_id',null,'district',null);
 elsif values_json->>'role'='DM' then
 if not exists(select 1 from public.occci_branches where active and district=nullif(values_json->>'district','')::smallint) then raise exception 'Choose a district with active branches';end if;
 values_json:=jsonb_build_object('role','DM','branch_id',null,'district',(values_json->>'district')::smallint);
 else
 if not exists(select 1 from public.occci_branches where id=values_json->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
 values_json:=jsonb_build_object('role',values_json->>'role','branch_id',values_json->>'branch_id','district',null);
 end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(record_id::uuid,values_json->>'role',nullif(values_json->>'branch_id',''),nullif(values_json->>'district','')::smallint) on conflict(user_id) do update set role=excluded.role,branch_id=excluded.branch_id,district=excluded.district;
 end if;
 insert into public.occci_audit(actor,member_id,branch_id,action,before_data,after_data,note,actor_name,actor_role) values(auth.uid(),record_id::uuid,null,'Team assignment changed',previous,case when remove_record then jsonb_build_object('role','Member') else values_json end,reason,(select full_name from public.occci_profiles where id=auth.uid()),r);
 else raise exception 'Unknown record type';end if;
end;$$;

create or replace function public.occci_apply_edit(request_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; p public.occci_profiles;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or q.kind<>'Profile edit' or coalesce(q.proposed->>'permission_only','false')='true' or q.status<>'BM approved' or q.submitted_by<>auth.uid() or not public.occci_can_read_branch(q.branch_id) or public.occci_role() not in ('Staff','BC','BM','DM','Admin') then raise exception 'Only the requesting staff member can apply this approved edit';end if;
 select * into p from public.occci_profiles where id=q.member_id for update;
 if p.revision<>q.base_revision or p.archived_at is not null or p.branch_id<>q.branch_id then raise exception 'Member details changed; submit a new edit request';end if;
 perform public.occci_profile_values(q.member_id,q.proposed);
 update public.occci_change_requests set status='Applied',reviewed_at=now() where id=request_id;
 perform public.occci_log(q.member_id,q.branch_id,'Approved member edit applied',to_jsonb(p),q.proposed,q.note);
end;$$;

create or replace function public.occci_save_work_report(target uuid,values_json jsonb,expected_revision integer,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;assignment public.occci_staff_assignments;result_id uuid;start_date date;end_date date;freq text;doc jsonb;docs jsonb;total bigint:=0;seen text[]:='{}';entry record;metrics_value jsonb;
begin
 select * into assignment from public.occci_staff_assignments where user_id=auth.uid() and role in ('Staff','BC');
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Staff assignment and reason / comments / notes are required';end if;
 if target is not null then
  select * into old from public.occci_work_reports where id=target for update;
  if not found or old.created_by<>auth.uid() or old.branch_id<>assignment.branch_id or old.status not in ('Draft','Returned') then raise exception 'Only your draft or returned work report can be edited';end if;
  if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before saving';end if;
 end if;
 freq:=values_json->>'frequency';start_date:=(values_json->>'period_start')::date;end_date:=(values_json->>'period_end')::date;
 if freq is null or freq not in ('Daily','Weekly','Monthly') or start_date is null or end_date is null or (freq='Daily' and end_date<>start_date) or (freq='Weekly' and (end_date<>start_date+6 or extract(isodow from start_date)<>1)) or (freq='Monthly' and (extract(day from start_date)<>1 or end_date<>(date_trunc('month',start_date)+interval '1 month - 1 day')::date)) then raise exception 'Use one day, seven days, or a complete calendar month for the report period';end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 3 and 150 or coalesce(length(values_json->>'summary'),0)>10000 then raise exception 'Provide a valid title and work summary';end if;
 metrics_value:=coalesce(values_json->'metrics','{}');
 if jsonb_typeof(metrics_value) is distinct from 'object' then raise exception 'Invalid work totals';end if;
 for entry in select * from jsonb_each_text(metrics_value) loop
  if entry.key not in ('registrations','account_updates','savings_collections','loan_releases','loan_repayments','followups') or entry.value is null or entry.value::numeric<0 or entry.value::numeric>99999999999999 then raise exception 'Invalid work totals';end if;
  if entry.key in ('registrations','account_updates','followups') and entry.value::numeric<>trunc(entry.value::numeric) then raise exception 'Work counts must be whole numbers';end if;
 end loop;
 docs:=coalesce(values_json->'documents','[]');
 if jsonb_typeof(docs) is distinct from 'array' or jsonb_array_length(docs)>10 then raise exception 'Attach at most 10 source documents';end if;
 for doc in select * from jsonb_array_elements(docs) loop
  if coalesce(doc->>'path','') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-reports' and name=doc->>'path') or coalesce(length(doc->>'name'),0) not between 1 and 255 or coalesce((doc->>'size')::bigint,0) not between 1 and 10485760 or (doc->>'path')=any(seen) then raise exception 'Invalid private source attachment';end if;
  total:=total+(doc->>'size')::bigint;seen:=array_append(seen,doc->>'path');
 end loop;
 if total>52428800 then raise exception 'Source documents exceed 50 MB';end if;
 if target is null then
  insert into public.occci_work_reports(created_by,branch_id,district,frequency,title,period_start,period_end,summary,metrics,documents)
  values(auth.uid(),assignment.branch_id,(select district from public.occci_branches where id=assignment.branch_id),freq,trim(values_json->>'title'),start_date,end_date,coalesce(values_json->>'summary',''),metrics_value,docs) returning id into result_id;
 else
  update public.occci_work_reports set frequency=freq,title=trim(values_json->>'title'),period_start=start_date,period_end=end_date,summary=coalesce(values_json->>'summary',''),metrics=metrics_value,documents=docs,revision=revision+1,updated_at=now() where id=target;result_id:=target;
 end if;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(result_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),case when target is null then 'Work report created' else 'Work report updated' end,to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=result_id),reason);
 return result_id;
end;$$;

create or replace function public.occci_work_report_transition(target uuid,decision text,expected_revision integer,reason text) returns void language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;report_id uuid;state text;
begin
 select * into old from public.occci_work_reports where id=target for update;
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid work report and reason / comments / notes';end if;
 if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before continuing';end if;
 if decision='Submit' then
  if public.occci_role() not in ('Staff','BC') or old.created_by<>auth.uid() or not public.occci_can_read_branch(old.branch_id) or old.status not in ('Draft','Returned') then raise exception 'Only Staff can submit their own draft or returned report';end if;
  if length(trim(old.summary))<3 or jsonb_array_length(old.documents)=0 then raise exception 'Add a work summary and original documents before BM review';end if;state:='For review';
 elsif decision in ('Approve','Return') then
  if public.occci_role()<>'BM' or not public.occci_can_read_branch(old.branch_id) or old.created_by=auth.uid() or old.status<>'For review' then raise exception 'Only the assigned BM can review submitted branch staff work';end if;
  state:=case decision when 'Approve' then 'Approved' else 'Returned' end;
  if decision='Approve' then
   if exists(select 1 from public.occci_work_reports w where w.created_by=old.created_by and w.frequency=old.frequency and w.period_start=old.period_start and w.period_end=old.period_end and w.status='Approved') then raise exception 'An approved report already exists for this staff member and period';end if;
   insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,status,summary,details,documents,created_by,reviewer,review_note)
   values('staff-'||lower(old.frequency),old.title,old.district,old.branch_id,old.period_start,old.period_end,'Approved',old.summary,old.metrics||jsonb_build_object('frequency',old.frequency,'staff_work_id',old.id),old.documents,old.created_by,auth.uid(),reason) returning id into report_id;
   insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,after_data,note)
   values(report_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Staff work approved and published',(select to_jsonb(r) from public.occci_reports r where id=report_id),reason);
  end if;
 else raise exception 'Choose submit, approve or return';end if;
 update public.occci_work_reports set status=state,reviewer=case when decision in ('Approve','Return') then auth.uid() else reviewer end,review_note=case when decision in ('Approve','Return') then reason else review_note end,published_report=coalesce(report_id,published_report),revision=revision+1,updated_at=now() where id=target;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(target,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Work report '||lower(decision),to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=target),reason);
end;$$;

drop policy if exists occci_document_insert on storage.objects;
create policy occci_document_insert on storage.objects for insert to authenticated with check(bucket_id='occci-documents' and (storage.foldername(name))[1]=auth.uid()::text and public.occci_role() in ('Staff','BC','BM','DM','Admin'));

drop policy if exists occci_report_types_read on public.occci_report_types;
create policy occci_report_types_read on public.occci_report_types for select to authenticated using((public.occci_role() in ('Admin','DM','BM') or public.occci_role() in ('Staff','BC') and category='Work'));

drop policy if exists occci_report_upload on storage.objects;
create policy occci_report_upload on storage.objects for insert to authenticated with check(bucket_id='occci-reports' and public.occci_role() in ('Admin','DM','BM','Staff','BC') and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and ((public.occci_role() in ('Admin','DM','BM','Staff','BC') and (storage.foldername(name))[1]=auth.uid()::text) or exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',name))) or exists(select 1 from public.occci_work_reports w where public.occci_work_access(w.created_by,w.branch_id) and w.documents @> jsonb_build_array(jsonb_build_object('path',name)))));

insert into public.occci_schema_versions(version) values('007_staff_invitations') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 007. Admin review drafts never grant a position or CMS access.
begin;
alter table public.occci_staff_applications add column if not exists review_draft jsonb not null default '{}' check(jsonb_typeof(review_draft)='object');
alter table public.occci_staff_applications add column if not exists draft_saved_by uuid references auth.users(id);
alter table public.occci_staff_applications add column if not exists draft_saved_at timestamptz;

create or replace function public.occci_save_staff_review(target uuid,values_json jsonb,reason text) returns void
language plpgsql security definer set search_path='' as $$
declare
 a public.occci_staff_applications;
 p public.occci_profiles;
 b public.occci_branches;
 choice text:=coalesce(values_json->>'decision','Approve');
 assigned text:=values_json->>'role';
 employee text;
 d smallint;
 draft jsonb;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only cooperative Admin can save staff reviews';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or choice not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then
  raise exception 'Choose a decision and provide reason / comments / notes';
 end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or target=auth.uid() then raise exception 'Choose another pending staff applicant';end if;
 select * into a from public.occci_staff_applications where user_id=target for update;
 if not found or a.status<>'Pending' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a pending staff applicant without an assigned position';end if;
 draft:=jsonb_build_object('decision',choice,'note',trim(reason));
 if choice='Approve' then
  if assigned is null or assigned not in ('Admin','DM','BM','Staff','BC') then raise exception 'Select the position to assign';end if;
  employee:=coalesce(nullif(trim(values_json->>'employee_id'),''),p.employee_id);
  if employee is null or employee !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,49}$' then raise exception 'Record a valid employee ID before saving the review';end if;
  if exists(select 1 from public.occci_profiles where lower(employee_id)=lower(employee) and id<>target) then raise exception 'Employee ID is already registered';end if;
  if assigned='DM' then
   d:=(values_json->>'district')::smallint;
   if d is null or not exists(select 1 from public.occci_branches where active and district=d) then raise exception 'Choose an active district';end if;
  elsif assigned in ('BM','Staff','BC') then
   select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
   if not found then raise exception 'Choose an active branch';end if;
   d:=b.district;
  end if;
  draft:=draft||jsonb_build_object('role',assigned,'employee_id',employee,'district',d,'branch_id',b.id);
 end if;
 update public.occci_staff_applications set review_draft=draft,draft_saved_by=auth.uid(),draft_saved_at=now() where user_id=target;
 perform public.occci_log(target,b.id,'Staff review saved as pending',jsonb_build_object('status',a.status,'review_draft',a.review_draft),jsonb_build_object('status','Pending','review_draft',draft),trim(reason));
end;$$;

revoke all on function public.occci_save_staff_review(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_save_staff_review(uuid,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('008_staff_review_drafts') on conflict do nothing;
notify pgrst,'reload schema';
commit;
