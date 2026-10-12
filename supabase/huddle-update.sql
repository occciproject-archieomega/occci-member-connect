-- OCCCI Huddle update for an existing database with migrations 001-023 installed.
-- Includes migrations 024 and 025; safe to run again.

-- Apply after 023. OCCCI Huddle authorization, session codes and scoped collaboration.
begin;
create table if not exists public.occci_huddle_sessions(
 id uuid primary key default gen_random_uuid(),host_id uuid not null references auth.users(id),title text not null check(length(title) between 1 and 150),
 join_code text not null unique,branch_id text references public.occci_branches(id),district smallint check(district between 1 and 6),
 status text not null default 'Active' check(status in ('Active','Ended')),mic_locked boolean not null default false,
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '12 hours',ended_at timestamptz,
 check(branch_id is null or district is null));
create table if not exists public.occci_huddle_attendees(
 session_id uuid references public.occci_huddle_sessions(id) on delete cascade,user_id uuid references auth.users(id) on delete cascade,
 mic_locked boolean not null default false,joined_at timestamptz not null default now(),left_at timestamptz,primary key(session_id,user_id));
create table if not exists public.occci_huddle_messages(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 sender_id uuid not null references auth.users(id),body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default now());
create table if not exists public.occci_huddle_cards(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.occci_huddle_sessions(id) on delete cascade,
 sender_id uuid not null references auth.users(id),branch_id text references public.occci_branches(id),district smallint check(district between 1 and 6),
 summary jsonb not null,created_at timestamptz not null default now());
create table if not exists public.occci_huddle_attempts(user_id uuid primary key references auth.users(id) on delete cascade,started_at timestamptz not null default now(),attempts integer not null default 0);
create index if not exists occci_huddle_host_idx on public.occci_huddle_sessions(host_id,created_at desc);
create index if not exists occci_huddle_messages_session_idx on public.occci_huddle_messages(session_id,created_at desc);
alter table public.occci_huddle_sessions enable row level security;
alter table public.occci_huddle_attendees enable row level security;
alter table public.occci_huddle_messages enable row level security;
alter table public.occci_huddle_cards enable row level security;
alter table public.occci_huddle_attempts enable row level security;
revoke all on public.occci_huddle_sessions,public.occci_huddle_attendees,public.occci_huddle_messages,public.occci_huddle_cards,public.occci_huddle_attempts from public,anon,authenticated;

create or replace function public.occci_huddle_valid(u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p where p.id=u and p.archived_at is null and p.onboarding_complete and
 ((p.registration_kind='Member' and p.membership_status='Active') or (p.registration_kind='Staff' and exists(select 1 from public.occci_staff_assignments s where s.user_id=u and s.role in ('Admin','DM','BM','Staff','BC')))));
