# TikTok 登录 —— 排查结论（2026-10-23 最终版）

> ## 🔬 2026-10-26 决定性突破：反编译 `authV2.js` 拿到错误生成机制
>
> 之前所有排查都卡在同一个死角：**TikTok 只给我们一个笼统的
> `error=invalid_request`，没有具体原因**。
>
> 本轮解开了这个死角 —— 把 TikTok 授权页的 `authV2.js`
> （webpack chunk `tiktok_4d_auth`）解出来，读懂了它**自己**的代码。
>
> ### 真相 1：`invalid_request` 是 TikTok **前端 JS 自己拼出来的**
>
> ```js
> // authV2.js —— 授权页加载后立刻 POST 这个接口
> d.default.post("/tiktok/v2/oauth/page/detail/", _, {
>     withCredentials: true, params: {locale: ...}
> });
>
> // 拿到响应后：
> if (T.error) {
>     g = T.error_code;                  // ← 数字错误码
>     h = u.headers["x-tt-logid"];       // ← 日志 ID
>     wt(b.V.AuthError, {error_code: g, error_source: b.V.AuthFetchDetail, log_id: h});
>     at.handleAuthError(T);
>     f = C(window.location.href, g, h); // ← 拼出 error= 跳转
>     window.location.assign(f);
> }
> ```
>
> 👉 **所以 `?error=invalid_request` 不是服务器 302 回来的，
> 是 TikTok 的前端 JS 拿到 `page/detail` 的响应后自己拼的。**
> 这修正了之前「服务器在返回 HTML 前就 302 了」的判断 —— 不成立。
>
> ### 真相 2：错误码 → error / error_type 的权威映射表
>
> ```js
> // C() 函数
> switch (error_code) {
>   case 5: case 10028: case 10006: case 100029: case 10002: return "invalid_request";
>   case 10003: return "unauthorized_client";
>   case 10004: return "invalid_scope";
>   case 1: case 4: return "server_error";
>   default: return "access_denied";
> }
>
> // error_type（只有这几个码会带 error_type）
> switch (error_code) {
>   case 10003: return "client_key";
>   case 10004: return "scope";
>   case 10028: case 10006: case 100029: return "redirect_uri";
>   case 10042: return "non_sandbox_target";
>   default: return;   // ← 5 和 10002 **不写** error_type
> }
> ```
>
> 📌 **由此可确定**：我们看到的
> `error=invalid_request` + `error_type` 为空，
> 对应的 `error_code` 只能是 **5 / 10028 / 10006 / 100029 / 10002** 之一。
>
> ### 真相 3：10002 的官方含义 = 「多余的 / 不支持的参数」
>
> StackOverflow 上有 TikTok 官方文档佐证：
> **10002 = 请求里带了 TikTok 不支持的参数**（经典场景是多传了
> OAuth2 标准的 `client_id`）。
>
> 🔗 https://stackoverflow.com/questions/74747343/tiktok-oauth-parameter-error-login-kit
>
> 而 10006 = `redirect_uri` 没在 Portal 登记（`error_type=redirect_uri`）。
>
> ### 真相 4：TikTok 官方 Web 流**根本不传** `code_challenge`
>
> 从 `authV2.js` 的 `Mt()`（构造 authorize 参数）看，TikTok 自己的逻辑是：
>
> ```js
> var s = u(redirect_uri);   // localhost/127.0.0.1 → DESKTOP，否则 WEB
> if (来自原生 SDK) {
>     a.set(CODE_CHALLENGE, ...);
>     a.set(CODE_CHALLENGE_METHOD, "S256");
>     a.set(SDK_NAME, ...);
>     ...
> } else if (s === DESKTOP) {      // ← 只有 localhost 才带 code_challenge
>     a.set(CODE_CHALLENGE, ...);
>     a.set(CODE_CHALLENGE_METHOD, ...);
> } else {
>     a.set(SOURCE, s);            // ← 普通 Web 流：只有 source
> }
> ```
>
> 👉 **普通 Web 流（source=web）根本不带 `code_challenge`**。
> 我们项目里 `AppConfig.tiktokUsePkce = true` **反而多传了一个参数**
> —— 这正好命中 10002「多余的参数」！
>
> 📌 官方文档给出的 Web 流参数只有 5 个：
> `client_key` / `response_type` / `scope` / `redirect_uri` / `state`
> 🔗 https://developers.tiktok.com/doc/login-kit-web/
>
> ### ✅ 结论与下一步
>
> 1. **PKCE 应该关掉**（`tiktokUsePkce = false`）—— Web 流不需要它，
>    而多传它可能正是 10002 的来源。
> 2. **不要再查 redirect_uri 是否在 Portal 登记** —— 10006 会带
>    `error_type=redirect_uri`，而我们**没有**这个字段，说明没走到那步。
> 3. **唯一的真相来源是 `page/detail` 的数字 `error_code`**。
>    本项目已实现直接调用该接口的探测器
>    （`tiktok_auth_service.dart` 的 `_diagPageDetail()`），
>    在 WebView 内用同步 XHR 复现 TikTok 自己的请求，
>    一次跑 9 个参数变体、每个约 300ms，
>    **登录完成后立刻就能拿到 `error_code`**。

