const fs = require('fs');
const path = 'C:\\Users\\admin\\arab_drama_app\\_head.txt';
const buf = fs.readFileSync(path);
const marker = Buffer.from('[MembershipPage] ===== VIP');
let idx = buf.indexOf(marker);
if (idx < 0) { console.log('marker not found'); process.exit(0); }
console.log('marker at byte:', idx);
const slice = buf.slice(idx, idx + 100);
console.log('bytes:', slice.toString('hex'));
console.log('bytes list:', Array.from(slice).join(','));

// Scan whole file for EF BF BD sequences
let count = 0;
const positions = [];
for (let i = 0; i < buf.length - 2; i++) {
  if (buf[i] === 0xEF && buf[i+1] === 0xBF && buf[i+2] === 0xBD) {
    count++;
    if (positions.length < 20) positions.push(i);
  }
}
console.log('total EF BF BD sequences:', count);
console.log('first 20 positions:', positions);
for (const p of positions) {
  const c = Math.max(0, p - 30);
  const s = buf.slice(c, p + 30);
  console.log('  @', p, JSON.stringify(s.toString('utf8')));
}
