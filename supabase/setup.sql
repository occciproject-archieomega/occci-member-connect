-- Run in the Supabase SQL Editor for project hlxcltqnlypptbykirzi.
begin;
create table if not exists public.occci_branches(id text primary key,name text not null,district smallint not null check(district between 1 and 6));
insert into public.occci_branches(id,name,district) values
('BR-02','Abuyog',1),
('BR-03','Albuera',1),
('BR-04','Bacolod',1),
('BR-05','Baybay',1),
('BR-06','Cebu',1),
('BR-07','Isabel',1),
('BR-08','Merida',1),
('BR-01','Ormoc',1),
('BR-09','Talisay',1),
('BR-10','San Francisco',1),
('BR-11','Alang-Alang',2),
('BR-12','Babatngon',2),
('BR-13','Calamba',2),
('BR-14','Lucena',2),
('BR-15','Pasay',2),
('BR-16','Tacloban',2),
('BR-17','Hilongos',3),
('BR-18','Inopacan',3),
('BR-19','Liloan',3),
('BR-20','Maasin',3),
('BR-21','San Juan',3),
('BR-22','Sogod',3),
('BR-23','Surigao',3),
('BR-24','Talibon',3),
('BR-25','Ubay',3),
('BR-26','Brooke''s Point',4),
('BR-27','Carigara',4),
('BR-28','Kananga',4),
('BR-29','Palompon',4),
('BR-30','Puerto Princesa',4),
('BR-31','Rio Tuba',4),
('BR-32','San Isidro',4),
('BR-33','Tabango',4),
('BR-34','Villaba',4),
('BR-35','Biliran',5),
('BR-36','Cabucgayan',5),
('BR-37','Caibiran',5),
('BR-38','Calubian',5),
('BR-39','Culaba',5),
('BR-40','Kalibo',5),
('BR-41','Kawayan',5),
('BR-42','Leyte',5),
('BR-43','Naval',5),
('BR-44','Allen',6),
('BR-45','Balangiga',6),
('BR-46','Borongan',6),
('BR-47','Calbayog',6),
('BR-48','Calbiga',6),
('BR-49','Catarman',6),
('BR-50','Catbalogan',6),
('BR-51','Dolores',6),
('BR-52','Guiuan',6) on conflict(id) do update set name=excluded.name,district=excluded.district;
create table if not exists public.occci_profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check(length(full_name) between 1 and 100),
 branch_id text not null references public.occci_branches(id),
 avatar text not null default 'lady' check(avatar in ('man','farmer','lady','lola','boy','girl')),
 membership_status text not null default 'Pending verification' check(membership_status in ('Pending verification','Active','Suspended')),
 created_at timestamptz not null default now()
);
create table if not exists public.occci_staff_assignments(
 user_id uuid primary key references auth.users(id) on delete cascade,
 branch_id text not null references public.occci_branches(id),
 role text not null check(role in ('Admin Head','Admin','Staff'))
);
alter table public.occci_branches enable row level security;
alter table public.occci_profiles enable row level security;
alter table public.occci_staff_assignments enable row level security;
create or replace function public.occci_can_read_branch(target_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s where s.user_id=(select auth.uid()) and (s.role='Admin Head' or s.branch_id=target_branch));
$$;
revoke all on function public.occci_can_read_branch(text) from public;
grant execute on function public.occci_can_read_branch(text) to authenticated;
drop policy if exists occci_branch_read on public.occci_branches;
create policy occci_branch_read on public.occci_branches for select to anon,authenticated using(true);
drop policy if exists occci_profile_read on public.occci_profiles;
create policy occci_profile_read on public.occci_profiles for select to authenticated using(id=(select auth.uid()) or public.occci_can_read_branch(branch_id));
drop policy if exists occci_profile_update on public.occci_profiles;
create policy occci_profile_update on public.occci_profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
drop policy if exists occci_staff_self_read on public.occci_staff_assignments;
create policy occci_staff_self_read on public.occci_staff_assignments for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.occci_profiles,public.occci_staff_assignments,public.occci_branches from anon,authenticated;
grant select on public.occci_branches to anon,authenticated;
grant select on public.occci_profiles,public.occci_staff_assignments to authenticated;
grant update(full_name,avatar) on public.occci_profiles to authenticated;
-- Role, membership status and branch cannot be changed by a member.
create or replace function public.occci_handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.occci_profiles(id,full_name,branch_id,avatar)
 values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'full_name',100),''),'Member'),
 case when exists(select 1 from public.occci_branches where id=new.raw_user_meta_data->>'branch_id') then new.raw_user_meta_data->>'branch_id' else 'BR-01' end,
 case when new.raw_user_meta_data->>'avatar' in ('man','farmer','lady','lola','boy','girl') then new.raw_user_meta_data->>'avatar' else 'lady' end);
 return new;
end;$$;
revoke all on function public.occci_handle_signup() from public,anon,authenticated;
drop trigger if exists occci_on_signup on auth.users;
create trigger occci_on_signup after insert on auth.users for each row execute function public.occci_handle_signup();
-- Backfill existing accounts conservatively: pending verification, default Ormoc.
insert into public.occci_profiles(id,full_name,branch_id,avatar)
select id,coalesce(nullif(left(raw_user_meta_data->>'full_name',100),''),'Member'),
case when exists(select 1 from public.occci_branches where id=raw_user_meta_data->>'branch_id') then raw_user_meta_data->>'branch_id' else 'BR-01' end,
case when raw_user_meta_data->>'avatar' in ('man','farmer','lady','lola','boy','girl') then raw_user_meta_data->>'avatar' else 'lady' end
from auth.users on conflict(id) do nothing;
commit;
-- Assign staff only through an administrator's SQL Editor or trusted server.
-- insert into public.occci_staff_assignments(user_id,branch_id,role)
-- values ('VERIFIED-AUTH-USER-UUID','BR-01','Admin Head');
