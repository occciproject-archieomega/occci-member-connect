-- Apply after 021. Resolved notifications leave the active inbox; audit records remain stored.
begin;
alter table public.occci_notifications add column if not exists resolved_at timestamptz;
alter table public.occci_notifications add column if not exists action_required boolean not null default false;
create or replace function public.occci_notification_action() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.action_required:=case new.target_type
 when 'profile' then exists(select 1 from public.occci_profiles where id::text=new.target_id and membership_status='Pending verification' and archived_at is null)
 when 'request' then exists(select 1 from public.occci_change_requests where id::text=new.target_id and status in ('Pending','BM approved'))
 when 'password_request' then exists(select 1 from public.occci_password_requests where id::text=new.target_id and status in ('Pending','Approved'))
 when 'staff_application' then exists(select 1 from public.occci_staff_applications where user_id::text=new.target_id and status='Pending')
 when 'work_report' then exists(select 1 from public.occci_work_reports where id::text=new.target_id and status in ('For review','Returned'))
 when 'report' then exists(select 1 from public.occci_reports where id::text=new.target_id and status in ('For review','Returned'))
 else false end;
 return new;
end;$$;
revoke all on function public.occci_notification_action() from public,anon,authenticated;
drop trigger if exists occci_notification_action on public.occci_notifications;
create trigger occci_notification_action before insert on public.occci_notifications for each row execute function public.occci_notification_action();
create or replace function public.occci_mark_notifications_read(notification_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.occci_notifications set read_at=coalesce(read_at,clock_timestamp()),resolved_at=case when action_required then resolved_at else coalesce(resolved_at,clock_timestamp()) end where (notification_id is null or id=notification_id) and public.occci_notification_visible(recipient_id,scope_kind,branch_id,district);
end;$$;
create or replace function public.occci_notify_route(source text,v jsonb,prior jsonb,operation text) returns void language plpgsql security definer set search_path='' as $$
declare branch text:=v->>'branch_id'; d smallint; uid uuid; author uuid; key_value text; status text:=v->>'status'; old_status text:=prior->>'status'; roles text[]:='{}'; users uuid[]:='{}'; title text; message text:='Open the record to view its details.'; target_kind text; target_value text:=coalesce(v->>'id',v->>'user_id'); personal boolean:=false; audience uuid[]; audience_branch text;
begin

 -- Resolve the previous stage before generating its successor notification.
 if operation='DELETE' or v->>'archived_at' is not null or (operation='UPDATE' and (v->>'status' is distinct from prior->>'status' or v->>'membership_status' is distinct from prior->>'membership_status' or v->>'published' is distinct from prior->>'published')) then
  update public.occci_notifications set resolved_at=clock_timestamp() where resolved_at is null and target_id=coalesce(v->>'id',v->>'user_id') and target_type=case source when 'occci_profiles' then 'profile' when 'occci_change_requests' then 'request' when 'occci_password_requests' then 'password_request' when 'occci_staff_applications' then 'staff_application' when 'occci_work_reports' then 'work_report' when 'occci_reports' then 'report' when 'occci_content' then 'content' when 'occci_cashier_payments' then 'payment' when 'occci_staff_assignments' then 'team' else source end;
 end if;
 if source='occci_change_requests' and v->>'kind'='Membership approval' then
  update public.occci_notifications set resolved_at=clock_timestamp() where resolved_at is null and target_type='profile' and target_id=v->>'member_id';
 end if;
 if operation='DELETE' then
  if source='occci_staff_assignments' then perform public.occci_notify_emit(source||':'||(v->>'user_id')||':removed:'||pg_catalog.txid_current()::text,array['Admin','BM','DM'],v->>'branch_id',null,array[]::uuid[],'Team assignment removed','A cooperative team assignment was removed.','activity',null);end if;
  return;
 end if;
 if coalesce(v->>'district','') ~ '^[1-6]$' then d:=(v->>'district')::smallint;end if;
 key_value:=source||':'||coalesce(target_value,'')||':'||coalesce(status,v->>'membership_status',v->>'role','event')||':'||coalesce(v->>'revision',v->>'reviewed_at',v->>'updated_at',v->>'created_at','initial');
 if source='occci_profiles' then
  if v->>'registration_kind'='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=(v->>'id')::uuid) or v->>'archived_at' is not null or coalesce(v->>'onboarding_complete','false')<>'true' or v->>'membership_status'<>'Pending verification' or (operation='UPDATE' and prior->>'membership_status'='Pending verification' and prior->>'onboarding_complete'='true') then return;end if;
  roles:=array['BM','Staff','BC'];title:='New member awaiting BM screening';target_kind:='profile';
 elsif source='occci_change_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  author:=(v->>'submitted_by')::uuid;target_kind:='request';users:=array[author];
  if status='Pending' then roles:=case when v->>'kind'='Profile edit' then array['BM','DM'] else array['BM'] end;title:=(v->>'kind')||' awaiting review';
  elsif status='BM approved' and v->>'kind' in ('Financial sync','Membership approval') then roles:=array['DM'];title:=(v->>'kind')||' needs final DM approval';
  else roles:=case when status='Applied' then array['Admin','BM','DM','Staff','BC'] else array[]::text[] end;title:=(v->>'kind')||': '||status;end if;
 elsif source='occci_password_requests' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  users:=array[(v->>'user_id')::uuid];target_kind:='password_request';title:='Cashier password request: '||status;
  if status='Pending' then roles:=array['BM'];message:='Review the cashier request and its reason.';elsif status='Completed' then roles:=array['BM'];end if;
 elsif source='occci_staff_applications' then
  if operation='UPDATE' and status is not distinct from old_status then return;end if;
  branch:=null;d:=null;personal:=status<>'Pending';target_kind:='staff_application';users:=case when status='Pending' then array[]::uuid[] else array[(v->>'user_id')::uuid] end;roles:=case when status='Pending' then array['Admin'] else array[]::text[] end;title:='Staff application: '||status;
 elsif source='occci_staff_assignments' then
  if operation='UPDATE' and v->>'role' is not distinct from prior->>'role' and branch is not distinct from prior->>'branch_id' and v->>'district' is not distinct from prior->>'district' then return;end if;
  key_value:=source||':'||(v->>'user_id')||':'||pg_catalog.txid_current()::text;uid:=(v->>'user_id')::uuid;target_kind:='team';title:='Team assignment updated';message:='A cooperative position or operating unit has changed.';
  perform public.occci_notify_emit(key_value,array[]::text[],branch,d,array[uid],title,message,target_kind,target_value,true);
  perform public.occci_notify_emit(key_value||':admin',array['Admin'],branch,d,array[]::uuid[],title,message,target_kind,target_value,false);return;
 elsif source='occci_cashier_payments' then
  if operation='UPDATE' then return;end if;
  roles:=array['Admin','BM','DM','Staff','BC'];target_kind:='payment';title:='Cashier payment recorded';message:='A receipt was recorded and member balances were updated.';
 elsif source in ('occci_work_reports','occci_reports') then
  if v->>'archived_at' is not null or status='Draft' or (source='occci_reports' and v->'details' ? 'staff_work_id') or (operation='UPDATE' and status is not distinct from old_status) then return;end if;
  users:=array[(v->>'created_by')::uuid];target_kind:=case when source='occci_work_reports' then 'work_report' else 'report' end;title:=case when source='occci_work_reports' then 'Staff work report' else 'Cooperative report' end||': '||status;
  if source='occci_work_reports' then roles:=case when status='For review' then array['BM'] when status='Approved' then array['Admin','DM'] else array[]::text[] end;
  else roles:=array['Admin','DM','BM'];end if;
 elsif source='occci_content' then
  if v->>'published' is distinct from 'true' or v->>'archived_at' is not null then
   if prior->>'published' is distinct from 'true' then return;end if;
   branch:=prior->>'branch_id';d:=null;if coalesce(prior->>'district','') ~ '^[1-6]$' then d:=(prior->>'district')::smallint;end if;
   title:='Published content withdrawn';
  else title:='Published cooperative content updated';end if;
  target_kind:='content';message:='Announcements, events or services in your workspace have changed.';
  if branch is null and d is null then
   select array_agg(user_id) into audience from public.occci_staff_assignments;
   perform public.occci_notify_emit(key_value,array[]::text[],null,null,coalesce(audience,array[]::uuid[]),title,message,target_kind,target_value,true);return;
  elsif branch is null then
   perform public.occci_notify_emit(key_value,array['Admin','DM'],null,d,array[]::uuid[],title,message,target_kind,target_value);
   for audience_branch in select id from public.occci_branches where district=d loop
    perform public.occci_notify_emit(key_value,array['BM','Staff','BC'],audience_branch,d,array[]::uuid[],title,message,target_kind,target_value);
   end loop;return;
  else roles:=array['Admin','DM','BM','Staff','BC'];end if;
 elsif source='occci_audit' then
  if operation<>'INSERT' then return;end if;
  -- Dedicated workflows above create focused notifications, so audit does not duplicate them.
  if v->>'action' ~* '(request|financial|membership|cashier password|cashier payment|receipt time|staff application|team assignment|profile edit|report|content)' then return;end if;
  roles:=case when v->>'action' ~* 'cashier pin' then array['BM'] when branch is null then array['Admin'] else array['Admin','BM','DM','Staff','BC'] end;target_kind:='activity';title:=v->>'action';message:='New cooperative activity was recorded in your authorized workspace.';
 else return;end if;
 perform public.occci_notify_emit(key_value,roles,branch,d,users,title,message,target_kind,target_value,personal);
end;$$;

drop trigger if exists occci_notification_backfill on public.occci_notifications;
create trigger occci_notification_backfill before update on public.occci_notifications for each row execute function public.occci_notification_action();
update public.occci_notifications set action_required=action_required;
drop trigger occci_notification_backfill on public.occci_notifications;
update public.occci_notifications set resolved_at=clock_timestamp() where read_at is not null and not action_required and resolved_at is null;

-- Retire obsolete stages that existed before this migration was installed.
update public.occci_notifications n set resolved_at=clock_timestamp() where n.resolved_at is null and (
 (n.target_type='request' and not exists(select 1 from public.occci_change_requests q where q.id::text=n.target_id and n.event_key like 'occci_change_requests:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='password_request' and not exists(select 1 from public.occci_password_requests q where q.id::text=n.target_id and n.event_key like 'occci_password_requests:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='staff_application' and not exists(select 1 from public.occci_staff_applications q where q.user_id::text=n.target_id and n.event_key like 'occci_staff_applications:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='work_report' and not exists(select 1 from public.occci_work_reports q where q.id::text=n.target_id and to_jsonb(q)->>'archived_at' is null and n.event_key like 'occci_work_reports:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='report' and not exists(select 1 from public.occci_reports q where q.id::text=n.target_id and to_jsonb(q)->>'archived_at' is null and n.event_key like 'occci_reports:'||n.target_id||':'||q.status||':%')) or
 (n.target_type='profile' and (not n.action_required or exists(select 1 from public.occci_change_requests q where q.member_id::text=n.target_id and q.kind='Membership approval' and q.status in ('BM approved','Applied'))))
);
insert into public.occci_schema_versions(version) values('022_notification_actions') on conflict do nothing;
notify pgrst,'reload schema';
commit;
