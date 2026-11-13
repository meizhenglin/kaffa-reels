# TikTok 登录（Login Kit · Web 流）—— 实现说明与根因分析

> 最后更新：2026-10-27
> 相关代码：`lib/features/auth/services/tiktok_auth_service.dart`

---

## 0-A. 2026-10-27 最终定位：TikTok `error_code = 10002`（已抓到原始响应体）

> 本节是**最终结论**，比下面第 0、1、2 节都更靠后、也更准确。
> 第 0 节说「`source=web` 是唯一缺口」——**这一条也已被证伪**：
> 补上 `source=web` 后**依然**报同样的错。

### 🎯 决定性证据：抓到 TikTok 自己的 `page/detail` 响应体

用 CDP 挂到 app 的 WebView，抓到 TikTok 授权页**自己** POST 的接口
`https://www.tiktok.com/tiktok/v2/oauth/page/detail/?locale=en`，
其请求体和响应体是：

```json
// 请求体（TikTok 自己发的）
{"response_type":"code","client_key":"awy65nxalrzf8a76",
 "scope":"user.info.basic","state":"...","redirect_uri":"https://tv.qahwatv.com/tiktok-callback/index.html",
 "source":"web","locale":"en","auth_version":"v2","app_id":1180}

// 响应体 —— 真正的数字错误码在这里
{"error":"invalid_request","error_code":10002,
 "error_description":"The request parameters are malformed.",
 "extra":{"fatal_item_ids":[],"logid":"202610270612459F4B3D2235751C06CE60","now":1793081565000},
 "page_detail":{},"status_code":0,"status_msg":""}
```

👉 **TikTok 的错误页把 `error_code` 压缩成了 `error=invalid_request`，
并且 `errCode` / `error_type` 全空 —— 所以只看 URL 参数永远拿不到真相。**
必须抓 `page/detail` 的 JSON 响应体。

### 🧪 完整消融实验（每组都是 POST page/detail）

| 变体 | 响应 |
|---|---|
| TikTok 原样的全字段 | `10002` / `The request parameters are malformed.` |
| 去掉 `app_id` | 同上，**完全一致** |
| 去掉 `auth_version` | 同上，**完全一致** |
| 去掉 `source` | 同上，**完全一致** |
| 去掉 `locale` / 去掉 `state` | 同上，**完全一致** |
| `scope=video.list` / `video.upload` / `user.info.basic,video.list` | 同上，**完全一致** |
| **假 scope**（`zzz.fake.scope`） | 同上，**完全一致** |
| **空 scope** | 同上，**完全一致** |
| `redirect_uri` 带 `?x=1`（TikTok 明文禁止） | 同上，**完全一致** |
| `redirect_uri` 带 `#frag`（明文禁止） | 同上，**完全一致** |
| `redirect_uri` 为 `http://`（明文禁止） | 同上，**完全一致** |
| `redirect_uri` 为空 / 完全乱写 `zzz` | 同上，**完全一致** |
| `response_type=token`（非法） | 同上，**完全一致** |
| **缺 `client_key`** | ⬅️ **唯一不同**：`error=invalid_param` / `request bind error` |
| 空 body | `invalid_param` / `request bind error` |

**所有变体的 `fatal_item_ids` 都是 `[]`（空）** —— 说明没有任何一个字段被判为「致命错误」。

### 📌 由消融实验得出的结论

1. **`redirect_uri` 根本没有被校验** —— 一个明显非法（带 query、带 fragment、
   `http://`、乱写）的 URI，和我们合法的 URI，报**一模一样**的错。
   → 失败发生在**更早**的阶段。
2. **`scope` 根本没有被校验** —— 假 scope、空 scope 都一样。
3. 请求在「**把 client_key 绑定到某个 App 产品**」这一步就被拒了
   （缺 `client_key` 时才变成 `invalid_param / request bind error`）。

