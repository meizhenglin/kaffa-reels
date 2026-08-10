const fs = require('fs');
const p = 'C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart';
const buf = fs.readFileSync(p);
let text = buf.toString('utf8');
const lines = text.split('\n');
function fixLine(n, repl) {
  if (!lines[n-1].includes('[MembershipPage]')) {
    console.log('SKIP line', n, 'no marker:', lines[n-1].slice(0, 60));
    return false;
  }
  const indent = lines[n-1].match(/^\s*/)[0];
  const newLine = indent + repl;
  if (lines[n-1] === newLine) { console.log('SKIP line', n, 'unchanged'); return false; }
  lines[n-1] = newLine;
  return true;
}
const changes = [];
if (fixLine(77,  "debugPrint('[MembershipPage] ===== VIP status refresh =====');")) changes.push(77);
if (fixLine(82,  "debugPrint('[MembershipPage] refresh_at: ${DateTime.now()}');"))      changes.push(82);
if (fixLine(127, "debugPrint('[MembershipPage] ===== purchase success =====');"))     changes.push(127);
if (fixLine(132, "debugPrint('[MembershipPage] refresh_at: ${DateTime.now()}');"))     changes.push(132);
console.log('changes:', changes);
const out = Buffer.from(lines.join('\n'), 'utf8');
fs.writeFileSync(p, out);
console.log('written, new size:', out.length);

// Re-verify: scan for U+FFFD in file
let efbd = 0;
for (let j = 0; j < out.length - 2; j++) {
  if (out[j] === 0xEF && out[j+1] === 0xBF && out[j+2] === 0xBD) efbd++;
}
console.log('U+FFFD bytes in file:', efbd);