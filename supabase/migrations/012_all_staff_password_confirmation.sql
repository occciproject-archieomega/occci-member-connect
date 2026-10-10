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
