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
