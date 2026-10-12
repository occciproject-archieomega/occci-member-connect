-- Apply after 022. Private announcement originals and 16:9 member display posters.
begin;
alter table public.occci_content add column if not exists poster_path text;
alter table public.occci_content add column if not exists poster_original_path text;
alter table public.occci_content add column if not exists poster_crop jsonb;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('occci-posters','occci-posters',false,5242880,array['image/jpeg','image/png']) on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png'];
create or replace function public.occci_can_manage_content(unit_branch text,unit_district smallint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_profiles p join public.occci_staff_assignments t on t.user_id=p.id where p.id=auth.uid() and p.archived_at is null and p.onboarding_complete and (t.role='Admin' or t.role='DM' and (unit_branch is not null and exists(select 1 from public.occci_branches b where b.id=unit_branch and b.district=t.district) or unit_branch is null and unit_district=t.district) or t.role='BM' and unit_branch is not null and t.branch_id=unit_branch));
$$;
create or replace function public.occci_can_read_poster(object_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.occci_content c where c.archived_at is null and
 (c.poster_original_path=object_path and public.occci_can_manage_content(c.branch_id,c.district) or c.poster_path=object_path and (public.occci_can_manage_content(c.branch_id,c.district) or c.published and exists(
 select 1 from public.occci_profiles p join public.occci_branches b on b.id=p.branch_id where p.id=auth.uid() and p.archived_at is null and p.onboarding_complete and p.registration_kind<>'Staff' and not exists(select 1 from public.occci_staff_assignments t where t.user_id=p.id) and (c.branch_id is null or c.branch_id=p.branch_id) and (c.district is null or c.district=b.district)
 ) or c.published and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and p.archived_at is null and p.onboarding_complete and (t.role='Admin' or t.role='DM' and (c.branch_id is null and (c.district is null or c.district=t.district) or exists(select 1 from public.occci_branches b where b.id=c.branch_id and b.district=t.district)) or t.role in ('BM','Staff','BC') and (c.branch_id is null and (c.district is null or c.district=(select district from public.occci_branches where id=t.branch_id)) or c.branch_id=t.branch_id))))));
$$;
drop policy if exists occci_poster_insert on storage.objects;
create policy occci_poster_insert on storage.objects for insert to authenticated with check(bucket_id='occci-posters' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.occci_staff_assignments t join public.occci_profiles p on p.id=t.user_id where t.user_id=auth.uid() and t.role in ('Admin','DM','BM') and p.archived_at is null and p.onboarding_complete));
drop policy if exists occci_poster_read on storage.objects;
create policy occci_poster_read on storage.objects for select to authenticated using(bucket_id='occci-posters' and public.occci_can_read_poster(name));
create or replace function public.occci_save_content_poster(record_id text,values_json jsonb,poster_path text,original_path text,crop jsonb,reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare current_row public.occci_content; saved public.occci_content; branch text:=nullif(values_json->>'branch_id',''); district smallint:=nullif(values_json->>'district','')::smallint; display_path text:=nullif(poster_path,''); source_path text:=nullif(original_path,''); recipe jsonb; field text;
begin
 if coalesce(length(trim(reason)),0) not between 3 and 5000 then raise exception 'Reason / Comments / Notes are required';end if;
 if coalesce(record_id,'')<>'' then select * into current_row from public.occci_content where id=record_id::uuid and archived_at is null for update;if not found then raise exception 'Content not found';end if;if not public.occci_can_manage_content(current_row.branch_id,current_row.district) then raise exception 'Content is outside your scope';end if;end if;
 if not public.occci_can_manage_content(branch,district) then raise exception 'Choose content scope within your assignment';end if;
 if district is not null and district not between 1 and 6 then raise exception 'Choose a valid district';end if;
 if branch is not null then if not exists(select 1 from public.occci_branches where id=branch and active) then raise exception 'Choose an active branch';end if;district:=null;end if;
 if coalesce(length(trim(values_json->>'title')),0) not between 1 and 150 or coalesce(length(trim(values_json->>'body')),0)=0 then raise exception 'Title and content are required';end if;
 if values_json->>'kind' not in ('Announcement','Event','Service') or values_json->>'kind' is null then raise exception 'Choose a valid content type';end if;
 if display_path is not null then
  if values_json->>'kind'<>'Announcement' then raise exception 'Posters are available for announcements';end if;
  if source_path is null or source_path=display_path or jsonb_typeof(crop) is distinct from 'object' then raise exception 'Original photo and crop settings are required';end if;
  foreach field in array array['zoom','x','y'] loop if jsonb_typeof(crop->field) is distinct from 'number' then raise exception 'Invalid crop settings';end if;end loop;
  if (crop->>'zoom')::numeric not between 1 and 3 or (crop->>'x')::numeric not between -1 and 1 or (crop->>'y')::numeric not between -1 and 1 then raise exception 'Invalid crop settings';end if;
  if not exists(select 1 from storage.objects where bucket_id='occci-posters' and name=display_path) or (display_path is distinct from current_row.poster_path and display_path not like auth.uid()::text||'/%') then raise exception 'Upload the cropped poster first';end if;
  if not exists(select 1 from storage.objects where bucket_id='occci-posters' and name=source_path) or (source_path is distinct from current_row.poster_original_path and source_path not like auth.uid()::text||'/%') then raise exception 'Upload the original poster first';end if;
  recipe:=jsonb_build_object('zoom',(crop->>'zoom')::numeric,'x',(crop->>'x')::numeric,'y',(crop->>'y')::numeric,'aspect','16:9');
 elsif source_path is not null or crop is not null then raise exception 'Remove both the poster and its crop settings';end if;
 insert into public.occci_content(id,kind,title,body,branch_id,district,event_date,published,created_by,poster_path,poster_original_path,poster_crop)
 values(coalesce(current_row.id,gen_random_uuid()),values_json->>'kind',trim(values_json->>'title'),values_json->>'body',branch,district,nullif(values_json->>'event_date','')::date,coalesce((values_json->>'published')::boolean,false),auth.uid(),display_path,source_path,recipe)
 on conflict(id) do update set kind=excluded.kind,title=excluded.title,body=excluded.body,branch_id=excluded.branch_id,district=excluded.district,event_date=excluded.event_date,published=excluded.published,poster_path=excluded.poster_path,poster_original_path=excluded.poster_original_path,poster_crop=excluded.poster_crop,updated_at=clock_timestamp() returning * into saved;
 perform public.occci_log(null,coalesce(branch,current_row.branch_id),'Content changed',case when current_row.id is null then null else to_jsonb(current_row) end,to_jsonb(saved),reason);
 return saved.id;
end;$$;
revoke all on function public.occci_can_manage_content(text,smallint),public.occci_can_read_poster(text),public.occci_save_content_poster(text,jsonb,text,text,jsonb,text) from public,anon;
grant execute on function public.occci_can_manage_content(text,smallint),public.occci_can_read_poster(text),public.occci_save_content_poster(text,jsonb,text,text,jsonb,text) to authenticated;
insert into public.occci_schema_versions(version) values('023_announcement_posters') on conflict do nothing;
notify pgrst,'reload schema';
commit;
