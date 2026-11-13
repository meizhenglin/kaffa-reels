# deploy 目录 —— 线上 vs 仓库 对照表

> 实测时间：2026-10-23
> 仓库目录：`deploy/`
> 用途：TikTok App Links 验证文件 + 授权回调页

---

## 一、结论先说

**线上跑的不是仓库里这份**，而且**即使把仓库这份部署上去，也解决不了当前的
`invalid_request`**（原因见最后一节）。

| 文件 | 仓库 `deploy/` | 线上实际 | 一致？ |
|------|---------------|----------|-------|
| `assetlinks.json` | 新旧两个包名（`com.video.storydrama` + `com.video.qahwatvshort`） | `.well-known/` 下是**旧包名单条** + `text/plain`；根路径 `/assetlinks.json` 是**新的** | ❌ |
| `apple-app-site-association` | 289 bytes，iOS bundle id | `.well-known/` 下 **404**；根路径下是**旧的** `C96YS2CU93.com.playlet.qahwatvshorts` | ❌ |
| `tiktok-callback/index.html` | 4063 bytes，**无**自动跳转（诊断页） | 3373 bytes，**有** `location.replace` 跳 apex | ❌ |
| `qahwa-login.html` | 2289 bytes | 未部署 | ❌ |

---

## 二、逐项明细

### 2.1 `assetlinks.json`

**仓库里**（`deploy/assetlinks.json`）——两个包名都在：

```json
[
  { "package_name": "com.video.storydrama",
    "sha256_cert_fingerprints": ["D5:E1:0C:...:C0:64"] },
  { "package_name": "com.video.qahwatvshort",
    "sha256_cert_fingerprints": ["49:11:77:...:F2:E4"] }
]
```

**线上**：

```
403  https://tv.qahwatv.com/.well-known/assetlinks.json    ← CDN 整个目录被拦
200  https://qahwatv.com/.well-known/assetlinks.json       ← 旧包名，Content-Type: text/plain
200  https://tv.qahwatv.com/assetlinks.json                ← 新包名，application/json ✅
200  https://qahwatv.com/assetlinks.json                   ← 新包名，application/json ✅
```

**要点：**
- `tv.qahwatv.com/.well-known/` 下**任何**路径都是 403（连不存在的文件也 403），
  响应头 `Server: openresty` + `via: EA-SGP-EDGE...-CACHE` + `X-CCDN-CacheTTL: 86400`
  → **阿里云 CDN 的目录级拦截规则**，不是文件缺失。
  同一个规则也拦了 `https://qahwatv.com/.well-known/`（目录本身 403，但目录内具体文件能通）。
- 根路径 `/assetlinks.json` 是通的且**内容正确** → 你上次部署更新的是根路径那份。
- **TikTok 服务器只认 `.well-known/`，不做根路径兜底**（Android 自己做兜底，所以
  你手机 `pm get-app-links` 显示 1024 verified）。

### 2.2 `tiktok-callback/index.html`

**仓库里**（4063 bytes）已经**去掉了**自动跳转，只是个诊断页：

```html
<!-- 为什么这里不能再 location.replace 回自己 -->
<!-- replace 到同一地址会造成无限刷新循环（浏览器里打开时）。 -->
```

**线上**（3373 bytes）还是旧版，**带自动跳转**：

```js
const targetUrl = 'https://qahwatv.com/tiktok-callback' + window.location.search;
// 用 replace 而非 href，避免用户按返回键回到这个页面
setTimeout(function () {
  window.location.replace(targetUrl);
}, 100);
```

**影响：** 如果 TikTok 跳到 `tv.qahwatv.com/tiktok-callback/index.html?code=xxx`，
这个 JS 会把用户**再跳到 apex**，而 apex 的 `/tiktok-callback` 是 301 → `/tiktok-callback/`
→ 又回到 `qahwatv.com/tiktok-callback/index.html`（还是那份带跳转的）→ 循环。

