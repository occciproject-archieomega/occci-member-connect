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
