import {readFileSync,writeFileSync} from 'node:fs';
import {approvedEconomy} from './furniture-economy.mjs';
const file='assets/data/furniture-products.json';
const products=JSON.parse(readFileSync(file,'utf8'));
if(products.length!==36||products.some(p=>p.is_test))throw Error('Expected 36 official styles');
for(const p of products)Object.assign(p,approvedEconomy(p.theme,p.kind));
writeFileSync(file,JSON.stringify(products,null,2)+'\n');
const q=s=>"'"+s.replaceAll("'","''")+"'";
const rows=products.map(p=>`(${q(p.sku)},${p.price})`);
writeFileSync('supabase/migrations/202610060006_approved_furniture_prices.sql',
  '-- Confirmed 2026-10-06: official prices, miao currency, one instance of each SKU per household.\n'+
  'update public.furniture_products p set price=v.price,currency=\'miao\',purchase_limit=1,active=true\nfrom (values\n'+
  rows.join(',\n')+'\n) v(sku,price) where p.sku=v.sku and not p.is_test;\n');
console.log('Configured 36 approved products: miao, unique per household');
