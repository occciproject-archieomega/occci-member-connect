-- Apply after 013. Verified share capital and branch-scoped cashier receipts.
-- Existing share capital stays unknown until verified; no contribution percentage is assumed.
begin;
alter table public.occci_financials add column if not exists share_capital numeric(16,2);
do $$ begin
 if not exists(select 1 from pg_catalog.pg_constraint where conname='occci_share_capital_valid' and conrelid='public.occci_financials'::regclass) then
  alter table public.occci_financials add constraint occci_share_capital_valid check(share_capital is null or (share_capital>=0 and share_capital<>'NaN'::numeric));
 end if;
end;$$;

-- These validators are private. Authenticated clients use the scoped public operations below.
create or replace function public.occci_cashier_amount(values_json jsonb,field_name text) returns numeric language plpgsql immutable set search_path='' as $$
declare value_text text:=trim(coalesce(values_json->>field_name,'0'));
begin
 if value_text !~ '^[0-9]{1,14}([.][0-9]{1,2})?$' then raise exception 'Use a nonnegative amount with at most two decimal places for %',replace(field_name,'_',' ');end if;
 return value_text::numeric;
end;$$;
create or replace function public.occci_validate_financial_additions(values_json jsonb) returns void language plpgsql immutable set search_path='' as $$
declare item jsonb; paid numeric; amount numeric;
begin
 if values_json ? 'share_capital' and values_json->>'share_capital' is not null then
  perform public.occci_cashier_amount(values_json,'share_capital');
 end if;
 if jsonb_typeof(values_json->'schedule')='array' then
  for item in select * from jsonb_array_elements(values_json->'schedule') loop
   if item ? 'paid_amount' then
    paid:=public.occci_cashier_amount(item,'paid_amount');
    amount:=public.occci_cashier_amount(item,'amount');
    if paid>amount then raise exception 'Scheduled paid amount cannot exceed the installment amount';end if;
   end if;
  end loop;
 end if;
end;$$;

create table if not exists public.occci_cashier_payments(
 id uuid primary key,
 member_id uuid not null references public.occci_profiles(id),
 branch_id text not null references public.occci_branches(id),
 member_name text not null,
 account_number text not null,
 cashier_id uuid not null references auth.users(id),
 cashier_name text not null,
 receipt_number text not null check(length(receipt_number) between 3 and 80),
 payment_date date not null,
 principal_amount numeric(16,2) not null check(principal_amount>=0),
 interest_amount numeric(16,2) not null check(interest_amount>=0),
 fees_amount numeric(16,2) not null check(fees_amount>=0),
 savings_amount numeric(16,2) not null check(savings_amount>=0),
 share_capital_amount numeric(16,2) not null check(share_capital_amount>=0),
 total_amount numeric(16,2) generated always as (principal_amount+interest_amount+fees_amount+savings_amount+share_capital_amount) stored,
 loan_balance_before numeric(16,2) not null,
 loan_balance_after numeric(16,2) not null,
 savings_before numeric(16,2) not null,
 savings_after numeric(16,2) not null,
 share_capital_before numeric(16,2),
 share_capital_after numeric(16,2),
 schedule_index integer,
 schedule_date date,
 revision_before integer not null,
 revision_after integer not null,
 note text not null,
 created_at timestamptz not null default now(),
 constraint occci_cashier_positive_total check(total_amount>0),
 constraint occci_cashier_nonnegative_balance check(loan_balance_after>=0 and savings_after>=0 and (share_capital_after is null or share_capital_after>=0))
);
create unique index if not exists occci_cashier_receipt_unique on public.occci_cashier_payments(branch_id,lower(receipt_number));
create index if not exists occci_cashier_member_date on public.occci_cashier_payments(member_id,payment_date desc,created_at desc);
alter table public.occci_cashier_payments enable row level security;
revoke all on public.occci_cashier_payments from public,anon,authenticated;
grant select on public.occci_cashier_payments to authenticated;
drop policy if exists occci_cashier_read on public.occci_cashier_payments;
create policy occci_cashier_read on public.occci_cashier_payments for select to authenticated using(
 auth.uid() is not null and (member_id=auth.uid() or
 (public.occci_can_read_branch(branch_id) and exists(select 1 from public.occci_profiles p where p.id=member_id and public.occci_can_read_profile(p.id,p.branch_id))))
);