> ## 🆕 已登录态下的参数级对照（2026-10-26 补充，本轮新证据）
>
> §2.2 的 20 组 A/B 全是在**未登录**状态做的（文档自己已指出这是无效证据）。
> 本轮补做了**已登录**（WebView 内有 TikTok cookie）状态下的参数级对照，
> 用**同一个 WebView** 依次加载多个 authorize 变体，各变体之间唯一的差别
> 就是被改动的那个参数：
>
> | 变体 | 改动 | 服务端反应 |
> |------|------|-----------|
> | V0 | 我们当前的 URL（带 PKCE） | `error=invalid_request`（errCode / error_type 均空） |
> | V1 | 去掉 `code_challenge` | **完全相同** |
> | V2 | scope 换成 `user.info.basic,user.info.email` | **完全相同** |
> | V3 | `code_challenge_method=plain` | **完全相同** |
> | V4 | `redirect_uri` 换成 `http://localhost/callback`（**不需要**在 Portal 登记） | **完全相同** |
> | V5 | **完全去掉** `scope` | **完全相同** |
>
> **这组结果的信息量**：
>
> - V4 用的是**绝对没在 Portal 登记过**的 `redirect_uri`，仍然返回同一个错。
>   → 在**这一层**，`redirect_uri` 的值根本还没被校验。
>   → 因此「Portal 里的 Web 标签页 redirect_uri 配得对不对」，
>   **无法解释当前的失败**（配错不会产生不同的报错）。
> - V5 连 `scope` 都没有，也不报 `error_type=scope`。
>   → `scope` 同样还没被校验。
> - V1/V2/V3 证明 PKCE 的有无与形式、scope 的组合，都不改变结果。
>
> ⚠️ **推论**：既然「参数缺失/不合法」会立刻换成
> `param_error` + `error_type=redirect_uri` + `errCode=10006`（§2.3 已验证），
> 而 V4/V5 这种**明显非法**的参数组合却仍然返回笼统的 `invalid_request`，
> 说明 TikTok 在这些参数被校验**之前**就中断了流程。
> 这与 §2.1 的埋点 `error_source=query-param-error` 一致。
>
> 🎯 **结论进一步收敛**：不要再去逐个调 redirect_uri / scope / PKCE
> —— 已登录态下的对照实验证明这些都不是触发点。剩下唯一值得查的是
> **应用/账号资格层**（Login Kit 审核状态、应用是否 Live、
> 该账号是否在允许名单内），以及拿 logid 找 TikTok 支持。
>
> ### 页面层证据：TikTok 的 React 授权页从未运行
>
> 在 WebView 内注入 JS 读 DOM + performance entries，实测：
>
> ```
> [TiktokDiag] {"text":"", "href":"<原始 authorize URL，无 error 参数>", "xhr":[]}
> ```
>
> - `text` 为空 → 页面正文**完全空白**
> - `xhr` 为空数组 → **一个 XHR 都没发出** → authV2.js 里的
>   `page/detail` 等接口**从未被调用**
> - `href` 停在**原始** authorize URL（还没带 error）
> - 时序：`page start` → 200~800ms → `page finished`（空白）→
>   才跳到带 `error=invalid_request&logid=...` 的地址
>
> → **服务器在返回任何 HTML 之前就 302 重定向了**，
> 客户端的 React 授权页根本没机会跑起来。
> 这也解释了为什么 `page/detail` 拿不到任何有用的 error_code。
>
> ### 工具：变体测试器
>
> 已把上述对照实验做成可复用的工具（见
> `lib/features/auth/services/tiktok_auth_service.dart`）：
> `_runVariantTest()` 在同一个 WebView 里依次加载各变体并记录结果，
> 右上角 🧪 按钮手动触发，登录完成后循环重跑以自动拿到已登录态的数据。
>
> ⚠️ **注意**：调试时曾用 PowerShell 的
> `Get-Content -Raw | Set-Content` 改这个文件，
> 那会把 UTF-8 的中文注释按 GBK 往返，**永久损坏文件**。
> 改这个文件请用编辑器，**不要用 PowerShell 重写**。

