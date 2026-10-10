import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {unifyWallArt} from './wall-art-catalog.mjs';
test('catalog export cannot revive themed paintings or sell album rights', () => {
  const source=JSON.parse(readFileSync('assets/data/furniture-products.json','utf8'));
  const result=unifyWallArt(source);
  assert.deepEqual(unifyWallArt(result), result);
  assert.equal(result.filter(p=>p.active).length,32);
  assert.equal(result.filter(p=>p.kind==='painting'&&p.active).length,5);
  assert.equal(result.filter(p=>p.kind==='photo').length,12);
  assert.ok(result.filter(p=>p.kind==='photo').every(p=>!p.active&&p.price===null&&p.theme==='wood'));
  assert.ok(result.filter(p=>p.kind==='painting'&&p.active).every(p=>p.price===30&&p.purchase_limit===1&&p.theme==='wood'));
  assert.ok(source.filter(p=>p.kind==='painting'&&p.sku.includes('-painting-')).every(p=>result.some(q=>q.sku===p.sku&&!q.active)));
  assert.deepEqual(result.filter(p=>p.placement!=='art'),source.filter(p=>p.placement!=='art'));
});