create or replace function public.occci_submit_change(target uuid,request_kind text,values_json jsonb,evidence text,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; r text:=public.occci_role(); request_id uuid; rev integer; item jsonb;
begin
 select * into p from public.occci_profiles where id=target;
 if not found or not public.occci_can_read_branch(p.branch_id) or r not in ('DM','BM','Staff','BC') or p.archived_at is not null then raise exception 'Request is not permitted';end if;
 if coalesce(length(trim(reason)),0)<3 then raise exception 'Provide a request note';end if;
 if request_kind='Profile edit' then rev:=p.revision;
 elsif request_kind='Financial sync' then
 if r not in ('BM','Staff','BC') then raise exception 'Branch Staff, BC or BM submit actual balances; the assigned DM performs final approval';end if;
 perform public.occci_validate_financial_additions(values_json);
 if p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=target) then raise exception 'Choose a cooperative member';end if;
 if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates'; end if;
 if coalesce(evidence,'') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects where bucket_id='occci-documents' and name=evidence) then raise exception 'Upload a source document first';end if;
 if lower(coalesce(values_json->>'savings','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'loan_balance','')) in ('nan','infinity','-infinity') or lower(coalesce(values_json->>'annual_interest','')) in ('nan','infinity','-infinity') then raise exception 'Finite financial amounts are required';end if;
 if coalesce(values_json->>'source_reference','')='' or (values_json->>'as_of')::date is null or (values_json->>'savings')::numeric<0 or (values_json->>'loan_balance')::numeric<0 or (values_json->>'annual_interest')::numeric not between 0 and 100 or values_json->>'loan_status' is null or values_json->>'loan_status' not in ('No active loan','Active','Paid','Overdue','Restructured') or coalesce(jsonb_typeof(values_json->'schedule'),'')<>'array' then raise exception 'Invalid financial details'; end if;
 if values_json->>'savings' is null or values_json->>'loan_balance' is null or values_json->>'annual_interest' is null then raise exception 'Financial amounts are required';end if;
 if jsonb_array_length(values_json->'schedule')>360 then raise exception 'Use at most 360 scheduled payments';end if;
 for item in select * from jsonb_array_elements(values_json->'schedule') loop
 if coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(item->>'status','') not in ('Scheduled','Paid','Overdue','Rescheduled','Cancelled') then raise exception 'Invalid payment date or status';end if;
 if lower(coalesce(item->>'amount','')) in ('nan','infinity','-infinity') then raise exception 'Invalid payment schedule';end if;
 if (item->>'date')::date is null or item->>'amount' is null or (item->>'amount')::numeric<0 then raise exception 'Invalid payment schedule';end if;
 end loop;
 select coalesce((select revision from public.occci_financials where member_id=target),0) into rev;
 else raise exception 'Invalid request type';end if;
 insert into public.occci_change_requests(member_id,branch_id,kind,proposed,base_revision,submitted_by,evidence_path,note,workflow_version) values(target,p.branch_id,request_kind,values_json,rev,auth.uid(),evidence,reason,2) returning id into request_id;
 perform public.occci_log(target,p.branch_id,'Request submitted',null,jsonb_build_object('request_id',request_id,'kind',request_kind,'proposed',values_json),reason);
 if request_kind='Financial sync' and r='BM' then
 update public.occci_change_requests set status='BM approved',bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 perform public.occci_log(target,p.branch_id,'Financial request screened by BM',null,jsonb_build_object('request_id',request_id,'status','BM approved'),reason);
 end if;
 return request_id;
end;$$;

create or replace function public.occci_review_change(request_id uuid,decision text,reason text) returns void language plpgsql security definer set search_path='' as $$
declare q public.occci_change_requests; r text:=public.occci_role(); f public.occci_financials; p public.occci_profiles; v jsonb; target_status text;
begin
 -- Keep the current role and district stable while recording this decision.
 perform pg_catalog.pg_advisory_xact_lock(771004);
 r:=public.occci_role();
 select * into q from public.occci_change_requests where id=request_id for update;
 if not found or not public.occci_can_read_branch(q.branch_id) then raise exception 'Review requires an authorized reviewer in the assigned branch or district';end if;
 -- A recorded BM screening survives reassignment of that account to this district's DM.
 -- Profile edits and membership requests retain their separate-reviewer requirement.
 if q.submitted_by=auth.uid() and not (q.kind='Financial sync' and q.status='BM approved' and r='DM' and q.bm_reviewer is not null) then raise exception 'Review requires a different authorized reviewer in the assigned branch or district';end if;
 if decision is null or decision not in ('Approve','Reject') or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Choose a decision and provide a review note';end if;
 if q.kind='Profile edit' then
  if r not in ('BM','DM') or q.status<>'Pending' then raise exception 'Profile edits require the assigned BM or DM approval';end if;
  target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
  update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
 elsif q.kind in ('Financial sync','Membership approval') then
  if q.status='Pending' and q.kind='Financial sync' and r='BM' then
   target_status:=case decision when 'Approve' then 'BM approved' else 'Rejected' end;
   update public.occci_change_requests set status=target_status,bm_reviewer=auth.uid(),review_note=trim(reason),reviewed_at=now() where id=request_id;
  elsif q.status='BM approved' and r='DM' and q.bm_reviewer is not null and (q.kind='Financial sync' or q.bm_reviewer<>auth.uid()) then
   target_status:=case decision when 'Approve' then 'Applied' else 'Rejected' end;
   if decision='Approve' then
    select * into p from public.occci_profiles where id=q.member_id for update;
    if not found or p.archived_at is not null or p.branch_id<>q.branch_id or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) then raise exception 'Member scope/status changed; submit a new request';end if;
    v:=q.proposed;
    if q.kind='Membership approval' then
     if p.membership_status<>'Pending verification' or not p.onboarding_complete or p.revision<>q.base_revision then raise exception 'Member details changed; obtain a new BM screening';end if;
     perform public.occci_assign_account(q.member_id,v->>'account_number',reason);
     update public.occci_profiles set membership_status='Active',revision=revision+1 where id=q.member_id;
     perform public.occci_log(q.member_id,q.branch_id,'Membership approved by DM',to_jsonb(p),jsonb_build_object('membership_status','Active','account_number',v->>'account_number','request_id',q.id),reason);
    else
     if p.membership_status<>'Active' or p.account_number is null then raise exception 'Only approved active memberships can receive financial updates';end if;
     perform public.occci_validate_financial_additions(v);
     select * into f from public.occci_financials where member_id=q.member_id for update;
     if coalesce(f.revision,0)<>q.base_revision then raise exception 'Financial record changed; submit a new request';end if;
     insert into public.occci_financials(member_id,savings,share_capital,loan_balance,loan_status,annual_interest,schedule,source_reference,evidence_path,evidence_files,as_of,revision)
     values(q.member_id,(v->>'savings')::numeric,case when v ? 'share_capital' and v->>'share_capital' is not null then (v->>'share_capital')::numeric else f.share_capital end,(v->>'loan_balance')::numeric,v->>'loan_status',(v->>'annual_interest')::numeric,v->'schedule',v->>'source_reference',q.evidence_path,q.evidence_files,(v->>'as_of')::date,q.base_revision+1)
     on conflict(member_id) do update set savings=excluded.savings,share_capital=excluded.share_capital,loan_balance=excluded.loan_balance,loan_status=excluded.loan_status,annual_interest=excluded.annual_interest,schedule=excluded.schedule,source_reference=excluded.source_reference,evidence_path=excluded.evidence_path,evidence_files=excluded.evidence_files,as_of=excluded.as_of,revision=excluded.revision,updated_at=now();
     perform public.occci_log(q.member_id,q.branch_id,'Financial record synchronized by DM',to_jsonb(f),v,reason);
    end if;
   end if;
   update public.occci_change_requests set status=target_status,dm_reviewer=auth.uid(),admin_reviewer=null,review_note=trim(reason),reviewed_at=now() where id=request_id;
  else raise exception 'BM screening is required before final approval by the assigned District Manager';end if;
 else raise exception 'Unknown request type';end if;
 perform public.occci_log(q.member_id,q.branch_id,'Request reviewed',jsonb_build_object('status',q.status),jsonb_build_object('request_id',request_id,'kind',q.kind,'status',target_status),reason);
end;$$;

-- A cashier records new receipts against an already DM-verified balance.
-- Principal reduces the loan; interest, fees and capital contributions do not.
-- Profile/financial locks, revision checks and unique receipt IDs prevent duplicate or stale posting.
create or replace function public.occci_record_cashier_payment(target uuid,values_json jsonb,expected_revision integer,client_reference uuid,reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.occci_profiles; f public.occci_financials; existing public.occci_cashier_payments; posted public.occci_cashier_payments;
 principal numeric; interest numeric; fees numeric; savings numeric; capital numeric; total numeric;
 receipt text:=trim(values_json->>'receipt_number'); paid_on date; installment integer;
 remaining_loan numeric; next_capital numeric; next_savings numeric; next_schedule jsonb; item jsonb;
 paid_to_date numeric; installment_amount numeric; installment_paid numeric; due_date date; next_status text;
 today_ph date:=(now() at time zone 'Asia/Manila')::date;
begin
 perform pg_catalog.pg_advisory_xact_lock(771004);
 if auth.uid() is null or public.occci_role()<>'BC' then raise exception 'Only the assigned Branch Cashier can record payments';end if;
 select * into p from public.occci_profiles where id=target for update;
 if not found or p.archived_at is not null or p.membership_status<>'Active' or p.account_number is null or not p.onboarding_complete or p.registration_kind='Staff' or exists(select 1 from public.occci_staff_assignments where user_id=p.id) or not public.occci_can_read_branch(p.branch_id) then
  raise exception 'Choose an approved cooperative member in your assigned branch';end if;
 if jsonb_typeof(values_json) is distinct from 'object' or client_reference is null or coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Provide a receipt, payment details and notes';end if;
 if coalesce(receipt,'') !~ '^[A-Za-z0-9][A-Za-z0-9 /._#-]{2,79}$' then raise exception 'Enter the official receipt number using 3 to 80 valid characters';end if;
 if coalesce(values_json->>'payment_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Choose a valid payment date';end if;
 paid_on:=(values_json->>'payment_date')::date;
 if paid_on>today_ph or paid_on<date '1900-01-01' then raise exception 'Payment date cannot be in the future';end if;
 principal:=public.occci_cashier_amount(values_json,'principal_amount');
 interest:=public.occci_cashier_amount(values_json,'interest_amount');
 fees:=public.occci_cashier_amount(values_json,'fees_amount');
 savings:=public.occci_cashier_amount(values_json,'savings_amount');
 capital:=public.occci_cashier_amount(values_json,'share_capital_amount');
 total:=principal+interest+fees+savings+capital;
 if total<=0 or total>99999999999999.99 then raise exception 'Enter a positive payment or deposit amount';end if;
 installment:=nullif(values_json->>'schedule_index','')::integer;
 if installment is not null and installment<0 then raise exception 'Choose a valid payment schedule entry';end if;
 -- Exact retries return the original receipt without another balance change or audit entry.
 select * into existing from public.occci_cashier_payments where id=client_reference;
 if found then
  if existing.cashier_id<>auth.uid() or existing.member_id<>target or existing.receipt_number<>receipt or existing.payment_date<>paid_on or existing.principal_amount<>principal or existing.interest_amount<>interest or existing.fees_amount<>fees or existing.savings_amount<>savings or existing.share_capital_amount<>capital or existing.schedule_index is distinct from installment or existing.note<>trim(reason) then
   raise exception 'This payment reference was already used for different details';end if;
  return to_jsonb(existing);
 end if;
 if exists(select 1 from public.occci_cashier_payments c where c.branch_id=p.branch_id and lower(c.receipt_number)=lower(receipt)) then raise exception 'This receipt number is already recorded in your branch';end if;
 select * into f from public.occci_financials where member_id=target for update;
 if not found then raise exception 'The member needs a DM-verified financial record before receiving payments';end if;
 if expected_revision is null or f.revision<>expected_revision then raise exception 'The member balance changed. Refresh the member before recording payment';end if;
 if principal>f.loan_balance then raise exception 'Principal paid cannot exceed the outstanding loan balance';end if;
 if capital>0 and f.share_capital is null then raise exception 'Verify the opening share capital balance through BM and DM before adding a contribution';end if;
 remaining_loan:=f.loan_balance-principal; next_savings:=f.savings+savings;
 next_capital:=case when f.share_capital is null then null else f.share_capital+capital end;
 next_schedule:=f.schedule;
 if installment is not null then
  if principal+interest<=0 or installment>=jsonb_array_length(f.schedule) then raise exception 'Choose an unpaid installment for the principal and interest payment';end if;
  item:=f.schedule->installment;
  if coalesce(item->>'status','Scheduled') in ('Paid','Cancelled') then raise exception 'This installment is already paid or cancelled';end if;
  installment_amount:=public.occci_cashier_amount(item,'amount');
  paid_to_date:=public.occci_cashier_amount(item,'paid_amount');
  installment_paid:=paid_to_date+principal+interest;
  if installment_amount<=0 or installment_paid>installment_amount then raise exception 'Payment exceeds the remaining installment. Use an unallocated payment for extra principal';end if;
  due_date:=(item->>'date')::date;
  next_status:=case when installment_paid=installment_amount then 'Paid' when due_date<today_ph then 'Overdue' when item->>'status'='Rescheduled' then 'Rescheduled' else 'Scheduled' end;
  next_schedule:=jsonb_set(f.schedule,array[installment::text],item||jsonb_build_object('paid_amount',installment_paid,'status',next_status));
 end if;
 insert into public.occci_cashier_payments(id,member_id,branch_id,member_name,account_number,cashier_id,cashier_name,receipt_number,payment_date,principal_amount,interest_amount,fees_amount,savings_amount,share_capital_amount,loan_balance_before,loan_balance_after,savings_before,savings_after,share_capital_before,share_capital_after,schedule_index,schedule_date,revision_before,revision_after,note)
 values(client_reference,target,p.branch_id,p.full_name,p.account_number,auth.uid(),(select full_name from public.occci_profiles where id=auth.uid()),receipt,paid_on,principal,interest,fees,savings,capital,f.loan_balance,remaining_loan,f.savings,next_savings,f.share_capital,next_capital,installment,due_date,f.revision,f.revision+1,trim(reason))
 returning * into posted;
 update public.occci_financials set loan_balance=remaining_loan,savings=next_savings,share_capital=next_capital,schedule=next_schedule,
 loan_status=case when f.loan_balance>0 and remaining_loan=0 then 'Paid' else f.loan_status end,
 as_of=greatest(f.as_of,paid_on),revision=f.revision+1,updated_at=now() where member_id=target;
 perform public.occci_log(target,p.branch_id,'Cashier payment posted',
 jsonb_build_object('loan_balance',f.loan_balance,'savings',f.savings,'share_capital',f.share_capital,'schedule',f.schedule),
 jsonb_build_object('payment_id',posted.id,'receipt_number',receipt,'payment_date',paid_on,'principal_amount',principal,'interest_amount',interest,'fees_amount',fees,'savings_amount',savings,'share_capital_amount',capital,'total_amount',total,'loan_balance',remaining_loan,'savings',next_savings,'share_capital',next_capital,'schedule',next_schedule),reason);
 return to_jsonb(posted);
end;$$;
revoke all on function public.occci_cashier_amount(jsonb,text),public.occci_validate_financial_additions(jsonb) from public,anon,authenticated;
revoke all on function public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text) from public,anon,authenticated;
grant execute on function public.occci_record_cashier_payment(uuid,jsonb,integer,uuid,text),public.occci_submit_change(uuid,text,jsonb,text,text),public.occci_review_change(uuid,text,text) to authenticated;
insert into public.occci_schema_versions(version) values('014_member_dashboard_cashier') on conflict do nothing;
notify pgrst,'reload schema';
commit;

