const fs = require('fs');
const { execSync } = require('child_process');
const buf = execSync('git -C "C:\\Users\\admin\\arab_drama_app" show HEAD:lib/features/payment/pages/membership_page.dart', { encoding: null });
console.log('blob size', buf.length);
fs.writeFileSync('C:\\Users\\admin\\arab_drama_app\\_blob.txt', buf);
const b = fs.readFileSync('C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart');
console.log('working size', b.length);
console.log('equal:', buf.length === b.length);
const c = require('crypto');
console.log('blob hash', c.createHash('sha256').update(buf).digest('hex'));
console.log('working hash', c.createHash('sha256').update(b).digest('hex'));

// scan blob for marker
const m = Buffer.from('[MembershipPage]');
let from = 0; let i; let count = 0;
while ((i = buf.indexOf(m, from)) >= 0) { count++; from = i + 1; }
console.log('MembershipPage count in blob:', count);