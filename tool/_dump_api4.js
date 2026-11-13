const fs = require('fs');
const raw = fs.readFileSync('C:/Users/admin/arab_drama_app/api-docs.json', 'utf8');
const doc = JSON.parse(raw.replace(/^\uFEFF/, ''));
const paths = doc.paths || {};
for (const k of ['/api/pay/getOrderIsPay', '/notice/pollOrder', '/api/google/rtdn']) {
  console.log('='.repeat(20), k);
  console.log(JSON.stringify(paths[k], null, 2).slice(0, 1800));
}