> ## ⚠️ 本文档 §2.2 的推论已被证伪（2026-10-26 更正）
>
> 原文结论：「瞎编的 `client_key` 也返回同样的 `invalid_request`，
> 说明 TikTok 在校验 `client_key` 之前就拒了 → 问题在应用配置」。
>
> **这个推论是错的。** 真机实测证明：
>
> | 场景 | 结果 |
> |------|------|
> | 未登录 + 真 key + 我们的 redirect_uri | 正常跳登录页，**无 error** |
> | **瞎编 key** + 我们的 redirect_uri | 正常跳登录页，**无 error** |
> | 已登录 + 真 key + 我们的 redirect_uri | `error=invalid_request`，`error_type` 空 |
> | 任意 key + **缺** redirect_uri | `param_error` / `error_type=redirect_uri` / 10006 |
>
> 也就是说：`redirect_uri` **只在参数缺失时才校验**，它的值不影响能否进入登录页；
> 而「瞎编 key 也一样」只能说明 **authorize 阶段不校验 `client_key`**，
> 不能推出任何关于 redirect_uri 注册状态的结论。
>
> **真实的失败点**（logid `202610260720431AC1543A684FB43A8B01`）：
> 登录成功后，TikTok **302 回 authorize 自身**（而非回 redirect_uri），
> 并带上 `error=invalid_request`、`errCode` 与 `error_type` **均为空**。
> 说明参数、client_key、scope 全部通过校验，拒绝发生在
> **「已登录账号是否有资格为该应用授权」** 这一步。
>
> 首选排查方向因此变为：**`redirect_uri` 是否与 Portal「Login Kit → Web」
> 里登记的完全一致**（逐字节比对），以及配置改动后是否漏了
> Create Revision → Submit for review。
>
> ⚠️ 注意一个**推理陷阱**：所有"未登录状态"下的 A/B 实验（包括乱填
> `client_key`、换各种 `redirect_uri`）都**不会**触发 redirect_uri 校验，
> 因为 TikTok 把它放在「登录之后、点击授权之后」。因此那些实验
> 既不能证明 redirect_uri 配好了，也不能证明它有问題 —— 它们只是无效证据。
>
> ## 已确认根因（2026-10-26 定论）：TikTok 后端返回通用拒绝码 5
>
> 反编译 `tiktok_4d_auth` 的 `authV2.js` 得到**权威映射表**：
>
> ```js
> // error_code → error
> case 5: case 10028: case 10006: case 100029: case 10002: return "invalid_request";
> case 10003: return "unauthorized_client";
> case 10004: return "invalid_scope";
>
> // error_code → error_type（只有这些码会写该参数）
> case 10003: return "client_key";
> case 10004: return "scope";
> case 10028: case 10006: case 100029: return "redirect_uri";
> case 10042: return "non_sandbox_target";
> // 其余（含 5）→ 不写 error_type
> ```
>
> 而且走这条分支时**只追加 `logid`，不追加 errCode**。实测抓到的 URL 正是：
>
> ```
> ...&error=invalid_request&logid=2026102607370650C54A15EFF9171E4F8F
> ```
>
> 无 errCode、无 error_type、无 error_string → 唯一交集是 **error_code 5**。
>
> ### 这意味着什么
>
> **所有客户端参数都是合法的。** 因为：
>
> | 若参数非法 | 会得到 |
> |---|---|
> | client_key 无效 | `10003` + `error_type=client_key` |
> | scope 非法 | `10004` + `error_type=scope` |
> | redirect_uri 未注册 | `10006` + `error_type=redirect_uri` |
> | 非沙箱目标用户 | `10042` + `error_type=non_sandbox_target` |
>
> **一个都没触发。** 拒绝发生在「应用/账号是否有资格完成这次授权」这一层，
> 客户端无从修复，属于 TikTok 服务端判定。
>
> ### 已用实验逐一排除
>
> - **client_key 无效**：`example.com` 这种完全未注册的 redirect_uri 与已登记值
>   在授权页加载阶段**表现完全相同**（都 302 到登录页）；乱填的 client_key
>   同样如此 —— 校验发生在点击授权之后，登录前的 A/B 全部无效
> - **PKCE 缺失**：已补齐 `code_challenge` / `S256` / 43+ 位 verifier，错误**一字不变**
> - **Sandbox**：应用为 Production + Live；`enter_from=dev_<client_key>` 对
>   **乱填的 client_key 同样出现**，只是固定格式，与沙箱无关
> - **域名验证**：验证文件对所有 UA（含 TikTok 爬虫）返回 `200` / `text/plain`
>   且 token 逐字节匹配
>
> ### 下一步只有一条路
>
> 拿 logid 找 TikTok 支持。他们后台能看到 error_code 5 的具体触发原因。
> 在此之前不要再改客户端参数 —— 已经没有参数可改。
>
> 结论一句话：**服务器侧全部就绪，卡点在 TikTok Developer Portal 的应用配置。**
>
> 🎯 **2026-10-26 补充**：本轮在**已登录态**下补做的参数级对照
> （V4 用未登记的 `localhost` redirect_uri、V5 完全去掉 scope，
> 结果与正确参数**一字不差**）已从正面确认：
> **redirect_uri / scope / PKCE 都不是触发点**。
> 请不要再花时间逐个调这三个参数。

> 📌 **后续进展**：本文档记录的是 Web 流（WebView / ChromeTab）的排查过程。
> 排查结论已直接促成改造 —— **现已接入官方 TikTok Android OpenSDK 2.4.0**（原生 App 流）。
> 完整实现说明见 **[`tiktok-native-sdk.md`](./tiktok-native-sdk.md)**。
> 本文 §2 的「20 组参数级 A/B 全是 `invalid_request`」结论依然成立，
> 并且后来用**官方 SDK 自己生成的 URL** 复现了同样的错误（决定性证据）。

