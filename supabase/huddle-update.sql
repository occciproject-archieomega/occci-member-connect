-- OCCCI Huddle update for an existing database with migrations 001-023 installed.
-- Includes migrations 024, 025 and 026; safe to run again.

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

-- Apply after 025. Recognize approved positions independently of signup category.
begin;
create or replace function public.occci_huddle_valid(u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p where p.id=u and p.archived_at is null and p.onboarding_complete and
 (exists(select 1 from public.occci_staff_assignments s where s.user_id=p.id and s.role in ('Admin','DM','BM','Staff','BC')) or
  (p.registration_kind='Member' and p.membership_status='Active')));
$$;

-- Current authenticated assignment is authoritative; never accept a client-supplied role.
-- A readiness check prevents a successful legacy list RPC from enabling an incompatible form.
create or replace function public.occci_huddle_permissions() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('role',public.occci_role(),'can_host',public.occci_huddle_host_scope(null,null),
  'can_join',public.occci_huddle_valid(auth.uid()),'database_ready',
  exists(select 1 from public.occci_schema_versions where version='025_occci_huddle_sessions') and
  exists(select 1 from public.occci_schema_versions where version='026_occci_huddle_staff_permissions'));
$$;
revoke all on function public.occci_huddle_valid(uuid) from public,anon,authenticated;
revoke all on function public.occci_huddle_permissions() from public,anon;
grant execute on function public.occci_huddle_permissions() to authenticated;
insert into public.occci_schema_versions(version) values('026_occci_huddle_staff_permissions') on conflict do nothing;
notify pgrst,'reload schema';
commit;

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
