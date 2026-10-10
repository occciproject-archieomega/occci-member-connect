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
