const fs = require('fs');
const raw = fs.readFileSync('C:/Users/admin/arab_drama_app/api-docs.json', 'utf8');
const doc = JSON.parse(raw.replace(/^\uFEFF/, ''));
const paths = doc.paths || {};
for (const k of Object.keys(paths)) {
  if (/pay|order|notice|vip/i.test(k)) console.log(k);
}
console.log('---- getOrderIsPay ----');
console.log(JSON.stringify(paths['/api/pay/getOrderIsPay'], null, 2).slice(0, 2000));
console.log('---- pollOrder ----');
console.log(JSON.stringify(paths['/notice/pollOrder'], null, 2).slice(0, 2000));
console.log('---- rtdn schema ----');
const schemas = doc.components.schemas;
console.log(JSON.stringify(schemas['SubscriptionNotification'], null, 2).slice(0, 2500));
