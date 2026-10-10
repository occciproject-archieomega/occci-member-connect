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