### ✅ 证明 client_key 本身是好的、且被 TikTok 识别

| 检查 | 结果 |
|---|---|
| authorize 页跳登录页时带 `enter_from=dev_awy65nxalrzf8a76` | ✅ **TikTok 认得这个 client_key**，按 developer app 处理 |
| token 端点 `client_credentials` + 假 secret | `{"error":"invalid_client","error_description":"Client key or secret is incorrect."}` ✅ 走的是**校验 secret** 的分支（说明 client_key 已被识别） |
| token 端点 `authorization_code` + 假 code | `{"error":"invalid_grant","error_description":"Authorization code is expired."}` ✅ 同样先认 client_key |

### 🎯 根因（最终结论）

> **TikTok Developer Portal 里，这个 App 的 Login Kit → Web 产品没有开启/没有生效**
> （或 App 仍处于 Staging，而当前登录的账号没有被加入 Sandbox 的 **Target User**）。

客户端（Flutter 代码、授权 URL、参数、redirect_uri）**全部正确，无需再改**。

**StackOverflow 上完全同症状的问题，答案也是这个**：
> "My app is in Staging, does that prevent the client_key from working? […]
> Hey what worked for me was using the sandbox and **adding target users**.
> Make sure you have target users in the sandbox settings."

### ✅ 顺带确认：域名验证文件已修好

```
https://tv.qahwatv.com/tiktok-verification.txt
https://tv.qahwatv.com/tiktok-developers-site-verification.txt
https://tv.qahwatv.com/.well-known/tiktok-developers-site-verification.txt
https://tv.qahwatv.com/.well-known/tiktok-verification.txt
```
四个路径现在**内容完全一致**（都是 `tiktok-developers-site-verification=WgOC8pILVKBknzqiN35Kyh3pc3gJeAlk`），
之前 `.well-known/tiktok-verification.txt` 多一个 `=` 的问题已修复。
回调页 `https://tv.qahwatv.com/tiktok-callback/index.html` 返回 **200 text/html**。

### 🛠️ 代码改动（本次）

- 移除 `invalid_request` 的**自动重试**（实测重试无效，纯粹浪费时间 + 误导）。
- 错误码从 `tiktok-authorize-code-refused` 改为 `tiktok-app-product-not-enabled`，
  提示文案直接指向 Portal 的 Login Kit → Web / Sandbox Target User。
- 保留全量 URL 参数日志（`FULL_ERROR_URL`）—— 排查同类问题仍需要。

---

## 0. 2026-10-27 重大修正（务必先读这一节）

