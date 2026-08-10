const fs = require('fs');
const path = 'C:\\Users\\admin\\arab_drama_app\\lib\\features\\payment\\pages\\membership_page.dart';
let text = fs.readFileSync(path, 'utf8');
const before = text.length;
console.log('before length:', before);

// Replace all debugPrint(...) statements with empty (handle multi-line too)
const lines = text.split('\n');
const out = [];
let removed = 0;
for (const line of lines) {
  const trimmed = line.trim();
  if (trimmed.startsWith('debugPrint(')) {
    // drop the line
    removed++;
    continue;
  }
  // Keep the line
  out.push(line);
}
let newText = out.join('\n');
console.log('removed debugPrint lines:', removed);
console.log('after length:', newText.length);
fs.writeFileSync(path, newText, 'utf8');
console.log('written');
