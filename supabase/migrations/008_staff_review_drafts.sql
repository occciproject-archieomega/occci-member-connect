-- Apply after 007. Admin review drafts never grant a position or CMS access.
begin;
alter table public.occci_staff_applications add column if not exists review_draft jsonb not null default '{}' check(jsonb_typeof(review_draft)='object');
alter table public.occci_staff_applications add column if not exists draft_saved_by uuid references auth.users(id);
alter table public.occci_staff_applications add column if not exists draft_saved_at timestamptz;

create or replace function public.occci_save_staff_review(target uuid,values_json jsonb,reason text) returns void
language plpgsql security definer set search_path='' as $$
declare
 a public.occci_staff_applications;
 p public.occci_profiles;
 b public.occci_branches;
 choice text:=coalesce(values_json->>'decision','Approve');
 assigned text:=values_json->>'role';
 employee text;
 d smallint;
 draft jsonb;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only cooperative Admin can save staff reviews';end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if public.occci_role()<>'Admin' then raise exception 'Your Admin assignment changed; sign in again';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or choice not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then
  raise exception 'Choose a decision and provide reason / comments / notes';
 end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or target=auth.uid() then raise exception 'Choose another pending staff applicant';end if;
 select * into a from public.occci_staff_applications where user_id=target for update;
 if not found or a.status<>'Pending' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a pending staff applicant without an assigned position';end if;
 draft:=jsonb_build_object('decision',choice,'note',trim(reason));
 if choice='Approve' then
  if assigned is null or assigned not in ('Admin','DM','BM','Staff','BC') then raise exception 'Select the position to assign';end if;
  employee:=coalesce(nullif(trim(values_json->>'employee_id'),''),p.employee_id);
  if employee is null or employee !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{1,49}$' then raise exception 'Record a valid employee ID before saving the review';end if;
  if exists(select 1 from public.occci_profiles where lower(employee_id)=lower(employee) and id<>target) then raise exception 'Employee ID is already registered';end if;
  if assigned='DM' then
   d:=(values_json->>'district')::smallint;
   if d is null or not exists(select 1 from public.occci_branches where active and district=d) then raise exception 'Choose an active district';end if;
  elsif assigned in ('BM','Staff','BC') then
   select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
   if not found then raise exception 'Choose an active branch';end if;
   d:=b.district;
  end if;
  draft:=draft||jsonb_build_object('role',assigned,'employee_id',employee,'district',d,'branch_id',b.id);
 end if;
 update public.occci_staff_applications set review_draft=draft,draft_saved_by=auth.uid(),draft_saved_at=now() where user_id=target;
 perform public.occci_log(target,b.id,'Staff review saved as pending',jsonb_build_object('status',a.status,'review_draft',a.review_draft),jsonb_build_object('status','Pending','review_draft',draft),trim(reason));
end;$$;

revoke all on function public.occci_save_staff_review(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.occci_save_staff_review(uuid,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('008_staff_review_drafts') on conflict do nothing;
notify pgrst,'reload schema';
commit;
