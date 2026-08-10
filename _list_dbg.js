const { execSync } = require('child_process');
const fs = require('fs');
const buf = execSync('git -C "C:\\Users\\admin\\arab_drama_app" show HEAD:lib/features/payment/pages/membership_page.dart', { encoding: null });
const text = buf.toString('utf8');
const lines = text.split('\n');
const hits = [];
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('[MembershipPage]')) {
    hits.push({ n: i + 1, t: lines[i].trim() });
  }
}
console.log('total hits:', hits.length);
for (const h of hits) console.log(h.n + ': ' + h.t);