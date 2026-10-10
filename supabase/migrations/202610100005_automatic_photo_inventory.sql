-- Photo rights automatically enter inventory in the same transaction as unlocking.
create function public.issue_photo_inventory(visit uuid, unlocked uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare home uuid; owner_id uuid; cat uuid; appearance_key text; destination_key text; item uuid;
begin
 if num_nonnulls(visit,unlocked)<>1 then raise exception 'One photo source required'; end if;
 if visit is not null then
  select c.family_id,c.owner_id,c.id,c.appearance,v.destination
   into strict home,owner_id,cat,appearance_key,destination_key
   from public.cat_travel_visits v join public.cats c on c.id=v.cat_id where v.id=visit;
 else
  select g.family_id,u.owner_id,u.appearance,u.destination
   into strict home,owner_id,appearance_key,destination_key
   from public.test_photo_unlocks u join public.test_account_grants g on g.request_id=u.grant_id where u.id=unlocked;
 end if;
 perform 1 from public.families where id=home for update;
 select inventory_id into item from public.photo_wall_inventory
  where visit_id=visit or unlock_id=unlocked;
 if item is not null then return item; end if;
 insert into public.furniture_inventory(family_id,sku,purchased_by,source,source_id,source_cat_id)
  values(home,'photo-'||appearance_key||'-'||destination_key,owner_id,'photo',coalesce(visit,unlocked),cat)
  returning id into item;
 insert into public.photo_wall_inventory(family_id,visit_id,unlock_id,inventory_id)
  values(home,visit,unlocked,item);
 return item;
end $$;
revoke all on function public.issue_photo_inventory(uuid,uuid) from public,anon,authenticated,service_role;

create function public.inventory_unlocked_photo() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='cat_travel_visits' then perform public.issue_photo_inventory(new.id,null);
 else perform public.issue_photo_inventory(null,new.id); end if;
 return new;
end $$;
revoke all on function public.inventory_unlocked_photo() from public,anon,authenticated,service_role;
create trigger inventory_travel_photo after insert on public.cat_travel_visits
 for each row execute function public.inventory_unlocked_photo();
create trigger inventory_test_photo after insert on public.test_photo_unlocks
 for each row execute function public.inventory_unlocked_photo();

-- Existing rights are also preserved as hangable instances; no wallet/layout changes.
do $$ declare photo record;
begin
 for photo in select id from public.cat_travel_visits order by id loop
  perform public.issue_photo_inventory(photo.id,null);
 end loop;
 for photo in select id from public.test_photo_unlocks order by id loop
  perform public.issue_photo_inventory(null,photo.id);
 end loop;
end $$;
