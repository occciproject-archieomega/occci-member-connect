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
