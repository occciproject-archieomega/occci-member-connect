-- Apply after 026. Dedicated Huddle stage, scoped reports and host drawing permissions.
begin;
alter table public.occci_huddle_attendees add column if not exists annotation_allowed boolean not null default false;
alter table public.occci_huddle_sessions add column if not exists mic_default_locked boolean not null default false;
create or replace function public.occci_huddle_attendee_defaults() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' or (new.left_at is null and (old.left_at is not null or new.joined_at is distinct from old.joined_at)) then
  new.mic_locked:=coalesce((select (h.mic_default_locked or h.mic_locked) and new.user_id<>h.host_id from public.occci_huddle_sessions h where h.id=new.session_id),false);
  new.annotation_allowed:=false;
 end if;
 return new;
end;$$;
revoke all on function public.occci_huddle_attendee_defaults() from public,anon,authenticated;
drop trigger if exists occci_huddle_attendee_defaults on public.occci_huddle_attendees;
create trigger occci_huddle_attendee_defaults before insert or update on public.occci_huddle_attendees for each row execute function public.occci_huddle_attendee_defaults();

create table if not exists public.occci_huddle_stage(
 session_id uuid primary key references public.occci_huddle_sessions(id) on delete cascade,
 kind text not null default 'camera' check(kind in ('camera','screen','report')),
 target uuid references auth.users(id),report_id uuid,report_source text check(report_source in ('work','register')),
 revision uuid not null default gen_random_uuid(),recording boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.occci_huddle_stage add column if not exists record_expires_at timestamptz;
create table if not exists public.occci_huddle_strokes(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 revision uuid not null,sender_id uuid not null references auth.users(id),tool text not null check(tool in ('pen','arrow')),
 color text not null check(color in ('red','cyan')),points jsonb not null,created_at timestamptz not null default now()
);
create index if not exists occci_huddle_strokes_stage_idx on public.occci_huddle_strokes(session_id,revision,created_at);
alter table public.occci_huddle_stage enable row level security;
alter table public.occci_huddle_strokes enable row level security;
revoke all on public.occci_huddle_stage,public.occci_huddle_strokes from public,anon,authenticated;
insert into public.occci_report_types(id,category,name,guidance)
values('special-project','District','Special project report','Record a district or branch project, results, approved budget and supporting documents.')
on conflict(id) do nothing;

create or replace function public.occci_huddle_report(sid uuid,rid uuid,source text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.occci_reports;w public.occci_work_reports;
begin
 if not public.occci_huddle_member(sid) then raise exception 'Join this Huddle first.' using errcode='42501';end if;
 if source='work' then
  select * into w from public.occci_work_reports where id=rid and status='Approved' and frequency='Monthly';
  if w.id is null or not public.occci_huddle_data_scope(w.branch_id,w.district) or not public.occci_work_access(w.created_by,w.branch_id) then raise exception 'This report is outside your authorized units.' using errcode='42501';end if;
  return jsonb_build_object('id',w.id,'source','work','title',w.title,'branch_id',w.branch_id,'district',w.district,'period_start',w.period_start,'period_end',w.period_end,'summary',w.summary,'metrics',w.metrics,'status',w.status,'updated_at',w.updated_at);
 elsif source='register' then
  select * into r from public.occci_reports where id=rid and archived_at is null and status in ('Approved','Filed') and type_id='special-project';
  if r.id is null or not public.occci_huddle_data_scope(r.branch_id,r.district) or not public.occci_report_access(r.district,r.branch_id,false) then raise exception 'This report is outside your authorized units.' using errcode='42501';end if;
  return jsonb_build_object('id',r.id,'source','register','title',r.title,'branch_id',r.branch_id,'district',r.district,'period_start',r.period_start,'period_end',r.period_end,'summary',r.summary,'metrics',r.details,'status',r.status,'updated_at',r.updated_at);
 end if;
 raise exception 'Choose a valid report source.';
end;$$;

drop function if exists public.occci_huddle_reports(uuid,text,smallint,date,text);
create or replace function public.occci_huddle_reports(sid uuid,branch text default null,dist smallint default null,month date default current_date,kind text default 'monthly',page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare first_day date:=date_trunc('month',month)::date;last_day date:=(date_trunc('month',month)+interval '1 month')::date;result jsonb;
begin
 perform public.occci_huddle_context(sid);
 if not public.occci_huddle_data_scope(branch,dist) then raise exception 'Choose an authorized operating unit.' using errcode='42501';end if;
 if page is null or page not between 0 and 9999 then raise exception 'Choose a valid report page.';end if;
 if month is null or kind is null or kind not in ('monthly','project') then raise exception 'Choose a month and report type.';end if;
 if kind='monthly' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.branch_id,x.title,x.id),'[]'::jsonb) into result from (
   select w.id,'work'::text source,w.title,w.branch_id,w.district,w.period_start,w.period_end,w.status
   from public.occci_work_reports w where w.status='Approved' and w.frequency='Monthly'
   and w.period_start>=first_day and w.period_start<last_day
   and (branch is null or w.branch_id=branch) and (dist is null or w.district=dist)
   and public.occci_huddle_data_scope(w.branch_id,w.district) and public.occci_work_access(w.created_by,w.branch_id)
   order by w.branch_id,w.title,w.id limit 101 offset page*100
  )x;
 else
  select coalesce(jsonb_agg(to_jsonb(x) order by x.district,x.branch_id,x.title,x.id),'[]'::jsonb) into result from (
   select r.id,'register'::text source,r.title,r.branch_id,r.district,r.period_start,r.period_end,r.status
   from public.occci_reports r where r.archived_at is null and r.status in ('Approved','Filed') and r.type_id='special-project'
   and r.period_start<last_day and r.period_end>=first_day
   and (branch is null or r.branch_id=branch) and (dist is null or r.district=dist)
   and public.occci_huddle_data_scope(r.branch_id,r.district) and public.occci_report_access(r.district,r.branch_id,false)
   order by r.district,r.branch_id,r.title,r.id limit 101 offset page*100
  )x;
 end if;
 return result;
end;$$;

-- Preserve the established session/chat/mic authorization and extend only its response.
do $$ begin
 if to_regprocedure('public.occci_huddle_context_base_027(uuid)') is null then
  alter function public.occci_huddle_context(uuid) rename to occci_huddle_context_base_027;
 end if;
end $$;
revoke all on function public.occci_huddle_context_base_027(uuid) from public,anon,authenticated;
create or replace function public.occci_huddle_context(sid uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;stage public.occci_huddle_stage;presentation jsonb;report jsonb;strokes jsonb:='[]';visible boolean:=true;
begin
 result:=public.occci_huddle_context_base_027(sid);
 select * into stage from public.occci_huddle_stage where session_id=sid;
 if stage.session_id is not null then
  if stage.kind='report' then
   begin report:=public.occci_huddle_report(sid,stage.report_id,stage.report_source);
   exception when insufficient_privilege then visible:=false;
   end;
  end if;
  presentation:=jsonb_build_object('kind',stage.kind,'target',stage.target,'revision',stage.revision,'restricted',not visible)||
   case when visible and report is not null then jsonb_build_object('report',report) else '{}'::jsonb end;
  if visible then
   select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]'::jsonb) into strokes from (
    select id,sender_id,tool,color,points,created_at from public.occci_huddle_strokes where session_id=sid and revision=stage.revision order by created_at desc,id limit 100
   )x;
  end if;
 end if;
 return result||jsonb_build_object('studio_ready',true,'presentation',presentation,'strokes',strokes,'recording',coalesce(stage.recording and stage.record_expires_at>now(),false),
  'annotation_allowed',(result->>'is_host')::boolean or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.left_at is null and a.annotation_allowed),
  'participants',(select coalesce(jsonb_agg(p||jsonb_build_object('annotation_allowed',coalesce(a.annotation_allowed,false))),'[]'::jsonb)
    from jsonb_array_elements(result->'participants') p left join public.occci_huddle_attendees a on a.session_id=sid and a.user_id=(p->>'user_id')::uuid));
