// Keep historical SKUs for receipts; only the five artworks remain purchasable.
export function unifyWallArt(products) {
  const result = products.map(p => ({...p}));
  const works = {
    starry: ['爪印星夜', 'landscape'], mona: ['猫娜丽莎', 'portrait'],
    scream: ['喵的呐喊', 'portrait'], pearl: ['戴珍珠耳环的猫', 'portrait'],
    sunflowers: ['向日葵', 'square'],
  };
  for (const p of result) if (p.kind === 'frame' || p.kind === 'painting') p.active = false;
  function upsert(product) {
    const index = result.findIndex(p => p.sku === product.sku);
    if (index < 0) result.push(product); else result[index] = product;
  }
  for (const [artwork, [label, template]] of Object.entries(works)) {
    upsert({sku: `painting-${artwork}`, label, theme: 'wood', kind: 'painting', placement: 'art',
      geometry: {template, artwork}, price: 30, currency: 'miao', purchase_limit: 1, active: true, is_test: false});
  }
  const destinations = {palace: '故宫', louvre: '卢浮宫', fuji: '富士山', pyramid: '埃及金字塔', eiffel: '埃菲尔铁塔', liberty: '自由女神像'};
  for (const [appearance, prefix, label] of [['black_short', 'calico', '三花旅行照片'], ['light_long', 'longhair', '长毛猫旅行照片']]) {
    for (const [destination, place] of Object.entries(destinations)) {
      upsert({sku: `photo-${appearance}-${destination}`, label: `${label} · ${place}`, theme: 'wood', kind: 'photo', placement: 'art',
        geometry: {template: 'landscape', artwork: prefix + destination[0].toUpperCase() + destination.slice(1)},
        price: null, currency: null, purchase_limit: 1, active: false, is_test: false});
    }
  }
  return result;
}