---

## 一、服务器侧：已全部验证通过 ✅

### 1.1 App Links 验证文件

```
200  https://tv.qahwatv.com/.well-known/assetlinks.json     application/json  265B
200  https://tv.qahwatv.com/assetlinks.json                  application/json  265B
200  https://tv.qahwatv.com/.well-known/apple-app-site-association  application/json  289B
```

内容正确：

```json
[{"relation":["delegate_permission/common.handle_all_urls"],
  "target":{"namespace":"android_app",
            "package_name":"com.video.storydrama",
            "sha256_cert_fingerprints":["D5:E1:0C:...:C0:64"]}}]
```

### 1.2 Android 系统侧验证

```
$ pm get-app-links com.video.storydrama
Signatures: [D5:E1:0C:FC:E8:02:22:E6:8A:62:77:C4:49:B6:EC:31:C1:10:1E:32:E5:FA:61:44:51:B8:21:7F:F4:4B:C0:64]
Domain verification state:
  qahwatv.com: 1024
  tv.qahwatv.com: verified        ← 已 verified
```

签名与 `assetlinks.json` **完全一致** ✅
（`qahwatv.com: 1024` 是 `1024 = 人工验证`，不是 verified —— 因为我们只用了 tv）

### 1.3 域名归属验证

```
$ curl https://tv.qahwatv.com/.well-known/tiktok-verification.txt
tiktok-developers-site-verification=zhrCyPPQyGJudTq7uNDfk7GvJvzXfdjk
```

DNS TXT 也有：`google-site-verification=GtV4FKqnnyAo2E5wz6UL_pki2JD_RZbMu4Ceas7pHRc`

---

## 二、TikTok 侧：授权页仍然拒绝

### 2.1 确切错误

```
error=invalid_request
logid=2026102307223622768F6F09808C19F30B
```

TikTok 页面文案：
> **出错了** — 无法通过 TikTok 进行登录。这可能是特定应用设置所致。

TikTok 自己的埋点（`bav2b_page` 事件里）给出了**权威定位**：

```json
{
  "event": "auth_error_page",
  "params": {
    "channel": "awy65nxalrzf8a76",
    "enter_method": "android",
    "error_source": "query-param-error"     ← TikTok 自己的判定
  }
}
```

`error_source: query-param-error` = TikTok 服务端在**解析 query 参数阶段**就拒了，
还没走到「校验 redirect_uri 是否在白名单」那一步。

同一条埋点里还确认了 TikTok 正确解析到了我们的参数：

```json
"categories":{
  "client_key":"awy65nxalrzf8a76",
  "redirect_host":"tv.qahwatv.com",
  "is_same_redirect_host":"false"
}
```

→ **`client_key` 被 TikTok 认出来了**，`redirect_host` 也解析对了。

### 2.2 参数级二分：全部一样

我把官方 Android SDK 的 URL 拆开，逐个参数做 A/B（真机，每组 15 秒）：

| 组 | 变体 | 结果 |
|---|------|------|
| BASE | 官方 SDK 完整格式 | `invalid_request` |
| 1 | 去掉 `certificate` | `invalid_request` |
| 2 | 去掉 `code_challenge` | `invalid_request` |
| 3 | 去掉 `sdk_name` | `invalid_request` |
| 4 | 去掉 `device_platform` | `invalid_request` |
| 5 | 去掉 `app_identity` | `invalid_request` |
| 6 | `scope=user.info.basic,user.info.profile` | `invalid_request` |
| 7 | `scope=user.info.profile` | `invalid_request` |
| 8 | 去掉 `scope` | `invalid_request` |
| 9 | `certificate` 带冒号 | `invalid_request` |
| 10 | `certificate` 填 MD5 | `invalid_request` |
| 11 | `device_platform=ios` | `invalid_request` |
| 12 | **完全瞎编的 16 位 `client_key`** | `invalid_request` |
| 13 | **旧包名 + 旧证书** | `invalid_request` |
| 14 | `redirect_uri` 去掉 `index.html` | `invalid_request` |
| 15 | `redirect_uri` 换成 apex | `invalid_request` |
| 16 | `redirect_uri` 换成根路径 | `invalid_request` |
| 17 | 加 `code_challenge_method=S256` | `invalid_request` |
| 18 | 加 `aid=1988` | `invalid_request` |
| 19 | 加 `language=en` / `lang=en` | `invalid_request` |
| 20 | `client_id` 代替 `client_key` | `invalid_request` |

**20 个变体，结果全部一模一样。**

第 12 组（瞎编 key）和第 13 组（旧包名旧证书）尤其关键：
→ 无论换成什么，TikTok 都给同一个错。说明这个错误**不是由某个具体参数值触发的**。

### 2.3 对照：只有「参数缺失」才会换错误码

