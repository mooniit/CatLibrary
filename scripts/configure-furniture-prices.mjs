import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {approvedEconomy} from './furniture-economy.mjs';
const file='assets/data/furniture-products.json';
const products=JSON.parse(readFileSync(file,'utf8'));
const active=products.filter(p=>p.active);
if(active.length!==32||active.some(p=>p.is_test||p.kind==='frame'||p.kind==='photo'||(p.kind==='painting'&&p.sku!==`painting-${p.geometry.artwork}`)))throw Error('Expected 32 official styles with unified wood paintings');
for(const p of active)Object.assign(p,approvedEconomy(p.theme,p.kind));
writeFileSync(file,JSON.stringify(products,null,2)+'\n');
const q=s=>"'"+s.replaceAll("'","''")+"'";
const rows=active.map(p=>`(${q(p.sku)},${p.price})`);
const target=process.argv[2];
if(target){
 if(!/^supabase\/migrations\/\d{12}_[a-z_]+\.sql$/.test(target)||existsSync(target))throw Error('Provide a new migration path; never overwrite applied history');
 writeFileSync(target,
  '-- Confirmed 2026-10-06: official prices, miao currency, one instance of each SKU per household.\n'+
  'update public.furniture_products p set price=v.price,currency=\'miao\',purchase_limit=1,active=true\nfrom (values\n'+
  rows.join(',\n')+'\n) v(sku,price) where p.sku=v.sku and not p.is_test;\n');
}
console.log('Configured 32 approved products: miao, unique per household; historical migrations preserved');
