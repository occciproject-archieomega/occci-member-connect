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