| 请求 | 结果 |
|------|------|
| 去掉 `redirect_uri` | `param_error` / `error_type=redirect_uri` / `errCode=10006` |
| 只留 `client_key` | `param_error` / `error_type=redirect_uri` / `errCode=10006` |

→ 参数**结构**是通的（TikTok 明确说缺的是 redirect_uri）。
→ 但只要 redirect_uri 存在，**不管它是什么值**，都变成笼统的 `invalid_request`。

---

## 三、结论

`error_source=query-param-error` + 「值怎么变都同一个错」+
「结构缺失时才会换错误码」这三件事合起来指向：

> **TikTok 在校验完参数结构之后、进入业务校验之前就中断了。**
> 这个位置的唯一「全局开关」就是**应用本身的状态**。

具体到 TikTok Developer Portal，对应的是这几件事之一：

1. **应用 / Login Kit 未通过审核**（最常见）
   - TikTok 官方文档：Login Kit 需要审核通过后才能给真实用户用
   - 沙箱状态（Sandbox）下 `client_key` 只能配「沙箱用户」，别人用不了
   - 表现就是授权页直接「出错了」
2. **应用处于 Draft / 未发布状态**
3. **改了 redirect URI 但没有 Create Revision → Submit for review**
   - Portal 里「看着配好了」，但生效的是旧 revision
   - **改过任何配置都必须重新提交审核**
4. **client_key 失效 / 应用被删除 / 换了应用**
   - 但 token 端点对同一个 key 返回 `invalid_grant`（而不是 `invalid_client`），
     说明 key 本身能被识别

---

## 四、行动清单（按性价比排序）

### 🔴 最优先：去 TikTok Developer Portal 逐项核对

打开 <https://developers.tiktok.com/apps> → 你的应用 → **Login Kit**：

- [ ] 应用状态是不是 **Live / 已发布**（不是 Draft）
- [ ] Login Kit 是不是 **审核通过**（不是 Pending / Rejected）
- [ ] **Android** 标签页下的 Redirect URI 是不是**逐字符**等于
      `https://tv.qahwatv.com/tiktok-callback/index.html`
      （注意结尾没有 `/`，没有多余空格，没有大写差异）
- [ ] **iOS** 标签页同理（iOS 也要配，虽然现在测 Android）
- [ ] Scopes 里 **勾选了** `user.info.basic` 且包含在 Login Kit 里
- [ ] 如果最近改过任何配置 → **Create Revision → Submit for review**，等审核通过
- [ ] 确认登录的**不是另一个应用**（同一个账号下多个 App 很容易搞混）

### 🟡 次要：核对 Web 标签页

TikTok 的 `redirect_uri` 白名单是**按平台分开**的。如果 Portal 里只配了 Web 标签页，
那 Android 标签页是空的 → 一样报 `invalid_request`。

**四个标签页（Web / Desktop / Android / iOS）都要配**对应的 redirect URI。

### 🟢 已完成（不用再动）

- ✅ `.well-known/assetlinks.json` 部署 + Content-Type 正确 + 系统 verified
- ✅ 域名归属验证文件 + DNS TXT
- ✅ APK 签名与 assetlinks 一致
- ✅ 前端 PKCE（hex SHA-256，对齐官方 SDK）
- ✅ 前端透传 `redirectUri` / `codeVerifier` 给后端
- ✅ `redirectUri` 候选只剩 `tv.qahwatv.com`

---

## 五、如果 Portal 全部正常，还有这两条路

### 路线 B：改用官方 TikTok Android SDK ✅ 已实施

不用手搓 WebView，直接用官方 SDK：

```gradle
implementation 'com.tiktok.open.sdk:tiktok-open-sdk-core:2.4.0'
implementation 'com.tiktok.open.sdk:tiktok-open-sdk-auth:2.4.0'
```

```kotlin
val codeVerifier = PKCEUtils.generateCodeVerifier()
val request = AuthRequest(
    clientKey = "awy65nxalrzf8a76",
    scope = "user.info.basic",
    redirectUri = "https://tv.qahwatv.com/tiktok-callback/index.html",
    codeVerifier = codeVerifier)
authApi.authorize(request, AuthMethod.TikTokApp)
```

官方 SDK 走 `AuthMethod.TikTokApp` 时是**跳 TikTok App 授权**，
和 WebView 模拟的「Web 流」是不同的服务端路径 —— 如果是 Web 流被限制、
App 流可用，这条路能通。

> ✅ **已实现**：`TikTokAuthHandler.kt` + `tiktok_native_auth_service.dart`，
> 已编译、安装、真机验证。详见 [`tiktok-native-sdk.md`](./tiktok-native-sdk.md)。
>
> ⚠️ **注意**：官方 SDK 自己生成的 Web URL 也返回 `invalid_request`，
> 所以**不要退回 `AuthMethod.ChromeTab`** —— 走 `TikTokApp`，靠 SDK 内部降级。
> 落到 ChromeTab 就等于回到已证伪的 Web 流。
>
> ⚠️ **注意**：用了官方 SDK 就必须把 `MainActivity` 恢复成 `singleTask`
> （ChromeTab 降级路径会通过 App Link 跳回来），详见 native-sdk 文档 §3.1。