正常流程下 Flutter 的 `onNavigationRequest` 会在渲染前拦掉 URL，所以**这个 JS
一般不会执行**；但它会让「在浏览器里手动打开回调链接」的行为变得很奇怪。

### 2.3 `apple-app-site-association`（iOS）

```
404  https://qahwatv.com/.well-known/apple-app-site-association
404  https://qahwatv.com/.well-known/apple-app-site-association
200  https://qahwatv.com/apple-app-site-association
     → {"applinks":{"apps":[],"details":[{"appID":"C96YS2CU93.com.playlet.qahwatvshorts","paths":["*"]}]}}
```

根路径下是**旧** bundle id（`com.playlet.qahwatvshorts`），而 iOS 现在的 bundle id
应该和 `com.video.storydrama` 对应。`.well-known` 那份压根 404。

> iOS 端目前不是阻塞点（你在 Android 上测），但上架前要一起修。

---

## 三、正确的部署方式

TikTok / Android App Links 要求文件在 **`/.well-known/`** 目录下，且
**Content-Type 必须是 `application/json`**（不是 `text/plain`）。

你现在被 CDN 拦了，所以要**二选一**：

### 方案 A（推荐）：让 CDN 放行 `.well-known/`

在阿里云 CDN 控制台把 `.well-known/` 目录的拦截规则去掉，
然后把 `deploy/assetlinks.json` 传到：

```
https://tv.qahwatv.com/.well-known/assetlinks.json
https://qahwatv.com/.well-known/assetlinks.json
```

两个域名都放一份（TikTok 会用你注册的 redirect_uri 的域名去查）。

### 方案 B：改用 `tv.qahwatv.com` 以外的域名

找一个 CDN 不拦 `.well-known` 的域名，比如 `www.qahwatv.com`，
把 redirect URI 换成那个域名，同时在 TikTok Portal 里更新。

### 无论哪个方案，都要做的

1. 确认响应头是 `application/json`（curl -I 检查）
2. `apple-app-site-association` 也要放一份到 `.well-known/`（iOS 用）
3. `tiktok-callback/index.html` 重新部署成**仓库里这份**（去掉自动跳转）

---

## 四、为什么这些**不是**当前 `invalid_request` 的原因

在真机上跑了完整对照矩阵，**所有变体返回的 error 完全一样**：

| # | 请求 | 结果 |
|---|------|------|
| A | 官方 SDK 精确格式（无尾斜杠 + 全参数 + PKCE hex challenge） | `invalid_request` |
| B | 去掉 `redirect_uri` | `param_error` / `error_type=redirect_uri` |
| D | 只留 `client_key` | `param_error` / `error_type=redirect_uri` |
| F | **完全瞎编的 16 位 `client_key`** | `invalid_request` |
| G | 真 key 但去掉全部 Android 参数 | `invalid_request` |
| H | 真 key 但用旧 App 的证书指纹 | `invalid_request` |
| I | 真 key 但去掉 `scope` | `invalid_request` |

- **B/D** 证明 `redirect_uri` 传到了、格式没被拒（否则也是 `param_error`）
- **F** 是**瞎编的 key**，返回的 `invalid_request` 和真 key（A）**一模一样**
  → TikTok 在校验 `client_key` 之前就拒了 → **问题在 TikTok 侧的应用配置**
- **G/H/I** 三个维度差异全被同一个错误吞掉 → 根本没走到那些校验逻辑

所以 deploy 的问题**要修**（不修的话 App Link / 域名归属验证永远过不了），
但**当前这一枪打不中**。真正要查的是 TikTok Developer Portal 那边：

- [ ] `client_key` `awy65nxalrzf8a76` 是否还有效、是否属于正确的应用
- [ ] Login Kit 是否**审核通过**（未通过时授权页会这样报错）
- [ ] redirect URI 是否配在**当前生效的 revision** 里
      （改了要 Create Revision → Submit for review）
- [ ] URL properties → Verify properties 是否验证了 `tv.qahwatv.com`
- [ ] 沙箱/生产环境是否搞混

相关文档：[`tiktok-login-backend.md`](./tiktok-login-backend.md)
