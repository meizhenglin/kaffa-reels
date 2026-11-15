// 临时调试脚本：通过 CDP 读取运行中 Flutter Web 页面的 console 输出
//
// 用法：
//   node tool/_cdp_log.js 13853 install    在页面里装一个 console 缓冲钩子
//   node tool/_cdp_log.js 13853 dump [pat] 打印缓冲里匹配 pat 的行
//   node tool/_cdp_log.js 13853 res  [pat] 打印资源加载耗时（.ts / .m3u8）
const http = require('http');
const WebSocket = require('ws');

const PORT = process.argv[2] || '13853';
const MODE = process.argv[3] || 'install';
const PAT = process.argv[4] || '';

function getJson(path) {
  return new Promise((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port: PORT, path }, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

const INSTALL = `(() => {
  if (window.__cbLogs) return 'already:' + window.__cbLogs.length;
  window.__cbLogs = [];
  const push = (level, args) => {
    try {
      const s = args.map((a) => {
        if (typeof a === 'string') return a;
        try { return JSON.stringify(a); } catch (e) { return String(a); }
      }).join(' ');
      window.__cbLogs.push(Date.now() + ' [' + level + '] ' + s);
      if (window.__cbLogs.length > 6000) window.__cbLogs.splice(0, 2000);
    } catch (e) {}
  };
  ['log', 'info', 'warn', 'error', 'debug'].forEach((l) => {
    const orig = console[l] ? console[l].bind(console) : function () {};
    console[l] = function (...args) { push(l, args); orig.apply(null, args); };
  });
  return 'installed';
})()`;

async function main() {
  const targets = await getJson('/json/list');
  const page = targets.find(
    (t) => t.type === 'page' && /^http:\/\/localhost/.test(t.url || '')
  );
  if (!page) {
    console.log('NO_PAGE');
    targets.forEach((t) => console.log(`${t.type} ${t.url}`));
    return;
  }

  const ws = new WebSocket(page.webSocketDebuggerUrl, { perMessageDeflate: false });
  let id = 0;
  const pending = new Map();

  const send = (method, params) =>
    new Promise((resolve) => {
      const mid = ++id;
      pending.set(mid, resolve);
      ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
    });

  let defaultContextId = null;
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.method === 'Runtime.executionContextCreated') {
      const ctx = msg.params && msg.params.context;
      if (ctx && ctx.auxData && ctx.auxData.isDefault) defaultContextId = ctx.id;
    }
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result);
      pending.delete(msg.id);
    }
  });

  await new Promise((r) => ws.on('open', r));
  await send('Runtime.enable');

  if (MODE.startsWith('nav:')) {
    // nav:<url>|<waitMs>|<filter>
    const parts = MODE.slice(4).split('|');
    const url = parts[0];
    const waitMs = parseInt(parts[1] || '30000', 10);
    const filter = parts.slice(2).join('|');
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Page.addScriptToEvaluateOnNewDocument', { source: INSTALL });
    await send('Runtime.evaluate', { expression: `location.href=${JSON.stringify(url)}` });
    await new Promise((r) => setTimeout(r, waitMs));
    const dumpParams = {
      expression: `JSON.stringify((window.__cbLogs||[]).filter((l) => ${JSON.stringify(
        filter
      )} === '' || new RegExp(${JSON.stringify(filter)}, 'i').test(l)))`,
      returnByValue: true,
    };
    if (defaultContextId != null) dumpParams.contextId = defaultContextId;
    const dump = await send('Runtime.evaluate', dumpParams);
    let arr = [];
    try {
      arr = JSON.parse((dump && dump.result && dump.result.value) || '[]');
    } catch (e) {}
    arr.forEach((l) => console.log(l));
    console.log('--- total ' + arr.length + ' ---');
    ws.close();
    process.exit(0);
  }

  if (MODE.startsWith('shot:')) {
    const fs = require('fs');
    const out = MODE.slice(5);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(out, Buffer.from(shot.data, 'base64'));
    console.log('SHOT ' + out);
    ws.close();
    process.exit(0);
  }

  let expr;
  if (MODE.startsWith('eval:')) {
    expr = MODE.slice(5);
  } else if (MODE === 'install') {
    expr = INSTALL;
  } else if (MODE === 'dump') {
    expr = `JSON.stringify((window.__cbLogs || []).filter((l) => ${JSON.stringify(
      PAT
    )} === '' || new RegExp(${JSON.stringify(PAT)}, 'i').test(l)))`;
  } else {
    expr = `JSON.stringify(performance.getEntriesByType('resource')
      .filter((e) => /\\.(ts|m3u8)(\\?|$)/.test(e.name))
      .map((e) => e.name.split('/').pop() + ' dur=' + Math.round(e.duration) +
        ' size=' + (e.transferSize || e.encodedBodySize) +
        ' start=' + Math.round(e.startTime)))`;
  }

  const res = await send('Runtime.evaluate', {
    expression: expr,
    returnByValue: true,
    awaitPromise: false,
  });
  const value = res && res.result ? res.result.value : undefined;
  console.log('MODE=' + MODE.slice(0, 60) + ' url=' + page.url);
  if (MODE === 'install' || MODE.startsWith('eval:')) {
    console.log(value);
  } else {
    let arr = [];
    try {
      arr = JSON.parse(value || '[]');
    } catch (e) {
      console.log('RAW:', value);
    }
    arr.forEach((l) => console.log(l));
    console.log('--- total ' + arr.length + ' ---');
  }
  ws.close();
  process.exit(0);
}

main().catch((e) => {
  console.log('ERR ' + e.message);
  process.exit(1);
});
