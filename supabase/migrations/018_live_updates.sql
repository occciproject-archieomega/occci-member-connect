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
