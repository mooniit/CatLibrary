import {readFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(new URL('../assets/data/furniture-economy.json',import.meta.url),'utf8'));
export function approvedEconomy(theme,kind) {
  const price=config.base_prices[kind]*config.theme_multipliers[theme];
  if(!Number.isInteger(price)||price<=0)throw Error('Missing approved price: '+theme+' '+kind);
  return {price,currency:config.currency,purchase_limit:config.purchase_limit,active:true};
}
