const fs = require('fs');
const p = 'C:\\Users\\admin\\arab_drama_app\\build\\web\\main.dart.js';
const st = fs.statSync(p);
console.log('size:', st.size, 'mtime:', st.mtime.toISOString());
const buf = fs.readFileSync(p);
const m = Buffer.from('[MembershipPage]');
let from = 0; let i; let count = 0;
while ((i = buf.indexOf(m, from)) >= 0) { count++; from = i + 1; }
console.log('[MembershipPage] count:', count);
// Count U+FFFD literal escape sequences \ufffd
const lit = Buffer.from('\\ufffd');
let lcount = 0; from = 0;
while ((i = buf.indexOf(lit, from)) >= 0) { lcount++; from = i + 1; }
console.log('\\ufffd literal count:', lcount);
let efbd = 0;
for (let j = 0; j < buf.length - 2; j++) {
  if (buf[j] === 0xEF && buf[j+1] === 0xBF && buf[j+2] === 0xBD) efbd++;
}
console.log('EF BF BD byte count:', efbd);