> ### ⚠️ 本文第 1、2 节的结论**已被证伪**
>
> 原文说「`invalid_request` 是 TikTok 服务端配置下发延迟造成的瞬时故障，
> 已无法复现」。**这个结论是错的** —— 它来自一个**无效的实验设计**：
> 所有测试都只跑到「加载出 TikTok 登录页」就结束了，
> **从来没有完成过一次真正的登录 + 授权**。
>
> 而 `invalid_request` **只在登录授权之后才出现**。
>
> ### 🔬 本轮的决定性证据（CDP 抓原始网络响应）
>
> 用 Chrome DevTools Protocol 挂到 app 的 WebView 上，抓到了
> authorize 端点的**原始 HTTP 响应**：
>
> ```
> >>> REQ GET https://www.tiktok.com/v2/auth/authorize/?response_type=code
>             &client_key=awy65nxalrzf8a76&scope=user.info.basic
>             &redirect_uri=...&state=...
>     RESP 200  →  302 到 https://www.tiktok.com/login?...
>                &enter_from=dev_awy65nxalrzf8a76
> ```
>
> 👉 **authorize 端点返回 200，正常跳登录页。**
> 所以「参数不合法」的说法在**首次加载阶段根本不成立**。
>
> 本轮又跑了 **7 组参数变体 + 8 次冷 cookie 重试 = 15 次**，
> 全部 ✅ 进入登录页，**0 次**出现 `invalid_request`。
>
> ### 🕐 logid 就是失败时刻的时间戳
>
> `logid` 前 14 位 = **TikTok 服务端生成该 id 的 UTC 时间戳**
> （用 token 端点自己的 `log_id` 交叉验证过，格式完全一致）：
>
> ```
> logid = 20261027035448D066F6910181548ACD82
>       → 2026-10-27 03:54:48 UTC = 11:54:48 (UTC+8)
> ```
>
> 设备时钟与 TikTok 服务器完全一致（已核对，无时钟偏移）。
> → 这个 logid 是**真实的一次授权失败**，不是误读。
>
> ### 📌 结论
>
> | 阶段 | 状态 |
> |---|---|
> | 加载 authorize 页（参数校验） | ✅ **完全正常**，15/15 次通过 |
> | 用户登录（提交账号密码） | ✅ 正常 |
> | **点击授权（服务端业务校验）** | ❌ **在这里失败** |
>
> 失败发生在「**已登录账号是否有资格为该应用授权**」这一层，
> 客户端参数无从修复。
>
> ### 🔧 本轮做的两个代码改动（唯一有依据的）
>
> 1. **补上 `source=web`** —— 反编译 `authV2.js` 的 `Mt()` 证明
>    TikTok **自己的** Web 流一定带这个参数，我们之前漏了。
>    漏参数正好命中 TikTok 的 `10002`「请求里带了不支持的参数」，
>    而 10002 会变成 `error=invalid_request` 且**不带 `error_type`**
>    —— 与观测到的现象完全吻合。**这是唯一一个「未测试过的真实缺口」**
>    （此前所有 `source=web` 对比实验都在未登录态下做，属于无效证据）。
> 2. **错误日志打全量 URL 参数** —— 原来只看 `error` / `errCode` /
>    `error_type` / `logid` 四个字段，数字 `error_code` 被前端 JS
>    压缩掉了。现在把 URL 上的**每一个** query 参数都打出来，
>    便于下次失败时拿到真正的数字码。

---

## 1. 一句话结论（**已过时，见第 0 节**）

**代码没问题，Portal 配置也没问题。**
之前的 `error=invalid_request` 是 **TikTok 服务端配置下发延迟**造成的瞬时故障，
现已**无法复现**（连续 3 轮全新卸载重装，全部正常进入 TikTok 登录页）。

代码侧已加**自动重试**兜底，永久消除这个瞬时故障的影响。

> ⛔ **为什么过时**：见第 0 节 —— 那些"复现"都只到登录页，
> 真正会失败的那一步从未被触发过。

---

## 2. 实测证据（真机 Android 13 / device `568c2aa4`）

### 2.1 参数矩阵（11 组变体，同一台设备逐个跑）

| 变体 | TikTok 回应 |
|---|---|
| **我们的配置**（`scope=user.info.basic` + 我们的 redirect_uri） | 首次 ❌ `invalid_request`+`logid`；**之后 ✅ 登录页** |
| 去掉 `scope` | ✅ 登录页 |
| `scope=user.info.basic,user.info.profile` | ✅ 登录页 |
| `scope=video.publish` | ✅ 登录页 |
| 加 `source=web` | ✅ 登录页 |
| 加 `code_challenge` + `code_challenge_method`（PKCE） | ✅ 登录页 |
| 加 `device_platform=web` | ✅ 登录页 |
| 去掉 `response_type` | ✅ 登录页 |
| `redirect_uri` 不带路径 | ✅ 登录页 |
| **明显错误的 `client_key`**（`zzzzzzzzzzzzzzzz`） | ✅ 登录页 |
| **未登记的 `redirect_uri`**（`https://example.com/cb`） | ✅ 登录页 |

### 2.2 决定性结论

**TikTok 在「登录页出现之前」根本不校验 `client_key` 和 `redirect_uri`。**