end;$$;

create or replace function public.occci_huddle_studio(sid uuid,command text,target uuid default null,values_json jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;stage public.occci_huddle_stage;rid uuid;source text;point jsonb;allowed boolean;host boolean;
begin
 -- Serialize stage, grants and drawings so stale strokes cannot cross presentations.
 perform 1 from public.occci_huddle_sessions where id=sid for update;
 ctx:=public.occci_huddle_context(sid);host:=(ctx->>'is_host')::boolean;
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then raise exception 'Join this Huddle first.' using errcode='42501';end if;
 if command in ('grant_pen','revoke_pen','camera','screen','record_start','record_stop','record_ping','clear') and not host then raise exception 'Only the host can control the stage and drawing permissions.' using errcode='42501';end if;
 insert into public.occci_huddle_stage(session_id,target) select sid,host_id from public.occci_huddle_sessions where id=sid on conflict do nothing;
 select * into stage from public.occci_huddle_stage where session_id=sid;
 if command in ('grant_pen','revoke_pen') then
  if target is null or not public.occci_huddle_valid(target) or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an active attendee.';end if;
  update public.occci_huddle_attendees set annotation_allowed=command='grant_pen' where session_id=sid and user_id=target;
 elsif command in ('camera','screen') then
  if target is null or not public.occci_huddle_valid(target) or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an active attendee.';end if;
  update public.occci_huddle_stage set kind=command,target=occci_huddle_studio.target,report_id=null,report_source=null,revision=gen_random_uuid(),updated_at=now() where session_id=sid;
  delete from public.occci_huddle_strokes where session_id=sid;
 elsif command='report' then
  -- Sharing does not expand report visibility: each viewer is checked separately.
  rid:=(values_json->>'report_id')::uuid;source:=values_json->>'source';
  perform public.occci_huddle_report(sid,rid,source);
  update public.occci_huddle_stage set kind='report',target=auth.uid(),report_id=rid,report_source=source,revision=gen_random_uuid(),updated_at=now() where session_id=sid;
  delete from public.occci_huddle_strokes where session_id=sid;
 elsif command in ('record_start','record_stop','record_ping') then
  if command='record_ping' and not stage.recording then raise exception 'Recording has stopped.';end if;
  update public.occci_huddle_stage set recording=command<>'record_stop',record_expires_at=case when command='record_stop' then null else now()+interval '45 seconds' end,updated_at=now() where session_id=sid;
 elsif command='clear' then
  delete from public.occci_huddle_strokes where session_id=sid;
  update public.occci_huddle_stage set revision=gen_random_uuid(),updated_at=now() where session_id=sid;
 elsif command='stroke' then
  allowed:=host or exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null and annotation_allowed);
  if not allowed or coalesce((ctx->'presentation'->>'restricted')::boolean,false) then raise exception 'The host must allow drawing on this presentation.' using errcode='42501';end if;
  if (values_json->>'revision')::uuid is distinct from stage.revision then raise exception 'The presentation changed. Draw again on the current stage.';end if;
  if values_json->>'tool' not in ('pen','arrow') or values_json->>'color' not in ('red','cyan') or jsonb_typeof(values_json->'points') is distinct from 'array' or jsonb_array_length(values_json->'points') not between 2 and 120 then raise exception 'Invalid drawing.';end if;
  for point in select value from jsonb_array_elements(values_json->'points') loop
   if jsonb_typeof(point) is distinct from 'array' or jsonb_array_length(point)<>2 then raise exception 'Invalid drawing coordinate.';end if;
   if jsonb_typeof(point->0)<>'number' or jsonb_typeof(point->1)<>'number' or (point->>0)::numeric not between 0 and 1 or (point->>1)::numeric not between 0 and 1 then raise exception 'Drawing coordinates must be inside the stage.';end if;
  end loop;
  if (select count(*) from public.occci_huddle_strokes where session_id=sid and sender_id=auth.uid() and created_at>now()-interval '1 minute')>=60 then raise exception 'Please slow down drawing.';end if;
  if (select count(*) from public.occci_huddle_strokes where session_id=sid)>=100 then raise exception 'The drawing board is full. Ask the host to clear it.';end if;
  insert into public.occci_huddle_strokes(session_id,revision,sender_id,tool,color,points) values(sid,stage.revision,auth.uid(),values_json->>'tool',values_json->>'color',values_json->'points');
 else raise exception 'Invalid stage command.';end if;
 if command not in ('stroke','record_ping') then perform public.occci_log(auth.uid(),null,'Huddle '||replace(command,'_',' '),null,jsonb_build_object('session_id',sid,'target',target),'OCCCI Huddle stage activity');end if;
 return public.occci_huddle_context(sid);
