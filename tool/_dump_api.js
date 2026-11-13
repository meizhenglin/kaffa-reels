const fs = require('fs');
const raw = fs.readFileSync('C:/Users/admin/arab_drama_app/api-docs.json', 'utf8');
const doc = JSON.parse(raw.replace(/^\uFEFF/, ''));
const paths = doc.paths || {};
const keys = ['/notice/google', '/api/pay/userRechange', '/api/pay/getOrderIsPay', '/api/user/userPersonalCenter', '/api/rechargeGoodsConfig/list'];
for (const k of keys) {
  console.log('='.repeat(30), k);
  console.log(JSON.stringify(paths[k], null, 2).slice(0, 3000));
}