$$;
create or replace function public.occci_huddle_scope(u uuid,branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(u) and ((branch is null and dist is null) or
 exists(select 1 from public.occci_staff_assignments s where s.user_id=u and (s.role='Admin' or
 (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or
 (s.role in ('BM','Staff','BC') and (s.branch_id=branch or (branch is null and exists(select 1 from public.occci_branches b where b.id=s.branch_id and b.district=dist)))))) or
 exists(select 1 from public.occci_profiles p where p.id=u and p.registration_kind='Member' and (p.branch_id=branch or (branch is null and exists(select 1 from public.occci_branches b where b.id=p.branch_id and b.district=dist)))));
$$;
create or replace function public.occci_huddle_host_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and
 (s.role='Admin' or (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or (s.role in ('BM','Staff','BC') and branch=s.branch_id)));
$$;
create or replace function public.occci_huddle_member(sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_huddle_sessions h where h.id=sid and public.occci_huddle_scope(auth.uid(),h.branch_id,h.district) and
 (h.host_id=auth.uid() or exists(select 1 from public.occci_huddle_attendees a where a.session_id=h.id and a.user_id=auth.uid())));
$$;
create or replace function public.occci_huddle_data_scope(branch text,dist smallint) returns boolean language sql stable security definer set search_path='' as $$
 select public.occci_huddle_valid(auth.uid()) and exists(select 1 from public.occci_staff_assignments s where s.user_id=auth.uid() and
 (s.role='Admin' or (s.role='DM' and s.district=coalesce(dist,(select b.district from public.occci_branches b where b.id=branch))) or (s.role in ('BM','Staff','BC') and branch=s.branch_id)));
$$;
-- All writes and reads below run through authenticated RPCs, never direct table mutations.
create or replace function public.occci_huddle_create(label text,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 if not public.occci_huddle_host_scope(branch,dist) then raise exception 'Your position cannot host this operating unit.' using errcode='42501'; end if;
 if length(trim(label)) not between 1 and 150 or (branch is not null and not exists(select 1 from public.occci_branches b where b.id=branch and b.active)) or (dist is not null and dist not between 1 and 6) or (branch is not null and dist is not null) then raise exception 'Choose a valid title and operating unit.'; end if;
 insert into public.occci_huddle_sessions(host_id,title,join_code,branch_id,district) values(auth.uid(),trim(label),upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),branch,dist) returning * into h;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid());
 perform public.occci_log(auth.uid(),h.branch_id,'Huddle created',null,jsonb_build_object('session_id',h.id,'title',h.title,'district',h.district),'Created OCCCI Huddle');
 return to_jsonb(h);
end;$$;
create or replace function public.occci_huddle_join(code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;n integer;
begin
 if not public.occci_huddle_valid(auth.uid()) then raise exception 'An active OCCCI account is required.' using errcode='42501';end if;
 insert into public.occci_huddle_attempts(user_id,attempts) values(auth.uid(),1) on conflict(user_id) do update set
 attempts=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then 1 else public.occci_huddle_attempts.attempts+1 end,
 started_at=case when public.occci_huddle_attempts.started_at<now()-interval '1 minute' then now() else public.occci_huddle_attempts.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('error','Too many join attempts. Wait one minute.');end if;
 select * into h from public.occci_huddle_sessions where join_code=upper(regexp_replace(code,'[^a-zA-Z0-9]','','g')) and status='Active' and expires_at>now() for update;
 if h.id is null or not public.occci_huddle_scope(auth.uid(),h.branch_id,h.district) then return jsonb_build_object('error','This code is invalid, expired or outside your assigned unit.');end if;
 if (select count(*) from public.occci_huddle_attendees where session_id=h.id and left_at is null)>=100 and not exists(select 1 from public.occci_huddle_attendees where session_id=h.id and user_id=auth.uid() and left_at is null) then return jsonb_build_object('error','This Huddle has reached its attendee capacity.');end if;
 insert into public.occci_huddle_attendees(session_id,user_id) values(h.id,auth.uid()) on conflict(session_id,user_id) do update set left_at=null,joined_at=now();
 perform public.occci_log(auth.uid(),h.branch_id,'Huddle joined',null,jsonb_build_object('session_id',h.id,'district',h.district),'Joined OCCCI Huddle');return to_jsonb(h);
end;$$;
create or replace function public.occci_huddle_list() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select h.* from public.occci_huddle_sessions h where public.occci_huddle_member(h.id) order by h.created_at desc limit 30)x;
$$;
create or replace function public.occci_huddle_context(sid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare h public.occci_huddle_sessions;people jsonb;messages jsonb;cards jsonb;host boolean;
begin
 select * into h from public.occci_huddle_sessions where id=sid;
 if h.id is null or not public.occci_huddle_member(sid) or h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended or your access changed.' using errcode='42501';end if;
 host:=h.host_id=auth.uid() and public.occci_huddle_host_scope(h.branch_id,h.district);
 select coalesce(jsonb_agg(jsonb_build_object('user_id',a.user_id,'name',p.full_name,'role',coalesce(s.role,'Member'),'mic_locked',a.mic_locked or (h.mic_locked and a.user_id<>h.host_id),'blocked',not public.occci_huddle_scope(a.user_id,h.branch_id,h.district))),'[]'::jsonb) into people from public.occci_huddle_attendees a join public.occci_profiles p on p.id=a.user_id left join public.occci_staff_assignments s on s.user_id=a.user_id where a.session_id=sid and a.left_at is null;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at),'[]'::jsonb) into messages from (select m.id,m.sender_id,m.body,m.created_at,p.full_name sender_name from public.occci_huddle_messages m join public.occci_profiles p on p.id=m.sender_id where m.session_id=sid order by m.created_at desc limit 60)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into cards from (select c.id,c.sender_id,c.summary,c.created_at from public.occci_huddle_cards c where c.session_id=sid and public.occci_huddle_data_scope(c.branch_id,c.district) order by c.created_at desc limit 10)x;
 return jsonb_build_object('session',to_jsonb(h),'identity',auth.uid(),'name',(select full_name from public.occci_profiles where id=auth.uid()),'role',public.occci_role(),'is_host',host,'participants',people,'messages',messages,'cards',cards,'mic_locked',h.host_id<>auth.uid() and (h.mic_locked or exists(select 1 from public.occci_huddle_attendees a where a.session_id=sid and a.user_id=auth.uid() and a.mic_locked)));