end;$$;

create or replace function public.occci_huddle_resume(sid uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;
begin
 ctx:=public.occci_huddle_context(sid);
 if not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=auth.uid() and left_at is null) then raise exception 'Enter the session code to join first.' using errcode='42501';end if;
 perform public.occci_log(auth.uid(),null,'Huddle resumed',null,jsonb_build_object('session_id',sid),'Resumed an existing active session');
 return (ctx->'session')-'join_code';
end;$$;

-- Returning to Connect keeps attendance active. Explicit Leave invalidates code-free resume.
create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) from (
  select h.id,h.created_at,jsonb_build_object('id',h.id,'title',h.title,'host_id',h.host_id,'host_name',p.full_name,'status',h.status,
   'created_at',h.created_at,'expires_at',h.expires_at,'is_host',h.host_id=auth.uid(),
   'can_resume',exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid() and a.left_at is null),
   'attendees',(select count(*) from public.occci_huddle_attendees a where a.session_id=h.id and a.left_at is null))||
   case when h.host_id=auth.uid() then jsonb_build_object('join_code',h.join_code) else '{}'::jsonb end item
  from public.occci_huddle_sessions h join public.occci_profiles p on p.id=h.host_id
  where public.occci_huddle_valid(auth.uid()) and h.status='Active' and h.expires_at>now() and public.occci_huddle_valid(h.host_id)
   and exists(select 1 from public.occci_staff_assignments s where s.user_id=h.host_id and s.role in ('Admin','DM','BM','Staff','BC'))
 )x;