### 路线 C：拿 logid 找 TikTok 支持

手上有一堆 logid，直接给 TikTok 支持团队，他们能查服务端日志：

```
2026102307223622768F6F09808C19F30B
20261023072335445AE7E2A59BA91C3731
2026102307245978AE0DDA9808571CA1D3
202611030312166EA3CD67521A72063EF5   ← 2026-11-03，无 PKCE 的 5 参数 Web 流
202611030335561995C67149EE4A007274   ← 2026-11-03，带 PKCE（hex challenge）
```

配合说明：`client_key=awy65nxalrzf8a76`，`enter_method=android`，
`error_source=query-param-error`。

---

## 2026-11-03 补充：PKCE 已在真实构建上再测一次，结论不变

客户端完整实现了 PKCE（`AppConfig.tiktokUsePkce = true`）：

- `code_verifier`：`Random.secure()` 取 48 字节 → base64url 去 padding，64 字符
- `code_challenge`：`sha256(verifier)` 的**小写十六进制**（64 字符，非 base64url）
- verifier 经 `TiktokLoginResult` → `api_service.tiktokLogin(codeVerifier:)` 透传给后端

实际发出的 URL（真机日志）：

```
https://www.tiktok.com/v2/auth/authorize/?response_type=code
&client_key=awy65nxalrzf8a76&scope=user.info.basic
&redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2F
&state=00837cb70bf983ab35aaa9adb33f2304
&code_challenge=f379ed2f2968cc659757100f17f8c1af851ba7cd51a6ef94261b9e24aaeac431
&code_challenge_method=S256
&error=invalid_request&logid=202611030335561995C67149EE4A007274
```

**PKCE 在场，仍是 `error=invalid_request`，且依旧没有 `errCode` / `error_type`。**

至此 PKCE 假设被三条独立证据否定：

1. 本文件 §「已登录态下的参数级对照」V0/V1/V3 —— 带、不带、改 plain，结果完全相同
2. [`tiktok-native-sdk.md`](./tiktok-native-sdk.md) §1.2 —— 官方 OpenSDK 2.4.0 自己
   生成的 URL **本来就带 `code_challenge`**，同样被拒
3. 本节 —— 真实构建带 PKCE，结果不变

👉 **不要再往 PKCE 方向排查。** 若后续需要回到 5 参数形态，把
`AppConfig.tiktokUsePkce` 设为 `false` 即可，无需改其他代码。

---

## 2026-11-03 决定性对照：脱离 App，在真实桌面 Chrome 里同样失败

App 内 WebView 反复失败后，把授权 URL 原样拿到**桌面 Chrome（已登录 tiktok.com）**
打开，排除一切客户端因素：

```
https://www.tiktok.com/v2/auth/authorize/?response_type=code
&client_key=awy65nxalrzf8a76&scope=user.info.basic
&redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2Findex.html
&state=0123456789abcdef0123456789abcdef&source=web
```

页面原文：

> **出错了**
> 无法通过 TikTok 进行登录。这可能是特定应用设置所致。
> 请参考我们的开发者文档以了解更多详情。
> logid: `202611030354...`（截图）

### 这一条排除了什么

| 假设 | 状态 |
|---|---|
| WebView / `webmssdk.js` 签名失败导致风控拒绝 | ❌ 真实 Chrome 表现一致，排除 |
| 客户端 UA / JSB 冲突 / CSP 拦截 | ❌ 同上，排除 |
| `source=web` 缺失才是根因 | ❌ 本次 URL 带了 `source=web`，结果不变 |
| 桌面 UA 伪装是必需的 | ⚠️ 真实桌面浏览器本身就满足，仍失败 |

### 同时确认的事实（服务器侧）

对着 Portal 截图和实际请求逐项核对过：

- Portal：Production → **Live**（绿勾），应用已审核通过
- Login Kit → **Web** 标签页登记值 = `https://tv.qahwatv.com/tiktok-callback/index.html`
- Scopes：`user.info.basic` —— "Included in Login Kit"
- 回调 URL 直连 → `200`，**无重定向**，TLS 正常
- `tv.qahwatv.com/.well-known/tiktok-developers-site-verification.txt` → `200`
- ⚠️ 顶点域 `qahwatv.com/.well-known/...` → **404**（只有子域有）

### 结论

失败与客户端实现**无关**，是 TikTok 侧对该 `client_key` 的应用级判定。
剩下的唯一有效动作是拿 logid 找 TikTok 支持，或到 Portal 逐项核对
「Client key 是否等同 `awy65nxalrzf8a76`」「Products → Login Kit 是否真的包含
Web 平台」「URL properties 里 `tv.qahwatv.com` 是否已验证」。

---

