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

-- Apply after 008. Branch/district isolation and BM screening followed by final DM approval.
begin;
alter table public.occci_profiles add column if not exists email text;
update public.occci_profiles p set email=u.email from auth.users u where u.id=p.id and p.email is distinct from u.email;
create or replace function public.occci_sync_identity_email() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.occci_profiles set email=new.email where id=new.id;
 return new;
end;$$;
drop trigger if exists z_occci_identity_email on auth.users;
create trigger z_occci_identity_email after insert or update of email on auth.users for each row execute function public.occci_sync_identity_email();
revoke all on function public.occci_sync_identity_email() from public,anon,authenticated;

create or replace function public.occci_can_read_profile(target uuid,target_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (target=auth.uid() or public.occci_role()='Admin' or
 case when exists(select 1 from public.occci_staff_assignments where user_id=target)
 then exists(select 1 from public.occci_staff_assignments s where s.user_id=target and
  ((s.role='DM' and public.occci_role()='DM' and s.district=public.occci_district()) or
   (s.role in ('BM','Staff','BC') and public.occci_can_read_branch(s.branch_id))))
 else public.occci_can_read_branch(target_branch) end);
$$;
drop policy if exists occci_profile_read on public.occci_profiles;
create policy occci_profile_read on public.occci_profiles for select to authenticated using(public.occci_can_read_profile(id,branch_id));

alter table public.occci_audit add column if not exists district smallint;
create or replace function public.occci_capture_audit_scope() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.branch_id is null then
  if coalesce(new.after_data->>'role','')='DM' then
   if coalesce(new.after_data->>'district','') ~ '^[1-6]$' then new.district:=(new.after_data->>'district')::smallint;end if;
  elsif coalesce(new.after_data->>'role','')='Admin' then new.district:=null;
  elsif exists(select 1 from public.occci_branches b where b.id=coalesce(new.after_data->>'branch_id',new.before_data->>'branch_id')) then
   select b.id,b.district into new.branch_id,new.district from public.occci_branches b
    where b.id=coalesce(new.after_data->>'branch_id',new.before_data->>'branch_id');
  end if;
 end if;
 if new.branch_id is not null then select b.district into new.district from public.occci_branches b where b.id=new.branch_id;end if;
 return new;
end;$$;
drop trigger if exists occci_audit_scope on public.occci_audit;
create trigger occci_audit_scope before insert on public.occci_audit for each row execute function public.occci_capture_audit_scope();
revoke all on function public.occci_capture_audit_scope() from public,anon,authenticated;
-- Capture the event's workplace rather than the actor's current workplace.
update public.occci_audit a set branch_id=coalesce(a.after_data->>'branch_id',a.before_data->>'branch_id')
 where a.branch_id is null and coalesce(a.after_data->>'role','') not in ('Admin','DM')
 and exists(select 1 from public.occci_branches b where b.id=coalesce(a.after_data->>'branch_id',a.before_data->>'branch_id'));
update public.occci_audit a set district=coalesce((select b.district from public.occci_branches b where b.id=a.branch_id),
 case when coalesce(a.after_data->>'district',a.before_data->>'district') ~ '^[1-6]$'
 then coalesce(a.after_data->>'district',a.before_data->>'district')::smallint end) where district is null;
create or replace function public.occci_can_read_audit(target uuid,branch text,event_district smallint) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (public.occci_role()='Admin' or
 (public.occci_role()='Member' and target=auth.uid()) or
 public.occci_can_read_branch(branch) or
 (public.occci_role()='DM' and branch is null and event_district=public.occci_district()));
$$;
drop policy if exists occci_audit_read on public.occci_audit;
create policy occci_audit_read on public.occci_audit for select to authenticated using(public.occci_can_read_audit(member_id,branch_id,district));
create or replace function public.occci_log(target uuid,branch text,action_name text,previous jsonb,new_data jsonb,reason text) returns void language sql security definer set search_path='' as $$
 insert into public.occci_audit(actor,member_id,branch_id,district,action,before_data,after_data,note,actor_name,actor_role)
 values(auth.uid(),target,branch,coalesce((select b.district from public.occci_branches b where b.id=branch),
 case when coalesce(new_data->>'district',previous->>'district') ~ '^[1-6]$' then coalesce(new_data->>'district',previous->>'district')::smallint end),
 action_name,previous,new_data,reason,(select full_name from public.occci_profiles where id=auth.uid()),case when auth.uid() is not null then public.occci_role() end);
$$;
create or replace function public.occci_activity() returns setof public.occci_audit language sql stable security definer set search_path='' as $$
 select jsonb_populate_record(null::public.occci_audit,to_jsonb(a)||jsonb_build_object('actor_name',coalesce(a.actor_name,p.full_name,case when a.actor is null then 'System' else 'Cooperative user' end)))
 from public.occci_audit a left join public.occci_profiles p on p.id=a.actor
 where public.occci_can_read_audit(a.member_id,a.branch_id,a.district)
 order by a.created_at desc,a.id desc;
$$;

create or replace function public.occci_report_access(d smallint,b text,write_access boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(public.occci_role()='Admin' or
 (public.occci_role()='DM' and d=public.occci_district() and (b is null or public.occci_can_read_branch(b))) or
 (public.occci_role()='BM' and b is not null and public.occci_can_read_branch(b)),false);
$$;
create or replace function public.occci_work_access(owner_id uuid,b text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.occci_can_read_branch(b) and (public.occci_role() in ('Admin','DM','BM') or public.occci_role() in ('Staff','BC') and owner_id=auth.uid());
$$;

create or replace function public.occci_can_read_document(bucket text,object_path text) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then return false;end if;
 if bucket='occci-documents' then
  return exists(select 1 from public.occci_change_requests q where public.occci_can_read_branch(q.branch_id) and (q.evidence_path=object_path or q.evidence_files @> jsonb_build_array(jsonb_build_object('path',object_path))))
   or exists(select 1 from public.occci_financials f join public.occci_profiles p on p.id=f.member_id where public.occci_can_read_profile(p.id,p.branch_id) and (f.evidence_path=object_path or f.evidence_files @> jsonb_build_array(jsonb_build_object('path',object_path))))
   or (object_path like auth.uid()::text||'/%' and not exists(select 1 from public.occci_change_requests q where q.evidence_path=object_path or q.evidence_files @> jsonb_build_array(jsonb_build_object('path',object_path))) and not exists(select 1 from public.occci_financials f where f.evidence_path=object_path or f.evidence_files @> jsonb_build_array(jsonb_build_object('path',object_path))));
 elsif bucket='occci-reports' then
  return exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',object_path)))
   or exists(select 1 from public.occci_work_reports w where public.occci_work_access(w.created_by,w.branch_id) and w.documents @> jsonb_build_array(jsonb_build_object('path',object_path)))
   or (object_path like auth.uid()::text||'/%' and not exists(select 1 from public.occci_reports r where r.documents @> jsonb_build_array(jsonb_build_object('path',object_path))) and not exists(select 1 from public.occci_work_reports w where w.documents @> jsonb_build_array(jsonb_build_object('path',object_path))));
 end if;
 return false;
end;$$;
revoke all on function public.occci_can_read_document(text,text) from public,anon,authenticated;
grant execute on function public.occci_can_read_document(text,text) to authenticated;
drop policy if exists occci_document_read on storage.objects;
create policy occci_document_read on storage.objects for select to authenticated using(bucket_id='occci-documents' and public.occci_can_read_document(bucket_id,name));
drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and public.occci_can_read_document(bucket_id,name));
drop policy if exists occci_avatar_read on storage.objects;
create policy occci_avatar_read on storage.objects for select to authenticated using(bucket_id='occci-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_profiles p where p.photo_path=name and public.occci_can_read_profile(p.id,p.branch_id))));

alter table public.occci_change_requests drop constraint if exists occci_change_requests_kind_check;
alter table public.occci_change_requests add constraint occci_change_requests_kind_check check(kind in ('Profile edit','Financial sync','Membership approval'));
alter table public.occci_change_requests add column if not exists workflow_version smallint not null default 1;
-- Unfinished requests from the old DM/Admin flow must receive BM screening.
insert into public.occci_audit(member_id,branch_id,district,action,before_data,after_data,note,actor_name,actor_role)
 select q.member_id,q.branch_id,b.district,'Financial approval workflow updated',
 jsonb_build_object('request_id',q.id,'status',q.status,'bm_reviewer',q.bm_reviewer,'dm_reviewer',q.dm_reviewer,'admin_reviewer',q.admin_reviewer,'reviewed_at',q.reviewed_at,'workflow_version',q.workflow_version,'review_note',q.review_note),
 jsonb_build_object('request_id',q.id,'status','Pending','workflow_version',2),
 'BM screening is now required before final approval by the assigned District Manager. Previous review remains recorded here.','System','System'
 from public.occci_change_requests q join public.occci_branches b on b.id=q.branch_id
 where q.kind='Financial sync' and q.workflow_version=1 and q.status in ('Pending','DM approved');
update public.occci_change_requests set status='Pending',workflow_version=2,bm_reviewer=null,dm_reviewer=null,admin_reviewer=null,
 review_note='Awaiting BM screening under the BM / DM approval workflow',reviewed_at=null
 where kind='Financial sync' and workflow_version=1 and status in ('Pending','DM approved');


create or replace function public.occci_profile_values(target uuid,values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare fn text; ln text; mn text; contact text; addr text; status_value text; avatar_value text;
begin
 fn:=trim(values_json->>'first_name'); ln:=trim(values_json->>'last_name');mn:=trim(coalesce(values_json->>'middle_name',''));contact:=trim(values_json->>'contact_number');addr:=trim(values_json->>'address');status_value:=values_json->>'membership_status';avatar_value:=values_json->>'avatar';
 if coalesce(length(fn),0) not between 1 and 50 or coalesce(length(ln),0) not between 1 and 50 or length(mn)>50 or coalesce(length(contact),0) not between 7 and 30 or coalesce(length(addr),0) not between 5 and 500 or status_value is null or status_value not in ('Active','Suspended','Pending verification') or avatar_value is null or avatar_value not in ('man','farmer','lady','lola','boy','girl') then raise exception 'Invalid member details'; end if;
 if status_value='Active' and exists(select 1 from public.occci_profiles where id=target and membership_status='Pending verification') then raise exception 'Membership activation requires BM screening and final DM approval';end if;
 if status_value='Active' and not exists(select 1 from public.occci_profiles where id=target and account_number is not null) then raise exception 'Approve membership and assign an account number first';end if;
 update public.occci_profiles set first_name=fn,last_name=ln,middle_name=mn,full_name=left(trim(concat_ws(' ',fn,nullif(mn,''),ln)),100),contact_number=contact,address=addr,membership_status=status_value,avatar=avatar_value,revision=revision+1 where id=target;
end;$$;

create or replace function public.occci_assign_account(target uuid,account text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles;
begin
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or not public.occci_can_read_branch(p.branch_id) or public.occci_role() not in ('DM','BM','Staff','BC') then raise exception 'Account assignment is not permitted in this branch';end if;
 if p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Use team assignment to manage employee IDs';end if;
 if not p.onboarding_complete then raise exception 'Complete the member profile before assigning an ID';end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid official ID and reason, comments or notes';end if;
 perform pg_catalog.pg_advisory_xact_lock(771005);
 if exists(select 1 from public.occci_profiles where lower(account_number)=lower(trim(account)) and id<>target) then raise exception 'This account number is already assigned to another member';end if;
 update public.occci_profiles set account_number=trim(account),revision=revision+1 where id=target;
 perform public.occci_log(target,p.branch_id,'Official ID assigned',jsonb_build_object('account_number',p.account_number),jsonb_build_object('account_number',trim(account)),reason);
end;$$;

create or replace function public.occci_submit_change(target uuid,request_kind text,values_json jsonb,evidence text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role(); request_id uuid; rev integer; item jsonb;
begin
 select * into p from public.occci_profiles where id=target;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('DM','BM','Staff','BC') or p.archived_at is not null then raise exception 'Request is not permitted';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a request note';end if;
 if request_kind='Profile edit' then rev:=p.revision;
 elsif request_kind='Financial sync' then
 if r not in ('BM','Staff','BC') then raise exception 'Branch Staff, BC or BM submit actual balances; the assigned DM performs final approval';end if;
 if p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a cooperative member';end if;
 if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates'; end if;
 if coalesce(evidence,'') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-documents' and name=evidence) then raise exception 'Upload a source document first';end if;
 if lower(coalesce(values_json->>'savings','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'loan_balance','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'annual_interest','')) in ('nan','infinity','-infinity') then raise exception 'Finite financial amounts are required';end if;
 if coalesce(values_json->>'source_reference','')='' or (values_json->>'as_of')::date is null or (values_json->>'savings')::numeric<0 or (values_json->>'loan_balance')::numeric<0 or (values_json->>'annual_interest')::numeric not between 0 and 100 or values_json->>'loan_status' is null or values_json->>'loan_status' not in ('No active loan','Active','Paid','Overdue','Restructured') or coalesce(jsonb_typeof(values_json->'schedule'),'')<>'array' then raise exception 'Invalid financial details'; end if;
 if values_json->>'savings' is null or values_json->>'loan_balance' is null or values_json->>'annual_interest' is null then raise exception 'Financial amounts are required';end if;
 if jsonb_array_length(values_json->'schedule')>360 then raise exception 'Use at most 360 scheduled payments';end if;
 for item in select * from jsonb_array_elements(values_json->'schedule') loop
 if coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(item->>'status','') not in ('Scheduled','Paid','Overdue','Rescheduled','Cancelled') then raise exception 'Invalid payment date or status';end if;
 if lower(coalesce(item->>'amount','')) in ('nan','infinity','-infinity') then raise exception 'Invalid payment schedule';end if;
 if (item->>'date')::date is null or item->>'amount' is null or (item->>'amount')::numeric<0 then raise exception 'Invalid payment schedule';end if;
 end loop;
 select coalesce((select revision from public.occci_financials where member_id=target),0) into rev;
 else raise exception 'Invalid request type';end if;
 insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,evidence_path,note,workflow_version) values(target,p.branch_id,request_kind,values_json,rev,auth.uid(),evidence,reason,2) returning id into request_id;
 perform public.occci_log(target,p.branch_id,'Request submitted',null,jsonb_build_object('request_id',request_id,'kind',request_kind,'proposed',values_json),reason);
 if request_kind='Financial sync' and r='BM' then
 update public.occci_change_requests set status='BM approved',bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 perform public.occci_log(target,p.branch_id,'Financial request screened by BM',null,jsonb_build_object('request_id',request_id,'status','BM approved'),reason);
 end if;
 return request_id;
end;$$;

create or replace function public.occci_submit_financial_documents(target uuid,values_json jsonb,documents jsonb,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare d jsonb; request_id uuid; total bigint:=0; paths text[]:='{}';
begin
 if public.occci_role() not in ('BM','Staff','BC') then raise exception 'Branch Staff, BC or BM submit actual balances; the assigned DM performs final approval';end if;
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
declare p public.occci_profiles; request_id uuid;
begin
 if public.occci_role()<>'BM' then raise exception 'Only the assigned BM screens new members; the assigned DM provides final approval';end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or not public.occci_can_read_branch(p.branch_id) or p.archived_at is not null or p.membership_status<>'Pending verification' or not p.onboarding_complete or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a pending cooperative member in your assigned branch';end if;
 if coalesce(trim(account),'')!~'^[A-Za-z0-9][A-Za-z0-9/-]{2,39}$' or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a valid unique account number and screening note';end if;
 if exists(select 1 from public.occci_profiles where lower(account_number)=lower(trim(account)) and id<>target) then raise exception 'This account number is already assigned';end if;
 if exists(select 1 from public.occci_change_requests where member_id=target and kind='Membership approval' and status in ('Pending','BM approved')) then raise exception 'This member already awaits DM approval';end if;
 insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,status,bm_reviewer,note,review_note,reviewed_at,workflow_version)
 values(target,p.branch_id,'Membership approval',jsonb_build_object('account_number',trim(account)),p.revision,auth.uid(),'BM approved',auth.uid(),trim(reason),trim(reason),now(),2) returning id into request_id;
 perform public.occci_log(target,p.branch_id,'Membership screened by BM',jsonb_build_object('membership_status',p.membership_status),jsonb_build_object('request_id',request_id,'account_number',trim(account),'status','BM approved'),reason);
end;$$;

create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) or q.submitted_by=auth.uid() then raise exception 'Review requires a different authorized reviewer in the assigned branch or district';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Choose a decision and provide a review note';end if;
 if q.kind='Profile edit' then
  if r not in ('BM','DM') or q.status<>'Pending' then raise exception 'Profile edits require the assigned BM or DM approval';end if;
  target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
  update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 elsif q.kind in ('Financial sync','Membership approval') then
  if q.status='Pending' and q.kind='Financial sync' and r='BM' then
   target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
   update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
  elsif q.status='BM approved' and r='DM' and q.bm_reviewer is not null and q.bm_reviewer<>auth.uid() then
   target_status:=case decision when 'Approve' then 'Applied' else 'Rejected' end;
   if decision='Approve' then
    select * into p from public.occci_profiles where id=q.member_id for update;
    if not found or p.archived_at is not null or p.branch_id<>q.branch_id or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) then raise exception 'Member scope/status changed; submit a new request';end if;
    v:=q.proposed;
    if q.kind='Membership approval' then
     if p.membership_status<>'Pending verification' or not p.onboarding_complete or p.revision<>q.base_revision then raise exception 'Member details changed; obtain a new BM screening';end if;
     perform public.occci_assign_account(q.member_id,v->>'account_number',reason);
     update public.occci_profiles set membership_status='Active',revision=revision+1 where id=q.member_id;
     perform public.occci_log(q.member_id,q.branch_id,'Membership approved by DM',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',v->>'account_number','request_id',q.id),reason);
    else
     if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates';end if;
     select * into f from public.occci_financials where member_id=q.member_id;
     if coalesce(f.revision,0)<>q.base_revision then raise exception 'Financial record changed; submit a new request';end if;
     insert into public.occci_financials(member_id,savings,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision)
     values(q.member_id,(v->>'savings')::numeric,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,q.evidence_files,(v->>'as_of')::date,q.base_revision+1)
     on conflict(member_id) do update set savings=excluded.savings,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,evidence_files=excluded.evidence_files,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
     perform public.occci_log(q.member_id,q.branch_id,'Financial record synchronized by DM',to_jsonb(f),v,reason);
    end if;
   end if;
   update public.occci_change_requests set status=target_status,dm_reviewer=auth.uid(),admin_reviewer=null,review_note=trim(reason),reviewed_at=now() where id=request_id;
  else raise exception 'BM screening is required before final approval by the assigned District Manager';end if;
 else raise exception 'Unknown request type';end if;
 perform public.occci_log(q.member_id,q.branch_id,'Request reviewed',jsonb_build_object('status',q.status),jsonb_build_object('request_id',request_id,'kind',q.kind,'status',target_status),reason);
end;$$;

revoke all on function public.occci_can_read_profile(uuid,text),public.occci_can_read_audit(uuid,text,smallint) from public,anon,authenticated;
grant execute on function public.occci_can_read_profile(uuid,text),public.occci_can_read_audit(uuid,text,smallint) to authenticated;
insert into public.occci_schema_versions(version) values('009_branch_approval_workflow') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Migration 010: affected account identities in audit entries.
-- Apply after 009. Preserve the affected account independently of the acting user.
begin;
alter table public.occci_audit add column if not exists subject_name text;
alter table public.occci_audit add column if not exists subject_employee_id text;
alter table public.occci_audit add column if not exists subject_role text;

-- Recover existing entries from their recorded identity or linked profile once.
-- A captured name is never refreshed after a profile rename or staff transfer.
update public.occci_audit a set
 subject_name=coalesce(nullif(btrim(a.after_data->>'full_name'),''),nullif(btrim(a.before_data->>'full_name'),''),nullif(btrim(p.full_name),'')),
 subject_employee_id=coalesce(a.subject_employee_id,nullif(btrim(a.after_data->>'employee_id'),''),nullif(btrim(a.before_data->>'employee_id'),''),nullif(btrim(p.employee_id),'')),
 subject_role=coalesce(nullif(a.after_data->>'role',''),(select s.role from public.occci_staff_assignments s where s.user_id=a.member_id),'Member')
 from public.occci_profiles p where p.id=a.member_id and nullif(btrim(a.subject_name),'') is null;

create or replace function public.occci_capture_audit_subject() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.member_id is null then
  new.subject_name:=null;
  new.subject_employee_id:=null;
  new.subject_role:=null;
 else
  select nullif(btrim(p.full_name),''),nullif(btrim(p.employee_id),'') into new.subject_name,new.subject_employee_id
   from public.occci_profiles p where p.id=new.member_id;
  new.subject_name:=coalesce(new.subject_name,nullif(btrim(new.after_data->>'full_name'),''),nullif(btrim(new.before_data->>'full_name'),''));
  new.subject_employee_id:=coalesce(new.subject_employee_id,nullif(btrim(new.after_data->>'employee_id'),''),nullif(btrim(new.before_data->>'employee_id'),''));
  new.subject_role:=coalesce(nullif(new.after_data->>'role',''),(select s.role from public.occci_staff_assignments s where s.user_id=new.member_id),'Member');
 end if;
 return new;
end;$$;
drop trigger if exists occci_audit_subject on public.occci_audit;
create trigger occci_audit_subject before insert on public.occci_audit for each row execute function public.occci_capture_audit_subject();
revoke all on function public.occci_capture_audit_subject() from public,anon,authenticated;
-- Existing audit policies and the activity RPC continue to restrict event scope.
insert into public.occci_schema_versions(version) values('010_audit_subject_identity') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Migration 011: Admin password confirmation for BM/DM assignments.
-- Apply after 010. Each BM/DM assignment requires a fresh, single-use Admin password sign-in.
begin;
create table if not exists public.occci_position_confirmations(
 id uuid primary key default gen_random_uuid(),
 actor uuid not null references auth.users(id),
 target uuid not null references public.occci_profiles(id),
 action_kind text not null check(action_kind in ('Team','Staff application')),
 assignment jsonb not null,
 original_session_id text not null,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '5 minutes',
 used_at timestamptz,
 used_session_id text
);
create unique index if not exists occci_position_confirmation_session_once on public.occci_position_confirmations(used_session_id) where used_session_id is not null;
alter table public.occci_position_confirmations enable row level security;
revoke all on public.occci_position_confirmations from public,anon,authenticated;

create or replace function public.occci_position_values(values_json jsonb) returns jsonb language plpgsql immutable security definer set search_path='' as $$
begin
 if jsonb_typeof(values_json) is distinct from 'object' or coalesce(values_json->>'role','') not in ('BM','DM') then raise exception 'Choose a BM or DM position to confirm';end if;
 return jsonb_build_object('role',values_json->>'role',
  'branch_id',case when values_json->>'role'='BM' then nullif(values_json->>'branch_id','') end,
  'district',case when values_json->>'role'='DM' then nullif(values_json->>'district','')::smallint end,
  'employee_id',nullif(btrim(values_json->>'employee_id'),''));
end;$$;

create or replace function public.occci_begin_position_confirmation(action_kind text,target uuid,values_json jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v jsonb; session_id text:=auth.jwt()->>'session_id'; confirmation_id uuid;
begin
 if auth.uid() is null or public.occci_role()<>'Admin' then raise exception 'Only Admin can confirm BM/DM assignments';end if;
 if coalesce(session_id,'')='' then raise exception 'Sign in again before confirming a position';end if;
 if action_kind is null or action_kind not in ('Team','Staff application') then raise exception 'Invalid position confirmation action';end if;
 if not exists(select 1 from public.occci_profiles where id=target and archived_at is null) then raise exception 'Choose an active registered user';end if;
 v:=public.occci_position_values(values_json);
 if v->>'role'='BM' and not exists(select 1 from public.occci_branches where id=v->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
 if v->>'role'='DM' and not exists(select 1 from public.occci_branches where district=(v->>'district')::smallint and active) then raise exception 'Choose an active district';end if;
 insert into public.occci_position_confirmations(actor,target,action_kind,assignment,original_session_id)
 values(auth.uid(),target,action_kind,v,session_id) returning id into confirmation_id;
 return confirmation_id;
end;$$;

create or replace function public.occci_consume_position_confirmation(action_kind text,target uuid,values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare c public.occci_position_confirmations; claims jsonb:=auth.jwt(); session_id text:=claims->>'session_id'; password_time bigint;
begin
 if auth.uid() is null or public.occci_role()<>'Admin' or claims->>'sub' is distinct from auth.uid()::text then raise exception 'Only the same Admin can confirm this position';end if;
 if coalesce(values_json->>'position_confirmation','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Re-enter your Admin password to assign BM or DM';end if;
 select * into c from public.occci_position_confirmations where id=(values_json->>'position_confirmation')::uuid for update;
 if not found or c.actor<>auth.uid() or c.target<>target or c.action_kind<>action_kind or c.assignment<>public.occci_position_values(values_json) or c.used_at is not null or c.expires_at<=clock_timestamp() then raise exception 'Position confirmation expired or changed. Re-enter your Admin password';end if;
 if coalesce(session_id,'')='' or session_id=c.original_session_id then raise exception 'Re-enter your Admin password for this assignment';end if;
 if jsonb_typeof(claims->'amr')='array' then
  select max((a->>'timestamp')::bigint) into password_time from jsonb_array_elements(claims->'amr') a
   where a->>'method'='password' and coalesce(a->>'timestamp','') ~ '^[0-9]{1,12}$';
 end if;
 if password_time is null or password_time<floor(extract(epoch from c.created_at))::bigint or password_time>extract(epoch from clock_timestamp())::bigint+30 then raise exception 'A fresh Admin password sign-in is required for this assignment';end if;
 if exists(select 1 from public.occci_position_confirmations where used_session_id=session_id) then raise exception 'Re-enter your Admin password before each BM/DM assignment';end if;
 begin
  update public.occci_position_confirmations set used_at=clock_timestamp(),used_session_id=session_id where id=c.id;
 exception when unique_violation then raise exception 'Re-enter your Admin password before each BM/DM assignment';
 end;
end;$$;

-- Keep the validated existing workflows private, with narrow public confirmation gates.
do $$begin
 if to_regprocedure('public.occci_manage_record_confirmed_impl(text,text,jsonb,boolean,text)') is null then
  alter function public.occci_manage_record(text,text,jsonb,boolean,text) rename to occci_manage_record_confirmed_impl;
 end if;
 if to_regprocedure('public.occci_review_staff_confirmed_impl(uuid,text,jsonb,text)') is null then
  alter function public.occci_review_staff(uuid,text,jsonb,text) rename to occci_review_staff_confirmed_impl;
 end if;
end;$$;
revoke all on function public.occci_manage_record_confirmed_impl(text,text,jsonb,boolean,text),public.occci_review_staff_confirmed_impl(uuid,text,jsonb,text) from public,anon,authenticated;

create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if record_kind='Team' and remove_record is distinct from true and values_json->>'role' in ('BM','DM') then
  perform public.occci_consume_position_confirmation('Team',record_id::uuid,values_json);
 end if;
 perform public.occci_manage_record_confirmed_impl(record_kind,record_id,values_json-'position_confirmation',remove_record,reason);
end;$$;
create or replace function public.occci_review_staff(target uuid,decision text,values_json jsonb,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if decision='Approve' and values_json->>'role' in ('BM','DM') then
  perform public.occci_consume_position_confirmation('Staff application',target,values_json);
 end if;
 perform public.occci_review_staff_confirmed_impl(target,decision,values_json-'position_confirmation',reason);
end;$$;
revoke all on function public.occci_position_values(jsonb),public.occci_consume_position_confirmation(text,uuid,jsonb),public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_review_staff(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_review_staff(uuid,text,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('011_admin_position_confirmation') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 011. Every staff assignment/removal and account archive needs a new Admin password session.
begin;
alter table public.occci_position_confirmations drop constraint if exists occci_position_confirmations_action_kind_check;
alter table public.occci_position_confirmations add constraint occci_position_confirmations_action_kind_check
 check(action_kind in ('Team','Staff application','Team removal','Account archive'));

create or replace function public.occci_position_values(values_json jsonb) returns jsonb language plpgsql immutable security definer set search_path='' as $$
begin
 if jsonb_typeof(values_json) is distinct from 'object' or coalesce(values_json->>'role','') not in ('Admin','DM','BM','Staff','BC') then raise exception 'Choose a valid staff position to confirm';end if;
 return jsonb_build_object('role',values_json->>'role',
  'branch_id',case when values_json->>'role' in ('BM','Staff','BC') then nullif(values_json->>'branch_id','') end,
  'district',case when values_json->>'role'='DM' then nullif(values_json->>'district','')::smallint end,
  'employee_id',nullif(btrim(values_json->>'employee_id'),''));
end;$$;

-- Removal confirmations use database state, never a client-provided role or scope.
create or replace function public.occci_confirmation_values(action_kind text,target uuid,values_json jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; current_assignment jsonb;
begin
 if action_kind in ('Team','Staff application') then return public.occci_position_values(values_json);end if;
 if action_kind not in ('Team removal','Account archive') or action_kind is null then raise exception 'Invalid password confirmation action';end if;
 select * into p from public.occci_profiles where id=target;
 if not found or p.archived_at is not null then raise exception 'Choose an active registered account';end if;
 select jsonb_build_object('role',s.role,'branch_id',s.branch_id,'district',s.district) into current_assignment
  from public.occci_staff_assignments s where s.user_id=target;
 if action_kind='Team removal' and current_assignment is null then raise exception 'This account has no staff assignment to remove';end if;
 return jsonb_build_object('operation',action_kind,'current_assignment',current_assignment,'profile_revision',p.revision);
end;$$;

create or replace function public.occci_begin_position_confirmation(action_kind text,target uuid,values_json jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v jsonb; session_id text:=auth.jwt()->>'session_id'; confirmation_id uuid;
begin
 if auth.uid() is null or public.occci_role()<>'Admin' then raise exception 'Only Admin can confirm staff changes or account archives';end if;
 if coalesce(session_id,'')='' then raise exception 'Sign in again before confirming this change';end if;
 if action_kind is null or action_kind not in ('Team','Staff application','Team removal','Account archive') then raise exception 'Invalid password confirmation action';end if;
 if not exists(select 1 from public.occci_profiles where id=target and archived_at is null) then raise exception 'Choose an active registered account';end if;
 v:=public.occci_confirmation_values(action_kind,target,values_json);
 if action_kind in ('Team','Staff application') then
  if v->>'role' in ('BM','Staff','BC') and not exists(select 1 from public.occci_branches where id=v->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
  if v->>'role'='DM' and not exists(select 1 from public.occci_branches where district=(v->>'district')::smallint and active) then raise exception 'Choose an active district';end if;
 end if;
 insert into public.occci_position_confirmations(actor,target,action_kind,assignment,original_session_id)
 values(auth.uid(),target,action_kind,v,session_id) returning id into confirmation_id;
 return confirmation_id;
end;$$;

create or replace function public.occci_consume_position_confirmation(action_kind text,target uuid,values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare c public.occci_position_confirmations; claims jsonb:=auth.jwt(); session_id text:=claims->>'session_id'; password_time bigint;
begin
 if auth.uid() is null or public.occci_role()<>'Admin' or claims->>'sub' is distinct from auth.uid()::text then raise exception 'Only the same Admin can confirm this change';end if;
 if coalesce(values_json->>'position_confirmation','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Re-enter your Admin password to confirm this change';end if;
 select * into c from public.occci_position_confirmations where id=(values_json->>'position_confirmation')::uuid for update;
 if not found or c.actor is distinct from auth.uid() or c.target is distinct from target or c.action_kind is distinct from action_kind or c.used_at is not null or c.expires_at<=clock_timestamp() then raise exception 'Password confirmation expired or changed. Re-enter your Admin password';end if;
 if c.assignment is distinct from public.occci_confirmation_values(action_kind,target,values_json) then raise exception 'Password confirmation expired or changed. Re-enter your Admin password';end if;
 if coalesce(session_id,'')='' or session_id=c.original_session_id then raise exception 'Re-enter your Admin password for this change';end if;
 if jsonb_typeof(claims->'amr')='array' then
  select max((a->>'timestamp')::bigint) into password_time from jsonb_array_elements(claims->'amr') a
   where a->>'method'='password' and coalesce(a->>'timestamp','') ~ '^[0-9]{1,12}$';
 end if;
 if password_time is null or password_time<floor(extract(epoch from c.created_at))::bigint or password_time>extract(epoch from clock_timestamp())::bigint+30 then raise exception 'A fresh Admin password sign-in is required for this change';end if;
 if exists(select 1 from public.occci_position_confirmations where used_session_id=session_id) then raise exception 'Re-enter your Admin password before each change';end if;
 begin
  update public.occci_position_confirmations set used_at=clock_timestamp(),used_session_id=session_id where id=c.id;
 exception when unique_violation then raise exception 'Re-enter your Admin password before each change';
 end;
end;$$;

create or replace function public.occci_manage_record(record_kind text,record_id text,values_json jsonb,remove_record boolean,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if record_kind='Team' then
  perform pg_catalog.pg_advisory_xact_lock(771004);
  perform public.occci_consume_position_confirmation(case when remove_record is true then 'Team removal' else 'Team' end,record_id::uuid,values_json);
 elsif record_kind='Member' and remove_record is true then
  -- Use the existing role-operation lock order, then lock the account snapshot.
  perform pg_catalog.pg_advisory_xact_lock(771004);
  perform 1 from public.occci_profiles where id=record_id::uuid for update;
  perform public.occci_consume_position_confirmation('Account archive',record_id::uuid,values_json);
 end if;
 perform public.occci_manage_record_confirmed_impl(record_kind,record_id,coalesce(values_json,'{}'::jsonb)-'position_confirmation',remove_record,reason);
end;$$;

create or replace function public.occci_review_staff(target uuid,decision text,values_json jsonb,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if decision='Approve' then
  perform pg_catalog.pg_advisory_xact_lock(771004);
  perform public.occci_consume_position_confirmation('Staff application',target,values_json);
 end if;
 perform public.occci_review_staff_confirmed_impl(target,decision,coalesce(values_json,'{}'::jsonb)-'position_confirmation',reason);
end;$$;

revoke all on function public.occci_position_values(jsonb),public.occci_confirmation_values(text,uuid,jsonb),public.occci_consume_position_confirmation(text,uuid,jsonb),public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_review_staff(uuid,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.occci_manage_record_confirmed_impl(text,text,jsonb,boolean,text),public.occci_review_staff_confirmed_impl(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_manage_record(text,text,jsonb,boolean,text),public.occci_review_staff(uuid,text,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('012_all_staff_password_confirmation') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 012. One DM per district, one BM per branch, and final financial review after role reassignment.
begin;
-- Stop on existing conflicts. No employee is removed or reassigned by this migration.
lock table public.occci_staff_assignments in share row exclusive mode;
do $$
begin
 if exists(select 1 from public.occci_staff_assignments where role='DM' group by district having count(*)>1) then
  raise exception 'Resolve duplicate District Manager assignments before applying this migration';
 end if;
 if exists(select 1 from public.occci_staff_assignments where role='BM' group by branch_id having count(*)>1) then
  raise exception 'Resolve duplicate Branch Manager assignments before applying this migration';
 end if;
end;$$;
create unique index if not exists occci_one_dm_per_district on public.occci_staff_assignments(district) where role='DM';
create unique index if not exists occci_one_bm_per_branch on public.occci_staff_assignments(branch_id) where role='BM';

-- Friendly preflight before a new password session. Unique indexes also protect every final write.
create or replace function public.occci_require_manager_slot(target uuid,values_json jsonb) returns void language plpgsql stable security definer set search_path='' as $$
begin
 if values_json->>'role'='DM' and exists(select 1 from public.occci_staff_assignments s where s.role='DM' and s.district=(values_json->>'district')::smallint and s.user_id<>target) then
  raise exception 'District % already has a DM. Update the existing assignment before assigning a replacement',values_json->>'district';
 end if;
 if values_json->>'role'='BM' and exists(select 1 from public.occci_staff_assignments s where s.role='BM' and s.branch_id=values_json->>'branch_id' and s.user_id<>target) then
  raise exception 'This branch already has a BM. Update the existing assignment before assigning a replacement';
 end if;
end;$$;

create or replace function public.occci_begin_position_confirmation(action_kind text,target uuid,values_json jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v jsonb; session_id text:=auth.jwt()->>'session_id'; confirmation_id uuid;
begin
 if auth.uid() is null or public.occci_role()<>'Admin' then raise exception 'Only Admin can confirm staff changes or account archives';end if;
 if coalesce(session_id,'')='' then raise exception 'Sign in again before confirming this change';end if;
 if action_kind is null or action_kind not in ('Team','Staff application','Team removal','Account archive') then raise exception 'Invalid password confirmation action';end if;
 if not exists(select 1 from public.occci_profiles where id=target and archived_at is null) then raise exception 'Choose an active registered account';end if;
 v:=public.occci_confirmation_values(action_kind,target,values_json);
 if action_kind in ('Team','Staff application') then
  if v->>'role' in ('BM','Staff','BC') and not exists(select 1 from public.occci_branches where id=v->>'branch_id' and active) then raise exception 'Choose an active branch';end if;
  if v->>'role'='DM' and not exists(select 1 from public.occci_branches where district=(v->>'district')::smallint and active) then raise exception 'Choose an active district';end if;
  perform public.occci_require_manager_slot(target,v);
 end if;
 insert into public.occci_position_confirmations(actor,target,action_kind,assignment,original_session_id)
 values(auth.uid(),target,action_kind,v,session_id) returning id into confirmation_id;
 return confirmation_id;
end;$$;

create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 -- Keep the current role and district stable while recording this decision.
 perform pg_catalog.pg_advisory_xact_lock(771004);
 r:=public.occci_role();
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) then raise exception 'Review requires an authorized reviewer in the assigned branch or district';end if;
 -- A recorded BM screening survives reassignment of that account to this district's DM.
 -- Profile edits and membership requests retain their separate-reviewer requirement.
 if q.submitted_by=auth.uid() and not (q.kind='Financial sync' and q.status='BM approved' and r='DM' and q.bm_reviewer is not null) then raise exception 'Review requires a different authorized reviewer in the assigned branch or district';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Choose a decision and provide a review note';end if;
 if q.kind='Profile edit' then
  if r not in ('BM','DM') or q.status<>'Pending' then raise exception 'Profile edits require the assigned BM or DM approval';end if;
  target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
  update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 elsif q.kind in ('Financial sync','Membership approval') then
  if q.status='Pending' and q.kind='Financial sync' and r='BM' then
   target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
   update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
  elsif q.status='BM approved' and r='DM' and q.bm_reviewer is not null and (q.kind='Financial sync' or q.bm_reviewer<>auth.uid()) then
   target_status:=case decision when 'Approve' then 'Applied' else 'Rejected' end;
   if decision='Approve' then
    select * into p from public.occci_profiles where id=q.member_id for update;
    if not found or p.archived_at is not null or p.branch_id<>q.branch_id or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) then raise exception 'Member scope/status changed; submit a new request';end if;
    v:=q.proposed;
    if q.kind='Membership approval' then
     if p.membership_status<>'Pending verification' or not p.onboarding_complete or p.revision<>q.base_revision then raise exception 'Member details changed; obtain a new BM screening';end if;
     perform public.occci_assign_account(q.member_id,v->>'account_number',reason);
     update public.occci_profiles set membership_status='Active',revision=revision+1 where id=q.member_id;
     perform public.occci_log(q.member_id,q.branch_id,'Membership approved by DM',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',v->>'account_number','request_id',q.id),reason);
    else
     if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates';end if;
     select * into f from public.occci_financials where member_id=q.member_id;
     if coalesce(f.revision,0)<>q.base_revision then raise exception 'Financial record changed; submit a new request';end if;
     insert into public.occci_financials(member_id,savings,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision)
     values(q.member_id,(v->>'savings')::numeric,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,q.evidence_files,(v->>'as_of')::date,q.base_revision+1)
     on conflict(member_id) do update set savings=excluded.savings,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,evidence_files=excluded.evidence_files,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
     perform public.occci_log(q.member_id,q.branch_id,'Financial record synchronized by DM',to_jsonb(f),v,reason);
    end if;
   end if;
   update public.occci_change_requests set status=target_status,dm_reviewer=auth.uid(),admin_reviewer=null,review_note=trim(reason),reviewed_at=now() where id=request_id;
  else raise exception 'BM screening is required before final approval by the assigned District Manager';end if;
 else raise exception 'Unknown request type';end if;
 perform public.occci_log(q.member_id,q.branch_id,'Request reviewed',jsonb_build_object('status',q.status),jsonb_build_object('request_id',request_id,'kind',q.kind,'status',target_status),reason);
end;$$;

revoke all on function public.occci_require_manager_slot(uuid,jsonb),public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_review_change(uuid,text,text) from public,anon,authenticated;
grant execute on function public.occci_begin_position_confirmation(text,uuid,jsonb),public.occci_review_change(uuid,text,text) to authenticated;
insert into public.occci_schema_versions(version) values('013_single_managers_financial_review') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 013. Verified share capital and branch-scoped cashier receipts.
-- Existing share capital stays unknown until verified; no contribution percentage is assumed.
begin;
alter table public.occci_financials add column if not exists share_capital numeric(16,2);
do $$ begin
 if not exists(select 1 from pg_catalog.pg_constraint where conname='occci_share_capital_valid' and conrelid='public.occci_financials'::regclass) then
  alter table public.occci_financials add constraint occci_share_capital_valid check(share_capital is null or (share_capital>=0 and share_capital<>'NaN'::numeric));
 end if;
end;$$;

-- These validators are private. Authenticated clients use the scoped public operations below.
create or replace function public.occci_cashier_amount(values_json jsonb,field_name text) returns numeric language plpgsql immutable set search_path='' as $$
declare value_text text:=trim(coalesce(values_json->>field_name,'0'));
begin
 if value_text !~ '^[0-9]{1,14}([.][0-9]{1,2})?$' then raise exception 'Use a nonnegative amount with at most two decimal places for %',replace(field_name,'_',' ');end if;
 return value_text::numeric;
end;$$;
create or replace function public.occci_validate_financial_additions(values_json jsonb) returns void language plpgsql immutable set search_path='' as $$
declare item jsonb; paid numeric; amount numeric;
begin
 if values_json ? 'share_capital' and values_json->>'share_capital' is not null then
  perform public.occci_cashier_amount(values_json,'share_capital');
 end if;
 if jsonb_typeof(values_json->'schedule')='array' then
  for item in select * from jsonb_array_elements(values_json->'schedule') loop
   if item ? 'paid_amount' then
    paid:=public.occci_cashier_amount(item,'paid_amount');
    amount:=public.occci_cashier_amount(item,'amount');
    if paid>amount then raise exception 'Scheduled paid amount cannot exceed the installment amount';end if;
   end if;
  end loop;
 end if;
end;$$;

create table if not exists public.occci_cashier_payments(
 id uuid primary key,
 member_id uuid not null references public.occci_profiles(id),
 branch_id text not null references public.occci_branches(id),
 member_name text not null,
 account_number text not null,
 cashier_id uuid not null references auth.users(id),
 cashier_name text not null,
 receipt_number text not null check(length(receipt_number) between 3 and 80),
 payment_date date not null,
 principal_amount numeric(16,2) not null check(principal_amount>=0),
 interest_amount numeric(16,2) not null check(interest_amount>=0),
 fees_amount numeric(16,2) not null check(fees_amount>=0),
 savings_amount numeric(16,2) not null check(savings_amount>=0),
 share_capital_amount numeric(16,2) not null check(share_capital_amount>=0),
 total_amount numeric(16,2) generated always as (principal_amount+interest_amount+fees_amount+savings_amount+share_capital_amount) stored,
 loan_balance_before numeric(16,2) not null,
 loan_balance_after numeric(16,2) not null,
 savings_before numeric(16,2) not null,
 savings_after numeric(16,2) not null,
 share_capital_before numeric(16,2),
 share_capital_after numeric(16,2),
 schedule_index integer,
 schedule_date date,
 revision_before integer not null,
 revision_after integer not null,
 note text not null,
 created_at timestamptz not null default now(),
 constraint occci_cashier_positive_total check(total_amount>0),
 constraint occci_cashier_nonnegative_balance check(loan_balance_after>=0 and savings_after>=0 and (share_capital_after is null or share_capital_after>=0))
);
create unique index if not exists occci_cashier_receipt_unique on public.occci_cashier_payments(branch_id,lower(receipt_number));
create index if not exists occci_cashier_member_date on public.occci_cashier_payments(member_id,payment_date desc,created_at desc);
alter table public.occci_cashier_payments enable row level security;
revoke all on public.occci_cashier_payments from public,anon,authenticated;
grant select on public.occci_cashier_payments to authenticated;
drop policy if exists occci_cashier_read on public.occci_cashier_payments;
create policy occci_cashier_read on public.occci_cashier_payments for select to authenticated using(
 auth.uid() is not null and (member_id=auth.uid() or
 (public.occci_can_read_branch(branch_id) and exists(select 1 from public.occci_profiles p where p.id=member_id and public.occci_can_read_profile(p.id,p.branch_id))))
);

create or replace function public.occci_submit_change(target uuid,request_kind text,values_json jsonb,evidence text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role(); request_id uuid; rev integer; item jsonb;
begin
 select * into p from public.occci_profiles where id=target;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('DM','BM','Staff','BC') or p.archived_at is not null then raise exception 'Request is not permitted';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a request note';end if;
 if request_kind='Profile edit' then rev:=p.revision;
 elsif request_kind='Financial sync' then
 if r not in ('BM','Staff','BC') then raise exception 'Branch Staff, BC or BM submit actual balances; the assigned DM performs final approval';end if;
 perform public.occci_validate_financial_additions(values_json);
 if p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a cooperative member';end if;
 if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates'; end if;
 if coalesce(evidence,'') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-documents' and name=evidence) then raise exception 'Upload a source document first';end if;
 if lower(coalesce(values_json->>'savings','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'loan_balance','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'annual_interest','')) in ('nan','infinity','-infinity') then raise exception 'Finite financial amounts are required';end if;
 if coalesce(values_json->>'source_reference','')='' or (values_json->>'as_of')::date is null or (values_json->>'savings')::numeric<0 or (values_json->>'loan_balance')::numeric<0 or (values_json->>'annual_interest')::numeric not between 0 and 100 or values_json->>'loan_status' is null or values_json->>'loan_status' not in ('No active loan','Active','Paid','Overdue','Restructured') or coalesce(jsonb_typeof(values_json->'schedule'),'')<>'array' then raise exception 'Invalid financial details'; end if;
 if values_json->>'savings' is null or values_json->>'loan_balance' is null or values_json->>'annual_interest' is null then raise exception 'Financial amounts are required';end if;
 if jsonb_array_length(values_json->'schedule')>360 then raise exception 'Use at most 360 scheduled payments';end if;
 for item in select * from jsonb_array_elements(values_json->'schedule') loop
 if coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(item->>'status','') not in ('Scheduled','Paid','Overdue','Rescheduled','Cancelled') then raise exception 'Invalid payment date or status';end if;
 if lower(coalesce(item->>'amount','')) in ('nan','infinity','-infinity') then raise exception 'Invalid payment schedule';end if;
 if (item->>'date')::date is null or item->>'amount' is null or (item->>'amount')::numeric<0 then raise exception 'Invalid payment schedule';end if;
 end loop;
 select coalesce((select revision from public.occci_financials where member_id=target),0) into rev;
 else raise exception 'Invalid request type';end if;
 insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,evidence_path,note,workflow_version) values(target,p.branch_id,request_kind,values_json,rev,auth.uid(),evidence,reason,2) returning id into request_id;
 perform public.occci_log(target,p.branch_id,'Request submitted',null,jsonb_build_object('request_id',request_id,'kind',request_kind,'proposed',values_json),reason);
 if request_kind='Financial sync' and r='BM' then
 update public.occci_change_requests set status='BM approved',bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 perform public.occci_log(target,p.branch_id,'Financial request screened by BM',null,jsonb_build_object('request_id',request_id,'status','BM approved'),reason);
 end if;
 return request_id;
end;$$;

create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 -- Keep the current role and district stable while recording this decision.
 perform pg_catalog.pg_advisory_xact_lock(771004);
 r:=public.occci_role();
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) then raise exception 'Review requires an authorized reviewer in the assigned branch or district';end if;
 -- A recorded BM screening survives reassignment of that account to this district's DM.
 -- Profile edits and membership requests retain their separate-reviewer requirement.
 if q.submitted_by=auth.uid() and not (q.kind='Financial sync' and q.status='BM approved' and r='DM' and q.bm_reviewer is not null) then raise exception 'Review requires a different authorized reviewer in the assigned branch or district';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Choose a decision and provide a review note';end if;
 if q.kind='Profile edit' then
  if r not in ('BM','DM') or q.status<>'Pending' then raise exception 'Profile edits require the assigned BM or DM approval';end if;
  target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
  update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 elsif q.kind in ('Financial sync','Membership approval') then
  if q.status='Pending' and q.kind='Financial sync' and r='BM' then
   target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
   update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
  elsif q.status='BM approved' and r='DM' and q.bm_reviewer is not null and (q.kind='Financial sync' or q.bm_reviewer<>auth.uid()) then
   target_status:=case decision when 'Approve' then 'Applied' else 'Rejected' end;
   if decision='Approve' then
    select * into p from public.occci_profiles where id=q.member_id for update;
    if not found or p.archived_at is not null or p.branch_id<>q.branch_id or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) then raise exception 'Member scope/status changed; submit a new request';end if;
    v:=q.proposed;
    if q.kind='Membership approval' then
     if p.membership_status<>'Pending verification' or not p.onboarding_complete or p.revision<>q.base_revision then raise exception 'Member details changed; obtain a new BM screening';end if;
     perform public.occci_assign_account(q.member_id,v->>'account_number',reason);
     update public.occci_profiles set membership_status='Active',revision=revision+1 where id=q.member_id;
     perform public.occci_log(q.member_id,q.branch_id,'Membership approved by DM',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',v->>'account_number','request_id',q.id),reason);
    else
     if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates';end if;
     perform public.occci_validate_financial_additions(v);
     select * into f from public.occci_financials where member_id=q.member_id for update;
     if coalesce(f.revision,0)<>q.base_revision then raise exception 'Financial record changed; submit a new request';end if;
     insert into public.occci_financials(member_id,savings,share_capital,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision)
     values(q.member_id,(v->>'savings')::numeric,case when v ? 'share_capital' and v->>'share_capital' is not null then (v->>'share_capital')::numeric else f.share_capital end,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,q.evidence_files,(v->>'as_of')::date,q.base_revision+1)
     on conflict(member_id) do update set savings=excluded.savings,share_capital=excluded.share_capital,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,evidence_files=excluded.evidence_files,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
     perform public.occci_log(q.member_id,q.branch_id,'Financial record synchronized by DM',to_jsonb(f),v,reason);
    end if;
   end if;
   update public.occci_change_requests set status=target_status,dm_reviewer=auth.uid(),admin_reviewer=null,review_note=trim(reason),reviewed_at=now() where id=request_id;
  else raise exception 'BM screening is required before final approval by the assigned District Manager';end if;
 else raise exception 'Unknown request type';end if;
 perform public.occci_log(q.member_id,q.branch_id,'Request reviewed',jsonb_build_object('status',q.status),jsonb_build_object('request_id',request_id,'kind',q.kind,'status',target_status),reason);
end;$$;

-- A cashier records new receipts against an already DM-verified balance.
-- Principal reduces the loan; interest, fees and capital contributions do not.
-- Profile/financial locks, revision checks and unique receipt IDs prevent duplicate or stale posting.
create or replace function public.occci_record_cashier_payment(target uuid,values_json jsonb,expected_revision integer,client_reference uuid,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; f public.occci_financials; existing public.occci_cashier_payments; posted public.occci_cashier_payments;
 principal numeric; interest numeric; fees numeric; savings numeric; capital numeric; total numeric;
 receipt text:=trim(values_json->>'receipt_number'); paid_on date; installment integer;
 remaining_loan numeric; next_capital numeric; next_savings numeric; next_schedule jsonb; item jsonb;
 paid_to_date numeric; installment_amount numeric; installment_paid numeric; due_date date; next_status text;
 today_ph date:=(now() at time zone 'Asia/Manila')::date;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only the assigned Branch Cashier can record payments';end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or p.membership_status<>'Active' or p.account_number is null or not p.onboarding_complete or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) or not public.occci_can_read_branch(p.branch_id) then
  raise exception 'Choose an approved cooperative member in your assigned branch';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or client_reference is null or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a receipt, payment details and notes';end if;
 if coalesce(receipt,'') !~ '^[A-Za-z0-9][A-Za-z0-9 /._#-]{2,79}$' then raise exception 'Enter the official receipt number using 3 to 80 valid characters';end if;
 if coalesce(values_json->>'payment_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Choose a valid payment date';end if;
 paid_on:=(values_json->>'payment_date')::date;
 if paid_on>today_ph or paid_on<date '1900-01-01' then raise exception 'Payment date cannot be in the future';end if;
 principal:=public.occci_cashier_amount(values_json,'principal_amount');
 interest:=public.occci_cashier_amount(values_json,'interest_amount');
 fees:=public.occci_cashier_amount(values_json,'fees_amount');
 savings:=public.occci_cashier_amount(values_json,'savings_amount');
 capital:=public.occci_cashier_amount(values_json,'share_capital_amount');
 total:=principal+interest+fees+savings+capital;
 if total<=0 or total>99999999999999.99 then raise exception 'Enter a positive payment or deposit amount';end if;
 installment:=nullif(values_json->>'schedule_index','')::integer;
 if installment is not null and installment<0 then raise exception 'Choose a valid payment schedule entry';end if;
 -- Exact retries return the original receipt without another balance change or audit entry.
 select * into existing from public.occci_cashier_payments where id=client_reference;
 if found then
  if existing.cashier_id<>auth.uid() or existing.member_id<>target or existing.receipt_number<>receipt or existing.payment_date<>paid_on or existing.principal_amount<>principal or existing.interest_amount<>interest or existing.fees_amount<>fees or existing.savings_amount<>savings or existing.share_capital_amount<>capital or existing.schedule_index is distinct from installment or existing.note<>trim(reason) then
   raise exception 'This payment reference was already used for different details';end if;
  return to_jsonb(existing);
 end if;
 if exists(select 1 from public.occci_cashier_payments c where c.branch_id=p.branch_id and lower(c.receipt_number)=lower(receipt)) then raise exception 'This receipt number is already recorded in your branch';end if;
 select * into f from public.occci_financials where member_id=target for update;
 if not found then raise exception 'The member needs a DM-verified financial record before receiving payments';end if;
 if expected_revision is null or f.revision<>expected_revision then raise exception 'The member balance changed. Refresh the member before recording payment';end if;
 if principal>f.loan_balance then raise exception 'Principal paid cannot exceed the outstanding loan balance';end if;
 if capital>0 and f.share_capital is null then raise exception 'Verify the opening share capital balance through BM and DM before adding a contribution';end if;
 remaining_loan:=f.loan_balance-principal; next_savings:=f.savings+savings;
 next_capital:=case when f.share_capital is null then null else f.share_capital+capital end;
 next_schedule:=f.schedule;
 if installment is not null then
  if principal+interest<=0 or installment>=jsonb_array_length(f.schedule) then raise exception 'Choose an unpaid installment for the principal and interest payment';end if;
  item:=f.schedule->installment;
  if coalesce(item->>'status','Scheduled') in ('Paid','Cancelled') then raise exception 'This installment is already paid or cancelled';end if;
  installment_amount:=public.occci_cashier_amount(item,'amount');
  paid_to_date:=public.occci_cashier_amount(item,'paid_amount');
  installment_paid:=paid_to_date+principal+interest;
  if installment_amount<=0 or installment_paid>installment_amount then raise exception 'Payment exceeds the remaining installment. Use an unallocated payment for extra principal';end if;
  due_date:=(item->>'date')::date;
  next_status:=case when installment_paid=installment_amount then 'Paid' when due_date<today_ph then 'Overdue' when item->>'status'='Rescheduled' then 'Rescheduled' else 'Scheduled' end;
  next_schedule:=jsonb_set(f.schedule,array[installment::text],item||jsonb_build_object('paid_amount',installment_paid,'status',next_status));
 end if;
 insert into public.occci_cashier_payments(id,member_id,branch_id,member_name,account_number,cashier_id,cashier_name,receipt_number,payment_date,principal_amount,interest_amount,fees_amount,savings_amount,share_capital_amount,loan_balance_before,loan_balance_after,savings_before,savings_after,share_capital_before,share_capital_after,schedule_index,schedule_date,revision_before,revision_after,note)
 values(client_reference,target,p.branch_id,p.full_name,p.account_number,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),receipt,paid_on,principal,interest,fees,savings,capital,f.loan_balance,remaining_loan,f.savings,next_savings,f.share_capital,next_capital,installment,due_date,f.revision,f.revision+1,trim(reason))
 returning * into posted;
 update public.occci_financials set loan_balance=remaining_loan,savings=next_savings,share_capital=next_capital,schedule=next_schedule,
 loan_status=case when f.loan_balance>0 and remaining_loan=0 then 'Paid' else f.loan_status end,
 as_of=greatest(f.as_of,paid_on),revision=f.revision+1,updated_at=now() where member_id=target;
 perform public.occci_log(target,p.branch_id,'Cashier payment posted',
 jsonb_build_object('loan_balance',f.loan_balance,'savings',f.savings,'share_capital',f.share_capital,'schedule',f.schedule),
 jsonb_build_object('payment_id',posted.id,'receipt_number',receipt,'payment_date',paid_on,'principal_amount',principal,'interest_amount',interest,'fees_amount',fees,'savings_amount',savings,'share_capital_amount',capital,'total_amount',total,'loan_balance',remaining_loan,'savings',next_savings,'share_capital',next_capital,'schedule',next_schedule),reason);
 return to_jsonb(posted);
end;$$;
revoke all on function public.occci_cashier_amount(jsonb,text),public.occci_validate_financial_additions(jsonb) from public,anon,authenticated;
revoke all on function public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text) from public,anon,authenticated;
grant execute on function public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text) to authenticated;
insert into public.occci_schema_versions(version) values('014_member_dashboard_cashier') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 014. Invitation creation does not approve employees or grant staff access.
begin;
alter table public.occci_staff_invites add column if not exists district smallint check(district between 1 and 6);
alter table public.occci_staff_invites add column if not exists branch_id text references public.occci_branches(id);
create or replace function public.occci_staff_invite_access(invite_district smallint,invite_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s join public.occci_profiles p on p.id=s.user_id
 where s.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and
 (s.role='Admin' or (s.role='DM' and s.district=invite_district) or (s.role='BM' and s.branch_id=invite_branch)));
$$;
revoke all on function public.occci_staff_invite_access(smallint,text) from public,anon,authenticated;
grant execute on function public.occci_staff_invite_access(smallint,text) to authenticated;
grant select(district,branch_id) on public.occci_staff_invites to authenticated;
drop policy if exists occci_staff_invites_read on public.occci_staff_invites;
create policy occci_staff_invites_read on public.occci_staff_invites for select to authenticated using(public.occci_staff_invite_access(district,branch_id));

create or replace function public.occci_create_staff_invite(label text,valid_days integer,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare invite uuid:=gen_random_uuid(); secret text:=upper(left(replace(gen_random_uuid()::text,'-',''),24)); expiry timestamptz; assignment public.occci_staff_assignments; d smallint; b text;
begin
 select s.* into assignment from public.occci_staff_assignments s join public.occci_profiles p on p.id=s.user_id
 where s.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete for share of s,p;
 if not found or assignment.role not in ('Admin','DM','BM') then raise exception 'Only Admin, DM or BM can generate staff invitations';end if;
 if assignment.role='DM' then d:=assignment.district;
 elsif assignment.role='BM' then
  b:=assignment.branch_id;select district into d from public.occci_branches where id=b and active;
  if not found then raise exception 'Your branch is unavailable for invitations';end if;
 end if;
 if not public.occci_staff_invite_access(d,b) then raise exception 'Your assigned invitation scope is unavailable';end if;
 if coalesce(length(trim(label)),0) not between 1 and 150 or valid_days is null or valid_days not between 1 and 30 or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a label, 1–30 days validity and reason / comments / notes';end if;
 expiry:=now()+make_interval(days=>valid_days);
 insert into public.occci_staff_invites(id,code_hash,label,created_by,expires_at,district,branch_id)
 values(invite,public.occci_invite_digest(invite,secret),trim(label),auth.uid(),expiry,d,b);
 perform public.occci_log(null,b,'Staff invitation created',null,jsonb_build_object('invite_id',invite,'label',trim(label),'expires_at',expiry,'district',d,'branch_id',b),reason);
 return jsonb_build_object('id',invite,'code',regexp_replace(secret,'(.{4})(.{4})(.{4})(.{4})(.{4})(.{4})','\1-\2-\3-\4-\5-\6'),'expires_at',expiry,'district',d,'branch_id',b);
end;$$;
create or replace function public.occci_revoke_staff_invite(invite_id uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
declare i public.occci_staff_invites;
begin
 if coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Reason / comments / notes are required';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or not public.occci_staff_invite_access(i.district,i.branch_id) then raise exception 'Invitation is outside your assigned district or branch';end if;
 if i.redeemed_at is not null or i.revoked_at is not null then raise exception 'Choose an unused active invitation';end if;
 update public.occci_staff_invites set revoked_at=now() where id=i.id;
 perform public.occci_log(null,i.branch_id,'Staff invitation revoked',jsonb_build_object('invite_id',i.id,'label',i.label,'district',i.district,'branch_id',i.branch_id),jsonb_build_object('revoked_at',now(),'district',i.district,'branch_id',i.branch_id),reason);
end;$$;
revoke all on function public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text) from public,anon,authenticated;
grant execute on function public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;

-- Apply after 015. Re-registration is explicit, owned and pending approval; history is retained.
begin;
create or replace function public.occci_reregister_member(values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; b public.occci_branches; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is null then raise exception 'This account is already registered. Please sign in instead';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or coalesce(values_json->>'registration_kind','Member')<>'Member' or values_json ?| array['role','requested_role','membership_status','account_number','employee_id','archived_at','photo_path','id','user_id'] then raise exception 'Re-registration is for cooperative membership only; staff positions require Admin approval';end if;
 select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
 if not found or b.district::text<>coalesce(values_json->>'district','') then raise exception 'Choose an active branch in the selected district';end if;
 perform public.occci_profile_values(p.id,values_json||jsonb_build_object('membership_status','Pending verification'));
 update public.occci_profiles set archived_at=null,onboarding_complete=true,registration_kind='Member',account_number=null,employee_id=null,photo_path=null,branch_id=b.id where id=p.id;
 -- An archived staff identity never recovers its old privileges through member registration.
 delete from public.occci_staff_assignments where user_id=p.id;
 select * into a from public.occci_staff_applications where user_id=p.id for update;
 if found and a.status in ('Pending','Approved') then
  update public.occci_staff_applications set status='Rejected',review_note='Member re-registration; prior staff access is not restored',reviewed_at=now() where user_id=p.id;
  perform public.occci_log(p.id,b.id,'Prior staff application closed for member re-registration',to_jsonb(a),jsonb_build_object('status','Rejected'),'Admin approval is required for any future staff assignment');
 end if;
 for q in select * from public.occci_change_requests where member_id=p.id and status in ('Pending','BM approved','Approved') for update loop
  update public.occci_change_requests set status='Rejected',review_note='Superseded by member re-registration',reviewed_at=now() where id=q.id;
  perform public.occci_log(p.id,q.branch_id,'Prior request closed for re-registration',to_jsonb(q),jsonb_build_object('request_id',q.id,'status','Rejected'),'New member registration requires fresh approval');
 end loop;
 perform public.occci_log(p.id,b.id,'Member registered again',to_jsonb(p),jsonb_build_object('registration_kind','Member','branch_id',b.id,'district',b.district,'membership_status','Pending verification','account_number',null),'Account owner re-registered using verified email; BM screening and DM approval are required again');
end;$$;
revoke all on function public.occci_reregister_member(jsonb) from public,anon,authenticated;
grant execute on function public.occci_reregister_member(jsonb) to authenticated;
create or replace function public.occci_prepare_staff_reregistration(invite_id uuid,code text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; i public.occci_staff_invites; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is null then raise exception 'This account is already registered. Please sign in instead';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or i.code_hash is distinct from public.occci_invite_digest(invite_id,code) or i.expires_at<=now() or i.revoked_at is not null or i.redeemed_at is not null then raise exception 'Use a fresh valid staff invitation and code from Admin, DM or BM';end if;
 update public.occci_profiles set archived_at=null,onboarding_complete=false,registration_kind='Member',membership_status='Pending verification',account_number=null,employee_id=null,photo_path=null,branch_id=null,revision=revision+1 where id=p.id;
 delete from public.occci_staff_assignments where user_id=p.id;
 select * into a from public.occci_staff_applications where user_id=p.id for update;
 if found and a.status in ('Pending','Approved') then
  update public.occci_staff_applications set status='Rejected',review_note='Staff re-registration; previous access is not restored',reviewed_at=now() where user_id=p.id;
  perform public.occci_log(p.id,p.branch_id,'Prior staff application closed for re-registration',to_jsonb(a),jsonb_build_object('status','Rejected'),'New invitation and Admin review are required');
 end if;
 for q in select * from public.occci_change_requests where member_id=p.id and status in ('Pending','BM approved','Approved') for update loop
  update public.occci_change_requests set status='Rejected',review_note='Superseded by staff re-registration',reviewed_at=now() where id=q.id;
  perform public.occci_log(p.id,q.branch_id,'Prior request closed for staff re-registration',to_jsonb(q),jsonb_build_object('request_id',q.id,'status','Rejected'),'Prior access is not restored');
 end loop;
 perform public.occci_log(p.id,p.branch_id,'Staff re-registration started',to_jsonb(p),jsonb_build_object('invite_id',i.id,'onboarding_complete',false,'membership_status','Pending verification'),'Account owner verified a fresh staff invitation; employee details and Admin approval are required');
end;$$;
revoke all on function public.occci_prepare_staff_reregistration(uuid,text) from public,anon,authenticated;
grant execute on function public.occci_prepare_staff_reregistration(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;

-- Apply after 016. Removed staff may have an existing profile but no active assignment.
begin;
create or replace function public.occci_prepare_staff_reregistration(invite_id uuid,code text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; i public.occci_staff_invites; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found then raise exception 'This account has no cooperative profile. Contact Admin';end if;
 if p.archived_at is null and not (p.onboarding_complete and not exists(select 1 from public.occci_staff_assignments where user_id=p.id) and not exists(select 1 from public.occci_staff_applications where user_id=p.id and status='Pending') and (exists(select 1 from public.occci_staff_applications where user_id=p.id and status='Approved') or exists(select 1 from public.occci_audit where member_id=p.id and action='Team assignment changed' and before_data->>'role' in ('Admin','DM','BM','Staff','BC') and after_data->>'role'='Member'))) then raise exception 'This account is already registered or has a pending application. Contact Admin';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or i.code_hash is distinct from public.occci_invite_digest(invite_id,code) or i.expires_at<=now() or i.revoked_at is not null or i.redeemed_at is not null then raise exception 'Use a fresh valid staff invitation and code from Admin, DM or BM';end if;
 update public.occci_profiles set archived_at=null,onboarding_complete=false,registration_kind='Member',membership_status='Pending verification',account_number=null,employee_id=null,photo_path=null,branch_id=null,revision=revision+1 where id=p.id;
 delete from public.occci_staff_assignments where user_id=p.id;
 select * into a from public.occci_staff_applications where user_id=p.id for update;
 if found and a.status in ('Pending','Approved') then
  update public.occci_staff_applications set status='Rejected',review_note='Staff re-registration; previous access is not restored',reviewed_at=now() where user_id=p.id;
  perform public.occci_log(p.id,p.branch_id,'Prior staff application closed for re-registration',to_jsonb(a),jsonb_build_object('status','Rejected'),'New invitation and Admin review are required');
 end if;
 for q in select * from public.occci_change_requests where member_id=p.id and status in ('Pending','BM approved','Approved') for update loop
  update public.occci_change_requests set status='Rejected',review_note='Superseded by staff re-registration',reviewed_at=now() where id=q.id;
  perform public.occci_log(p.id,q.branch_id,'Prior request closed for staff re-registration',to_jsonb(q),jsonb_build_object('request_id',q.id,'status','Rejected'),'Prior access is not restored');
 end loop;
 perform public.occci_log(p.id,p.branch_id,'Staff re-registration started',to_jsonb(p),jsonb_build_object('invite_id',i.id,'onboarding_complete',false,'membership_status','Pending verification'),'Account owner verified a fresh staff invitation; employee details and Admin approval are required');
end;$$;
revoke all on function public.occci_prepare_staff_reregistration(uuid,text) from public,anon,authenticated;
grant execute on function public.occci_prepare_staff_reregistration(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;

-- Apply after 017. RLS and existing permissions remain unchanged.
-- Publish only data already protected by table RLS. Invitation secrets and auth tables are excluded.
begin;
-- Scope-only invalidation signals let old branches remove rows that no longer pass their RLS.
-- No names, balances, notes, documents or invitation codes are stored in this table.
create table if not exists public.occci_live_scopes(
 scope_key text primary key, branch_id text, district smallint check(district between 1 and 6),
 user_id uuid references auth.users(id) on delete cascade, is_public boolean not null default false,
 version bigint not null default 1, updated_at timestamptz not null default now()
);
alter table public.occci_live_scopes enable row level security;
revoke all on public.occci_live_scopes from public,anon,authenticated;
grant select on public.occci_live_scopes to authenticated;
drop policy if exists occci_live_scopes_read on public.occci_live_scopes;
create policy occci_live_scopes_read on public.occci_live_scopes for select to authenticated using(
 public.occci_role()='Admin' or user_id=auth.uid() or
 (branch_id is not null and public.occci_can_read_branch(branch_id)) or
 (branch_id is null and district is not null and public.occci_role()='DM' and public.occci_district()=district) or
 (is_public and (branch_id is null and district is null or exists(select 1 from public.occci_profiles p left join public.occci_branches b on b.id=p.branch_id where p.id=auth.uid() and p.archived_at is null and
 ((occci_live_scopes.branch_id is not null and p.branch_id=occci_live_scopes.branch_id) or (occci_live_scopes.branch_id is null and b.district=occci_live_scopes.district)))))
);
create or replace function public.occci_live_touch(kind text,unit_branch text,unit_district smallint,unit_user uuid,public_unit boolean) returns void language plpgsql security definer set search_path='' as $$
declare key_value text;
begin
 key_value:=(case when public_unit then 'public:' else '' end)||kind||':'||coalesce(unit_branch,unit_district::text,unit_user::text,'cooperative');
 insert into public.occci_live_scopes(scope_key,branch_id,district,user_id,is_public) values(key_value,unit_branch,unit_district,unit_user,public_unit)
 on conflict(scope_key) do update set version=public.occci_live_scopes.version+1,district=excluded.district,updated_at=now();
end;$$;
create or replace function public.occci_live_signal() returns trigger language plpgsql security definer set search_path='' as $$
declare snapshots jsonb[]; snapshot jsonb; branch_value text; district_value smallint; user_value text; found_scope boolean:=false; public_change boolean:=TG_TABLE_NAME in ('occci_content','occci_report_types');
begin
 snapshots:=array[case when TG_OP<>'INSERT' then to_jsonb(old) else '{}'::jsonb end,case when TG_OP<>'DELETE' then to_jsonb(new) else '{}'::jsonb end];
 foreach snapshot in array snapshots loop
  if public_change and snapshot ? 'id' and snapshot->>'branch_id' is null and snapshot->>'district' is null then perform public.occci_live_touch('global',null,null,null,true);end if;
  for branch_value in select distinct value from (values(snapshot->>'branch_id'),(snapshot->'before_data'->>'branch_id'),(snapshot->'after_data'->>'branch_id'),(case when TG_TABLE_NAME='occci_branches' then snapshot->>'id' end),((select p.branch_id from public.occci_profiles p where p.id::text=snapshot->>'member_id'))) branches(value) where value is not null loop
   select district into district_value from public.occci_branches where id=branch_value;
   perform public.occci_live_touch('branch',branch_value,district_value,null,false);found_scope:=true;
   if district_value is not null then perform public.occci_live_touch('district',null,district_value,null,false);end if;
   if public_change then perform public.occci_live_touch('branch',branch_value,district_value,null,true);end if;
  end loop;
  for district_value in select distinct value::smallint from (values(snapshot->>'district'),(snapshot->'before_data'->>'district'),(snapshot->'after_data'->>'district')) districts(value) where value ~ '^[1-6]$' loop
   perform public.occci_live_touch('district',null,district_value,null,false);found_scope:=true;
   if public_change then perform public.occci_live_touch('district',null,district_value,null,true);end if;
  end loop;
  for user_value in select distinct value from (values(snapshot->>'member_id'),(snapshot->>'user_id'),(snapshot->>'actor'),(case when TG_TABLE_NAME='occci_profiles' then snapshot->>'id' end)) users(value) where value ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' loop
   if exists(select 1 from auth.users where id=user_value::uuid) then perform public.occci_live_touch('user',null,null,user_value::uuid,false);end if;
  end loop;
 end loop;
 if not found_scope then perform public.occci_live_touch('global',null,null,null,false);if public_change then perform public.occci_live_touch('global',null,null,null,true);end if;end if;
 return null;
end;$$;
revoke all on function public.occci_live_touch(text,text,smallint,uuid,boolean),public.occci_live_signal() from public,anon,authenticated;
do $$
declare target text;
begin
 if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
  create publication supabase_realtime;
 end if;
 foreach target in array array['occci_profiles','occci_staff_assignments','occci_financials','occci_cashier_payments','occci_change_requests','occci_content','occci_audit','occci_staff_applications','occci_branches','occci_report_types','occci_reports','occci_report_events','occci_work_reports','occci_work_report_events','occci_live_scopes'] loop
  if to_regclass('public.'||target) is null then raise exception 'Apply earlier OCCCI migrations first: missing %',target;end if;
  if not exists(select 1 from pg_class where oid=to_regclass('public.'||target) and relrowsecurity) then raise exception 'Row level security is required for %',target;end if;
  if target<>'occci_live_scopes' then
   execute format('drop trigger if exists occci_live_signal on public.%I',target);
   execute format('create trigger occci_live_signal after insert or update or delete on public.%I for each row execute function public.occci_live_signal()',target);
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=target) then
   execute format('alter publication supabase_realtime add table public.%I',target);
  end if;
 end loop;
end;$$;
insert into public.occci_schema_versions(version) values('018_live_updates') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 018. Private cashier PINs and timed receipts.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
alter table public.occci_cashier_payments add column if not exists payment_time time;
create table if not exists public.occci_cashier_credentials(
 user_id uuid primary key references auth.users(id) on delete cascade,
 pin_hash text not null, failures integer not null default 0, locked_until timestamptz,
 updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.occci_cashier_pin_confirmations(
 id uuid primary key default gen_random_uuid(), actor uuid not null references auth.users(id) on delete cascade,
 branch_id text not null, pin_hash text not null, original_session text not null,
 created_at timestamptz not null default clock_timestamp(), used_at timestamptz, used_session text unique
);
alter table public.occci_cashier_credentials enable row level security;
alter table public.occci_cashier_pin_confirmations enable row level security;
revoke all on public.occci_cashier_credentials,public.occci_cashier_pin_confirmations from public,anon,authenticated;
-- Resolve the extension namespace so existing pgcrypto installations remain supported.
create or replace function public.occci_pin_hash(pin text,salt text default null) returns text language plpgsql security definer set search_path='' as $$
declare ns text; result text;
begin
 select n.nspname into ns from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';
 if ns is null then raise exception 'Activate pgcrypto before cashier PIN setup';end if;
 if salt is null then execute format('select %I.crypt($1,%I.gen_salt(''bf'',10))',ns,ns) into result using pin;
 else execute format('select %I.crypt($1,$2)',ns) into result using pin,salt;end if;
 return result;
end;$$;
create or replace function public.occci_begin_cashier_pin(new_pin text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; branch text; session_value text:=auth.jwt()->>'session_id';
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' or coalesce(session_value,'')='' then raise exception 'Only a signed-in Branch Cashier can set a PIN';end if;
 if coalesce(new_pin,'') !~ '^[0-9]{6}$' then raise exception 'Use a six-digit PIN';end if;
 select branch_id into branch from public.occci_staff_assignments where user_id=auth.uid();
 delete from public.occci_cashier_pin_confirmations where actor=auth.uid() and used_at is null;
 insert into public.occci_cashier_pin_confirmations(actor,branch_id,pin_hash,original_session) values(auth.uid(),branch,public.occci_pin_hash(new_pin),session_value) returning id into result;
 return result;
end;$$;
create or replace function public.occci_set_cashier_pin(confirmation uuid) returns void language plpgsql security definer set search_path='' as $$
declare c public.occci_cashier_pin_confirmations; claims jsonb:=auth.jwt(); session_value text:=claims->>'session_id'; password_time bigint; branch text; existed boolean;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' or claims->>'sub' is distinct from auth.uid()::text then raise exception 'Only the same Branch Cashier can set this PIN';end if;
 select * into c from public.occci_cashier_pin_confirmations where id=confirmation for update;
 select branch_id into branch from public.occci_staff_assignments where user_id=auth.uid();
 if c.id is null or c.actor<>auth.uid() or c.branch_id is distinct from branch or c.used_at is not null or c.created_at<clock_timestamp()-interval '5 minutes' then raise exception 'PIN confirmation expired or changed. Confirm your password again';end if;
 if coalesce(session_value,'')='' or session_value=c.original_session then raise exception 'Confirm your account password before setting a PIN';end if;
 if jsonb_typeof(claims->'amr')='array' then select max((a->>'timestamp')::bigint) into password_time from jsonb_array_elements(claims->'amr') a where a->>'method'='password' and coalesce(a->>'timestamp','') ~ '^[0-9]{1,12}$';end if;
 if password_time is null or password_time<floor(extract(epoch from c.created_at))::bigint or password_time>extract(epoch from clock_timestamp())::bigint+30 then raise exception 'A fresh account password sign-in is required';end if;
 if exists(select 1 from public.occci_cashier_pin_confirmations where used_session=session_value) then raise exception 'Confirm your password again for each PIN replacement';end if;
 existed:=exists(select 1 from public.occci_cashier_credentials where user_id=auth.uid());
 insert into public.occci_cashier_credentials(user_id,pin_hash) values(auth.uid(),c.pin_hash) on conflict(user_id) do update set pin_hash=excluded.pin_hash,failures=0,locked_until=null,updated_at=clock_timestamp();
 update public.occci_cashier_pin_confirmations set used_at=clock_timestamp(),used_session=session_value where id=c.id;
 perform public.occci_log(auth.uid(),branch,case when existed then 'Cashier PIN replaced' else 'Cashier PIN created' end,null,jsonb_build_object('pin_configured',true),'Account password confirmed');
end;$$;
create or replace function public.occci_cashier_pin_status() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only Branch Cashier can access PIN settings';end if;
 return jsonb_build_object('configured',exists(select 1 from public.occci_cashier_credentials where user_id=auth.uid()));
end;$$;
do $$begin
 if to_regprocedure('public.occci_record_cashier_payment_pin_impl(uuid,jsonb,integer,uuid,text)') is null then alter function public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text) rename to occci_record_cashier_payment_pin_impl;end if;
end;$$;
revoke all on function public.occci_record_cashier_payment_pin_impl(uuid,jsonb,integer,uuid,text) from public,anon,authenticated;
create or replace function public.occci_record_cashier_payment(target uuid,values_json jsonb,expected_revision integer,client_reference uuid,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.occci_cashier_credentials; posted jsonb; pin text:=values_json->>'cashier_pin'; payment_clock time; existing_time time; prior_exists boolean; failures_next integer;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only the assigned Branch Cashier can record payments';end if;
 select * into c from public.occci_cashier_credentials where user_id=auth.uid() for update;
 if not found then return jsonb_build_object('error','Create your secret PIN in Settings before recording a payment.');end if;
 if c.locked_until>clock_timestamp() then return jsonb_build_object('error','PIN temporarily locked. Try again after 15 minutes or replace it in Settings using your password.');end if;
 if coalesce(pin,'') !~ '^[0-9]{6}$' or public.occci_pin_hash(pin,c.pin_hash)<>c.pin_hash then
  failures_next:=case when c.locked_until is not null then 1 else c.failures+1 end;
  update public.occci_cashier_credentials set failures=failures_next,locked_until=case when failures_next>=5 then clock_timestamp()+interval '15 minutes' end where user_id=auth.uid();
  -- Return a failure rather than raising: the attempt counter must commit.
  return jsonb_build_object('error',case when failures_next>=5 then 'PIN temporarily locked for 15 minutes.' else 'Incorrect PIN. Payment was not recorded.' end);
 end if;
 if coalesce(values_json->>'payment_time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then raise exception 'Choose a valid payment time';end if;
 payment_clock:=(values_json->>'payment_time')::time;
 if (values_json->>'payment_date')::date+payment_clock>(clock_timestamp() at time zone 'Asia/Manila')+interval '1 minute' then raise exception 'Payment date and time cannot be in the future';end if;
 select payment_time,true into existing_time,prior_exists from public.occci_cashier_payments where id=client_reference;
 if prior_exists and existing_time is distinct from payment_clock then raise exception 'This payment reference was already used for a different time';end if;
 posted:=public.occci_record_cashier_payment_pin_impl(target,values_json-'cashier_pin'-'payment_time',expected_revision,client_reference,reason);
 if prior_exists is distinct from true then
  update public.occci_cashier_payments set payment_time=payment_clock where id=client_reference;
  perform public.occci_log(target,posted->>'branch_id','Receipt time recorded',null,jsonb_build_object('receipt_id',client_reference,'payment_date',posted->>'payment_date','payment_time',payment_clock),'Receipt time in Asia/Manila');
 end if;
 update public.occci_cashier_credentials set failures=0,locked_until=null where user_id=auth.uid();
 return posted||jsonb_build_object('payment_time',payment_clock);
end;$$;
revoke all on function public.occci_cashier_pin_status(),public.occci_pin_hash(text,text),public.occci_begin_cashier_pin(text),public.occci_set_cashier_pin(uuid),public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text) from public,anon,authenticated;
grant execute on function public.occci_cashier_pin_status(),public.occci_begin_cashier_pin(text),public.occci_set_cashier_pin(uuid),public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text) to authenticated;
insert into public.occci_schema_versions(version) values('019_cashier_pin_time') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 019. Cashier password approval belongs to the assigned BM.
begin;
create table if not exists public.occci_password_requests(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 branch_id text not null references public.occci_branches(id), purpose text not null check(purpose in ('Change password','Recover password')),
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected','Completed','Expired')),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 created_at timestamptz not null default clock_timestamp(), reviewer_id uuid references auth.users(id),
 review_note text, reviewed_at timestamptz, approval_expires_at timestamptz, completed_at timestamptz
);
create unique index if not exists occci_password_request_active on public.occci_password_requests(user_id) where status in ('Pending','Approved');
alter table public.occci_password_requests enable row level security;
revoke all on public.occci_password_requests from public,anon,authenticated;
grant select on public.occci_password_requests to authenticated;
drop policy if exists occci_password_requests_read on public.occci_password_requests;
create policy occci_password_requests_read on public.occci_password_requests for select to authenticated using(
 exists(select 1 from public.occci_profiles p where p.id=auth.uid() and p.archived_at is null) and
 (user_id=auth.uid() or public.occci_role()='Admin' or (public.occci_role() in ('BM','DM') and public.occci_can_read_branch(branch_id)))
);
create or replace function public.occci_request_cashier_password(purpose text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare branch text; result uuid;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only Branch Cashier can submit this request';end if;
 if purpose is null or purpose not in ('Change password','Recover password') or coalesce(length(btrim(reason)),0) not between 3 and 2000 then raise exception 'Choose the request type and provide a reason';end if;
 select branch_id into branch from public.occci_staff_assignments where user_id=auth.uid();
 if not exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.role='BM' and t.branch_id=branch and p.archived_at is null) then raise exception 'Your branch needs an assigned BM before a password request can be submitted';end if;
 update public.occci_password_requests set status='Expired' where user_id=auth.uid() and status in ('Pending','Approved') and (branch_id<>branch or status='Approved' and approval_expires_at<=clock_timestamp());
 if exists(select 1 from public.occci_password_requests where user_id=auth.uid() and status in ('Pending','Approved')) then raise exception 'You already have a pending or approved password request';end if;
 insert into public.occci_password_requests(user_id,branch_id,purpose,reason) values(auth.uid(),branch,purpose,btrim(reason)) returning id into result;
 perform public.occci_log(auth.uid(),branch,'Cashier password request submitted',null,jsonb_build_object('request_id',result,'purpose',purpose,'status','Pending'),'Sent to the assigned Branch Manager');
 return result;
end;$$;
create or replace function public.occci_review_cashier_password(request_id uuid,decision text,note text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_password_requests;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 select * into q from public.occci_password_requests where id=request_id for update;
 if q.id is null or public.occci_role()<>'BM' or not public.occci_can_read_branch(q.branch_id) or q.user_id=auth.uid() then raise exception 'Only the assigned Branch Manager can decide this request';end if;
 if q.status<>'Pending' then raise exception 'This request has already been reviewed';end if;
 if not exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=q.user_id and t.role='BC' and t.branch_id=q.branch_id and p.archived_at is null) then raise exception 'The cashier assignment changed. A new request is required';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(btrim(note)),0) not between 3 and 2000 then raise exception 'Choose approve or reject and provide decision notes';end if;
 update public.occci_password_requests set status=case decision when 'Approve' then 'Approved' else 'Rejected' end,reviewer_id=auth.uid(),review_note=btrim(note),reviewed_at=clock_timestamp(),approval_expires_at=case when decision='Approve' then clock_timestamp()+interval '24 hours' end where id=request_id;
 perform public.occci_log(q.user_id,q.branch_id,'Cashier password request reviewed',null,jsonb_build_object('request_id',q.id,'decision',decision),'Branch Manager decision recorded');
end;$$;
-- This gate is enforced at the Auth password update, including requests made outside the UI.
-- It never copies old/new password hashes into cooperative tables or logs.
create or replace function public.occci_guard_cashier_password() returns trigger language plpgsql security definer set search_path='' as $$
declare branch text; q public.occci_password_requests;
begin
 if new.encrypted_password is not distinct from old.encrypted_password then return new;end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 select t.branch_id into branch from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=new.id and t.role='BC' and p.archived_at is null;
 if branch is null then return new;end if;
 select * into q from public.occci_password_requests where user_id=new.id and branch_id=branch and status='Approved' and approval_expires_at>clock_timestamp() for update;
 if q.id is null then raise exception 'A current Branch Manager approval is required to change this cashier password';end if;
 update public.occci_password_requests set status='Completed',completed_at=clock_timestamp() where id=q.id;
 perform public.occci_log(new.id,branch,'Cashier password updated',null,jsonb_build_object('request_id',q.id,'purpose',q.purpose,'status','Completed'),'Approved password change completed through Supabase Auth');
 return new;
end;$$;
drop trigger if exists occci_guard_cashier_password on auth.users;
create trigger occci_guard_cashier_password before update of encrypted_password on auth.users for each row execute function public.occci_guard_cashier_password();
revoke all on function public.occci_request_cashier_password(text,text),public.occci_review_cashier_password(uuid,text,text),public.occci_guard_cashier_password() from public,anon,authenticated;
grant execute on function public.occci_request_cashier_password(text,text),public.occci_review_cashier_password(uuid,text,text) to authenticated;
drop trigger if exists occci_live_signal on public.occci_password_requests;
create trigger occci_live_signal after insert or update or delete on public.occci_password_requests for each row execute function public.occci_live_signal();
do $$begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='occci_password_requests') then alter publication supabase_realtime add table public.occci_password_requests;end if;
end;$$;
insert into public.occci_schema_versions(version) values('020_cashier_password_requests') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 020. Per-user notifications never expand operational permissions.
begin;
create table if not exists public.occci_notifications(
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null, event_key text not null,
 scope_kind text not null check(scope_kind in ('personal','unit')), branch_id text references public.occci_branches(id), district smallint,
 title text not null, body text not null, target_type text not null, target_id text,
 created_at timestamptz not null default clock_timestamp(), read_at timestamptz,
 unique(recipient_id,event_key)
);
create index if not exists occci_notification_inbox on public.occci_notifications(recipient_id,created_at desc,id);
alter table public.occci_notifications enable row level security;
revoke all on public.occci_notifications from public,anon,authenticated;
grant select on public.occci_notifications to authenticated;
create or replace function public.occci_notification_visible(recipient uuid,kind text,branch text,unit_district smallint) returns boolean language sql stable security definer set search_path='' as $$
 select recipient=auth.uid() and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and
 (kind='personal' or t.role='Admin' or (t.role='DM' and t.district=unit_district) or (t.role in ('BM','Staff','BC') and branch is not null and t.branch_id=branch)));
$$;
drop policy if exists occci_notification_read on public.occci_notifications;
create policy occci_notification_read on public.occci_notifications for select to authenticated using(public.occci_notification_visible(recipient_id,scope_kind,branch_id,district));
create or replace function public.occci_mark_notifications_read(notification_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.occci_notifications set read_at=clock_timestamp() where read_at is null and (notification_id is null or id=notification_id) and public.occci_notification_visible(recipient_id,scope_kind,branch_id,district);
end;$$;
-- Only private business triggers can create notifications. No client can choose recipients or messages.
-- Correct earlier personal classifications if this migration has already been applied.
-- Global Admin queue notices are not personal notices about the recipient's own account.
create or replace function public.occci_notification_scope_signal() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.scope_kind is distinct from old.scope_kind or new.branch_id is distinct from old.branch_id or new.district is distinct from old.district then
  perform public.occci_live_touch('user',null,null,new.recipient_id,false);
 end if;
 return null;
end;$$;
revoke all on function public.occci_notification_scope_signal() from public,anon,authenticated;
drop trigger if exists occci_notification_scope_signal on public.occci_notifications;
create trigger occci_notification_scope_signal after update on public.occci_notifications for each row execute function public.occci_notification_scope_signal();
update public.occci_notifications set scope_kind='unit',branch_id=null,district=null
 where scope_kind='personal' and target_type in ('staff_application','team') and recipient_id::text is distinct from target_id;
create or replace function public.occci_notify_emit(key_value text,roles text[],unit_branch text,unit_district smallint,users uuid[],heading text,message text,target_kind text,target_value text,personal boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare d smallint:=coalesce(unit_district,(select district from public.occci_branches where id=unit_branch));
begin
 insert into public.occci_notifications(recipient_id,actor_id,event_key,scope_kind,branch_id,district,title,body,target_type,target_id)
 select t.user_id,auth.uid(),key_value,case when personal then 'personal' else 'unit' end,case when personal then null else unit_branch end,case when personal then null else d end,left(heading,140),left(message,400),target_kind,target_value
 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id
 where p.archived_at is null and p.onboarding_complete and t.user_id is distinct from auth.uid() and not (not personal and target_kind='team' and t.user_id::text=target_value) and
 ((t.role=any(roles) and (t.role='Admin' or t.role='DM' and t.district=d or t.role in ('BM','Staff','BC') and t.branch_id=unit_branch)) or
 (t.user_id=any(users) and (personal or t.role='Admin' or t.role='DM' and t.district=d or t.role in ('BM','Staff','BC') and t.branch_id=unit_branch)))
 on conflict(recipient_id,event_key) do nothing;
end;$$;
create or replace function public.occci_notify_route(source text,v jsonb,prior jsonb,operation text) returns void language plpgsql security definer set search_path='' as $$
declare branch text:=v->>'branch_id'; d smallint; uid uuid; author uuid; key_value text; status text:=v->>'status'; old_status text:=prior->>'status'; roles text[]:='{}'; users uuid[]:='{}'; title text; message text:='Open the record to view its details.'; target_kind text; target_value text:=coalesce(v->>'id',v->>'user_id'); personal boolean:=false; audience uuid[]; audience_branch text;
begin
 if operation='DELETE' then
  if source='occci_staff_assignments' then perform public.occci_notify_emit(source||':'||(v->>'user_id')||':removed:'||pg_catalog.txid_current()::text,array['Admin','BM','DM'],v->>'branch_id',null,array[]::uuid[],'Team assignment removed','A cooperative team assignment was removed.','activity',null);end if;
  return;
 end if;
 if coalesce(v->>'district','') ~ '^[1-6]$' then d:=(v->>'district')::smallint;end if;
 key_value:=source||':'||coalesce(target_value,'')||':'||coalesce(status,v->>'membership_status',v->>'role','event')||':'||coalesce(v->>'revision',v->>'reviewed_at',v->>'updated_at',v->>'created_at','initial');
 if source='occci_profiles' then
  if v->>'registration_kind'='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=(v->>'id')::uuid) or v->>'archived_at' is not null or coalesce(v->>'onboarding_complete','false')<>'true' or v->>'membership_status'<>'Pending verification' or (operation='UPDATE' and prior->>'membership_status'='Pending verification' and prior->>'onboarding_complete'='true') then return;end if;
  roles:=array['BM','Staff','BC'];title:='New member awaiting BM screening';target_kind:='profile';
 elsif source='occci_change_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  author:=(v->>'submitted_by')::uuid;target_kind:='request';users:=array[author];
  if status='Pending' then roles:=case when v->>'kind'='Profile edit' then array['BM','DM'] else array['BM'] end;title:=(v->>'kind')||' awaiting review';
  elsif status='BM approved' and v->>'kind' in ('Financial sync','Membership approval') then roles:=array['DM'];title:=(v->>'kind')||' needs final DM approval';
  else roles:=case when status='Applied' then array['Admin','BM','DM','Staff','BC'] else array[]::text[] end;title:=(v->>'kind')||': '||status;end if;
 elsif source='occci_password_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  users:=array[(v->>'user_id')::uuid];target_kind:='password_request';title:='Cashier password request: '||status;
  if status='Pending' then roles:=array['BM'];message:='Review the cashier request and its reason.';elsif status='Completed' then roles:=array['BM'];end if;
 elsif source='occci_staff_applications' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  branch:=null;d:=null;personal:=status<>'Pending';target_kind:='staff_application';users:=case when status='Pending' then array[]::uuid[] else array[(v->>'user_id')::uuid] end;roles:=case when status='Pending' then array['Admin'] else array[]::text[] end;title:='Staff application: '||status;
 elsif source='occci_staff_assignments' then
  if operation='UPDATE' and v->>'role' is not distinct from prior->>'role' and branch is not distinct from prior->>'branch_id' and v->>'district' is not distinct from prior->>'district' then return;end if;
  key_value:=source||':'||(v->>'user_id')||':'||pg_catalog.txid_current()::text;uid:=(v->>'user_id')::uuid;target_kind:='team';title:='Team assignment updated';message:='A cooperative position or operating unit has changed.';
  perform public.occci_notify_emit(key_value,array[]::text[],branch,d,array[uid],title,message,target_kind,target_value,true);
  perform public.occci_notify_emit(key_value||':admin',array['Admin'],branch,d,array[]::uuid[],title,message,target_kind,target_value,false);return;
 elsif source='occci_cashier_payments' then
  if operation='UPDATE' then return;end if;
  roles:=array['Admin','BM','DM','Staff','BC'];target_kind:='payment';title:='Cashier payment recorded';message:='A receipt was recorded and member balances were updated.';
 elsif source in ('occci_work_reports','occci_reports') then
  if v->>'archived_at' is not null or status='Draft' or (source='occci_reports' and v->'details' ? 'staff_work_id') or (operation='UPDATE' and status is not distinct from old_status) then return;end if;
  users:=array[(v->>'created_by')::uuid];target_kind:=case when source='occci_work_reports' then 'work_report' else 'report' end;title:=case when source='occci_work_reports' then 'Staff work report' else 'Cooperative report' end||': '||status;
  if source='occci_work_reports' then roles:=case when status='For review' then array['BM'] when status='Approved' then array['Admin','DM'] else array[]::text[] end;
  else roles:=array['Admin','DM','BM'];end if;
 elsif source='occci_content' then
  if v->>'published' is distinct from 'true' or v->>'archived_at' is not null then
   if prior->>'published' is distinct from 'true' then return;end if;
   branch:=prior->>'branch_id';d:=null;if coalesce(prior->>'district','') ~ '^[1-6]$' then d:=(prior->>'district')::smallint;end if;
   title:='Published content withdrawn';
  else title:='Published cooperative content updated';end if;
  target_kind:='content';message:='Announcements, events or services in your workspace have changed.';
  if branch is null and d is null then
   select array_agg(user_id) into audience from public.occci_staff_assignments;
   perform public.occci_notify_emit(key_value,array[]::text[],null,null,coalesce(audience,array[]::uuid[]),title,message,target_kind,target_value,true);return;
  elsif branch is null then
   perform public.occci_notify_emit(key_value,array['Admin','DM'],null,d,array[]::uuid[],title,message,target_kind,target_value);
   for audience_branch in select id from public.occci_branches where district=d loop
    perform public.occci_notify_emit(key_value,array['BM','Staff','BC'],audience_branch,d,array[]::uuid[],title,message,target_kind,target_value);
   end loop;return;
  else roles:=array['Admin','DM','BM','Staff','BC'];end if;
 elsif source='occci_audit' then
  if operation<>'INSERT' then return;end if;
  -- Dedicated workflows above create focused notifications, so audit does not duplicate them.
  if v->>'action' ~* '(request|financial|membership|cashier password|cashier payment|receipt time|staff application|team assignment|profile edit|report|content)' then return;end if;
  roles:=case when v->>'action' ~* 'cashier pin' then array['BM'] when branch is null then array['Admin'] else array['Admin','BM','DM','Staff','BC'] end;target_kind:='activity';title:=v->>'action';message:='New cooperative activity was recorded in your authorized workspace.';
 else return;end if;
 perform public.occci_notify_emit(key_value,roles,branch,d,users,title,message,target_kind,target_value,personal);
end;$$;
create or replace function public.occci_notify_business() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform public.occci_notify_route(TG_TABLE_NAME,case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end,case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end,TG_OP);
 return null;
end;$$;
revoke all on function public.occci_notification_visible(uuid,text,text,smallint),public.occci_mark_notifications_read(uuid),public.occci_notify_emit(text,text[],text,smallint,uuid[],text,text,text,text,boolean),public.occci_notify_route(text,jsonb,jsonb,text),public.occci_notify_business() from public,anon,authenticated;
grant execute on function public.occci_notification_visible(uuid,text,text,smallint),public.occci_mark_notifications_read(uuid) to authenticated;
do $$declare table_name text;begin
 foreach table_name in array array['occci_profiles','occci_change_requests','occci_password_requests','occci_staff_applications','occci_staff_assignments','occci_cashier_payments','occci_work_reports','occci_reports','occci_content','occci_audit'] loop
  execute format('drop trigger if exists occci_notify_business on public.%I',table_name);
  execute format('create trigger occci_notify_business after insert or update or delete on public.%I for each row execute function public.occci_notify_business()',table_name);
 end loop;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='occci_notifications') then alter publication supabase_realtime add table public.occci_notifications;end if;
end;$$;
-- Seed actionable queues once, without replaying historical payments/activity.
do $$declare table_name text; row_value jsonb;begin
 foreach table_name in array array['occci_profiles','occci_change_requests','occci_password_requests','occci_staff_applications','occci_work_reports','occci_reports'] loop
  for row_value in execute format('select to_jsonb(t) from public.%I t',table_name) loop
   if coalesce(row_value->>'status',row_value->>'membership_status') in ('Pending','BM approved','For review','Pending verification') then
    perform public.occci_notify_route(table_name,row_value,'{}'::jsonb,'SEED');
   end if;
  end loop;
 end loop;
end;$$;
insert into public.occci_schema_versions(version) values('021_staff_notifications') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 021. Resolved notifications leave the active inbox; audit records remain stored.
begin;
alter table public.occci_notifications add column if not exists resolved_at timestamptz;
alter table public.occci_notifications add column if not exists action_required boolean not null default false;
create or replace function public.occci_notification_action() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.action_required:=case new.target_type
 when 'profile' then exists(select 1 from public.occci_profiles where id::text=new.target_id and membership_status='Pending verification' and archived_at is null)
 when 'request' then exists(select 1 from public.occci_change_requests where id::text=new.target_id and status in ('Pending','BM approved'))
 when 'password_request' then exists(select 1 from public.occci_password_requests where id::text=new.target_id and status in ('Pending','Approved'))
 when 'staff_application' then exists(select 1 from public.occci_staff_applications where user_id::text=new.target_id and status='Pending')
 when 'work_report' then exists(select 1 from public.occci_work_reports where id::text=new.target_id and status in ('For review','Returned'))
 when 'report' then exists(select 1 from public.occci_reports where id::text=new.target_id and status in ('For review','Returned'))
 else false end;
 return new;
end;$$;
revoke all on function public.occci_notification_action() from public,anon,authenticated;
drop trigger if exists occci_notification_action on public.occci_notifications;
create trigger occci_notification_action before insert on public.occci_notifications for each row execute function public.occci_notification_action();
create or replace function public.occci_mark_notifications_read(notification_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.occci_notifications set read_at=coalesce(read_at,clock_timestamp()),resolved_at=case when action_required then resolved_at else coalesce(resolved_at,clock_timestamp()) end where (notification_id is null or id=notification_id) and public.occci_notification_visible(recipient_id,scope_kind,branch_id,district);
end;$$;
create or replace function public.occci_notify_route(source text,v jsonb,prior jsonb,operation text) returns void language plpgsql security definer set search_path='' as $$
declare branch text:=v->>'branch_id'; d smallint; uid uuid; author uuid; key_value text; status text:=v->>'status'; old_status text:=prior->>'status'; roles text[]:='{}'; users uuid[]:='{}'; title text; message text:='Open the record to view its details.'; target_kind text; target_value text:=coalesce(v->>'id',v->>'user_id'); personal boolean:=false; audience uuid[]; audience_branch text;
begin

 -- Resolve the previous stage before generating its successor notification.
 if operation='DELETE' or v->>'archived_at' is not null or (operation='UPDATE' and (v->>'status' is distinct from prior->>'status' or v->>'membership_status' is distinct from prior->>'membership_status' or v->>'published' is distinct from prior->>'published')) then
  update public.occci_notifications set resolved_at=clock_timestamp() where resolved_at is null and target_id=coalesce(v->>'id',v->>'user_id') and target_type=case source when 'occci_profiles' then 'profile' when 'occci_change_requests' then 'request' when 'occci_password_requests' then 'password_request' when 'occci_staff_applications' then 'staff_application' when 'occci_work_reports' then 'work_report' when 'occci_reports' then 'report' when 'occci_content' then 'content' when 'occci_cashier_payments' then 'payment' when 'occci_staff_assignments' then 'team' else source end;
 end if;
 if source='occci_change_requests' and v->>'kind'='Membership approval' then
  update public.occci_notifications set resolved_at=clock_timestamp() where resolved_at is null and target_type='profile' and target_id=v->>'member_id';
 end if;
 if operation='DELETE' then
  if source='occci_staff_assignments' then perform public.occci_notify_emit(source||':'||(v->>'user_id')||':removed:'||pg_catalog.txid_current()::text,array['Admin','BM','DM'],v->>'branch_id',null,array[]::uuid[],'Team assignment removed','A cooperative team assignment was removed.','activity',null);end if;
  return;
 end if;
 if coalesce(v->>'district','') ~ '^[1-6]$' then d:=(v->>'district')::smallint;end if;
 key_value:=source||':'||coalesce(target_value,'')||':'||coalesce(status,v->>'membership_status',v->>'role','event')||':'||coalesce(v->>'revision',v->>'reviewed_at',v->>'updated_at',v->>'created_at','initial');
 if source='occci_profiles' then
  if v->>'registration_kind'='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=(v->>'id')::uuid) or v->>'archived_at' is not null or coalesce(v->>'onboarding_complete','false')<>'true' or v->>'membership_status'<>'Pending verification' or (operation='UPDATE' and prior->>'membership_status'='Pending verification' and prior->>'onboarding_complete'='true') then return;end if;
  roles:=array['BM','Staff','BC'];title:='New member awaiting BM screening';target_kind:='profile';
 elsif source='occci_change_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  author:=(v->>'submitted_by')::uuid;target_kind:='request';users:=array[author];
  if status='Pending' then roles:=case when v->>'kind'='Profile edit' then array['BM','DM'] else array['BM'] end;title:=(v->>'kind')||' awaiting review';
  elsif status='BM approved' and v->>'kind' in ('Financial sync','Membership approval') then roles:=array['DM'];title:=(v->>'kind')||' needs final DM approval';
  else roles:=case when status='Applied' then array['Admin','BM','DM','Staff','BC'] else array[]::text[] end;title:=(v->>'kind')||': '||status;end if;
 elsif source='occci_password_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  users:=array[(v->>'user_id')::uuid];target_kind:='password_request';title:='Cashier password request: '||status;
  if status='Pending' then roles:=array['BM'];message:='Review the cashier request and its reason.';elsif status='Completed' then roles:=array['BM'];end if;
 elsif source='occci_staff_applications' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  branch:=null;d:=null;personal:=status<>'Pending';target_kind:='staff_application';users:=case when status='Pending' then array[]::uuid[] else array[(v->>'user_id')::uuid] end;roles:=case when status='Pending' then array['Admin'] else array[]::text[] end;title:='Staff application: '||status;
 elsif source='occci_staff_assignments' then
  if operation='UPDATE' and v->>'role' is not distinct from prior->>'role' and branch is not distinct from prior->>'branch_id' and v->>'district' is not distinct from prior->>'district' then return;end if;
  key_value:=source||':'||(v->>'user_id')||':'||pg_catalog.txid_current()::text;uid:=(v->>'user_id')::uuid;target_kind:='team';title:='Team assignment updated';message:='A cooperative position or operating unit has changed.';
  perform public.occci_notify_emit(key_value,array[]::text[],branch,d,array[uid],title,message,target_kind,target_value,true);
  perform public.occci_notify_emit(key_value||':admin',array['Admin'],branch,d,array[]::uuid[],title,message,target_kind,target_value,false);return;
 elsif source='occci_cashier_payments' then
  if operation='UPDATE' then return;end if;
  roles:=array['Admin','BM','DM','Staff','BC'];target_kind:='payment';title:='Cashier payment recorded';message:='A receipt was recorded and member balances were updated.';
 elsif source in ('occci_work_reports','occci_reports') then
  if v->>'archived_at' is not null or status='Draft' or (source='occci_reports' and v->'details' ? 'staff_work_id') or (operation='UPDATE' and status is not distinct from old_status) then return;end if;
  users:=array[(v->>'created_by')::uuid];target_kind:=case when source='occci_work_reports' then 'work_report' else 'report' end;title:=case when source='occci_work_reports' then 'Staff work report' else 'Cooperative report' end||': '||status;
  if source='occci_work_reports' then roles:=case when status='For review' then array['BM'] when status='Approved' then array['Admin','DM'] else array[]::text[] end;
  else roles:=array['Admin','DM','BM'];end if;
 elsif source='occci_content' then
  if v->>'published' is distinct from 'true' or v->>'archived_at' is not null then
   if prior->>'published' is distinct from 'true' then return;end if;
   branch:=prior->>'branch_id';d:=null;if coalesce(prior->>'district','') ~ '^[1-6]$' then d:=(prior->>'district')::smallint;end if;
   title:='Published content withdrawn';
  else title:='Published cooperative content updated';end if;
  target_kind:='content';message:='Announcements, events or services in your workspace have changed.';
  if branch is null and d is null then
   select array_agg(user_id) into audience from public.occci_staff_assignments;
   perform public.occci_notify_emit(key_value,array[]::text[],null,null,coalesce(audience,array[]::uuid[]),title,message,target_kind,target_value,true);return;
  elsif branch is null then
   perform public.occci_notify_emit(key_value,array['Admin','DM'],null,d,array[]::uuid[],title,message,target_kind,target_value);
   for audience_branch in select id from public.occci_branches where district=d loop
    perform public.occci_notify_emit(key_value,array['BM','Staff','BC'],audience_branch,d,array[]::uuid[],title,message,target_kind,target_value);
   end loop;return;
  else roles:=array['Admin','DM','BM','Staff','BC'];end if;
 elsif source='occci_audit' then
  if operation<>'INSERT' then return;end if;
  -- Dedicated workflows above create focused notifications, so audit does not duplicate them.
  if v->>'action' ~* '(request|financial|membership|cashier password|cashier payment|receipt time|staff application|team assignment|profile edit|report|content)' then return;end if;
  roles:=case when v->>'action' ~* 'cashier pin' then array['BM'] when branch is null then array['Admin'] else array['Admin','BM','DM','Staff','BC'] end;target_kind:='activity';title:=v->>'action';message:='New cooperative activity was recorded in your authorized workspace.';
 else return;end if;
 perform public.occci_notify_emit(key_value,roles,branch,d,users,title,message,target_kind,target_value,personal);
end;$$;

drop trigger if exists occci_notification_backfill on public.occci_notifications;
create trigger occci_notification_backfill before update on public.occci_notifications for each row execute function public.occci_notification_action();
update public.occci_notifications set action_required=action_required;
drop trigger occci_notification_backfill on public.occci_notifications;
update public.occci_notifications set resolved_at=clock_timestamp() where read_at is not null and not action_required and resolved_at is null;

-- Retire obsolete stages that existed before this migration was installed.
update public.occci_notifications n set resolved_at=clock_timestamp() where n.resolved_at is null and (
 (n.target_type='request' and not exists(select 1 from public.occci_change_requests q where q.id::text=n.target_id and n.event_key like 'occci_change_requests:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='password_request' and not exists(select 1 from public.occci_password_requests q where q.id::text=n.target_id and n.event_key like 'occci_password_requests:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='staff_application' and not exists(select 1 from public.occci_staff_applications q where q.user_id::text=n.target_id and n.event_key like 'occci_staff_applications:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='work_report' and not exists(select 1 from public.occci_work_reports q where q.id::text=n.target_id and to_jsonb(q)->>'archived_at' is null and n.event_key like 'occci_work_reports:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='report' and not exists(select 1 from public.occci_reports q where q.id::text=n.target_id and to_jsonb(q)->>'archived_at' is null and n.event_key like 'occci_reports:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='profile' and (not n.action_required or exists(select 1 from public.occci_change_requests q where q.member_id::text=n.target_id and q.kind='Membership approval' and q.status in ('BM approved','Applied'))))
);
insert into public.occci_schema_versions(version) values('022_notification_actions') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 022. Private announcement originals and 16:9 member display posters.
begin;
alter table public.occci_content add column if not exists poster_path text;
alter table public.occci_content add column if not exists poster_original_path text;
alter table public.occci_content add column if not exists poster_crop jsonb;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('occci-posters','occci-posters',false,300000,array['image/webp']) on conflict(id) do update set public=false,file_size_limit=300000,allowed_mime_types=array['image/webp'];
create or replace function public.occci_can_manage_content(unit_branch text,unit_district smallint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p join public.occci_staff_assignments t on t.user_id=p.id where p.id=auth.uid() and p.archived_at is null and p.onboarding_complete and (t.role='Admin' or t.role='DM' and (unit_branch is not null and exists(select 1 from public.occci_branches b where b.id=unit_branch and b.district=t.district) or unit_branch is null and unit_district=t.district) or t.role='BM' and unit_branch is not null and t.branch_id=unit_branch));
$$;
create or replace function public.occci_can_read_poster(object_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_content c where c.archived_at is null and
 (c.poster_original_path=object_path and public.occci_can_manage_content(c.branch_id,c.district) or c.poster_path=object_path and (public.occci_can_manage_content(c.branch_id,c.district) or c.published and exists(
 select 1 from public.occci_profiles p join public.occci_branches b on b.id=p.branch_id where p.id=auth.uid() and p.archived_at is null and p.onboarding_complete and p.registration_kind<>'Staff' and not exists(select 1 from public.occci_staff_assignments t where t.user_id=p.id) and (c.branch_id is null or c.branch_id=p.branch_id) and (c.district is null or c.district=b.district)
 ) or c.published and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and (t.role='Admin' or t.role='DM' and (c.branch_id is null and (c.district is null or c.district=t.district) or exists(select 1 from public.occci_branches b where b.id=c.branch_id and b.district=t.district)) or t.role in ('BM','Staff','BC') and (c.branch_id is null and (c.district is null or c.district=(select district from public.occci_branches where id=t.branch_id)) or c.branch_id=t.branch_id))))));
$$;
drop policy if exists occci_poster_insert on storage.objects;
create policy occci_poster_insert on storage.objects for insert to authenticated with check(bucket_id='occci-posters' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and t.role in ('Admin','DM','BM') and p.archived_at is null and p.onboarding_complete));
drop policy if exists occci_poster_read on storage.objects;
create policy occci_poster_read on storage.objects for select to authenticated using(bucket_id='occci-posters' and public.occci_can_read_poster(name));
create or replace function public.occci_save_content_poster(record_id text,values_json jsonb,poster_path text,original_path text,crop jsonb,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare current_row public.occci_content; saved public.occci_content; branch text:=nullif(values_json->>'branch_id',''); district smallint:=nullif(values_json->>'district','')::smallint; display_path text:=nullif(poster_path,''); source_path text:=nullif(original_path,''); recipe jsonb; field text;
begin
 if coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Reason / Comments / Notes are required';end if;
 if coalesce(record_id,'')<>'' then select * into current_row from public.occci_content where id=record_id::uuid and archived_at is null for update;if not found then raise exception 'Content not found';end if;if not public.occci_can_manage_content(current_row.branch_id,current_row.district) then raise exception 'Content is outside your scope';end if;end if;
 if not public.occci_can_manage_content(branch,district) then raise exception 'Choose content scope within your assignment';end if;
 if district is not null and district not between 1 and 6 then raise exception 'Choose a valid district';end if;
 if branch is not null then if not exists(select 1 from public.occci_branches where id=branch and active) then raise exception 'Choose an active branch';end if;district:=null;end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 1 and 150 or coalesce(length(trim(values_json->>'body')),0)=0 then raise exception 'Title and content are required';end if;
 if values_json->>'kind' not in ('Announcement','Event','Service') or values_json->>'kind' is null then raise exception 'Choose a valid content type';end if;
 if display_path is not null then
  if values_json->>'kind'<>'Announcement' then raise exception 'Posters are available for announcements';end if;
  if source_path is null or source_path=display_path or jsonb_typeof(crop) is distinct from 'object' then raise exception 'Original photo and crop settings are required';end if;
  foreach field in array array['zoom','x','y'] loop if jsonb_typeof(crop->field) is distinct from 'number' then raise exception 'Invalid crop settings';end if;end loop;
  if (crop->>'zoom')::numeric not between 1 and 3 or (crop->>'x')::numeric not between -1 and 1 or (crop->>'y')::numeric not between -1 and 1 then raise exception 'Invalid crop settings';end if;
  if not exists(select 1 from storage.objects where bucket_id='occci-posters' and name=display_path and coalesce(metadata->>'mimetype','')='image/webp' and coalesce((metadata->>'size')::bigint,300001) between 1 and 300000) or (display_path is distinct from current_row.poster_path and display_path not like auth.uid()::text||'/%') then raise exception 'Upload the cropped poster first';end if;
  if not exists(select 1 from storage.objects where bucket_id='occci-posters' and name=source_path and coalesce(metadata->>'mimetype','')='image/webp' and coalesce((metadata->>'size')::bigint,300001) between 1 and 300000) or (source_path is distinct from current_row.poster_original_path and source_path not like auth.uid()::text||'/%') then raise exception 'Upload the original poster first';end if;
  recipe:=jsonb_build_object('zoom',(crop->>'zoom')::numeric,'x',(crop->>'x')::numeric,'y',(crop->>'y')::numeric,'aspect','16:9');
 elsif source_path is not null or crop is not null then raise exception 'Remove both the poster and its crop settings';end if;
 insert into public.occci_content(id,kind,title,body,branch_id,district,event_date,published,created_by,poster_path,poster_original_path,poster_crop)
 values(coalesce(current_row.id,gen_random_uuid()),values_json->>'kind',trim(values_json->>'title'),values_json->>'body',branch,district,nullif(values_json->>'event_date','')::date,coalesce((values_json->>'published')::boolean,false),auth.uid(),display_path,source_path,recipe)
 on conflict(id) do update set kind=excluded.kind,title=excluded.title,body=excluded.body,branch_id=excluded.branch_id,district=excluded.district,event_date=excluded.event_date,published=excluded.published,poster_path=excluded.poster_path,poster_original_path=excluded.poster_original_path,poster_crop=excluded.poster_crop,updated_at=clock_timestamp() returning * into saved;
 perform public.occci_log(null,coalesce(branch,current_row.branch_id),'Content changed',case when current_row.id is null then null else to_jsonb(current_row) end,to_jsonb(saved),reason);
 return saved.id;
end;$$;
revoke all on function public.occci_can_manage_content(text,smallint),public.occci_can_read_poster(text),public.occci_save_content_poster(text,jsonb,text,text,jsonb,text) from public,anon;
grant execute on function public.occci_can_manage_content(text,smallint),public.occci_can_read_poster(text),public.occci_save_content_poster(text,jsonb,text,text,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('023_announcement_posters') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 023. OCCCI Huddle authorization, session codes and scoped collaboration.
begin;
create table if not exists public.occci_huddle_sessions(
 id uuid primary key default gen_random_uuid(),host_id uuid not null references auth.users(id),title text not null check(length(title) between 1 and 150),
 join_code text not null unique,branch_id text references public.occci_branches(id),district smallint check(district between 1 and 6),
 status text not null default 'Active' check(status in ('Active','Ended')),mic_locked boolean not null default false,
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '12 hours',ended_at timestamptz,
 check(branch_id is null or district is null));
create table if not exists public.occci_huddle_attendees(
 session_id uuid references public.occci_huddle_sessions(id) on delete cascade,user_id uuid references auth.users(id) on delete cascade,
 mic_locked boolean not null default false,joined_at timestamptz not null default now(),left_at timestamptz,primary key(session_id,user_id));
create table if not exists public.occci_huddle_messages(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 sender_id uuid not null references auth.users(id),body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default now());
create table if not exists public.occci_huddle_cards(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 sender_id uuid not null references auth.users(id),branch_id text references public.occci_branches(id),district smallint check(district between 1 and 6),
 summary jsonb not null,created_at timestamptz not null default now());
create table if not exists public.occci_huddle_attempts(user_id uuid primary key references auth.users(id) on delete cascade,started_at timestamptz not null default now(),attempts integer not null default 0);
create index if not exists occci_huddle_host_idx on public.occci_huddle_sessions(host_id,created_at desc);
create index if not exists occci_huddle_messages_session_idx on public.occci_huddle_messages(session_id,created_at desc);
alter table public.occci_huddle_sessions enable row level security;
alter table public.occci_huddle_attendees enable row level security;
alter table public.occci_huddle_messages enable row level security;
alter table public.occci_huddle_cards enable row level security;
alter table public.occci_huddle_attempts enable row level security;
revoke all on public.occci_huddle_sessions,public.occci_huddle_attendees,public.occci_huddle_messages,public.occci_huddle_cards,public.occci_huddle_attempts from public,anon,authenticated;

create or replace function public.occci_huddle_valid(u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p where p.id=u and p.archived_at is null and p.onboarding_complete and
 ((p.registration_kind='Member' and p.membership_status='Active') or (p.registration_kind='Staff' and exists(select 1 from public.occci_staff_assignments s where s.user_id=u and s.role in ('Admin','DM','BM','Staff','BC')))));
$$;
create or replace function public.occci_huddle_scope(u uuid,branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(u) and ((branch is null and dist is null) or
 exists(select 1 from public.occci_staff_assignments s where s.user_id=u and (s.role='Admin' or
 (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or
 (s.role in ('BM','Staff','BC') and (s.branch_id=branch or (branch is null and exists(select 1 from public.occci_branches b where b.id=s.branch_id and b.district=dist)))))) or
 exists(select 1 from public.occci_profiles p where p.id=u and p.registration_kind='Member' and (p.branch_id=branch or (branch is null and exists(select 1 from public.occci_branches b where b.id=p.branch_id and b.district=dist)))));
$$;
create or replace function public.occci_huddle_host_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and
 (s.role='Admin' or (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or (s.role in ('BM','Staff','BC') and branch=s.branch_id)));
$$;
create or replace function public.occci_huddle_member(sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_huddle_sessions h where h.id=sid and public.occci_huddle_scope(auth.uid(),h.branch_id,h.district) and
 (h.host_id=auth.uid() or exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid())));
$$;
create or replace function public.occci_huddle_data_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and
 (s.role='Admin' or (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or (s.role in ('BM','Staff','BC') and branch=s.branch_id)));
$$;
-- All writes and reads below run through authenticated RPCs, never direct table mutations.
create or replace function public.occci_huddle_create(label text,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 if not public.occci_huddle_host_scope(branch,dist) then raise exception 'Your position cannot host this operating unit.' using errcode='42501'; end if;
 if length(trim(label)) not between 1 and 150 or (branch is not null and not exists(select 1 from public.occci_branches b where b.id=branch and b.active)) or (dist is not null and dist not between 1 and 6) or (branch is not null and dist is not null) then raise exception 'Choose a valid title and operating unit.'; end if;
 insert into public.occci_huddle_sessions(host_id,title,join_code,branch_id,district) values(auth.uid(),trim(label),upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),branch,dist) returning * into h;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid());
 perform public.occci_log(auth.uid(),h.branch_id,'Huddle created',null,jsonb_build_object('session_id',h.id,'title',h.title,'district',h.district),'Created OCCCI Huddle');
 return to_jsonb(h);
end;$$;
create or replace function public.occci_huddle_join(code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;n integer;
begin
 if not public.occci_huddle_valid(auth.uid()) then raise exception 'An active OCCCI account is required.' using errcode='42501';end if;
 insert into public.occci_huddle_attempts(user_id,attempts) values(auth.uid(),1) on conflict(user_id) do update set
 attempts=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then 1 else public.occci_huddle_attempts.attempts+1 end,
 started_at=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then now() else public.occci_huddle_attempts.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('error','Too many join attempts. Wait one minute.');end if;
 select * into h from public.occci_huddle_sessions where join_code=upper(regexp_replace(code,'[^a-zA-Z0-9]','','g')) and status='Active' and expires_at>now() for update;
 if h.id is null or not public.occci_huddle_scope(auth.uid(),h.branch_id,h.district) then return jsonb_build_object('error','This code is invalid, expired or outside your assigned unit.');end if;
 if (select count(*) from public.occci_huddle_attendees where session_id=h.id and left_at is null)>=100 and not exists(select 1 from public.occci_huddle_attendees where session_id=h.id and user_id=auth.uid() and left_at is null) then return jsonb_build_object('error','This Huddle has reached its attendee capacity.');end if;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid()) on conflict(session_id,user_id) do update set left_at=null,joined_at=now();
 perform public.occci_log(auth.uid(),h.branch_id,'Huddle joined',null,jsonb_build_object('session_id',h.id,'district',h.district),'Joined OCCCI Huddle');return to_jsonb(h);
end;$$;
create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select h.* from public.occci_huddle_sessions h where public.occci_huddle_member(h.id) order by h.created_at desc limit 30)x;
$$;
create or replace function public.occci_huddle_context(sid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare h public.occci_huddle_sessions;people jsonb;messages jsonb;cards jsonb;host boolean;
begin
 select * into h from public.occci_huddle_sessions where id=sid;
 if h.id is null or not public.occci_huddle_member(sid) or h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended or your access changed.' using errcode='42501';end if;
 host:=h.host_id=auth.uid() and public.occci_huddle_host_scope(h.branch_id,h.district);
 select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'name',p.full_name,'role',coalesce(s.role,'Member'),'mic_locked',a.mic_locked or (h.mic_locked and a.user_id<>h.host_id),'blocked',not public.occci_huddle_scope(a.user_id,h.branch_id,h.district))),'[]'::jsonb) into people from public.occci_huddle_attendees a join public.occci_profiles p on p.id=a.user_id left join public.occci_staff_assignments s on s.user_id=a.user_id where a.session_id=sid and a.left_at is null;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into messages from (select m.id,m.sender_id,m.body,m.created_at,p.full_name sender_name from public.occci_huddle_messages m join public.occci_profiles p on p.id=m.sender_id where m.session_id=sid order by m.created_at desc limit 60)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into cards from (select c.id,c.sender_id,c.summary,c.created_at from public.occci_huddle_cards c where c.session_id=sid and public.occci_huddle_data_scope(c.branch_id,c.district) order by c.created_at desc limit 10)x;
 return jsonb_build_object('session',to_jsonb(h),'identity',auth.uid(),'name',(select full_name from public.occci_profiles where id=auth.uid()),'role',public.occci_role(),'is_host',host,'participants',people,'messages',messages,'cards',cards,'mic_locked',h.host_id<>auth.uid() and (h.mic_locked or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.mic_locked)));
end;$$;
create or replace function public.occci_huddle_command(sid uuid,command text,target uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 select * into h from public.occci_huddle_sessions where id=sid for update;
 if h.id is null or not public.occci_huddle_member(sid) then raise exception 'Huddle access denied.' using errcode='42501';end if;
 if command='leave' then update public.occci_huddle_attendees set left_at=now() where session_id=sid and user_id=auth.uid();
 else
 if h.host_id<>auth.uid() or not public.occci_huddle_host_scope(h.branch_id,h.district) then raise exception 'Only this Huddle host can manage attendees.' using errcode='42501';end if;
 if command='end' then update public.occci_huddle_sessions set status='Ended',ended_at=now() where id=sid;
 elsif h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended.';
 elsif command in ('mute_all','allow_all') then update public.occci_huddle_sessions set mic_locked=command='mute_all' where id=sid;update public.occci_huddle_attendees set mic_locked=command='mute_all' where session_id=sid and user_id<>h.host_id;
 elsif command in ('mute','allow') then
 if target is null or target=h.host_id or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an attendee in this Huddle.';end if;
 if command='allow' and h.mic_locked then raise exception 'Allow all microphones before enabling an individual attendee.';end if;
 update public.occci_huddle_attendees set mic_locked=command='mute' where session_id=sid and user_id=target;
 else raise exception 'Invalid Huddle command.';end if;end if;
 perform public.occci_log(auth.uid(),h.branch_id,case command when 'mute_all' then 'Huddle attendees muted' when 'allow_all' then 'Huddle microphones allowed' when 'mute' then 'Huddle attendee muted' when 'allow' then 'Huddle microphone allowed' when 'end' then 'Huddle ended' else 'Huddle left' end,null,jsonb_build_object('session_id',sid,'target',target,'district',h.district),'OCCCI Huddle activity');
 return jsonb_build_object('ok',true);
end;$$;
create or replace function public.occci_huddle_chat(sid uuid,message text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.occci_huddle_context(sid);
 if length(trim(message)) not between 1 and 2000 then raise exception 'Message must contain 1 to 2000 characters.';end if;
 insert into public.occci_huddle_messages(session_id,sender_id,body) values(sid,auth.uid(),trim(message));
 perform public.occci_log(auth.uid(),(select branch_id from public.occci_huddle_sessions where id=sid),'Huddle message sent',null,jsonb_build_object('session_id',sid),'Sent a session chat message');
end;$$;
create or replace function public.occci_huddle_summary(sid uuid,branch text default null,dist smallint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform public.occci_huddle_context(sid);
 if not public.occci_huddle_data_scope(branch,dist) or (branch is not null and not exists(select 1 from public.occci_branches b where b.id=branch and b.active)) or (dist is not null and dist not between 1 and 6) or (branch is not null and dist is not null) or (branch is null and dist is null) then raise exception 'Choose a district or branch within your assignment.' using errcode='42501';end if;
 select jsonb_build_object('unit',coalesce((select name||' Branch' from public.occci_branches where id=branch),'District '||dist),'branch_id',branch,'district',coalesce(dist,(select district from public.occci_branches where id=branch)),
 'members',count(*),'verified_records',count(f.member_id),'savings',coalesce(sum(f.savings),0),'share_capital',coalesce(sum(f.share_capital),0),'loans',coalesce(sum(f.loan_balance),0),'active_loans',count(*) filter(where f.loan_balance>0),'as_of',now()) into result
 from public.occci_profiles p join public.occci_branches b on b.id=p.branch_id left join public.occci_financials f on f.member_id=p.id
 where p.archived_at is null and p.registration_kind='Member' and p.membership_status='Active' and not exists(select 1 from public.occci_staff_assignments s where s.user_id=p.id) and (p.branch_id=branch or (branch is null and b.district=dist));
 return result;
end;$$;
create or replace function public.occci_huddle_share(sid uuid,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare data jsonb;card public.occci_huddle_cards;
begin
 data:=public.occci_huddle_summary(sid,branch,dist);
 insert into public.occci_huddle_cards(session_id,sender_id,branch_id,district,summary) values(sid,auth.uid(),branch,dist,data) returning * into card;
 perform public.occci_log(auth.uid(),branch,'Huddle data shared',null,jsonb_build_object('session_id',sid,'card_id',card.id,'district',dist),'Shared verified operating unit summary');return to_jsonb(card);
end;$$;
revoke all on function public.occci_huddle_valid(uuid),public.occci_huddle_scope(uuid,text,smallint),public.occci_huddle_host_scope(text,smallint),public.occci_huddle_member(uuid),public.occci_huddle_data_scope(text,smallint) from public,anon,authenticated;
revoke all on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text),public.occci_huddle_list(),public.occci_huddle_context(uuid),public.occci_huddle_command(uuid,text,uuid),public.occci_huddle_chat(uuid,text),public.occci_huddle_summary(uuid,text,smallint),public.occci_huddle_share(uuid,text,smallint) from public,anon;
grant execute on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text),public.occci_huddle_list(),public.occci_huddle_context(uuid),public.occci_huddle_command(uuid,text,uuid),public.occci_huddle_chat(uuid,text),public.occci_huddle_summary(uuid,text,smallint),public.occci_huddle_share(uuid,text,smallint) to authenticated;
insert into public.occci_schema_versions(version) values('024_occci_huddle') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 024. Open code-based meetings; financial data keeps its existing scope.
begin;
create index if not exists occci_huddle_active_idx on public.occci_huddle_sessions(status,expires_at,created_at desc);

create or replace function public.occci_huddle_scope(u uuid,branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(u);
$$;
create or replace function public.occci_huddle_host_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and s.role in ('Admin','DM','BM','Staff','BC'));
$$;
create or replace function public.occci_huddle_member(sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_huddle_sessions h where h.id=sid and
 (h.host_id=auth.uid() or exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid() and a.left_at is null)));
$$;

-- Keep optional legacy arguments so older clients can create open sessions too.
-- No operating-unit values supplied by a client restrict conference membership.
create or replace function public.occci_huddle_create(label text,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 if not public.occci_huddle_host_scope(null,null) then raise exception 'Only assigned OCCCI staff can create a Huddle.' using errcode='42501';end if;
 if label is null or length(trim(label)) not between 1 and 150 then raise exception 'Enter a session title up to 150 characters.';end if;
 insert into public.occci_huddle_sessions(host_id,title,join_code) values(auth.uid(),trim(label),upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))) returning * into h;
 -- Creation does not count the host as an attendee or start their media.
 perform public.occci_log(auth.uid(),null,'Huddle created',null,jsonb_build_object('session_id',h.id,'title',h.title),'Created OCCCI Huddle');
 return to_jsonb(h);
end;$$;

-- A default second argument keeps previous code-only invitations compatible.
-- Remove the old overload to avoid ambiguous PostgREST RPC resolution.
drop function if exists public.occci_huddle_join(text);
create or replace function public.occci_huddle_join(code text,expected_session uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;n integer;
begin
 if not public.occci_huddle_valid(auth.uid()) then raise exception 'An active OCCCI account is required.' using errcode='42501';end if;
 insert into public.occci_huddle_attempts(user_id,attempts) values(auth.uid(),1) on conflict(user_id) do update set
 attempts=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then 1 else public.occci_huddle_attempts.attempts+1 end,
 started_at=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then now() else public.occci_huddle_attempts.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('error','Too many join attempts. Wait one minute.');end if;
 select * into h from public.occci_huddle_sessions where join_code=upper(regexp_replace(code,'[^a-zA-Z0-9]','','g')) and status='Active' and expires_at>now() for update;
 if h.id is null or (expected_session is not null and h.id<>expected_session) then return jsonb_build_object('error','This code is invalid for the selected session, expired or ended.');end if;
 if (select count(*) from public.occci_huddle_attendees where session_id=h.id and left_at is null)>=100 and not exists(select 1 from public.occci_huddle_attendees where session_id=h.id and user_id=auth.uid() and left_at is null) then return jsonb_build_object('error','This Huddle has reached its attendee capacity.');end if;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid()) on conflict(session_id,user_id) do update set left_at=null,joined_at=now();
 perform public.occci_log(auth.uid(),null,'Huddle joined',null,jsonb_build_object('session_id',h.id),'Joined OCCCI Huddle');
 -- The code is already known by the joiner; subsequent reads expose it only to the host.
 return to_jsonb(h)-'join_code';
end;$$;

create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) from (
  select h.id,h.created_at,jsonb_build_object('id',h.id,'title',h.title,'host_id',h.host_id,'host_name',p.full_name,'status',h.status,
   'created_at',h.created_at,'expires_at',h.expires_at,'is_host',h.host_id=auth.uid(),
   'attendees',(select count(*) from public.occci_huddle_attendees a where a.session_id=h.id and a.left_at is null)) ||
   case when h.host_id=auth.uid() then jsonb_build_object('join_code',h.join_code) else '{}'::jsonb end item
  from public.occci_huddle_sessions h join public.occci_profiles p on p.id=h.host_id
  where public.occci_huddle_valid(auth.uid()) and h.status='Active' and h.expires_at>now() and public.occci_huddle_valid(h.host_id)
   and exists(select 1 from public.occci_staff_assignments s where s.user_id=h.host_id and s.role in ('Admin','DM','BM','Staff','BC'))
 )x;
$$;

create or replace function public.occci_huddle_context(sid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare h public.occci_huddle_sessions;people jsonb;messages jsonb;cards jsonb;host boolean;
begin
 select * into h from public.occci_huddle_sessions where id=sid;
 if h.id is null or not public.occci_huddle_member(sid) or h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended or your access changed.' using errcode='42501';end if;
 host:=h.host_id=auth.uid() and public.occci_huddle_host_scope(null,null);
 select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'name',p.full_name,'role',coalesce(s.role,'Member'),'mic_locked',a.mic_locked or (h.mic_locked and a.user_id<>h.host_id),'blocked',not public.occci_huddle_valid(a.user_id))),'[]'::jsonb) into people from public.occci_huddle_attendees a join public.occci_profiles p on p.id=a.user_id left join public.occci_staff_assignments s on s.user_id=a.user_id where a.session_id=sid and a.left_at is null;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into messages from (select m.id,m.sender_id,m.body,m.created_at,p.full_name sender_name from public.occci_huddle_messages m join public.occci_profiles p on p.id=m.sender_id where m.session_id=sid order by m.created_at desc limit 60)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into cards from (select c.id,c.sender_id,c.summary,c.created_at from public.occci_huddle_cards c where c.session_id=sid and public.occci_huddle_data_scope(c.branch_id,c.district) order by c.created_at desc limit 10)x;
 return jsonb_build_object('session',case when host then to_jsonb(h) else to_jsonb(h)-'join_code' end,'identity',auth.uid(),'name',(select full_name from public.occci_profiles where id=auth.uid()),'role',public.occci_role(),'is_host',host,'participants',people,'messages',messages,'cards',cards,'mic_locked',h.host_id<>auth.uid() and (h.mic_locked or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.mic_locked)));
end;$$;

-- occci_huddle_data_scope, summary and share are intentionally unchanged.
revoke all on function public.occci_huddle_scope(uuid,text,smallint),public.occci_huddle_host_scope(text,smallint),public.occci_huddle_member(uuid) from public,anon,authenticated;
revoke all on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text,uuid),public.occci_huddle_list(),public.occci_huddle_context(uuid) from public,anon;
grant execute on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text,uuid),public.occci_huddle_list(),public.occci_huddle_context(uuid) to authenticated;
insert into public.occci_schema_versions(version) values('025_occci_huddle_sessions') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 025. Recognize approved positions independently of signup category.
begin;
create or replace function public.occci_huddle_valid(u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p where p.id=u and p.archived_at is null and p.onboarding_complete and
 (exists(select 1 from public.occci_staff_assignments s where s.user_id=p.id and s.role in ('Admin','DM','BM','Staff','BC')) or
  (p.registration_kind='Member' and p.membership_status='Active')));
$$;

-- Current authenticated assignment is authoritative; never accept a client-supplied role.
-- A readiness check prevents a successful legacy list RPC from enabling an incompatible form.
create or replace function public.occci_huddle_permissions() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('role',public.occci_role(),'can_host',public.occci_huddle_host_scope(null,null),
  'can_join',public.occci_huddle_valid(auth.uid()),'database_ready',
  exists(select 1 from public.occci_schema_versions where version='025_occci_huddle_sessions') and
  exists(select 1 from public.occci_schema_versions where version='026_occci_huddle_staff_permissions'));
$$;
revoke all on function public.occci_huddle_valid(uuid) from public,anon,authenticated;
revoke all on function public.occci_huddle_permissions() from public,anon;
grant execute on function public.occci_huddle_permissions() to authenticated;
insert into public.occci_schema_versions(version) values('026_occci_huddle_staff_permissions') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 026. Dedicated Huddle stage, scoped reports and host drawing permissions.
begin;
alter table public.occci_huddle_attendees add column if not exists annotation_allowed boolean not null default false;
alter table public.occci_huddle_sessions add column if not exists mic_default_locked boolean not null default false;
create or replace function public.occci_huddle_attendee_defaults() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' or (new.left_at is null and (old.left_at is not null or new.joined_at is distinct from old.joined_at)) then
  new.mic_locked:=coalesce((select (h.mic_default_locked or h.mic_locked) and new.user_id<>h.host_id from public.occci_huddle_sessions h where h.id=new.session_id),false);
  new.annotation_allowed:=false;
 end if;
 return new;
end;$$;
revoke all on function public.occci_huddle_attendee_defaults() from public,anon,authenticated;
drop trigger if exists occci_huddle_attendee_defaults on public.occci_huddle_attendees;
create trigger occci_huddle_attendee_defaults before insert or update on public.occci_huddle_attendees for each row execute function public.occci_huddle_attendee_defaults();

create table if not exists public.occci_huddle_stage(
 session_id uuid primary key references public.occci_huddle_sessions(id) on delete cascade,
 kind text not null default 'camera' check(kind in ('camera','screen','report')),
 target uuid references auth.users(id),report_id uuid,report_source text check(report_source in ('work','register')),
 revision uuid not null default gen_random_uuid(),recording boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.occci_huddle_stage add column if not exists record_expires_at timestamptz;
create table if not exists public.occci_huddle_strokes(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 revision uuid not null,sender_id uuid not null references auth.users(id),tool text not null check(tool in ('pen','arrow')),
 color text not null check(color in ('red','cyan')),points jsonb not null,created_at timestamptz not null default now()
);
create index if not exists occci_huddle_strokes_stage_idx on public.occci_huddle_strokes(session_id,revision,created_at);
alter table public.occci_huddle_stage enable row level security;
alter table public.occci_huddle_strokes enable row level security;
revoke all on public.occci_huddle_stage,public.occci_huddle_strokes from public,anon,authenticated;
insert into public.occci_report_types(id,category,name,guidance)
values('special-project','District','Special project report','Record a district or branch project, results, approved budget and supporting documents.')
on conflict(id) do nothing;

create or replace function public.occci_huddle_report(sid uuid,rid uuid,source text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.occci_reports;w public.occci_work_reports;
begin
 if not public.occci_huddle_member(sid) then raise exception 'Join this Huddle first.' using errcode='42501';end if;
 if source='work' then
  select * into w from public.occci_work_reports where id=rid and status='Approved' and frequency='Monthly';
  if w.id is null or not public.occci_huddle_data_scope(w.branch_id,w.district) or not public.occci_work_access(w.created_by,w.branch_id) then raise exception 'This report is outside your authorized units.' using errcode='42501';end if;
  return jsonb_build_object('id',w.id,'source','work','title',w.title,'branch_id',w.branch_id,'district',w.district,'period_start',w.period_start,'period_end',w.period_end,'summary',w.summary,'metrics',w.metrics,'status',w.status,'updated_at',w.updated_at);
 elsif source='register' then
  select * into r from public.occci_reports where id=rid and archived_at is null and status in ('Approved','Filed') and type_id='special-project';
  if r.id is null or not public.occci_huddle_data_scope(r.branch_id,r.district) or not public.occci_report_access(r.district,r.branch_id,false) then raise exception 'This report is outside your authorized units.' using errcode='42501';end if;
  return jsonb_build_object('id',r.id,'source','register','title',r.title,'branch_id',r.branch_id,'district',r.district,'period_start',r.period_start,'period_end',r.period_end,'summary',r.summary,'metrics',r.details,'status',r.status,'updated_at',r.updated_at);
 end if;
 raise exception 'Choose a valid report source.';
end;$$;

drop function if exists public.occci_huddle_reports(uuid,text,smallint,date,text);
create or replace function public.occci_huddle_reports(sid uuid,branch text default null,dist smallint default null,month date default current_date,kind text default 'monthly',page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare first_day date:=date_trunc('month',month)::date;last_day date:=(date_trunc('month',month)+interval '1 month')::date;result jsonb;
begin
 perform public.occci_huddle_context(sid);
 if not public.occci_huddle_data_scope(branch,dist) then raise exception 'Choose an authorized operating unit.' using errcode='42501';end if;
 if page is null or page not between 0 and 9999 then raise exception 'Choose a valid report page.';end if;
 if month is null or kind is null or kind not in ('monthly','project') then raise exception 'Choose a month and report type.';end if;
 if kind='monthly' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.branch_id,x.title,x.id),'[]'::jsonb) into result from (
   select w.id,'work'::text source,w.title,w.branch_id,w.district,w.period_start,w.period_end,w.status
   from public.occci_work_reports w where w.status='Approved' and w.frequency='Monthly'
   and w.period_start>=first_day and w.period_start<last_day
   and (branch is null or w.branch_id=branch) and (dist is null or w.district=dist)
   and public.occci_huddle_data_scope(w.branch_id,w.district) and public.occci_work_access(w.created_by,w.branch_id)
   order by w.branch_id,w.title,w.id limit 101 offset page*100
  )x;
 else
  select coalesce(jsonb_agg(to_jsonb(x) order by x.district,x.branch_id,x.title,x.id),'[]'::jsonb) into result from (
   select r.id,'register'::text source,r.title,r.branch_id,r.district,r.period_start,r.period_end,r.status
   from public.occci_reports r where r.archived_at is null and r.status in ('Approved','Filed') and r.type_id='special-project'
   and r.period_start<last_day and r.period_end>=first_day
   and (branch is null or r.branch_id=branch) and (dist is null or r.district=dist)
   and public.occci_huddle_data_scope(r.branch_id,r.district) and public.occci_report_access(r.district,r.branch_id,false)
   order by r.district,r.branch_id,r.title,r.id limit 101 offset page*100
  )x;
 end if;
 return result;
end;$$;

-- Preserve the established session/chat/mic authorization and extend only its response.
do $$ begin
 if to_regprocedure('public.occci_huddle_context_base_027(uuid)') is null then
  alter function public.occci_huddle_context(uuid) rename to occci_huddle_context_base_027;
 end if;
end $$;
revoke all on function public.occci_huddle_context_base_027(uuid) from public,anon,authenticated;
create or replace function public.occci_huddle_context(sid uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;stage public.occci_huddle_stage;presentation jsonb;report jsonb;strokes jsonb:='[]';visible boolean:=true;
begin
 result:=public.occci_huddle_context_base_027(sid);
 select * into stage from public.occci_huddle_stage where session_id=sid;
 if stage.session_id is not null then
  if stage.kind='report' then
   begin report:=public.occci_huddle_report(sid,stage.report_id,stage.report_source);
   exception when insufficient_privilege then visible:=false;
   end;
  end if;
  presentation:=jsonb_build_object('kind',stage.kind,'target',stage.target,'revision',stage.revision,'restricted',not visible)||
   case when visible and report is not null then jsonb_build_object('report',report) else '{}'::jsonb end;
  if visible then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]'::jsonb) into strokes from (
    select id,sender_id,tool,color,points,created_at from public.occci_huddle_strokes where session_id=sid and revision=stage.revision order by created_at desc,id limit 100
   )x;
  end if;
 end if;
 return result||jsonb_build_object('studio_ready',true,'presentation',presentation,'strokes',strokes,'recording',coalesce(stage.recording and stage.record_expires_at>now(),false),
  'annotation_allowed',(result->>'is_host')::boolean or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.left_at is null and a.annotation_allowed),
  'participants',(select coalesce(jsonb_agg(p||jsonb_build_object('annotation_allowed',coalesce(a.annotation_allowed,false))),'[]'::jsonb)
    from jsonb_array_elements(result->'participants') p left join public.occci_huddle_attendees a on a.session_id=sid and a.user_id=(p->>'user_id')::uuid));
end;$$;

create or replace function public.occci_huddle_studio(sid uuid,command text,target uuid default null,values_json jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;stage public.occci_huddle_stage;rid uuid;source text;point jsonb;allowed boolean;host boolean;
begin
 -- Serialize stage, grants and drawings so stale strokes cannot cross presentations.
 perform 1 from public.occci_huddle_sessions where id=sid for update;
 ctx:=public.occci_huddle_context(sid);host:=(ctx->>'is_host')::boolean;
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then raise exception 'Join this Huddle first.' using errcode='42501';end if;
 if command in ('grant_pen','revoke_pen','camera','screen','record_start','record_stop','record_ping','clear') and not host then raise exception 'Only the host can control the stage and drawing permissions.' using errcode='42501';end if;
 insert into public.occci_huddle_stage(session_id,target) select sid,host_id from public.occci_huddle_sessions where id=sid on conflict do nothing;
 select * into stage from public.occci_huddle_stage where session_id=sid;
 if command in ('grant_pen','revoke_pen') then
  if target is null or not public.occci_huddle_valid(target) or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an active attendee.';end if;
  update public.occci_huddle_attendees set annotation_allowed=command='grant_pen' where session_id=sid and user_id=target;
 elsif command in ('camera','screen') then
  if target is null or not public.occci_huddle_valid(target) or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an active attendee.';end if;
  update public.occci_huddle_stage set kind=command,target=occci_huddle_studio.target,report_id=null,report_source=null,revision=gen_random_uuid(),updated_at=now() where session_id=sid;
  delete from public.occci_huddle_strokes where session_id=sid;
 elsif command='report' then
  -- Sharing does not expand report visibility: each viewer is checked separately.
  rid:=(values_json->>'report_id')::uuid;source:=values_json->>'source';
  perform public.occci_huddle_report(sid,rid,source);
  update public.occci_huddle_stage set kind='report',target=auth.uid(),report_id=rid,report_source=source,revision=gen_random_uuid(),updated_at=now() where session_id=sid;
  delete from public.occci_huddle_strokes where session_id=sid;
 elsif command in ('record_start','record_stop','record_ping') then
  if command='record_ping' and not stage.recording then raise exception 'Recording has stopped.';end if;
  update public.occci_huddle_stage set recording=command<>'record_stop',record_expires_at=case when command='record_stop' then null else now()+interval '45 seconds' end,updated_at=now() where session_id=sid;
 elsif command='clear' then
  delete from public.occci_huddle_strokes where session_id=sid;
  update public.occci_huddle_stage set revision=gen_random_uuid(),updated_at=now() where session_id=sid;
 elsif command='stroke' then
  allowed:=host or exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null and annotation_allowed);
  if not allowed or coalesce((ctx->'presentation'->>'restricted')::boolean,false) then raise exception 'The host must allow drawing on this presentation.' using errcode='42501';end if;
  if (values_json->>'revision')::uuid is distinct from stage.revision then raise exception 'The presentation changed. Draw again on the current stage.';end if;
  if values_json->>'tool' not in ('pen','arrow') or values_json->>'color' not in ('red','cyan') or jsonb_typeof(values_json->'points') is distinct from 'array' or jsonb_array_length(values_json->'points') not between 2 and 120 then raise exception 'Invalid drawing.';end if;
  for point in select value from jsonb_array_elements(values_json->'points') loop
   if jsonb_typeof(point) is distinct from 'array' or jsonb_array_length(point)<>2 then raise exception 'Invalid drawing coordinate.';end if;
   if jsonb_typeof(point->0)<>'number' or jsonb_typeof(point->1)<>'number' or (point->>0)::numeric not between 0 and 1 or (point->>1)::numeric not between 0 and 1 then raise exception 'Drawing coordinates must be inside the stage.';end if;
  end loop;
  if (select count(*) from public.occci_huddle_strokes where session_id=sid and sender_id=auth.uid() and created_at>now()-interval '1 minute')>=60 then raise exception 'Please slow down drawing.';end if;
  if (select count(*) from public.occci_huddle_strokes where session_id=sid)>=100 then raise exception 'The drawing board is full. Ask the host to clear it.';end if;
  insert into public.occci_huddle_strokes(session_id,revision,sender_id,tool,color,points) values(sid,stage.revision,auth.uid(),values_json->>'tool',values_json->>'color',values_json->'points');
 else raise exception 'Invalid stage command.';end if;
 if command not in ('stroke','record_ping') then perform public.occci_log(auth.uid(),null,'Huddle '||replace(command,'_',' '),null,jsonb_build_object('session_id',sid,'target',target),'OCCCI Huddle stage activity');end if;
 return public.occci_huddle_context(sid);
end;$$;

create or replace function public.occci_huddle_resume(sid uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;
begin
 ctx:=public.occci_huddle_context(sid);
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then raise exception 'Enter the session code to join first.' using errcode='42501';end if;
 perform public.occci_log(auth.uid(),null,'Huddle resumed',null,jsonb_build_object('session_id',sid),'Resumed an existing active session');
 return (ctx->'session')-'join_code';
end;$$;

-- Returning to Connect keeps attendance active. Explicit Leave invalidates code-free resume.
create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) from (
  select h.id,h.created_at,jsonb_build_object('id',h.id,'title',h.title,'host_id',h.host_id,'host_name',p.full_name,'status',h.status,
   'created_at',h.created_at,'expires_at',h.expires_at,'is_host',h.host_id=auth.uid(),
   'can_resume',exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid() and a.left_at is null),
   'attendees',(select count(*) from public.occci_huddle_attendees a where a.session_id=h.id and a.left_at is null))||
   case when h.host_id=auth.uid() then jsonb_build_object('join_code',h.join_code) else '{}'::jsonb end item
  from public.occci_huddle_sessions h join public.occci_profiles p on p.id=h.host_id
  where public.occci_huddle_valid(auth.uid()) and h.status='Active' and h.expires_at>now() and public.occci_huddle_valid(h.host_id)
   and exists(select 1 from public.occci_staff_assignments s where s.user_id=h.host_id and s.role in ('Admin','DM','BM','Staff','BC'))
 )x;
$$;
-- Let the host allow one attendee after Mute all, without unlocking everybody.
create or replace function public.occci_huddle_command(sid uuid,command text,target uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 select * into h from public.occci_huddle_sessions where id=sid for update;
 if h.id is null or not public.occci_huddle_member(sid) then raise exception 'Huddle access denied.' using errcode='42501';end if;
 if command='leave' then
  update public.occci_huddle_attendees set left_at=now(),annotation_allowed=false where session_id=sid and user_id=auth.uid();
  if h.host_id=auth.uid() then update public.occci_huddle_stage set recording=false where session_id=sid;end if;
 else
  if h.host_id<>auth.uid() or not public.occci_huddle_host_scope(null,null) then raise exception 'Only this Huddle host can manage attendees.' using errcode='42501';end if;
  if command='end' then
   update public.occci_huddle_sessions set status='Ended',ended_at=now() where id=sid;
   update public.occci_huddle_stage set recording=false where session_id=sid;
  elsif h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended.';
  elsif command in ('mute_all','allow_all') then
   update public.occci_huddle_sessions set mic_locked=false,mic_default_locked=command='mute_all' where id=sid;
   update public.occci_huddle_attendees set mic_locked=command='mute_all' where session_id=sid and user_id<>h.host_id;
  elsif command in ('mute','allow') then
   if target is null or target=h.host_id or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an attendee in this Huddle.';end if;
   if h.mic_locked then
    update public.occci_huddle_attendees set mic_locked=true where session_id=sid and user_id<>h.host_id;
    update public.occci_huddle_sessions set mic_locked=false,mic_default_locked=true where id=sid;
   end if;
   update public.occci_huddle_attendees set mic_locked=command='mute' where session_id=sid and user_id=target;
  else raise exception 'Invalid Huddle command.';end if;
 end if;
 perform public.occci_log(auth.uid(),null,'Huddle '||replace(command,'_',' '),null,jsonb_build_object('session_id',sid,'target',target),'OCCCI Huddle activity');
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.occci_huddle_report(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.occci_huddle_reports(uuid,text,smallint,date,text,integer),public.occci_huddle_studio(uuid,text,uuid,jsonb),public.occci_huddle_resume(uuid),public.occci_huddle_context(uuid),public.occci_huddle_list(),public.occci_huddle_command(uuid,text,uuid) from public,anon;
grant execute on function public.occci_huddle_reports(uuid,text,smallint,date,text,integer),public.occci_huddle_studio(uuid,text,uuid,jsonb),public.occci_huddle_resume(uuid),public.occci_huddle_context(uuid),public.occci_huddle_list(),public.occci_huddle_command(uuid,text,uuid) to authenticated;
insert into public.occci_schema_versions(version) values('027_occci_huddle_studio') on conflict do nothing;
notify pgrst,'reload schema';
commit;

-- Apply after 026 (or 027 if using Huddle Studio). Remove shared snapshots without modifying financial records.
begin;
create or replace function public.occci_huddle_delete_card(sid uuid,cid uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;card public.occci_huddle_cards;
begin
 ctx:=public.occci_huddle_context(sid);
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then
  raise exception 'Join this Huddle first.' using errcode='42501';
 end if;
 select * into card from public.occci_huddle_cards where id=cid and session_id=sid for update;
 if card.id is null then return jsonb_build_object('ok',true);end if;
 if not public.occci_huddle_data_scope(card.branch_id,card.district) or
  (card.sender_id<>auth.uid() and not (ctx->>'is_host')::boolean) then
  raise exception 'You can delete your own snapshots, or manage visible snapshots as the host.' using errcode='42501';
 end if;
 delete from public.occci_huddle_cards where id=cid and session_id=sid;
 perform public.occci_log(auth.uid(),card.branch_id,'Huddle snapshot deleted',null,
  jsonb_build_object('session_id',sid,'snapshot_id',cid,'district',card.district),'Removed a shared Huddle snapshot; source financial records were not changed');
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.occci_huddle_delete_card(uuid,uuid) from public,anon;
grant execute on function public.occci_huddle_delete_card(uuid,uuid) to authenticated;
insert into public.occci_schema_versions(version) values('028_occci_huddle_snapshot_delete') on conflict do nothing;
notify pgrst,'reload schema';
commit;
