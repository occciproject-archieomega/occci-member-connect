-- Apply after 024. Open code-based meetings; financial data keeps its existing scope.
begin;
create index if not exists occci_huddle_active_idx on public.occci_huddle_sessions(status,expires_at,created_at desc);

create or replace function public.occci_huddle_scope(u uuid,branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(u);
$$;
create or replace function public.occci_huddle_host_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and s.role in ('Admin','DM','BM','Staff','BC'));
$$;
create or replace function public.occci_huddle_member(sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_huddle_sessions h where h.id=sid and
 (h.host_id=auth.uid() or exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid() and a.left_at is null)));
$$;

-- Keep optional legacy arguments so older clients can create open sessions too.
-- No operating-unit values supplied by a client restrict conference membership.
create or replace function public.occci_huddle_create(label text,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 if not public.occci_huddle_host_scope(null,null) then raise exception 'Only assigned OCCCI staff can create a Huddle.' using errcode='42501';end if;
 if label is null or length(trim(label)) not between 1 and 150 then raise exception 'Enter a session title up to 150 characters.';end if;
 insert into public.occci_huddle_sessions(host_id,title,join_code) values(auth.uid(),trim(label),upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))) returning * into h;
 -- Creation does not count the host as an attendee or start their media.
 perform public.occci_log(auth.uid(),null,'Huddle created',null,jsonb_build_object('session_id',h.id,'title',h.title),'Created OCCCI Huddle');
 return to_jsonb(h);
end;$$;

-- A default second argument keeps previous code-only invitations compatible.
-- Remove the old overload to avoid ambiguous PostgREST RPC resolution.
drop function if exists public.occci_huddle_join(text);
create or replace function public.occci_huddle_join(code text,expected_session uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;n integer;
begin
 if not public.occci_huddle_valid(auth.uid()) then raise exception 'An active OCCCI account is required.' using errcode='42501';end if;
 insert into public.occci_huddle_attempts(user_id,attempts) values(auth.uid(),1) on conflict(user_id) do update set
 attempts=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then 1 else public.occci_huddle_attempts.attempts+1 end,
 started_at=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then now() else public.occci_huddle_attempts.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('error','Too many join attempts. Wait one minute.');end if;
 select * into h from public.occci_huddle_sessions where join_code=upper(regexp_replace(code,'[^a-zA-Z0-9]','','g')) and status='Active' and expires_at>now() for update;
 if h.id is null or (expected_session is not null and h.id<>expected_session) then return jsonb_build_object('error','This code is invalid for the selected session, expired or ended.');end if;
 if (select count(*) from public.occci_huddle_attendees where session_id=h.id and left_at is null)>=100 and not exists(select 1 from public.occci_huddle_attendees where session_id=h.id and user_id=auth.uid() and left_at is null) then return jsonb_build_object('error','This Huddle has reached its attendee capacity.');end if;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid()) on conflict(session_id,user_id) do update set left_at=null,joined_at=now();
 perform public.occci_log(auth.uid(),null,'Huddle joined',null,jsonb_build_object('session_id',h.id),'Joined OCCCI Huddle');
 -- The code is already known by the joiner; subsequent reads expose it only to the host.
 return to_jsonb(h)-'join_code';
end;$$;

create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) from (
  select h.id,h.created_at,jsonb_build_object('id',h.id,'title',h.title,'host_id',h.host_id,'host_name',p.full_name,'status',h.status,
   'created_at',h.created_at,'expires_at',h.expires_at,'is_host',h.host_id=auth.uid(),
   'attendees',(select count(*) from public.occci_huddle_attendees a where a.session_id=h.id and a.left_at is null)) ||
   case when h.host_id=auth.uid() then jsonb_build_object('join_code',h.join_code) else '{}'::jsonb end item
  from public.occci_huddle_sessions h join public.occci_profiles p on p.id=h.host_id
  where public.occci_huddle_valid(auth.uid()) and h.status='Active' and h.expires_at>now() and public.occci_huddle_valid(h.host_id)
   and exists(select 1 from public.occci_staff_assignments s where s.user_id=h.host_id and s.role in ('Admin','DM','BM','Staff','BC'))
 )x;
$$;

create or replace function public.occci_huddle_context(sid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare h public.occci_huddle_sessions;people jsonb;messages jsonb;cards jsonb;host boolean;
begin
 select * into h from public.occci_huddle_sessions where id=sid;
 if h.id is null or not public.occci_huddle_member(sid) or h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended or your access changed.' using errcode='42501';end if;
 host:=h.host_id=auth.uid() and public.occci_huddle_host_scope(null,null);
 select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'name',p.full_name,'role',coalesce(s.role,'Member'),'mic_locked',a.mic_locked or (h.mic_locked and a.user_id<>h.host_id),'blocked',not public.occci_huddle_valid(a.user_id))),'[]'::jsonb) into people from public.occci_huddle_attendees a join public.occci_profiles p on p.id=a.user_id left join public.occci_staff_assignments s on s.user_id=a.user_id where a.session_id=sid and a.left_at is null;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into messages from (select m.id,m.sender_id,m.body,m.created_at,p.full_name sender_name from public.occci_huddle_messages m join public.occci_profiles p on p.id=m.sender_id where m.session_id=sid order by m.created_at desc limit 60)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into cards from (select c.id,c.sender_id,c.summary,c.created_at from public.occci_huddle_cards c where c.session_id=sid and public.occci_huddle_data_scope(c.branch_id,c.district) order by c.created_at desc limit 10)x;
 return jsonb_build_object('session',case when host then to_jsonb(h) else to_jsonb(h)-'join_code' end,'identity',auth.uid(),'name',(select full_name from public.occci_profiles where id=auth.uid()),'role',public.occci_role(),'is_host',host,'participants',people,'messages',messages,'cards',cards,'mic_locked',h.host_id<>auth.uid() and (h.mic_locked or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.mic_locked)));
end;$$;

-- occci_huddle_data_scope, summary and share are intentionally unchanged.
revoke all on function public.occci_huddle_scope(uuid,text,smallint),public.occci_huddle_host_scope(text,smallint),public.occci_huddle_member(uuid) from public,anon,authenticated;
revoke all on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text,uuid),public.occci_huddle_list(),public.occci_huddle_context(uuid) from public,anon;
grant execute on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text,uuid),public.occci_huddle_list(),public.occci_huddle_context(uuid) to authenticated;
insert into public.occci_schema_versions(version) values('025_occci_huddle_sessions') on conflict do nothing;
notify pgrst,'reload schema';
commit;
