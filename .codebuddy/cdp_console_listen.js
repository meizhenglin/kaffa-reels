// 接入 Chrome DevTools Protocol 抓取页面 console 输出
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');

const OUT = process.env.TEMP + '\\web_console_log2.txt';
const PAGE_ID = 'B67FA26BB3FD86FA0C47EDFE3000AA72';
const PORT = 11256;

try { fs.unlinkSync(OUT); } catch (e) {}
const log = (s) => { try { fs.appendFileSync(OUT, s + '\n'); } catch (e) {} };

const key = crypto.randomBytes(16).toString('base64');
const req = http.request({
  host: '127.0.0.1',
  port: PORT,
  path: `/devtools/page/${PAGE_ID}`,
  headers: {
    Connection: 'Upgrade',
    Upgrade: 'websocket',
    'Sec-WebSocket-Key': key,
    'Sec-WebSocket-Version': '13',
  },
});
req.end();

req.on('response', (res) => {
  log(`HTTP ${res.statusCode} (no upgrade)`);
  let body = '';
  res.on('data', (c) => (body += c));
  res.on('end', () => { log(`body: ${body}`); process.exit(1); });
});

req.on('upgrade', (res, socket) => {
  log(`C ${new Date().toLocaleTimeString('zh-CN', { hour12: false })} CDP connected`);
  const send = (obj) => {
    const data = Buffer.from(JSON.stringify(obj));
    const mask = crypto.randomBytes(4);
    let header;
    if (data.length < 126) header = Buffer.from([0x81, 0x80 | data.length]);
    else if (data.length < 65536) header = Buffer.from([0x81, 0x80 | 126, data.length >> 8, data.length & 0xff]);
    else header = Buffer.from([0x81, 0x80 | 127, 0, 0, 0, 0, data.length >>> 24 & 0xff, data.length >>> 16 & 0xff, data.length >>> 8 & 0xff, data.length & 0xff]);
    const masked = Buffer.from(data.map((b, i) => b ^ mask[i % 4]));
    socket.write(Buffer.concat([header, mask, masked]));
  };

  send({ id: 1, method: 'Runtime.enable' });
  send({ id: 2, method: 'Log.enable' });

  let buf = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (true) {
      if (buf.length < 2) return;
      const len0 = buf[1] & 0x7f;
      let off = 2, len = len0;
      if (len0 === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len0 === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (buf.length < off + len) return;
      const payload = buf.slice(off, off + len);
      buf = buf.slice(off + len);
      handle(payload);
    }
  });

  const handle = (payload) => {
    let msg;
    try { msg = JSON.parse(payload.toString('utf8')); } catch (e) { return; }
    const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    if (msg.method === 'Runtime.consoleAPICalled') {
      const { type, args } = msg.params;
      const text = args.map((a) => {
        if (a.value !== undefined) return String(a.value);
        if (a.description) return a.description;
        return a.type || '';
      }).join(' ');
      log(`${ts} [${type}] ${text}`);
    } else if (msg.method === 'Log.entryAdded') {
      log(`${ts} [${msg.params.entry.level}] ${msg.params.entry.text}`);
    } else if (msg.method === 'Runtime.exceptionThrown') {
      log(`${ts} [EXCEPTION] ${JSON.stringify(msg.params.exceptionDetails).slice(0, 500)}`);
    }
  };

  socket.on('error', (e) => log(`socket error: ${e.message}`));
  socket.on('close', () => log(`C closed`));
});

req.on('error', (e) => { log(`connect error: ${e.message}`); process.exit(1); });
