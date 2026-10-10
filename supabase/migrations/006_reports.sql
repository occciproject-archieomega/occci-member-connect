-- Apply after 005_member_documents.sql. Private managerial reports; no member data is copied.
begin;
create table if not exists public.occci_report_types(
 id text primary key, category text not null check(category in ('Assembly','Compliance','District','Cluster','Work')),
 name text not null, guidance text not null default '', active boolean not null default true);
insert into public.occci_report_types(id,category,name,guidance) values
('staff-daily','Work','Daily staff work report','Daily branch work, source documents and actual transaction totals.'),
('staff-weekly','Work','Weekly staff work report','Seven-day summary of branch work and actual transaction totals.'),
('staff-monthly','Work','Monthly staff work report','Calendar-month summary of branch work and actual transaction totals.'),
('assembly-minutes','Assembly','Minutes of the last general assembly','Proceedings, attendance, resolutions and approvals.'),
('board-report','Assembly','Consolidated Board of Directors report','Management performance, operations, achievements and strategic updates.'),
('committee-report','Assembly','Committee report','Audit, Election, Ethics or another committee. Identify the committee in the title.'),
('assembly-afs','Assembly','Audited financial statements','Attach the signed statements and auditor report; identify the external auditor.'),
('budget-program','Assembly','Proposed budget and program of activities','Plans and financial projections for assembly consideration.'),
('capr','Compliance','Cooperative Annual Progress Report (CAPR)','Record the prepared report and submission acknowledgement.'),
('compliance-afs','Compliance','Audited financial statements package','Statements, management responsibility, auditor opinion, representation and notes.'),
('social-audit','Compliance','Social audit report','Socio-civic programs and related activities.'),
('performance-audit','Compliance','Performance audit report','Governance, management and financial performance.'),
('officers-training','Compliance','List of officers and mandatory training','Officers and completed or undertaken training.'),
('mediation','Compliance','Semi-annual mediation and conciliation report','Specify the reporting half-year in the period.'),
('sworn-statement','Compliance','Sworn statement of cooperative officers','Attach the signed prescribed statement.'),
('atir-abr','Compliance','Annual tax incentives / benefits reports','Applicable to cooperatives with a certificate of tax exemption.'),
('coc-record','Compliance','Certificate of Compliance and payment record','Receipt, acknowledgement and certificate tracking.'),
('district-management','District','Consolidated district management report','Branch operations, membership and verified financial growth.'),
('district-credit','District','District financial and credit performance','Approved balances; attach source documents for assets, provisions and surplus.'),
('district-resolutions','District','District resolutions and proposals','Policy proposals, regional budgets and recorded decisions.'),
('district-election','District','District Election Committee report','Candidate screening, election returns and delegates.'),
('cluster-performance','Cluster','Branch performance and local updates','Membership recruitment, verified savings and branch programs.'),
('cluster-credit','Cluster','Loan portfolio and delinquency review','Approved loan balances and overdue status; attach collection records.'),
('cluster-welfare','Cluster','Member benefit and welfare report','Scholarships, insurance, calamity aid and other branch programs.'),
('cluster-election','Cluster','Cluster minutes and delegate election report','Attendance, resolutions, elected delegates and election results.')
on conflict(id) do nothing;
create table if not exists public.occci_reports(
 id uuid primary key default gen_random_uuid(), type_id text not null references public.occci_report_types(id), title text not null,
 district smallint check(district between 1 and 6), branch_id text references public.occci_branches(id),
 period_start date not null, period_end date not null, meeting_date date, due_date date,
 status text not null default 'Draft' check(status in ('Draft','For review','Approved','Returned','Filed')),
 summary text not null default '', details jsonb not null default '{}', documents jsonb not null default '[]',
 created_by uuid not null references auth.users(id), reviewer uuid references auth.users(id), review_note text,
 filed_on date, filing_reference text, revision integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), archived_at timestamptz,
 check(period_end>=period_start), check(jsonb_typeof(documents)='array'), check(jsonb_typeof(details)='object'));
