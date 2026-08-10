const fs = require('fs');
const p = 'C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart';
const buf = fs.readFileSync(p);
const lines = buf.toString('utf8').split('\n');
let removed = 0;
const out = [];
for (const line of lines) {
  if (line.trimStart().startsWith('debugPrint(')) {
    removed++;
    continue;
  }
  out.push(line);
}
const cleaned = out.join('\n');
const cleanedBuf = Buffer.from(cleaned, 'utf8');
// Replace any remaining U+FFFD char with empty
let efbd = 0;
for (let i = 0; i < cleanedBuf.length - 2; i++) {
  if (cleanedBuf[i] === 0xEF && cleanedBuf[i+1] === 0xBF && cleanedBuf[i+2] === 0xBD) efbd++;
}
console.log('removed debugPrint lines:', removed);
console.log('U+FFFD bytes still in file:', efbd);
fs.writeFileSync(p, cleanedBuf);
console.log('written size:', cleanedBuf.length);