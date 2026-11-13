const fs = require('fs');
const raw = fs.readFileSync('C:/Users/admin/arab_drama_app/api-docs.json', 'utf8');
const doc = JSON.parse(raw.replace(/^\uFEFF/, ''));
const paths = doc.paths || {};
console.log(Object.keys(paths).join('\n'));
console.log('--- schemas ---');
const schemas = (doc.components && doc.components.schemas) || {};
for (const k of ['PayRequestBO', 'RechargeGoodsConfigRequestBO', 'ApiResponse']) {
  console.log('==', k, JSON.stringify(schemas[k], null, 2));
}