create table if not exists public.occci_report_events(
 id bigint generated always as identity primary key, report_id uuid not null references public.occci_reports(id),
 actor uuid not null references auth.users(id), actor_name text, actor_role text,
 action text not null, before_data jsonb, after_data jsonb, note text not null, created_at timestamptz not null default now());
create index if not exists occci_report_scope_idx on public.occci_reports(district,branch_id,period_start);
create index if not exists occci_report_event_idx on public.occci_report_events(report_id,created_at);
create or replace function public.occci_report_access(d smallint,b text,write_access boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce((public.occci_role()='Admin' or (public.occci_role()='DM' and d=public.occci_district()) or (public.occci_role()='BM' and b is not null and public.occci_can_read_branch(b)) or (not write_access and public.occci_role() in ('DM','BM') and d is null and b is null)),false);
$$;
alter table public.occci_report_types enable row level security;
alter table public.occci_reports enable row level security;
alter table public.occci_report_events enable row level security;
revoke all on public.occci_report_types,public.occci_reports,public.occci_report_events from public,anon,authenticated;
grant select on public.occci_report_types,public.occci_reports,public.occci_report_events to authenticated;
drop policy if exists occci_report_types_read on public.occci_report_types;
create policy occci_report_types_read on public.occci_report_types for select to authenticated using((public.occci_role() in ('Admin','DM','BM') or public.occci_role()='Staff' and category='Work'));
drop policy if exists occci_reports_read on public.occci_reports;
create policy occci_reports_read on public.occci_reports for select to authenticated using(public.occci_report_access(district,branch_id,false));
drop policy if exists occci_report_events_read on public.occci_report_events;
create policy occci_report_events_read on public.occci_report_events for select to authenticated using(exists(select 1 from public.occci_reports r where r.id=report_id and public.occci_report_access(r.district,r.branch_id,false)));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('occci-reports','occci-reports',false,10485760,null) on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=null;
drop policy if exists occci_report_upload on storage.objects;
create policy occci_report_upload on storage.objects for insert to authenticated with check(bucket_id='occci-reports' and public.occci_role() in ('Admin','DM','BM','Staff') and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and public.occci_role() in ('Admin','DM','BM') and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',name)))));
create or replace function public.occci_save_report(target uuid,values_json jsonb,expected_revision integer,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.occci_reports; result_id uuid; d smallint; b text; category_value text; doc jsonb; docs jsonb; total bigint:=0; seen text[]:='{}';
begin
 if public.occci_role() not in ('Admin','DM','BM') or coalesce(length(trim(reason)),0)<3 then raise exception 'Manager access and reason / comments / notes are required';end if;
 if target is not null then
  select * into old from public.occci_reports where id=target for update;
  if not found or old.archived_at is not null or not public.occci_report_access(old.district,old.branch_id,true) then raise exception 'Report editing is not permitted';end if;
  if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before saving';end if;
  if old.status not in ('Draft','Returned') then raise exception 'Only draft or returned reports can be edited';end if;
 end if;
 b:=nullif(values_json->>'branch_id','');d:=nullif(values_json->>'district','')::smallint;
 if b is not null then select district into d from public.occci_branches where id=b and active;if not found then raise exception 'Choose an active branch';end if;end if;
 if not public.occci_report_access(d,b,true) then raise exception 'Report scope is outside your assignment';end if;
 select category into category_value from public.occci_report_types where id=values_json->>'type_id' and active;
 if not found then raise exception 'Choose an active report type';end if;
 if category_value='Work' then raise exception 'Staff work reports require the BM approval workflow';end if;
 if category_value='Compliance' and (d is not null or b is not null) then raise exception 'Annual compliance records use cooperative scope';end if;
 if category_value='District' and (d is null or b is not null) then raise exception 'District assembly reports need a district scope';end if;
 if category_value='Cluster' and b is null then raise exception 'Cluster meeting reports need a branch';end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 3 and 150 or coalesce(length(values_json->>'summary'),0)>10000 or coalesce(values_json->>'period_start','')='' or coalesce(values_json->>'period_end','')='' or (values_json->>'period_end')::date<(values_json->>'period_start')::date then raise exception 'Provide title and a valid reporting period';end if;
 if jsonb_typeof(coalesce(values_json->'details','{}')) is distinct from 'object' or length(coalesce(values_json->'details','{}')::text)>30000 then raise exception 'Invalid report details';end if;
 if coalesce((values_json->'details'->>'attended')::integer,0)<0 or coalesce((values_json->'details'->>'eligible')::integer,0)<0 or (values_json->'details'->>'attended')::integer>(values_json->'details'->>'eligible')::integer then raise exception 'Attendance must be non-negative and cannot exceed eligible participants';end if;
 docs:=coalesce(values_json->'documents','[]');
 if jsonb_typeof(docs) is distinct from 'array' or jsonb_array_length(docs)>10 then raise exception 'Attach at most 10 original documents';end if;
 for doc in select * from jsonb_array_elements(docs) loop
  if not exists(select 1 from storage.objects where bucket_id='occci-reports' and name=doc->>'path') or (coalesce(doc->>'path','') not like auth.uid()::text||'/%' and not coalesce(old.documents,'[]') @> jsonb_build_array(jsonb_build_object('path',doc->>'path'))) then raise exception 'Upload new files to your own private folder';end if;
  if coalesce(length(doc->>'name'),0) not between 1 and 255 or coalesce((doc->>'size')::bigint,0) not between 1 and 10485760 or (doc->>'path')=any(seen) then raise exception 'Invalid document name, size or duplicate attachment';end if;
  total:=total+(doc->>'size')::bigint;seen:=array_append(seen,doc->>'path');
 end loop;
 if total>52428800 then raise exception 'Attachments exceed 50 MB total';end if;
 if target is null then
  insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,meeting_date,due_date,summary,details,documents,created_by)
  values(values_json->>'type_id',trim(values_json->>'title'),d,b,(values_json->>'period_start')::date,(values_json->>'period_end')::date,nullif(values_json->>'meeting_date','')::date,nullif(values_json->>'due_date','')::date,coalesce(values_json->>'summary',''),coalesce(values_json->'details','{}'),docs,auth.uid()) returning id into result_id;
 else
  update public.occci_reports set type_id=values_json->>'type_id',title=trim(values_json->>'title'),district=d,branch_id=b,period_start=(values_json->>'period_start')::date,period_end=(values_json->>'period_end')::date,meeting_date=nullif(values_json->>'meeting_date','')::date,due_date=nullif(values_json->>'due_date','')::date,summary=coalesce(values_json->>'summary',''),details=coalesce(values_json->'details','{}'),documents=docs,revision=revision+1,updated_at=now() where id=target;result_id:=target;
 end if;
 insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(result_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),case when target is null then 'Report created' else 'Report updated' end,to_jsonb(old),(select to_jsonb(r) from public.occci_reports r where id=result_id),reason);
 return result_id;
end;$$;
create or replace function public.occci_report_transition(target uuid,decision text,expected_revision integer,reason text,filed_date date default null,reference text default null) returns void language plpgsql security definer set search_path='' as $$
declare old public.occci_reports; new_status text;
begin
 select * into old from public.occci_reports where id=target for update;
 if not found or not public.occci_report_access(old.district,old.branch_id,true) or coalesce(length(trim(reason)),0)<3 then raise exception 'Report action is not permitted; provide reason / comments / notes';end if;
 if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before continuing';end if;
 if decision='Restore' then
  if old.archived_at is null then raise exception 'Report is not archived';end if;
  update public.occci_reports set archived_at=null,revision=revision+1,updated_at=now() where id=target;
 else
  if old.archived_at is not null then raise exception 'Restore the archived report first';end if;
  if decision='Archive' then update public.occci_reports set archived_at=now(),revision=revision+1,updated_at=now() where id=target;
  else
   if decision='Submit' and old.status in ('Draft','Returned') then
    if length(trim(old.summary))<3 or jsonb_array_length(old.documents)=0 then raise exception 'Add a summary and source documents before review';end if;new_status:='For review';
   elsif decision in ('Approve','Return') and old.status='For review' then
    if old.created_by=auth.uid() and not (public.occci_role()='Admin' and old.district is null and old.branch_id is null) then raise exception 'A different authorized manager must review this report';end if;
    new_status:=case decision when 'Approve' then 'Approved' else 'Returned' end;
   elsif decision='File' and old.status='Approved' then
    if filed_date is null or filed_date>current_date or coalesce(length(trim(reference)),0)<3 then raise exception 'Record a valid filing date and acknowledgement reference';end if;new_status:='Filed';
   else raise exception 'This action does not match the current report status';end if;
   update public.occci_reports set status=new_status,reviewer=case when decision in ('Approve','Return') then auth.uid() else reviewer end,review_note=case when decision in ('Approve','Return') then reason else review_note end,filed_on=case when decision='File' then filed_date else filed_on end,filing_reference=case when decision='File' then trim(reference) else filing_reference end,revision=revision+1,updated_at=now() where id=target;
  end if;
 end if;
 insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(target,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Report '||lower(decision),to_jsonb(old),(select to_jsonb(r) from public.occci_reports r where id=target),reason);
end;$$;
-- Staff prepares work reports privately; a branch manager publishes the approved record.
create table if not exists public.occci_work_reports(
 id uuid primary key default gen_random_uuid(), created_by uuid not null references auth.users(id),
 branch_id text not null references public.occci_branches(id), district smallint not null,
 frequency text not null check(frequency in ('Daily','Weekly','Monthly')), title text not null,
 period_start date not null,period_end date not null, summary text not null default '', metrics jsonb not null default '{}',
 documents jsonb not null default '[]',status text not null default 'Draft' check(status in ('Draft','For review','Approved','Returned')),
 review_note text,reviewer uuid references auth.users(id), published_report uuid references public.occci_reports(id),
 revision integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(period_end>=period_start),check(jsonb_typeof(metrics)='object'),check(jsonb_typeof(documents)='array'));
create unique index if not exists occci_work_approved_period on public.occci_work_reports(created_by,frequency,period_start,period_end) where status='Approved';
create table if not exists public.occci_work_report_events(
 id bigint generated always as identity primary key,work_report_id uuid not null references public.occci_work_reports(id),
 actor uuid not null references auth.users(id),actor_name text,actor_role text,action text not null,
 before_data jsonb,after_data jsonb,note text not null,created_at timestamptz not null default now());
create or replace function public.occci_work_access(owner_id uuid,b text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (owner_id=auth.uid() or public.occci_role() in ('Admin','DM','BM') and public.occci_can_read_branch(b));
$$;
alter table public.occci_work_reports enable row level security;
alter table public.occci_work_report_events enable row level security;
revoke all on public.occci_work_reports,public.occci_work_report_events from public,anon,authenticated;
grant select on public.occci_work_reports,public.occci_work_report_events to authenticated;
drop policy if exists occci_work_reports_read on public.occci_work_reports;
create policy occci_work_reports_read on public.occci_work_reports for select to authenticated using(public.occci_work_access(created_by,branch_id));
drop policy if exists occci_work_events_read on public.occci_work_report_events;
create policy occci_work_events_read on public.occci_work_report_events for select to authenticated using(exists(select 1 from public.occci_work_reports w where w.id=work_report_id and public.occci_work_access(w.created_by,w.branch_id)));
-- Managers retain branch-scoped documents; staff sees only their own staged work.
drop policy if exists occci_report_document_read on storage.objects;
create policy occci_report_document_read on storage.objects for select to authenticated using(bucket_id='occci-reports' and ((public.occci_role() in ('Admin','DM','BM','Staff') and (storage.foldername(name))[1]=auth.uid()::text) or exists(select 1 from public.occci_reports r where public.occci_report_access(r.district,r.branch_id,false) and r.documents @> jsonb_build_array(jsonb_build_object('path',name))) or exists(select 1 from public.occci_work_reports w where public.occci_work_access(w.created_by,w.branch_id) and w.documents @> jsonb_build_array(jsonb_build_object('path',name)))));
create or replace function public.occci_save_work_report(target uuid,values_json jsonb,expected_revision integer,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;assignment public.occci_staff_assignments;result_id uuid;start_date date;end_date date;freq text;doc jsonb;docs jsonb;total bigint:=0;seen text[]:='{}';entry record;metrics_value jsonb;
begin
 select * into assignment from public.occci_staff_assignments where user_id=auth.uid() and role='Staff';
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Staff assignment and reason / comments / notes are required';end if;
 if target is not null then
  select * into old from public.occci_work_reports where id=target for update;
  if not found or old.created_by<>auth.uid() or old.branch_id<>assignment.branch_id or old.status not in ('Draft','Returned') then raise exception 'Only your draft or returned work report can be edited';end if;
  if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before saving';end if;
 end if;
 freq:=values_json->>'frequency';start_date:=(values_json->>'period_start')::date;end_date:=(values_json->>'period_end')::date;
 if freq is null or freq not in ('Daily','Weekly','Monthly') or start_date is null or end_date is null or (freq='Daily' and end_date<>start_date) or (freq='Weekly' and (end_date<>start_date+6 or extract(isodow from start_date)<>1)) or (freq='Monthly' and (extract(day from start_date)<>1 or end_date<>(date_trunc('month',start_date)+interval '1 month - 1 day')::date)) then raise exception 'Use one day, seven days, or a complete calendar month for the report period';end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 3 and 150 or coalesce(length(values_json->>'summary'),0)>10000 then raise exception 'Provide a valid title and work summary';end if;
 metrics_value:=coalesce(values_json->'metrics','{}');
 if jsonb_typeof(metrics_value) is distinct from 'object' then raise exception 'Invalid work totals';end if;
 for entry in select * from jsonb_each_text(metrics_value) loop
  if entry.key not in ('registrations','account_updates','savings_collections','loan_releases','loan_repayments','followups') or entry.value is null or entry.value::numeric<0 or entry.value::numeric>99999999999999 then raise exception 'Invalid work totals';end if;
  if entry.key in ('registrations','account_updates','followups') and entry.value::numeric<>trunc(entry.value::numeric) then raise exception 'Work counts must be whole numbers';end if;
 end loop;
 docs:=coalesce(values_json->'documents','[]');
 if jsonb_typeof(docs) is distinct from 'array' or jsonb_array_length(docs)>10 then raise exception 'Attach at most 10 source documents';end if;
 for doc in select * from jsonb_array_elements(docs) loop
  if coalesce(doc->>'path','') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-reports' and name=doc->>'path') or coalesce(length(doc->>'name'),0) not between 1 and 255 or coalesce((doc->>'size')::bigint,0) not between 1 and 10485760 or (doc->>'path')=any(seen) then raise exception 'Invalid private source attachment';end if;
  total:=total+(doc->>'size')::bigint;seen:=array_append(seen,doc->>'path');
 end loop;
 if total>52428800 then raise exception 'Source documents exceed 50 MB';end if;
 if target is null then
  insert into public.occci_work_reports(created_by,branch_id,district,frequency,title,period_start,period_end,summary,metrics,documents)
  values(auth.uid(),assignment.branch_id,(select district from public.occci_branches where id=assignment.branch_id),freq,trim(values_json->>'title'),start_date,end_date,coalesce(values_json->>'summary',''),metrics_value,docs) returning id into result_id;
 else
  update public.occci_work_reports set frequency=freq,title=trim(values_json->>'title'),period_start=start_date,period_end=end_date,summary=coalesce(values_json->>'summary',''),metrics=metrics_value,documents=docs,revision=revision+1,updated_at=now() where id=target;result_id:=target;
 end if;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(result_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),case when target is null then 'Work report created' else 'Work report updated' end,to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=result_id),reason);
 return result_id;
end;$$;
create or replace function public.occci_work_report_transition(target uuid,decision text,expected_revision integer,reason text) returns void language plpgsql security definer set search_path='' as $$
declare old public.occci_work_reports;report_id uuid;state text;
begin
 select * into old from public.occci_work_reports where id=target for update;
 if not found or coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a valid work report and reason / comments / notes';end if;
 if old.revision is distinct from expected_revision then raise exception 'Report changed; refresh before continuing';end if;
 if decision='Submit' then
  if public.occci_role()<>'Staff' or old.created_by<>auth.uid() or not public.occci_can_read_branch(old.branch_id) or old.status not in ('Draft','Returned') then raise exception 'Only Staff can submit their own draft or returned report';end if;
  if length(trim(old.summary))<3 or jsonb_array_length(old.documents)=0 then raise exception 'Add a work summary and original documents before BM review';end if;state:='For review';
 elsif decision in ('Approve','Return') then
  if public.occci_role()<>'BM' or not public.occci_can_read_branch(old.branch_id) or old.created_by=auth.uid() or old.status<>'For review' then raise exception 'Only the assigned BM can review submitted branch staff work';end if;
  state:=case decision when 'Approve' then 'Approved' else 'Returned' end;
  if decision='Approve' then
   if exists(select 1 from public.occci_work_reports w where w.created_by=old.created_by and w.frequency=old.frequency and w.period_start=old.period_start and w.period_end=old.period_end and w.status='Approved') then raise exception 'An approved report already exists for this staff member and period';end if;
   insert into public.occci_reports(type_id,title,district,branch_id,period_start,period_end,status,summary,details,documents,created_by,reviewer,review_note)
   values('staff-'||lower(old.frequency),old.title,old.district,old.branch_id,old.period_start,old.period_end,'Approved',old.summary,old.metrics||jsonb_build_object('frequency',old.frequency,'staff_work_id',old.id),old.documents,old.created_by,auth.uid(),reason) returning id into report_id;
   insert into public.occci_report_events(report_id,actor,actor_name,actor_role,action,after_data,note)
   values(report_id,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Staff work approved and published',(select to_jsonb(r) from public.occci_reports r where id=report_id),reason);
  end if;
 else raise exception 'Choose submit, approve or return';end if;
 update public.occci_work_reports set status=state,reviewer=case when decision in ('Approve','Return') then auth.uid() else reviewer end,review_note=case when decision in ('Approve','Return') then reason else review_note end,published_report=coalesce(report_id,published_report),revision=revision+1,updated_at=now() where id=target;
 insert into public.occci_work_report_events(work_report_id,actor,actor_name,actor_role,action,before_data,after_data,note)
 values(target,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),public.occci_role(),'Work report '||lower(decision),to_jsonb(old),(select to_jsonb(w) from public.occci_work_reports w where id=target),reason);
end;$$;
revoke all on function public.occci_work_access(uuid,text),public.occci_save_work_report(uuid,jsonb,integer,text),public.occci_work_report_transition(uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.occci_work_access(uuid,text),public.occci_save_work_report(uuid,jsonb,integer,text),public.occci_work_report_transition(uuid,text,integer,text) to authenticated;
revoke all on function public.occci_report_access(smallint,text,boolean),public.occci_save_report(uuid,jsonb,integer,text),public.occci_report_transition(uuid,text,integer,text,date,text) from public,anon,authenticated;
grant execute on function public.occci_report_access(smallint,text,boolean),public.occci_save_report(uuid,jsonb,integer,text),public.occci_report_transition(uuid,text,integer,text,date,text) to authenticated;
insert into public.occci_schema_versions values('006_reports') on conflict do nothing;
notify pgrst,'reload schema';
commit;
