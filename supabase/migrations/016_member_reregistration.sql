-- Apply after 015. Re-registration is explicit, owned and pending approval; history is retained.
begin;
create or replace function public.occci_reregister_member(values_json jsonb) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; b public.occci_branches; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is null then raise exception 'This account is already registered. Please sign in instead';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or coalesce(values_json->>'registration_kind','Member')<>'Member' or values_json ?| array['role','requested_role','membership_status','account_number','employee_id','archived_at','photo_path','id','user_id'] then raise exception 'Re-registration is for cooperative membership only; staff positions require Admin approval';end if;
 select * into b from public.occci_branches where id=values_json->>'branch_id' and active;
 if not found or b.district::text<>coalesce(values_json->>'district','') then raise exception 'Choose an active branch in the selected district';end if;
 perform public.occci_profile_values(p.id,values_json||jsonb_build_object('membership_status','Pending verification'));
 update public.occci_profiles set archived_at=null,onboarding_complete=true,registration_kind='Member',account_number=null,employee_id=null,photo_path=null,branch_id=b.id where id=p.id;
 -- An archived staff identity never recovers its old privileges through member registration.
 delete from public.occci_staff_assignments where user_id=p.id;
 select * into a from public.occci_staff_applications where user_id=p.id for update;
 if found and a.status in ('Pending','Approved') then
  update public.occci_staff_applications set status='Rejected',review_note='Member re-registration; prior staff access is not restored',reviewed_at=now() where user_id=p.id;
  perform public.occci_log(p.id,b.id,'Prior staff application closed for member re-registration',to_jsonb(a),jsonb_build_object('status','Rejected'),'Admin approval is required for any future staff assignment');
 end if;
 for q in select * from public.occci_change_requests where member_id=p.id and status in ('Pending','BM approved','Approved') for update loop
  update public.occci_change_requests set status='Rejected',review_note='Superseded by member re-registration',reviewed_at=now() where id=q.id;
  perform public.occci_log(p.id,q.branch_id,'Prior request closed for re-registration',to_jsonb(q),jsonb_build_object('request_id',q.id,'status','Rejected'),'New member registration requires fresh approval');
 end loop;
 perform public.occci_log(p.id,b.id,'Member registered again',to_jsonb(p),jsonb_build_object('registration_kind','Member','branch_id',b.id,'district',b.district,'membership_status','Pending verification','account_number',null),'Account owner re-registered using verified email; BM screening and DM approval are required again');
end;$$;
revoke all on function public.occci_reregister_member(jsonb) from public,anon,authenticated;
grant execute on function public.occci_reregister_member(jsonb) to authenticated;
create or replace function public.occci_prepare_staff_reregistration(invite_id uuid,code text) returns void language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; i public.occci_staff_invites; q public.occci_change_requests; a public.occci_staff_applications;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verify your existing email account before registering again';end if;
 select * into p from public.occci_profiles where id=auth.uid() for update;
 if not found or p.archived_at is null then raise exception 'This account is already registered. Please sign in instead';end if;
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
