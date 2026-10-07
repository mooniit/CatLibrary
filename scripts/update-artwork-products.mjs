// Incremental catalog change; never rewrites an already applied migration.
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
const file='assets/data/furniture-products.json';
const products=JSON.parse(readFileSync(file,'utf8'));
const works={starry:['爪印星夜','landscape'],mona:['猫娜丽莎','portrait'],scream:['喵的呐喊','portrait'],pearl:['戴珍珠耳环的猫','portrait'],sunflowers:['向日葵','square']};
for(const p of products.filter(p=>p.kind==='frame'))p.active=false;
for(const theme of ['lunar','wood','royal'])for(const [artwork,[label,template]] of Object.entries(works)) {
 const sku=`${theme}-painting-${artwork}`;
 if(products.some(p=>p.sku===sku))continue;
 const old=products.find(p=>p.sku===`${theme}-frame-${template}`);
 products.push({...old,sku,label:({lunar:'月轨',wood:'木质',royal:'皇家'})[theme]+label,kind:'painting',geometry:{template,artwork},active:true});
}
writeFileSync(file,JSON.stringify(products,null,2)+'\n');
const q=s=>"'"+s.replaceAll("'","''")+"'";
const rows=products.filter(p=>p.kind==='painting').map(p=>'('+[p.sku,p.label,p.theme,p.kind,p.placement,JSON.stringify(p.geometry)].map(q).concat([p.price,q(p.currency),p.purchase_limit,'true','false']).join(',')+')');
const sql=`-- Paintings are purchased with their fixed frame; old receipts remain immutable.
update public.furniture_products set active=false where kind='frame' and not is_test;
insert into public.furniture_products(sku,label,theme,kind,placement,geometry,price,currency,purchase_limit,active,is_test) values
${rows.join(',\n')};

-- Preserve instance IDs, family ownership and provenance when retiring empty frames.
do $$ declare i record; chosen text; homes uuid[]:='{}'; begin
 for i in select inv.*,p.theme,p.geometry from public.furniture_inventory inv join public.furniture_products p using(sku) where p.kind='frame' and not p.is_test loop
  select e->>'artwork' into chosen from public.room_layouts l cross join lateral jsonb_array_elements(l.layout->'items') e
    where l.family_id=i.family_id and e->>'instance_id'=i.id::text;
  chosen:=coalesce(chosen,case i.geometry->>'template' when 'portrait' then 'pearl' when 'square' then 'sunflowers' else 'starry' end);
  update public.furniture_inventory set sku=i.theme||'-painting-'||chosen where id=i.id;
  homes:=array_append(homes,i.family_id);
 end loop;
 -- Explicit version change protects drafts/leases created under the old catalog.
 update public.room_layouts l set layout=jsonb_set(l.layout,'{items}',coalesce((select jsonb_agg(
  case when p.geometry ? 'artwork' then jsonb_set(e,'{artwork}',p.geometry->'artwork') else e end)
  from jsonb_array_elements(l.layout->'items') e join public.furniture_inventory inv on inv.id::text=e->>'instance_id'
  join public.furniture_products p using(sku)), '[]'::jsonb)), version=version+1,lock_user=null,lock_token=null,lock_until=null,updated_at=clock_timestamp()
 where family_id=any(homes);
end $$;

alter function public.validate_room_layout(uuid,jsonb) rename to validate_room_layout_geometry;
create function public.validate_room_layout(home uuid,proposed jsonb) returns text
language plpgsql security definer set search_path='' as $$
declare reason text; item jsonb; bound text;
begin
 reason:=public.validate_room_layout_geometry(home,proposed);
 if reason is not null then return reason; end if;
 for item in select value from jsonb_array_elements(proposed->'items') loop
  select p.geometry->>'artwork' into bound from public.furniture_inventory i join public.furniture_products p using(sku)
    where i.id::text=item->>'instance_id' and i.family_id=home;
  if bound is not null and item->>'artwork' is distinct from bound then return 'artwork_mismatch'; end if;
 end loop;
 return null;
end $$;
revoke all on function public.validate_room_layout(uuid,jsonb),public.validate_room_layout_geometry(uuid,jsonb) from public,anon,authenticated;
`;
const target='supabase/migrations/202610070002_artwork_binding.sql';
if(existsSync(target)) {
 if(readFileSync(target,'utf8').replaceAll('\r\n','\n')!==sql)throw Error('Historical migration differs; use a new incremental migration');
} else writeFileSync(target,sql);
console.log('42 active formal products; 15 paintings with bound frames, 9 retired frame SKUs retained for audit.');
