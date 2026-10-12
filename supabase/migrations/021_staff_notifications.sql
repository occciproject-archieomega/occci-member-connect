-- Apply after 020. Per-user notifications never expand operational permissions.
begin;
create table if not exists public.occci_notifications(
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null, event_key text not null,
 scope_kind text not null check(scope_kind in ('personal','unit')), branch_id text references public.occci_branches(id), district smallint,
 title text not null, body text not null, target_type text not null, target_id text,
 created_at timestamptz not null default clock_timestamp(), read_at timestamptz,
 unique(recipient_id,event_key)
);
create index if not exists occci_notification_inbox on public.occci_notifications(recipient_id,created_at desc,id);
alter table public.occci_notifications enable row level security;
revoke all on public.occci_notifications from public,anon,authenticated;
grant select on public.occci_notifications to authenticated;
create or replace function public.occci_notification_visible(recipient uuid,kind text,branch text,unit_district smallint) returns boolean language sql stable security definer set search_path='' as $$
 select recipient=auth.uid() and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and
 (kind='personal' or t.role='Admin' or (t.role='DM' and t.district=unit_district) or (t.role in ('BM','Staff','BC') and branch is not null and t.branch_id=branch)));
$$;
drop policy if exists occci_notification_read on public.occci_notifications;
create policy occci_notification_read on public.occci_notifications for select to authenticated using(public.occci_notification_visible(recipient_id,scope_kind,branch_id,district));
create or replace function public.occci_mark_notifications_read(notification_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.occci_notifications set read_at=clock_timestamp() where read_at is null and (notification_id is null or id=notification_id) and public.occci_notification_visible(recipient_id,scope_kind,branch_id,district);
end;$$;
-- Only private business triggers can create notifications. No client can choose recipients or messages.
create or replace function public.occci_notify_emit(key_value text,roles text[],unit_branch text,unit_district smallint,users uuid[],heading text,message text,target_kind text,target_value text,personal boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare d smallint:=coalesce(unit_district,(select district from public.occci_branches where id=unit_branch));
begin
 insert into public.occci_notifications(recipient_id,actor_id,event_key,scope_kind,branch_id,district,title,body,target_type,target_id)
 select t.user_id,auth.uid(),key_value,case when personal then 'personal' else 'unit' end,case when personal then null else unit_branch end,case when personal then null else d end,left(heading,140),left(message,400),target_kind,target_value
 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id
 where p.archived_at is null and p.onboarding_complete and t.user_id is distinct from auth.uid() and
 ((t.role=any(roles) and (t.role='Admin' or t.role='DM' and t.district=d or t.role in ('BM','Staff','BC') and t.branch_id=unit_branch)) or
 (t.user_id=any(users) and (personal or t.role='Admin' or t.role='DM' and t.district=d or t.role in ('BM','Staff','BC') and t.branch_id=unit_branch)))
 on conflict(recipient_id,event_key) do nothing;
end;$$;
create or replace function public.occci_notify_route(source text,v jsonb,prior jsonb,operation text) returns void language plpgsql security definer set search_path='' as $$
declare branch text:=v->>'branch_id'; d smallint; uid uuid; author uuid; key_value text; status text:=v->>'status'; old_status text:=prior->>'status'; roles text[]:='{}'; users uuid[]:='{}'; title text; message text:='Open the record to view its details.'; target_kind text; target_value text:=coalesce(v->>'id',v->>'user_id'); personal boolean:=false; audience uuid[]; audience_branch text;
begin
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
  branch:=null;d:=null;personal:=true;target_kind:='staff_application';users:=array[(v->>'user_id')::uuid];roles:=case when status='Pending' then array['Admin'] else array[]::text[] end;title:='Staff application: '||status;
 elsif source='occci_staff_assignments' then
  if operation='UPDATE' and v->>'role' is not distinct from prior->>'role' and branch is not distinct from prior->>'branch_id' and v->>'district' is not distinct from prior->>'district' then return;end if;
  key_value:=source||':'||(v->>'user_id')||':'||pg_catalog.txid_current()::text;uid:=(v->>'user_id')::uuid;roles:=array['Admin'];users:=array[uid];personal:=true;target_kind:='team';title:='Team assignment updated';message:='A cooperative position or operating unit has changed.';
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
create or replace function public.occci_notify_business() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform public.occci_notify_route(TG_TABLE_NAME,case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end,case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end,TG_OP);
 return null;
end;$$;
revoke all on function public.occci_notification_visible(uuid,text,text,smallint),public.occci_mark_notifications_read(uuid),public.occci_notify_emit(text,text[],text,smallint,uuid[],text,text,text,text,boolean),public.occci_notify_route(text,jsonb,jsonb,text),public.occci_notify_business() from public,anon,authenticated;
grant execute on function public.occci_notification_visible(uuid,text,text,smallint),public.occci_mark_notifications_read(uuid) to authenticated;
do $$declare table_name text;begin
 foreach table_name in array array['occci_profiles','occci_change_requests','occci_password_requests','occci_staff_applications','occci_staff_assignments','occci_cashier_payments','occci_work_reports','occci_reports','occci_content','occci_audit'] loop
  execute format('drop trigger if exists occci_notify_business on public.%I',table_name);
  execute format('create trigger occci_notify_business after insert or update or delete on public.%I for each row execute function public.occci_notify_business()',table_name);
 end loop;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='occci_notifications') then alter publication supabase_realtime add table public.occci_notifications;end if;
end;$$;
-- Seed actionable queues once, without replaying historical payments/activity.
do $$declare table_name text; row_value jsonb;begin
 foreach table_name in array array['occci_profiles','occci_change_requests','occci_password_requests','occci_staff_applications','occci_work_reports','occci_reports'] loop
  for row_value in execute format('select to_jsonb(t) from public.%I t',table_name) loop
   if coalesce(row_value->>'status',row_value->>'membership_status') in ('Pending','BM approved','For review','Pending verification') then
    perform public.occci_notify_route(table_name,row_value,'{}'::jsonb,'SEED');
   end if;
  end loop;
 end loop;
end;$$;
insert into public.occci_schema_versions(version) values('021_staff_notifications') on conflict do nothing;
notify pgrst,'reload schema';
commit;
