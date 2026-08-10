const fs = require('fs');
const path = require('path');
const root = 'C:\\Users\\admin\\arab_drama_app\\lib';
function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (e.isFile() && p.endsWith('.dart')) out.push(p);
  }
  return out;
}
const files = walk(root);
console.log('total dart files:', files.length);
let total = 0;
const hits = [];
for (const f of files) {
  const buf = fs.readFileSync(f);
  let c = 0;
  for (let j = 0; j < buf.length - 2; j++) {
    if (buf[j] === 0xEF && buf[j+1] === 0xBF && buf[j+2] === 0xBD) c++;
  }
  if (c > 0) {
    hits.push({ f: f.replace(root, ''), c });
    total += c;
  }
}
hits.sort((a, b) => b.c - a.c);
console.log('total U+FFFD bytes:', total);
for (const h of hits.slice(0, 20)) console.log('  ' + h.c + '  ' + h.f);