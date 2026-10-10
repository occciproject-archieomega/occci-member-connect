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
