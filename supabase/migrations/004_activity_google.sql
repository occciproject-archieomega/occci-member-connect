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