end;$$;
create or replace function public.occci_huddle_command(sid uuid,command text,target uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare h public.occci_huddle_sessions;
begin
 select * into h from public.occci_huddle_sessions where id=sid for update;
 if h.id is null or not public.occci_huddle_member(sid) then raise exception 'Huddle access denied.' using errcode='42501';end if;
 if command='leave' then update public.occci_huddle_attendees set left_at=now() where session_id=sid and user_id=auth.uid();
 else
 if h.host_id<>auth.uid() or not public.occci_huddle_host_scope(h.branch_id,h.district) then raise exception 'Only this Huddle host can manage attendees.' using errcode='42501';end if;
 if command='end' then update public.occci_huddle_sessions set status='Ended',ended_at=now() where id=sid;
 elsif h.status<>'Active' or h.expires_at<=now() then raise exception 'This Huddle ended.';
 elsif command in ('mute_all','allow_all') then update public.occci_huddle_sessions set mic_locked=command='mute_all' where id=sid;update public.occci_huddle_attendees set mic_locked=command='mute_all' where session_id=sid and user_id<>h.host_id;
 elsif command in ('mute','allow') then
 if target is null or target=h.host_id or not exists(select 1 from public.occci_huddle_attendees where session_id=sid and user_id=target and left_at is null) then raise exception 'Choose an attendee in this Huddle.';end if;
 if command='allow' and h.mic_locked then raise exception 'Allow all microphones before enabling an individual attendee.';end if;
 update public.occci_huddle_attendees set mic_locked=command='mute' where session_id=sid and user_id=target;
 else raise exception 'Invalid Huddle command.';end if;end if;
 perform public.occci_log(auth.uid(),h.branch_id,case command when 'mute_all' then 'Huddle attendees muted' when 'allow_all' then 'Huddle microphones allowed' when 'mute' then 'Huddle attendee muted' when 'allow' then 'Huddle microphone allowed' when 'end' then 'Huddle ended' else 'Huddle left' end,null,jsonb_build_object('session_id',sid,'target',target,'district',h.district),'OCCCI Huddle activity');
 return jsonb_build_object('ok',true);
end;$$;
create or replace function public.occci_huddle_chat(sid uuid,message text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.occci_huddle_context(sid);
 if length(trim(message)) not between 1 and 2000 then raise exception 'Message must contain 1 to 2000 characters.';end if;
 insert into public.occci_huddle_messages(session_id,sender_id,body) values(sid,auth.uid(),trim(message));
 perform public.occci_log(auth.uid(),(select branch_id from public.occci_huddle_sessions where id=sid),'Huddle message sent',null,jsonb_build_object('session_id',sid),'Sent a session chat message');
end;$$;
create or replace function public.occci_huddle_summary(sid uuid,branch text default null,dist smallint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform public.occci_huddle_context(sid);
 if not public.occci_huddle_data_scope(branch,dist) or (branch is not null and not exists(select 1 from public.occci_branches b where b.id=branch and b.active)) or (dist is not null and dist not between 1 and 6) or (branch is not null and dist is not null) or (branch is null and dist is null) then raise exception 'Choose a district or branch within your assignment.' using errcode='42501';end if;
 select jsonb_build_object('unit',coalesce((select name||' Branch' from public.occci_branches where id=branch),'District '||dist),'branch_id',branch,'district',coalesce(dist,(select district from public.occci_branches where id=branch)),
 'members',count(*),'verified_records',count(f.member_id),'savings',coalesce(sum(f.savings),0),'share_capital',coalesce(sum(f.share_capital),0),'loans',coalesce(sum(f.loan_balance),0),'active_loans',count(*) filter(where f.loan_balance>0),'as_of',now()) into result
 from public.occci_profiles p join public.occci_branches b on b.id=p.branch_id left join public.occci_financials f on f.member_id=p.id
 where p.archived_at is null and p.registration_kind='Member' and p.membership_status='Active' and not exists(select 1 from public.occci_staff_assignments s where s.user_id=p.id) and (p.branch_id=branch or (branch is null and b.district=dist));
 return result;
end;$$;
create or replace function public.occci_huddle_share(sid uuid,branch text default null,dist smallint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare data jsonb;card public.occci_huddle_cards;
begin
 data:=public.occci_huddle_summary(sid,branch,dist);
 insert into public.occci_huddle_cards(session_id,sender_id,branch_id,district,summary) values(sid,auth.uid(),branch,dist,data) returning * into card;
 perform public.occci_log(auth.uid(),branch,'Huddle data shared',null,jsonb_build_object('session_id',sid,'card_id',card.id,'district',dist),'Shared verified operating unit summary');return to_jsonb(card);
end;$$;
revoke all on function public.occci_huddle_valid(uuid),public.occci_huddle_scope(uuid,text,smallint),public.occci_huddle_host_scope(text,smallint),public.occci_huddle_member(uuid),public.occci_huddle_data_scope(text,smallint) from public,anon,authenticated;
revoke all on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text),public.occci_huddle_list(),public.occci_huddle_context(uuid),public.occci_huddle_command(uuid,text,uuid),public.occci_huddle_chat(uuid,text),public.occci_huddle_summary(uuid,text,smallint),public.occci_huddle_share(uuid,text,smallint) from public,anon;
grant execute on function public.occci_huddle_create(text,text,smallint),public.occci_huddle_join(text),public.occci_huddle_list(),public.occci_huddle_context(uuid),public.occci_huddle_command(uuid,text,uuid),public.occci_huddle_chat(uuid,text),public.occci_huddle_summary(uuid,text,smallint),public.occci_huddle_share(uuid,text,smallint) to authenticated;
insert into public.occci_schema_versions(version) values('024_occci_huddle') on conflict do nothing;
notify pgrst,'reload schema';
commit;

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
