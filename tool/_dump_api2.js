const fs = require('fs');
const raw = fs.readFileSync('C:/Users/admin/arab_drama_app/api-docs.json', 'utf8');
const doc = JSON.parse(raw.replace(/^\uFEFF/, ''));
const paths = doc.paths || {};
for (const k of ['/api/google/rtdn', '/api/pay/userRechange', '/api/rechargeGoodsConfig/list']) {
  console.log('='.repeat(20), k);
  console.log(JSON.stringify(paths[k], null, 2).slice(0, 2500));
}
const schemas = (doc.components && doc.components.schemas) || {};
console.log('schema keys:', Object.keys(schemas).join(', '));
console.log('PayRequestBO:', JSON.stringify(schemas['PayRequestBO'], null, 2));