## 2026-11-03 第二次抓包：Web 产品已生效、请求零偏差，`page/detail` 仍是 10002

前提条件已由 Portal 截图确认：应用 Production / **Live**；
Login Kit → **Web** 的 redirect URI = `https://tv.qahwatv.com/tiktok-callback/index.html`；
URL properties 中 `https://tv.qahwatv.com/`（URL prefix）与 `tv.qahwatv.com`（Domain）
**均已验证**；scope `user.info.basic` 显示 "Included in Login Kit"；测试账号为正常账号。

请求已收敛到官方文档的精确形态（无 PKCE、无 `source`）：

```
https://www.tiktok.com/v2/auth/authorize/?response_type=code
&client_key=awy65nxalrzf8a76&scope=user.info.basic
&redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2Findex.html
&state=431ef0b8936a157c2db9ea14f974a190
```

在 WebView 内（同源、带 cookie）重放 `POST /tiktok/v2/oauth/page/detail/?locale=en`，
两次独立尝试的原样响应：

```json
{"error":"invalid_request","error_code":10002,
 "error_description":"The request parameters are malformed.",
 "extra":{"fatal_item_ids":[],"logid":"2026110304451930AA94367E8980060FDD",
          "now":1793681119000},
 "log_pb":{"impr_id":"2026110304451930AA94367E8980060FDD"},
 "page_detail":{},"status_code":0,"status_msg":""}
```

```json
{"error":"invalid_request","error_code":10002,
 "error_description":"The request parameters are malformed.",
 "extra":{"fatal_item_ids":[],"logid":"20261103044532710B9AB6DA77C405CD19"},
 "page_detail":{},"status_code":0,"status_msg":""}
```

### 由 `fatal_item_ids: []` 得到的硬结论

`fatal_item_ids` 是 TikTok 用来标记「哪个字段致命」的列表。它在两次请求里**都是空数组**，
配合本文件 §「完整消融实验」中「改任何单个字段结果都不变」的对照，可以确定：

> **10002 不是某个字段值写错，而是请求在「把 client_key 绑定到该产品」这一步
> 就无法继续。没有任何一个客户端可控字段能把它变成别的错误码。**

同时确认 client_key 本身有效：登录跳转 URL 带 `enter_from=dev_awy65nxalrzf8a76`，
说明 TikTok 按 developer app 处理它。

### 因此仍需 TikTok 侧回答的问题

这一轮之前"Portal 里 Web 产品没开启"的推断**已不成立**（Portal 明确是 Live 且已登记）。
剩下的可能只剩服务端绑定状态本身，必须由 TikTok 查：

- 该 `client_key` 在**当前已审核生效的版本**里，是否真的绑定了 Login Kit 的 Web 产品？
  Portal 展示的可能是草稿/未提审 revision（界面字段为只读灰色，属于 Live 或待审视图）。
- 请求里 TikTok 自己填的 `app_id: 1180`（Login Kit Web 的产品标识）与该 client_key 的绑定是否正常？

给支持的凭据（`page/detail` 的 JSON 比错误页 logid 有用得多，直接贴原文）：

```
logid 2026110304451930AA94367E8980060FDD  error_code 10002  fatal_item_ids []
logid 20261103044532710B9AB6DA77C405CD19  error_code 10002  fatal_item_ids []
```

### 顺带修掉的两个客户端问题

1. **错误从未被 App 捕获**：`onNavigationRequest` 原本只对回调域名调用
   `_handleUrl`，而 TikTok 是把 authorize URL 原地换成 `?error=...`，
   于是这段处理逻辑成了死代码——WebView 显示错误页，Dart 侧一无所知，
   直到 5 分钟超时。现已拦截 authorize 端点上的 `error` 参数并立即上报。
2. **`error_description` 被丢弃**：回调分支和 authorize 分支现在都会读取并透出它。

### 新增的诊断能力（仅 debug 构建）

`_probePageDetail()` 在检测到 authorize 错误时，于 WebView 内重放
`page/detail` 并把 JSON 响应经 `TiktokDiag` 通道打到日志；debug 下错误上报
延后 1.5 秒，避免页面被提前关闭导致请求发不出去。这条日志是后续排查的
**唯一真相来源**——错误页本身永远只说 `invalid_request`。

---

## 2026-11-03 第三次抓包：换 client_key 做了 A/B，10002 原因确定

### 结论先行

同一个账号、同一台设备、同一条 `redirect_uri`、同一份客户端代码，
**只改 `client_key`，结果完全不同**：

| client_key | authorize 结果 |
| --- | --- |
| `awy65nxalrzf8a76`（生产应用） | `error=invalid_request`，`page/detail` 返回 `error_code 10002` |
| `sbaw17e7imyq8yhdd2`（沙盒应用） | **返回 authorization code（len=261）** |

这是一次干净的对照实验。它同时排除了三类嫌疑：请求本身写错（同一份请求
换 key 就成功）、账号资格（同一个 Google 账号）、设备或网络（同一台机器）。

