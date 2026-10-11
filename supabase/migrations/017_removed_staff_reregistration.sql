-- Apply after 016. Removed staff may have an existing profile but no active assignment.
begin;
create or replace function public.occci_prepare_staff_reregistration(invite_id uuid,code text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; i public.occci_staff_invites; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found then raise exception 'This account has no cooperative profile. Contact Admin';end if;
 if p.archived_at is null and not (p.onboarding_complete and not exists(select 1 from public.occci_staff_assignments where user_id=p.id) and not exists(select 1 from public.occci_staff_applications where user_id=p.id and status='Pending') and (exists(select 1 from public.occci_staff_applications where user_id=p.id and status='Approved') or exists(select 1 from public.occci_audit where member_id=p.id and action='Team assignment changed' and before_data->>'role' in ('Admin','DM','BM','Staff','BC') and after_data->>'role'='Member'))) then raise exception 'This account is already registered or has a pending application. Contact Admin';end if;
 select * into i from public.occci_staff_invites where id=invite_id for update;
 if not found or i.code_hash is distinct from public.occci_invite_digest(invite_id,code) or i.expires_at<=now() or i.revoked_at is not null or i.redeemed_at is not null then raise exception 'Use a fresh valid staff invitation and code from Admin, DM or BM';end if;
 update public.occci_profiles set archived_at=null,onboarding_complete=false,registration_kind='Member',membership_status='Pending verification',account_number=null,employee_id=null,photo_path=null,branch_id=null,revision=revision+1 where id=p.id;
 delete from public.occci_staff_assignments where user_id=p.id;
 select * into a from public.occci_staff_applications where user_id=p.id for update;
 if found and a.status in ('Pending','Approved') then
  update public.occci_staff_applications set status='Rejected',review_note='Staff re-registration; previous access is not restored',reviewed_at=now() where user_id=p.id;
  perform public.occci_log(p.id,p.branch_id,'Prior staff application closed for re-registration',to_jsonb(a),jsonb_build_object('status','Rejected'),'New invitation and Admin review are required');
 end if;
 for q in select * from public.occci_change_requests where member_id=p.id and status in ('Pending','BM approved','Approved') for update loop
  update public.occci_change_requests set status='Rejected',review_note='Superseded by staff re-registration',reviewed_at=now() where id=q.id;
  perform public.occci_log(p.id,q.branch_id,'Prior request closed for staff re-registration',to_jsonb(q),jsonb_build_object('request_id',q.id,'status','Rejected'),'Prior access is not restored');
 end loop;
 perform public.occci_log(p.id,p.branch_id,'Staff re-registration started',to_jsonb(p),jsonb_build_object('invite_id',i.id,'onboarding_complete',false,'membership_status','Pending verification'),'Account owner verified a fresh staff invitation; employee details and Admin approval are required');
end;$$;
revoke all on function public.occci_prepare_staff_reregistration(uuid,text) from public,anon,authenticated;
grant execute on function public.occci_prepare_staff_reregistration(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