证据：连乱码 `client_key` 和未登记的 `example.com` 都能正常进登录页。
→ 之前那个 `invalid_request` **不是**「redirect_uri 没登记」，
也**不是**「client_key 写错」，**不是**「scope 没申请」。

### 2.3 真正的失败模式：**首次加载**

后续所有实验都指向同一个模式：

| 场景 | 结果 |
|---|---|
| 全新 WebView 的**第 1 次** authorize 加载 | ❌ 可能失败 |
| 同一 WebView 的**第 2 次及以后** | ✅ 100% 成功 |
| 全新安装（卸载重装）后首次 | ✅ 成功（3/3 轮） |
| 冷 profile（清 cookie+cache）后首次 | ✅ 成功 |
| 先加载 `tiktok.com` 首页再 authorize | ✅ 成功 |

**同一个 URL，第一次失败、第二次成功** —— 这是服务端瞬时故障的典型特征，
不是配置错误的特征（配置错误会 100% 稳定复现）。

### 2.4 时间线

| 时刻 | 现象 |
|---|---|
| ~11:06 | 首次参数矩阵：只有第 1 个用例失败，其余 10 个全过 |
| ~11:15 起 | 同一套代码、同一台设备，**所有用例（含原失败的 A）全部通过** |
| 11:22–11:40 | 3 轮全新卸载重装，全部正常进入 TikTok 登录页 |

→ 用户在 Portal 登记 redirect URI 之后，**TikTok 侧配置下发生效**，
正好落在 11:06–11:15 这个窗口。**登记本身是对的，只是下发有延迟。**

### 2.5 佐证：scope / client_key / redirect_uri 都不是原因

`authV2.js`（TikTok 授权页 webpack chunk `tiktok_4d_auth`）自带错误码表：

```js
switch (t) {
  case 5: case 10028: case 10006: case 100029: case 10002: return "invalid_request";
  case 10003: return "unauthorized_client";   // error_type = client_key
  case 10004: return "invalid_scope";          // error_type = scope
  case 1: case 4: return "server_error";
  default: return "access_denied";
}
```

我们遇到的 `invalid_request` **既没有 `errCode` 也没有 `error_type`**，
对应表里的 **`5`（或 `10002`）** —— TikTok 的**通用拒绝码**：
请求参数本身没问题，但**这个应用 / 这次请求没有资格**。

反过来，TikTok 对**真正的参数错误**是会明确给出 `errCode` + `error_type` 的：

| 真实参数错误 | 错误码 | `error_type` |
|---|---|---|
| 缺 `redirect_uri` | `10006` | `redirect_uri` |
| localhost 回调但缺 PKCE | `10007` | `code_challenge` |

**我们从没拿到过 `errCode=10006` / `10007`** → 我们的 `redirect_uri`
（逐字节与 Portal 一致）和 scope **都通过了 TikTok 的参数校验**。

---

## 3. 已排除的可能

| 假设 | 排除依据 |
|---|---|
| client_key 写错 | 换成乱码 `zzzzzzzzzzzzzzzz` 也能进登录页；且 TikTok 在 `enter_from=dev_awy65nxalrzf8a76` 里认它 |
| scope 没申请 | 不带 scope / 换别的 scope 全部正常 |
| **redirect_uri 没登记** | 未登记的 `https://example.com/cb` 同样正常进登录页；且 TikTok 从没返回过 `errCode=10006` |
| redirect_uri 少了 `.html` | 不带路径同样正常 |
| 域名验证文件没放对 | `https://tv.qahwatv.com/.well-known/tiktok-developers-site-verification.txt` → HTTP 200，内容正确 |
| 回调页 404 | `https://tv.qahwatv.com/tiktok-callback/index.html` → HTTP 200 |
| 需要 PKCE | 自建域名回调按 TikTok 规则**不该**带 PKCE；实测带不带都正常 |
| 用了原生 SDK 的参数 | 已全部清掉：`sdk_name` / `device_platform` / `app_identity` / `certificate` 都不传 |
| UA 被 TikTok 拦截 | 桌面 UA 已生效，登录表单完整渲染 |

