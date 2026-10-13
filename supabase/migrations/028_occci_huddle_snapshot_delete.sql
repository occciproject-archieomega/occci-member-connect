-- Apply after 026 (or 027 if using Huddle Studio). Remove shared snapshots without modifying financial records.
begin;
create or replace function public.occci_huddle_delete_card(sid uuid,cid uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;card public.occci_huddle_cards;
begin
 ctx:=public.occci_huddle_context(sid);
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then
  raise exception 'Join this Huddle first.' using errcode='42501';
 end if;
 select * into card from public.occci_huddle_cards where id=cid and session_id=sid for update;
 if card.id is null then return jsonb_build_object('ok',true);end if;
 if not public.occci_huddle_data_scope(card.branch_id,card.district) or
  (card.sender_id<>auth.uid() and not (ctx->>'is_host')::boolean) then
  raise exception 'You can delete your own snapshots, or manage visible snapshots as the host.' using errcode='42501';
 end if;
 delete from public.occci_huddle_cards where id=cid and session_id=sid;
 perform public.occci_log(auth.uid(),card.branch_id,'Huddle snapshot deleted',null,
  jsonb_build_object('session_id',sid,'snapshot_id',cid,'district',card.district),'Removed a shared Huddle snapshot; source financial records were not changed');
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.occci_huddle_delete_card(uuid,uuid) from public,anon;
grant execute on function public.occci_huddle_delete_card(uuid,uuid) to authenticated;
insert into public.occci_schema_versions(version) values('028_occci_huddle_snapshot_delete') on conflict do nothing;
notify pgrst,'reload schema';
commit;
