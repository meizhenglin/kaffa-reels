const fs = require('fs');
const p = 'C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart';
const buf = fs.readFileSync(p);
const efbd = Buffer.from([0xEF, 0xBF, 0xBD]);
let count = 0;
let i = 0;
while ((i = buf.indexOf(efbd, i)) >= 0) { count++; i += 3; }
console.log('U+FFFD count before:', count);
const cleaned = Buffer.alloc(0);
const out = [];
let last = 0;
for (let i = 0; i < buf.length; i++) {
  if (i + 2 < buf.length && buf[i] === 0xEF && buf[i+1] === 0xBF && buf[i+2] === 0xBD) {
    if (i > last) out.push(buf.slice(last, i));
    last = i + 3;
    i += 2;
  }
}
if (last < buf.length) out.push(buf.slice(last));
const final = Buffer.concat(out);
fs.writeFileSync(p, final);
let newCount = 0;
for (let i = 0; i < final.length - 2; i++) {
  if (final[i] === 0xEF && final[i+1] === 0xBF && final[i+2] === 0xBD) newCount++;
}
console.log('U+FFFD count after:', newCount);
console.log('size:', buf.length, '->', final.length);