> 注：域名验证文件目前只放在 `tv.qahwatv.com`（HTTP 200）。
> 根域名 `qahwatv.com` 的两个标准路径都是 404。
> **当前不影响 Web 流**（TikTok 校验的是 redirect_uri 所在主机），
> 但建议一并补上，避免以后加 **App Link / 深度链接**时被卡。

---

## 4. 实现要点

### 4.1 授权 URL

```
https://www.tiktok.com/v2/auth/authorize/
  ?response_type=code
  &client_key=awy65nxalrzf8a76
  &scope=user.info.basic
  &redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2Findex.html
  &state=<32 位随机 hex>
```

**只有这 5 个参数。** 依据：TikTok 官方 Web 流文档只列了这 5 个。

### 4.2 PKCE 的规则（照抄 TikTok 自己的判断）

反编译 `authV2.js` 的 `Mt()`（构造请求参数的函数）：

```js
function u(redirectUri) {                       // 判断回调类型
  var host = new URL(redirectUri).hostname;
  return ['127.0.0.1','localhost'].includes(host)
      ? DESKTOP     // 桌面 App
      : WEB;        // 普通 Web
}
...
} else if (s === DESKTOP) {
  a.set(SOURCE, s);
  a.set(CODE_CHALLENGE, ...);      // ← 只有 localhost 才带
  a.set(CODE_CHALLENGE_METHOD, ...);
} else {
  a.set(SOURCE, s);                // ← 普通 Web 流：只带 source
}
```

👉 **普通 Web 流（回调不是 localhost）根本不带 `code_challenge`。**
多传反而会命中 TikTok 的 `10002`「请求里带了不支持的参数」。

代码里对应实现：

```dart
static bool _usesPkce(String redirectUri) {
  final host = Uri.parse(redirectUri).host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1';
}
```

我们用自建域名 → `_usesPkce == false` → **不带 PKCE**，后端用
`client_secret` 换 token。

### 4.3 User-Agent 必须伪装成桌面

TikTok 对**移动端 UA**（应用内 WebView / Chrome Android / iPhone）的授权页
会整页替换成一块阻断提示：

> "For security purposes, use the TikTok app to continue."

上面只有 "Open TikTok" 按钮，**没有任何账号密码输入框**，
用户无论如何都登不进去，App 侧自然永远收不到 code。

所以 `_TiktokWebViewPageState` 里写死了桌面 UA：

```dart
static const String _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
```

### 4.4 回调拦截

`onNavigationRequest` 在页面加载**之前**拦下 redirect_uri：

1. 先看是不是 TikTok **在 authorize 端点直接报错**
   （URL 上带 `error=`）→ 映射成细分错误码，把 `logid` 带进提示文案
   （`logid` 是 TikTok 支持团队定位服务端日志的**唯一**凭据）。
2. 再看是不是命中了登记的 redirect_uri：
   - 带 `error=` → 取消 / 报错
   - `state` 对不上 → CSRF 报错
   - 有 `code` → 成功
   - 都没有 → 缺 code 报错

**插件层面确认过拦截是可靠的**：
`webview_flutter_android-4.13.0` 的
`AndroidNavigationDelegate.setOnNavigationRequest` 会调用
`setSynchronousReturnValueForShouldOverrideUrlLoading(true)`，
让 `WebViewClient.shouldOverrideUrlLoading` 真正**阻止**跳转；
Dart 侧返回 `NavigationDecision.navigate` 时插件再自己 `loadUrl`。
所以 **TikTok 服务端 302 回我们的 redirect_uri 时，拦截必然命中**。

### 4.5 `invalid_request` 自动重试（新增）

针对 §2.3 的瞬时故障，拦截到 `invalid_request` 时自动重试：

