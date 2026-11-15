// 接入 Flutter VM Service，抓取 Stdout/Log 流，输出到文件
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');

const OUT = process.env.TEMP + '\\web_console_log.txt';
const URL_PATH = '/2SSo1XCG09I=/ws';

try { fs.unlinkSync(OUT); } catch (e) {}
const log = (s) => { try { fs.appendFileSync(OUT, s + '\n'); } catch (e) {} };

const key = crypto.randomBytes(16).toString('base64');
const req = http.request({
  host: '127.0.0.1',
  port: 8497,
  path: URL_PATH,
  headers: {
    Connection: 'Upgrade',
    Upgrade: 'websocket',
    'Sec-WebSocket-Key': key,
    'Sec-WebSocket-Version': '13',
    Origin: 'http://localhost',
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
  log(`C ${new Date().toLocaleTimeString('zh-CN', { hour12: false })} connected`);
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

  send({ jsonrpc: '2.0', id: 1, method: 'streamListen', params: { streamId: 'Stdout' } });
  send({ jsonrpc: '2.0', id: 2, method: 'streamListen', params: { streamId: 'Log' } });

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
    if (msg.event === 'stdout' || msg.event === 'stderr') {
      log(`${ts} ${Buffer.from(msg.params.bytes, 'base64').toString('utf8').trim()}`);
    } else if (msg.event === 'Log') {
      log(`${ts} [Log:${msg.params.kind}] ${msg.params.logRecord.message}`);
    }
  };

  socket.on('error', (e) => log(`socket error: ${e.message}`));
  socket.on('close', () => log(`C closed`));
});

req.on('error', (e) => { log(`connect error: ${e.message}`); process.exit(1); });
