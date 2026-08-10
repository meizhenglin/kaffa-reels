const fs = require('fs');
const p = 'C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart';
const text = fs.readFileSync(p, 'utf8');
const lines = text.split('\n');
const issues = [];
for (let i = 0; i < lines.length; i++) {
  const ln = lines[i];
  if (ln.includes('\ufffd') && !ln.trimStart().startsWith('//')) {
    issues.push({ n: i + 1, t: ln.trim() });
  }
}
console.log('non-comment lines containing U+FFFD:', issues.length);
for (const it of issues) console.log(it.n + ': ' + it.t.slice(0, 120));