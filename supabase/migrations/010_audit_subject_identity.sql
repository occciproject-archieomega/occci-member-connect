-- Apply after 009. Preserve the affected account independently of the acting user.
begin;
alter table public.occci_audit add column if not exists subject_name text;
alter table public.occci_audit add column if not exists subject_employee_id text;
alter table public.occci_audit add column if not exists subject_role text;

-- Recover existing entries from their recorded identity or linked profile once.
-- A captured name is never refreshed after a profile rename or staff transfer.
update public.occci_audit a set
 subject_name=coalesce(nullif(btrim(a.after_data->>'full_name'),''),nullif(btrim(a.before_data->>'full_name'),''),nullif(btrim(p.full_name),'')),
 subject_employee_id=coalesce(a.subject_employee_id,nullif(btrim(a.after_data->>'employee_id'),''),nullif(btrim(a.before_data->>'employee_id'),''),nullif(btrim(p.employee_id),'')),
 subject_role=coalesce(nullif(a.after_data->>'role',''),(select s.role from public.occci_staff_assignments s where s.user_id=a.member_id),'Member')
 from public.occci_profiles p where p.id=a.member_id and nullif(btrim(a.subject_name),'') is null;

create or replace function public.occci_capture_audit_subject() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.member_id is null then
  new.subject_name:=null;
  new.subject_employee_id:=null;
  new.subject_role:=null;
 else
  select nullif(btrim(p.full_name),''),nullif(btrim(p.employee_id),'') into new.subject_name,new.subject_employee_id
   from public.occci_profiles p where p.id=new.member_id;
  new.subject_name:=coalesce(new.subject_name,nullif(btrim(new.after_data->>'full_name'),''),nullif(btrim(new.before_data->>'full_name'),''));
  new.subject_employee_id:=coalesce(new.subject_employee_id,nullif(btrim(new.after_data->>'employee_id'),''),nullif(btrim(new.before_data->>'employee_id'),''));
  new.subject_role:=coalesce(nullif(new.after_data->>'role',''),(select s.role from public.occci_staff_assignments s where s.user_id=new.member_id),'Member');
 end if;
 return new;
end;$$;
drop trigger if exists occci_audit_subject on public.occci_audit;
create trigger occci_audit_subject before insert on public.occci_audit for each row execute function public.occci_capture_audit_subject();
revoke all on function public.occci_capture_audit_subject() from public,anon,authenticated;
-- Existing audit policies and the activity RPC continue to restrict event scope.
insert into public.occci_schema_versions(version) values('010_audit_subject_identity') on conflict do nothing;
notify pgrst,'reload schema';
commit;
