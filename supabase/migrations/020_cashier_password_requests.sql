-- Apply after 019. Cashier password approval belongs to the assigned BM.
begin;
create table if not exists public.occci_password_requests(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 branch_id text not null references public.occci_branches(id), purpose text not null check(purpose in ('Change password','Recover password')),
 status text not null default 'Pending' check(status in ('Pending','Approved','Rejected','Completed','Expired')),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 created_at timestamptz not null default clock_timestamp(), reviewer_id uuid references auth.users(id),
 review_note text, reviewed_at timestamptz, approval_expires_at timestamptz, completed_at timestamptz
);
create unique index if not exists occci_password_request_active on public.occci_password_requests(user_id) where status in ('Pending','Approved');
alter table public.occci_password_requests enable row level security;
revoke all on public.occci_password_requests from public,anon,authenticated;
grant select on public.occci_password_requests to authenticated;
drop policy if exists occci_password_requests_read on public.occci_password_requests;
create policy occci_password_requests_read on public.occci_password_requests for select to authenticated using(
 exists(select 1 from public.occci_profiles p where p.id=auth.uid() and p.archived_at is null) and
 (user_id=auth.uid() or public.occci_role()='Admin' or (public.occci_role() in ('BM','DM') and public.occci_can_read_branch(branch_id)))
);
create or replace function public.occci_request_cashier_password(purpose text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare branch text; result uuid;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only Branch Cashier can submit this request';end if;
 if purpose is null or purpose not in ('Change password','Recover password') or coalesce(length(btrim(reason)),0) not between 3 and 2000 then raise exception 'Choose the request type and provide a reason';end if;
 select branch_id into branch from public.occci_staff_assignments where user_id=auth.uid();
 if not exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.role='BM' and t.branch_id=branch and p.archived_at is null) then raise exception 'Your branch needs an assigned BM before a password request can be submitted';end if;
 update public.occci_password_requests set status='Expired' where user_id=auth.uid() and status in ('Pending','Approved') and (branch_id<>branch or status='Approved' and approval_expires_at<=clock_timestamp());
 if exists(select 1 from public.occci_password_requests where user_id=auth.uid() and status in ('Pending','Approved')) then raise exception 'You already have a pending or approved password request';end if;
 insert into public.occci_password_requests(user_id,branch_id,purpose,reason) values(auth.uid(),branch,purpose,btrim(reason)) returning id into result;
 perform public.occci_log(auth.uid(),branch,'Cashier password request submitted',null,jsonb_build_object('request_id',result,'purpose',purpose,'status','Pending'),'Sent to the assigned Branch Manager');
 return result;
end;$$;
create or replace function public.occci_review_cashier_password(request_id uuid,decision text,note text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_password_requests;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 select * into q from public.occci_password_requests where id=request_id for update;
 if q.id is null or public.occci_role()<>'BM' or not public.occci_can_read_branch(q.branch_id) or q.user_id=auth.uid() then raise exception 'Only the assigned Branch Manager can decide this request';end if;
 if q.status<>'Pending' then raise exception 'This request has already been reviewed';end if;
 if not exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=q.user_id and t.role='BC' and t.branch_id=q.branch_id and p.archived_at is null) then raise exception 'The cashier assignment changed. A new request is required';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(btrim(note)),0) not between 3 and 2000 then raise exception 'Choose approve or reject and provide decision notes';end if;
 update public.occci_password_requests set status=case decision when 'Approve' then 'Approved' else 'Rejected' end,reviewer_id=auth.uid(),review_note=btrim(note),reviewed_at=clock_timestamp(),approval_expires_at=case when decision='Approve' then clock_timestamp()+interval '24 hours' end where id=request_id;
 perform public.occci_log(q.user_id,q.branch_id,'Cashier password request reviewed',null,jsonb_build_object('request_id',q.id,'decision',decision),'Branch Manager decision recorded');
end;$$;
-- This gate is enforced at the Auth password update, including requests made outside the UI.
-- It never copies old/new password hashes into cooperative tables or logs.
create or replace function public.occci_guard_cashier_password() returns trigger language plpgsql security definer set search_path='' as $$
declare branch text; q public.occci_password_requests;
begin
 if new.encrypted_password is not distinct from old.encrypted_password then return new;end if;
 perform pg_catalog.pg_advisory_xact_lock(771004);
 select t.branch_id into branch from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=new.id and t.role='BC' and p.archived_at is null;
 if branch is null then return new;end if;
 select * into q from public.occci_password_requests where user_id=new.id and branch_id=branch and status='Approved' and approval_expires_at>clock_timestamp() for update;
 if q.id is null then raise exception 'A current Branch Manager approval is required to change this cashier password';end if;
 update public.occci_password_requests set status='Completed',completed_at=clock_timestamp() where id=q.id;
 perform public.occci_log(new.id,branch,'Cashier password updated',null,jsonb_build_object('request_id',q.id,'purpose',q.purpose,'status','Completed'),'Approved password change completed through Supabase Auth');
 return new;
end;$$;
drop trigger if exists occci_guard_cashier_password on auth.users;
create trigger occci_guard_cashier_password before update of encrypted_password on auth.users for each row execute function public.occci_guard_cashier_password();
revoke all on function public.occci_request_cashier_password(text,text),public.occci_review_cashier_password(uuid,text,text),public.occci_guard_cashier_password() from public,anon,authenticated;
grant execute on function public.occci_request_cashier_password(text,text),public.occci_review_cashier_password(uuid,text,text) to authenticated;
drop trigger if exists occci_live_signal on public.occci_password_requests;
create trigger occci_live_signal after insert or update or delete on public.occci_password_requests for each row execute function public.occci_live_signal();
do $$begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='occci_password_requests') then alter publication supabase_realtime add table public.occci_password_requests;end if;
end;$$;
insert into public.occci_schema_versions(version) values('020_cashier_password_requests') on conflict do nothing;
notify pgrst,'reload schema';
commit;