$$;
-- Let the host allow one attendee after Mute all, without unlocking everybody.
create or replace function public.occci_huddle_command(sid uuid,command text,target uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 select * into h from public.occci_huddle_sessions where id=sid for update;
 if h.id is null or not public.occci_huddle_member(sid) then raise exception 'Huddle access denied.' using errcode='42501';end if;
 if command='leave' then
  update public.occci_huddle_attendees set left_at=now(),annotation_allowed=false where session_id=sid and user_id=auth.uid();
  if h.host_id=auth.uid() then update public.occci_huddle_stage set recording=false where session_id=sid;end if;
 else
  if h.host_id<>auth.uid() or not public.occci_huddle_host_scope(null,null) then raise exception 'Only this Huddle host can manage attendees.' using errcode='42501';end if;
  if command='end' then
   update public.occci_huddle_sessions set status='Ended',ended_at=now() where id=sid;
   update public.occci_huddle_stage set recording=false where session_id=sid;
  elsif h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended.';
  elsif command in ('mute_all','allow_all') then
   update public.occci_huddle_sessions set mic_locked=false,mic_default_locked=command='mute_all' where id=sid;
   update public.occci_huddle_attendees set mic_locked=command='mute_all' where session_id=sid and user_id<>h.host_id;
  elsif command in ('mute','allow') then
   if target is null or target=h.host_id or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an attendee in this Huddle.';end if;
   if h.mic_locked then
    update public.occci_huddle_attendees set mic_locked=true where session_id=sid and user_id<>h.host_id;
    update public.occci_huddle_sessions set mic_locked=false,mic_default_locked=true where id=sid;
   end if;
   update public.occci_huddle_attendees set mic_locked=command='mute' where session_id=sid and user_id=target;
  else raise exception 'Invalid Huddle command.';end if;
 end if;
 perform public.occci_log(auth.uid(),null,'Huddle '||replace(command,'_',' '),null,jsonb_build_object('session_id',sid,'target',target),'OCCCI Huddle activity');
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.occci_huddle_report(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.occci_huddle_reports(uuid,text,smallint,date,text,integer),public.occci_huddle_studio(uuid,text,uuid,jsonb),public.occci_huddle_resume(uuid),public.occci_huddle_context(uuid),public.occci_huddle_list(),public.occci_huddle_command(uuid,text,uuid) from public,anon;
grant execute on function public.occci_huddle_reports(uuid,text,smallint,date,text,integer),public.occci_huddle_studio(uuid,text,uuid,jsonb),public.occci_huddle_resume(uuid),public.occci_huddle_context(uuid),public.occci_huddle_list(),public.occci_huddle_command(uuid,text,uuid) to authenticated;
insert into public.occci_schema_versions(version) values('027_occci_huddle_studio') on conflict do nothing;
notify pgrst,'reload schema';
commit;