> **（已被后续实测推翻，见 14:40 的更正）**
>
> 当时的判断：10002 的原因是生产应用 `awy65nxalrzf8a76` 在 TikTok 服务端的
> Login Kit Web 绑定没有真正生效。
>
> ⚠️ **2026-11-03 14:11 同一台设备、同一份代码、同一个生产 `client_key`
> 已经能正常下发 code。** 授权 URL 一个参数都没变。所以「生产应用绑定
> 不生效」这个结论只在当时那个时间点成立，**不是根因**——真正变化的是
> TikTok 侧的应用状态（Portal 配置生效 / 审核通过 / 版本切换等），
> 而不是客户端或请求形态。详见本节末尾「更正」。

### 更正：10002 不是客户端问题，也不是参数问题

14:11 与 14:22 两次实测，用生产 key `awy65nxalrzf8a76` 走完整 Google 登录，
均成功拿到 code：

```
11-03 14:11:43  [TiktokWebView] authorization code received (len=261)
11-03 14:22:32  page started: https://www.tiktok.com/v2/auth/authorize/
                ?response_type=code&client_key=awy65nxalrzf8a76
                &scope=user.info.basic
                &redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2Findex.html
```

对照失败期的日志，这两次的授权 URL **逐字节相同**（同样的 5 个参数、
同样不带 PKCE、同样的 redirect_uri）。也就是说客户端从未参与 10002 的成因。

这反过来解释了为什么早前所有参数变体（带/不带 PKCE、尾斜杠有无、
Android 参数有无）返回的错误一字不差：TikTok 在校验到参数之前就已经
拒绝了这个应用，参数怎么调都不会改变结果。

**正确的结论**：10002 由 TikTok 侧的应用状态决定，随时间变化。
遇到它不要去调客户端参数，而是核对 Portal 里该应用的 Live 版本、
Login Kit → Web 的产品状态、以及 redirect URI 是否在**当前生效版本**里。

### 客户端侧的第二个障碍：Google 登录白屏（已修）

沙盒 key 第一次测试时停在 `accounts.google.com/gsi/transform` 白屏。
原因是 TikTok 的 Google 登录走 Google Identity Services 的弹窗流程
（`display=popup` + `redirect_uri=gis_transform` + `response_mode=form_post`）：
弹窗把凭据 `postMessage` 给 `window.opener` 再 `window.close()`。
`webview_flutter` 只渲染单窗口，没有 opener，于是流程永久卡死。
控制台证据：`Scripts may close only the windows that were opened by them.`

改用 `flutter_inappwebview` 并开启多窗口后解决：

```dart
InAppWebViewSettings(
  supportMultipleWindows: true,
  javaScriptCanOpenWindowsAutomatically: true,
  useShouldOverrideUrlLoading: true,
  thirdPartyCookiesEnabled: true,
  sharedCookiesEnabled: true,
  // ...
)
```

`onCreateWindow` 返回 `true`，再用带 `windowId` 的
`InAppWebView(windowId: popupWindowId)` 覆盖层承载子窗口，`window.opener`
才真实存在。实测日志：

```
[TiktokWebView] popup requested windowId=1
[TiktokWebView] page started: about:blank
[TiktokWebView] page finished: https://accounts.google.com/signin/oauth/v3/consent
[TiktokWebView] page started: https://accounts.google.com/gsi/transform
[TiktokWebView] popup closed
[TiktokWebView] blocked navigation: scheme=bytedance
[TiktokWebView] authorization code received (len=261)
```

`scheme=bytedance` 是 TikTok 尝试唤起自家 App 的深链，被非 https 拦截规则
挡掉，属正常现象。

诊断通道的调用约定同步改为
`window.flutter_inappwebview.callHandler('TiktokDiag', ...)`，
`webview_flutter` 的 `TiktokDiag.postMessage` 在新实现下不存在。

### 换 token 这一步仍会失败（后端凭据未切换）

拿到 code 后后端返回：

```
【RESPONSE】500 https://tvapi.qahwatv.com/api/user/userAuthorization
【CODE】500  【MSG】System error
→ _syncBackendToken 返回 false → StateError → auth action failed
```

原因是后端仍用**生产**的 `client_key` + `client_secret`，而 code 是签发给
沙盒 client 的，TikTok 换 token 时会拒绝。沙盒联调必须让后端同步换成
`sbaw17e7imyq8yhdd2` 对应的 key + secret。

### 生产应用待办

1. 核对 Portal 里那个已配置 Web 的应用，**App details → Client key 是否
   等于 `awy65nxalrzf8a76`**。若不等，改 `AppConfig` 里那一行即可。
2. 若确实相等，则用「同环境换 key 就通」这组对照去开单，证据强度远高于
   之前只有 logid 的求助。

---

相关文档：
- [`tiktok-deploy-tv-only.md`](./tiktok-deploy-tv-only.md) —— 服务器部署清单（已完成）
- [`tiktok-login-backend.md`](./tiktok-login-backend.md) —— 后端要做什么