```dart
if (_invalidRequestRetries < 2) {
  _invalidRequestRetries++;
  final retryUrl = widget.authorizeUrlBuilder(widget.redirectUri);
  Future.delayed(const Duration(milliseconds: 800), () {
    if (mounted) _controller.loadRequest(Uri.parse(retryUrl));
  });
  return NavigationDecision.prevent;
}
```

**重试保留同一个 `state`**（TikTok 不校验 state 唯一性），
实测「同一个 URL 第二次必成功」，所以重试一次即可解决。

### 4.6 后端换 token

```
POST /api/user/userAuthorization
{
  "passportType": 7,                 // PassportType.tiktok
  "passportName": "TikTok_access_token",
  "code": "<authCode>",
  "redirectUri": "https://tv.qahwatv.com/tiktok-callback/index.html"
}
```

⚠️ `redirectUri` 必须与「请求 code 时用的」**逐字节一致**，否则 TikTok
换 token 时返回 `invalid_grant`。所以前端原样透传，不自己拼。

`client_secret` 只在服务端用，**绝不能进客户端**。

---

## 5. Developer Portal 现状（已确认，无需再改）

- **Client Key**：`awy65nxalrzf8a76`
- **Scope**：`user.info.basic`
- **Login Kit → Web → Redirect URI**：`https://tv.qahwatv.com/tiktok-callback/index.html`（已登记）
- 无待提交的 revision

---

## 6. 排障手册

### 6.1 遇到 `invalid_request` 且没有 `errCode`

这是 TikTok 的**通用拒绝码**。按顺序排查：

1. **等 5–10 分钟重试** —— 最常见原因是配置下发延迟。
2. 手动重试一次（App 已内置自动重试）。
3. 若持续失败，记录 **`logid`** 找 TikTok 支持查服务端日志。
   - `logid` 是定位服务端日志的**唯一**凭据，必须保留。

### 6.2 错误码速查

| 现象 | 含义 | 处理 |
|---|---|---|
| `error=invalid_request` + 无 `errCode` | 通用拒绝 | 等待 / 重试；持续则找 TikTok（带 `logid`） |
| `errCode=10006` + `error_type=redirect_uri` | redirect_uri 缺失或未登记 | 核对 Portal 里的逐字节一致性 |
| `errCode=10007` + `error_type=code_challenge` | localhost 回调缺 PKCE | 加 PKCE（仅 localhost） |
| `errCode=10003` + `error_type=client_key` | client_key 无效 | 核对 Portal |
| `errCode=10004` + `error_type=scope` | scope 未申请 | 在 Portal 申请该 scope |
| 页面显示 "use the TikTok app to continue" | UA 被识别为移动端 | 用桌面 UA（已处理） |
| 页面有登录表单但收不到 code | 拦截没命中 | 检查 redirect_uri 逐字节一致 + state 校验 |

### 6.3 回调页

`deploy/tiktok-callback/index.html` 只是**诊断 / 兜底页**。
正常流程下 Flutter 的 `onNavigationRequest` 会在页面加载**之前**就拦下这个 URL
并取走 `code`，所以这个 HTML 根本不会被渲染。

用户看到这一页说明：浏览器里手动打开，或 App Link 验证失败。

---

## 7. 已清理的东西

- 全部临时探针 / 诊断脚本（根目录 20+ 个 `_*.js` / `*_out.txt`）
- `main.dart` 里的自动登录测试钩子
- `android/app/src/main/AndroidManifest.xml` 里 TikTok 原生 SDK 的 Activity / Provider
- `android/build.gradle.kts` 里 TikTok 原生 SDK 的 Maven 仓库
- 原生 SDK 的 `sdk_name` / `device_platform` / `app_identity` / `certificate` 参数

`flutter analyze` 对 `lib/features/auth/**` 与 `lib/core/config/app_config.dart`
**无 error**。
