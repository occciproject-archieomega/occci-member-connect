-- Apply after 002_workflow.sql. One-time developer bootstrap and reviewed staff signup.
begin;
alter table public.occci_profiles add column if not exists registration_kind text not null default 'Member' check(registration_kind in ('Member','Staff'));
create table if not exists public.occci_staff_applications(
 user_id uuid primary key references public.occci_profiles(id), requested_role text not null check(requested_role in ('DM','BM','Staff')),
 district smallint not null check(district between 1 and 6), branch_id text not null references public.occci_branches(id),
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected')), reviewed_by uuid references auth.users(id),
 review_note text, created_at timestamptz not null default now(), reviewed_at timestamptz);
alter table public.occci_staff_applications enable row level security;
revoke all on public.occci_staff_applications from public,anon,authenticated;
grant select on public.occci_staff_applications to authenticated;
drop policy if exists occci_application_read on public.occci_staff_applications;
create policy occci_application_read on public.occci_staff_applications for select to authenticated using(user_id=auth.uid() or public.occci_role()='Admin');
create or replace function public.occci_staff_signup() returns trigger language plpgsql security definer set search_path='' as $$
declare meta jsonb:=new.raw_user_meta_data; d smallint;
begin
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
-- Alphabetical trigger order: profile creation runs before staff application creation.
drop trigger if exists occci_staff_signup on auth.users;
create trigger occci_staff_signup after insert on auth.users for each row execute function public.occci_staff_signup();
create or replace function public.occci_review_staff(target uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare a public.occci_staff_applications; p public.occci_profiles; previous jsonb;
begin
 if public.occci_role()<>'Admin' then raise exception 'Only cooperative Admin can approve staff positions';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0)<3 then raise exception 'Choose a decision and provide a review note';end if;
 select * into a from public.occci_staff_applications where user_id=target for update;
 if not found or a.status<>'Pending' or target=auth.uid() then raise exception 'Choose another pending staff applicant';end if;
 select * into p from public.occci_profiles where id=target for update;
 if p.archived_at is not null then raise exception 'Applicant is archived';end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=target;
 if decision='Approve' then
 if not exists(select 1 from auth.users where id=target and email_confirmed_at is not null) then raise exception 'Applicant must confirm their email before approval';end if;
 if not exists(select 1 from public.occci_branches where id=a.branch_id and active and district=a.district) then raise exception 'Requested branch/district changed; correct the directory before approval';end if;
 if previous is not null then raise exception 'Applicant already has a team assignment; manage it in Team';end if;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(target,a.requested_role,case when a.requested_role='DM' then null else a.branch_id end,case when a.requested_role='DM' then a.district else null end);
 end if;
 update public.occci_staff_applications set status=case decision when 'Approve' then 'Approved' else 'Rejected' end,reviewed_by=auth.uid(),review_note=reason,reviewed_at=now() where user_id=target;
 perform public.occci_log(target,a.branch_id,'Staff application reviewed',to_jsonb(a),jsonb_build_object('decision',decision,'role',a.requested_role,'district',a.district,'branch_id',a.branch_id),reason);
 if decision='Approve' then perform public.occci_log(target,a.branch_id,'Team assignment approved',previous,jsonb_build_object('role',a.requested_role,'district',a.district,'branch_id',a.branch_id),reason);end if;
end;$$;
-- Private, one-use bootstrap. Email comes from trusted auth.users, never client metadata.
create table if not exists public.occci_developer_bootstrap(
 singleton boolean primary key default true check(singleton), email text not null, consumed_by uuid references auth.users(id), consumed_at timestamptz);
alter table public.occci_developer_bootstrap enable row level security;
revoke all on public.occci_developer_bootstrap from public,anon,authenticated;
-- Configure the private target in SQL Editor before running this migration:
-- select set_config('occci.bootstrap_email','REPLACE_WITH_VERIFIED_DEVELOPER_EMAIL',false);
insert into public.occci_developer_bootstrap(singleton,email) values(true,coalesce(current_setting('occci.bootstrap_email',true),''))
on conflict(singleton) do update set email=excluded.email where occci_developer_bootstrap.consumed_at is null and occci_developer_bootstrap.email='' and excluded.email<>'';
create or replace function public.occci_bootstrap_developer(target uuid) returns void language plpgsql security definer set search_path='' as $$
declare config public.occci_developer_bootstrap; previous jsonb;
begin
 select * into config from public.occci_developer_bootstrap where singleton for update;
 if config.consumed_at is not null then return;end if;
 if not exists(select 1 from auth.users u join public.occci_profiles p on p.id=u.id where u.id=target and lower(u.email)=lower(config.email) and u.email_confirmed_at is not null and p.archived_at is null) then return;end if;
 select to_jsonb(s) into previous from public.occci_staff_assignments s where user_id=target;
 insert into public.occci_staff_assignments(user_id,role,branch_id,district) values(target,'Admin',null,null) on conflict(user_id) do update set role='Admin',branch_id=null,district=null;
 update public.occci_developer_bootstrap set consumed_by=target,consumed_at=now() where singleton;
 perform public.occci_log(target,null,'Temporary developer Admin activated',previous,jsonb_build_object('role','Admin'),'One-time verified developer bootstrap; transfer to cooperative Admin and remove this assignment after setup');
end;$$;
create or replace function public.occci_developer_confirmed() returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.occci_bootstrap_developer(new.id);return new;end;$$;
drop trigger if exists occci_z_developer_confirmed on auth.users;
create trigger occci_z_developer_confirmed after insert or update of email,email_confirmed_at on auth.users for each row execute function public.occci_developer_confirmed();
-- Activate an already registered/confirmed developer, or wait for signup + confirmation.
select public.occci_bootstrap_developer(id) from auth.users where lower(email)=(select lower(email) from public.occci_developer_bootstrap where singleton) and email_confirmed_at is not null;
revoke all on function public.occci_staff_signup(),public.occci_bootstrap_developer(uuid),public.occci_developer_confirmed(),public.occci_review_staff(uuid,text,text) from public,anon,authenticated;
grant execute on function public.occci_review_staff(uuid,text,text) to authenticated;
commit;
