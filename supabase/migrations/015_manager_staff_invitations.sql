-- Apply after 014. Invitation creation does not approve employees or grant staff access.
begin;
alter table public.occci_staff_invites add column if not exists district smallint check(district between 1 and 6);
alter table public.occci_staff_invites add column if not exists branch_id text references public.occci_branches(id);
create or replace function public.occci_staff_invite_access(invite_district smallint,invite_branch text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_staff_assignments s join public.occci_profiles p on p.id=s.user_id
 where s.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and
 (s.role='Admin' or (s.role='DM' and s.district=invite_district) or (s.role='BM' and s.branch_id=invite_branch)));
$$;
revoke all on function public.occci_staff_invite_access(smallint,text) from public,anon,authenticated;
grant execute on function public.occci_staff_invite_access(smallint,text) to authenticated;
grant select(district,branch_id) on public.occci_staff_invites to authenticated;
drop policy if exists occci_staff_invites_read on public.occci_staff_invites;
create policy occci_staff_invites_read on public.occci_staff_invites for select to authenticated using(public.occci_staff_invite_access(district,branch_id));

create or replace function public.occci_create_staff_invite(label text,valid_days integer,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare invite uuid:=gen_random_uuid(); secret text:=upper(left(replace(gen_random_uuid()::text,'-',''),24)); expiry timestamptz; assignment public.occci_staff_assignments; d smallint; b text;
begin
 select s.* into assignment from public.occci_staff_assignments s join public.occci_profiles p on p.id=s.user_id
 where s.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete for share of s,p;
 if not found or assignment.role not in ('Admin','DM','BM') then raise exception 'Only Admin, DM or BM can generate staff invitations';end if;
 if assignment.role='DM' then d:=assignment.district;
 elsif assignment.role='BM' then
  b:=assignment.branch_id;select district into d from public.occci_branches where id=b and active;
  if not found then raise exception 'Your branch is unavailable for invitations';end if;
 end if;
 if not public.occci_staff_invite_access(d,b) then raise exception 'Your assigned invitation scope is unavailable';end if;
 if coalesce(length(trim(label)),0) not between 1 and 150 or valid_days is null or valid_days not between 1 and 30 or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a label, 1–30 days validity and reason / comments / notes';end if;
 expiry:=now()+make_interval(days=>valid_days);
 insert into public.occci_staff_invites(id,code_hash,label,created_by,expires_at,district,branch_id)
 values(invite,public.occci_invite_digest(invite,secret),trim(label),auth.uid(),expiry,d,b);
 perform public.occci_log(null,b,'Staff invitation created',null,jsonb_build_object('invite_id',invite,'label',trim(label),'expires_at',expiry,'district',d,'branch_id',b),reason);
 return jsonb_build_object('id',invite,'code',regexp_replace(secret,'(.{4})(.{4})(.{4})(.{4})(.{4})(.{4})','\1-\2-\3-\4-\5-\6'),'expires_at',expiry,'district',d,'branch_id',b);
end;$$;
create or replace function public.occci_revoke_staff_invite(invite_id uuid,reason text) returns void language plpgsql security definer set search_path='' as $$
declare i public.occci_staff_invites;
begin
 if coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Reason / comments / notes are required';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or not public.occci_staff_invite_access(i.district,i.branch_id) then raise exception 'Invitation is outside your assigned district or branch';end if;
 if i.redeemed_at is not null or i.revoked_at is not null then raise exception 'Choose an unused active invitation';end if;
 update public.occci_staff_invites set revoked_at=now() where id=i.id;
 perform public.occci_log(null,i.branch_id,'Staff invitation revoked',jsonb_build_object('invite_id',i.id,'label',i.label,'district',i.district,'branch_id',i.branch_id),jsonb_build_object('revoked_at',now(),'district',i.district,'branch_id',i.branch_id),reason);
end;$$;
revoke all on function public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text) from public,anon,authenticated;
grant execute on function public.occci_create_staff_invite(text,integer,text),public.occci_revoke_staff_invite(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
