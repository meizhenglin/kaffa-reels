# TikTok 登录 —— 后端实现说明

> 面向：后端开发
> 前端：`lib/features/auth/services/tiktok_auth_service.dart`（应用内 WebView 方案）
> 最后更新：2026-10-23

---

## 0. 一句话总结

后端要做的事只有一件：**拿前端传来的 TikTok `code`，调 TikTok 官方接口换成 `access_token` / `open_id`，
然后用 `open_id` 走你现有的 `userAuthorization` 落库逻辑，返回 App 自己的 token。**

前端已经把用户授权这一步做完了，TikTok 的 `code` 已经拿到了（只是目前因为 TikTok 服务端
`url doesn't match` 拿不到，见文末「当前阻塞点」）。

---

## 1. 前端现在发过来的请求

`POST /api/user/userAuthorization`
`Content-Type: application/json`

```json
{
  "passportType": 7,
  "passportName": "TikTok_access_token",
  "code": "TikTok返回的授权码",
  "redirectUri": "https://tv.qahwatv.com/tiktok-callback/index.html",
  "codeVerifier": "本次授权用的PKCE校验串",
  "invitedCode": "xxx"
}
```

代码位置：`lib/core/network/api_service.dart` → `tiktokLogin()`

> ✅ `redirectUri` / `codeVerifier` 前端**已经补齐**（2026-10-23）。
> 后端直接读这两个字段即可，字段名就是上面这样。

### ⚠️ 唯一还需要后端确认的事：`passportType`

`lib/core/model/api_endpoints.dart` 里现在是：

```dart
static const int facebook = 4;   // 原有
static const int tiktok   = 7;   // 已改成 7，待后端确认
```

**请后端确认 TikTok 分支用哪个 `passportType` 值。**
- 如果后端约定就是 `7` → 不用改，前端已就位
- 如果后端用别的值 → 告诉前端具体数字，改一行常量即可
- ⚠️ 千万别用 `4`，`4` 已经被 Facebook 占用了

---

## 2. 后端核心流程（两步）

```
前端 code
   │
   ├─① POST https://open.tiktokapis.com/v2/oauth/token/     换 token
   │      → access_token, refresh_token, open_id, expires_in
   │
   └─② GET  https://open.tiktokapis.com/v2/user/info/       读用户资料
          → display_name, avatar_url
          │
          ▼
      用 open_id 落库 → 返回 App token（跟其它登录方式一样）
```

---

## 3. 第一步：用 code 换 access_token

**Endpoint**

```
POST https://open.tiktokapis.com/v2/oauth/token/
Content-Type: application/x-www-form-urlencoded
```

**请求参数**（官方定义）

| 参数 | 必填 | 说明 |
|---|---|---|
| `client_key` | ✅ | `awy65nxalrzf8a76`（Portal 拿的） |
| `client_secret` | ✅ | Portal 拿的，**只存在后端**，绝不能下发到 App |
| `code` | ✅ | 前端传来的授权码，**需要 URL decode** |
| `grant_type` | ✅ | 固定 `authorization_code` |
| `redirect_uri` | ✅ | **必须和请求 code 时用的完全一致** |
| `code_verifier` | 移动端必填 | PKCE 校验串（Android 走 PKCE 时必传） |

**curl 示例**

```bash
curl --location --request POST 'https://open.tiktokapis.com/v2/oauth/token/' \
--header 'Content-Type: application/x-www-form-urlencoded' \
--header 'Cache-Control: no-cache' \
--data-urlencode 'client_key=awy65nxalrzf8a76' \
--data-urlencode 'client_secret=YOUR_CLIENT_SECRET' \
--data-urlencode 'code=CODE_FROM_FRONTEND' \
--data-urlencode 'grant_type=authorization_code' \
--data-urlencode 'redirect_uri=https://tv.qahwatv.com/tiktok-callback/index.html' \
--data-urlencode 'code_verifier=CODE_VERIFIER'   # 移动端必传
```

**成功响应**

```json
{
  "access_token": "act.xxx",
  "expires_in": 86400,
  "open_id": "723f24d7-e717-40f8-a2b6-cb8464cd23b4",
  "refresh_expires_in": 31536000,
  "refresh_token": "rft.xxx",
  "scope": "user.info.basic",
  "token_type": "Bearer"
}
```

**失败响应**（要透传错误原因给前端排查）

```json
{
  "error": "invalid_request",
  "error_description": "Redirect_uri is not matched with the uri when requesting code.",
  "log_id": "202206221854370101130062072500FFA2"
}
```

> ⚠️ `log_id` 一定要记进后端日志，出问题时 TikTok 官方要求提供这个。

**常见错误码**（TikTok 官方 Error Handling）

| 错误 | 含义 | 排查方向 |
|---|---|---|
| `invalid_request` | 参数缺失/格式错 | 检查 `redirect_uri` 是否和前端一致、`code_verifier` 是否漏传 |
| `invalid_client` | client_key/secret 不对 | 检查环境变量 |
| `invalid_grant` | code 已过期/已用过 | code 有效期很短，**只能用一次** |
| `invalid_scope` | scope 没申请 | 确认 `user.info.basic` 已勾选并包含在 Login Kit 里 |

---

## 4. 第二步：读用户资料

**Endpoint**

```
GET https://open.tiktokapis.com/v2/user/info/?fields=open_id,union_id,avatar_url,display_name
Authorization: Bearer <access_token>
```

**curl 示例**

```bash
curl -L -X GET \
 'https://open.tiktokapis.com/v2/user/info/?fields=open_id,union_id,avatar_url,display_name' \
 -H 'Authorization: Bearer act.xxx'
```

**响应**

```json
{
  "data": {
    "user": {
      "open_id": "723f24d7-e717-40f8-a2b6-cb8464cd23b4",
      "union_id": "c9c60f44-a68e-4f5d-84dd-ce22faeb0ba1",
      "avatar_url": "https://p19-sign.tiktokcdn-us.com/...jpeg",
      "display_name": "Tik Toker"
    }
  },
  "error": { "code": "ok", "message": "", "log_id": "..." }
}
```

**`user.info.basic` scope 只能拿到这几个字段**：
`open_id` / `union_id` / `avatar_url` / `avatar_url_100` / `avatar_large_url` / `display_name`

> `username` / `is_verified` / `follower_count` 等需要额外 scope（`user.info.profile` / `user.info.stats`），
> 要用得单独在 Portal 申请。当前 App 只需要昵称 + 头像，够用。

---

## 5. 落库 / 返回

拿到 `open_id` 后，后端应该：

1. 用 `open_id` 作为 TikTok 用户的唯一标识（**不要用 `display_name`**，会重名会变）
2. 复用你现有的 `userAuthorization` 落库逻辑，**新建或更新用户**
3. 返回 App 自己的 token

**响应格式必须和现有登录方式完全一致**（前端强依赖这个结构）：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "token": "APP_TOKEN",
    "userId": "...",
    "nickName": "Tik Toker",
    "userAvatar": "https://.../avatar.jpeg",
    "passportType": 4,
    "isVip": 0,
    "vipEndTime": null
  }
}
```

前端解析逻辑在 `lib/core/network/api_service.dart`：

```dart
if (code == ApiErrorCode.success || code == ApiErrorCode.ok) {
  return ApiResponse.success(body['data']);   // data 里必须有 token
}
```

- 外层 `code` 必须是 `0` 或 `200`（`ApiErrorCode.success` / `ok`）
- `data.token` 必须存在且非空，否则前端会判失败
- 字段名对应关系：`nickName` → 昵称，`userAvatar` → 头像，`userId` → 用户 ID

---

## 6. 落库时的字段映射

| TikTok | App 字段 |
|---|---|
| `open_id` | 用户唯一标识（建议存 `tiktok_open_id`） |
| `display_name` | `nickName` |
| `avatar_url` | `userAvatar` |
| `union_id` | 可选，跨 App 同一开发者下唯一，可存备用 |

TikTok **不返回** email、手机号。`email` 字段留空。

---

## 7. refresh_token 处理（可选但建议）

`access_token` 有效期 **24 小时**，`refresh_token` 有效期 **365 天**。

- 如果只是「登录一次拿一个 App token」的简单模式 → 可以不存 refresh_token，用户下次重新授权即可
- 如果要「长期保持登录」→ 需要存 `refresh_token`，并在过期前刷新

刷新接口（和换 token 同 endpoint）：

```
POST https://open.tiktokapis.com/v2/oauth/token/
grant_type=refresh_token
&client_key=...&client_secret=...&refresh_token=...
```

---

## 8. 安全要求

| 项 | 要求 |
|---|---|
| `client_secret` | **只存在后端**（环境变量 / 配置中心），绝不能进 App 包 |
| `refresh_token` | 同上，加密存储 |
| `code` | 一次性，用完即弃；**不要打日志**（等同密码） |
| `access_token` | 存库要加密 |
| 日志 | 打 `log_id` / `open_id` / 错误码；**不要打** `code` / `client_secret` / `access_token` |

---

## 9. Java / Spring Boot 参考实现

```java
@RestController
@RequestMapping("/api/user")
public class TikTokAuthController {

    // client_key / client_secret 从配置中心读，勿硬编码
    @Value("${tiktok.client-key}")     private String clientKey;
    @Value("${tiktok.client-secret}") private String clientSecret;
    @Value("${tiktok.redirect-uri}")  private String redirectUri;

    @PostMapping("/tiktokLogin")
    public R<?> tiktokLogin(@RequestBody TikTokLoginReq req) {
        // 1. 换 token
        String form = "client_key=" + enc(clientKey)
                + "&client_secret=" + enc(clientSecret)
                + "&grant_type=authorization_code"
                + "&code=" + enc(URLDecoder.decode(req.getCode(), UTF_8))
                + "&redirect_uri=" + enc(req.getRedirectUri() != null
                                          ? req.getRedirectUri() : redirectUri);
        if (StringUtils.hasText(req.getCodeVerifier())) {
            form += "&code_verifier=" + enc(req.getCodeVerifier());
        }

        JsonNode tok = postForm("https://open.tiktokapis.com/v2/oauth/token/", form);
        if (tok.has("error")) {
            // 把 TikTok 的 log_id 记下来，方便官方排查
            log.error("tiktok token exchange failed: error={}, desc={}, log_id={}",
                    tok.path("error").asText(),
                    tok.path("error_description").asText(),
                    tok.path("log_id").asText());
            return R.fail("TikTok authorization failed");
        }
        String accessToken = tok.path("access_token").asText();
        String openId     = tok.path("open_id").asText();

        // 2. 读用户资料
        JsonNode user = getUserInfo(accessToken);

        // 3. 落库 + 发 App token（复用现有 userAuthorization 逻辑）
        return userService.loginByTikTok(
            openId,
            user.path("display_name").asText(null),
            user.path("avatar_url").asText(null),
            PASS_PORT_TYPE_TIKTOK);
    }
}
```

---

## 10. 当前阻塞点（**不阻塞后端开发，但阻塞联调**）

后端这套写完也**暂时跑不通**，因为 TikTok 服务端在授权阶段就拒绝了请求。

### 现在的确切错误（2026-10-23 真机实测）

TikTok 授权页返回：

```
error=invalid_request
logid=202610230509012468F862E478C31E9459
```

页面文案（TikTok 官方中文）：
> **出错了**
> 无法通过 TikTok 进行登录。这可能是特定应用设置所致。

TikTok 内部接口 `/tiktok/v2/oauth/page/detail/` 返回：

```json
{"error":"invalid_request","error_code":10002,
 "error_description":"The request parameters are malformed."}
```

### 关键判断：**这不是 deploy 文件的问题**

我在真机上跑了完整对照矩阵，**所有变体返回的 error 一模一样**：

| # | 请求 | 结果 |
|---|------|------|
| A | 官方 SDK 精确格式（无尾斜杠 + 全参数 + PKCE hex challenge） | `invalid_request` |
| B | 去掉 `redirect_uri` | `param_error` / `error_type=redirect_uri` |
| D | 只留 `client_key` | `param_error` / `error_type=redirect_uri` |
| F | **完全瞎编的 16 位 `client_key`** | `invalid_request` |
| G | 真 key 但去掉全部 Android 参数 | `invalid_request` |
| H | 真 key 但用旧 App 的证书指纹 | `invalid_request` |
| I | 真 key 但去掉 `scope` | `invalid_request` |

**读法：**
- B/D 证明 `redirect_uri` 确实传到了、格式没被拒（否则也会是 `param_error`）
- F 是**瞎编的 key**，返回的 `invalid_request` 和真 key（A）**完全相同**
  → 说明 TikTok 在校验 `client_key` 之前就拒了
  → 问题出在 **client_key 本身 / 应用配置**，不在 redirect_uri、证书、PKCE
- G/H/I 三个不同维度的差异**全都被同一个错误吞掉**
  → TikTok 根本没走到那几项的校验逻辑

**结论**：`url doesn't match` 那个老错误已经变成了笼统的 `invalid_request`，
而真正卡住的是 **TikTok 侧的应用配置**（client_key 无效 / Login Kit 未审核通过 /
redirect URI 没配在生效版本里 / 域名归属没验证）。

### 服务器侧还有 3 个必须修的（但都不是「唯一原因」）

**① `tv.qahwatv.com/.well-known/` 被 CDN 全拦 403**

```
403  https://tv.qahwatv.com/.well-known/assetlinks.json
403  https://tv.qahwatv.com/.well-known/anything      ← 整个目录被拦
403  https://qahwatv.com/.well-known/                 ← apex 目录也被拦
200  https://tv.qahwatv.com/assetlinks.json            ← 根路径反而通
```

`Server: openresty` + `via: EA-SGP-EDGE...-CACHE` + `X-CCDN-CacheTTL: 86400`
→ 阿里云 CDN 的**目录级**拦截规则，不是文件缺失。

TikTok 服务端验证 Android App Link 时必须能 fetch
`https://tv.qahwatv.com/.well-known/assetlinks.json`，现在直接 403 →
**TikTok 无法确认 `tv.qahwatv.com` 属于这个 App** → 拒绝授权。

> 你手机 `pm get-app-links` 显示 1024 verified，是因为 Android 自己会去试根路径兜底；
> **TikTok 服务器不做这个兜底**，它只认 `.well-known`。

**② `qahwatv.com/.well-known/assetlinks.json` 内容是旧包名**

```
200 text/plain
[{"package_name":"com.video.qahwatvshort", "sha256...":"49:11:77:..."}]   ← 旧 App
```

现在包名是 `com.video.storydrama`、指纹是 `D5:E1:0C:...`（已从安装的 APK 用
`apksigner` 核验，与 `app_config.dart` 一致）。而且 Content-Type 是 `text/plain`，
Android/TikTok 要求 `application/json`。

> 根路径 `https://qahwatv.com/assetlinks.json` 已经是**新的**（`com.video.storydrama`），
> 说明你上次部署只更新了根路径那份，`.well-known` 那份没更新。

**③ 域名归属验证（URL properties）没做**

`tv.qahwatv.com` 的 DNS TXT 只有 `google-site-verification=...`，
**没有任何 TikTok 验证记录**；TikTok 的签名文件也没部署
（`https://qahwatv.com/tiktok-verification.txt` → 404）。

TikTok 官方文档明确：**2024-09-09 之后创建的应用必须验证 URL properties**，
在 Portal 页面点 **URL properties → Verify properties** 验证 `tv.qahwatv.com`。

### 解封后要做的事

1. 上述 ①②③ 修好
2. Portal 里如果改了 redirect URI，属于配置变更 → 需要
   **Create Revision → Submit for review → 等审核通过**才生效
3. ✅ 前端 PKCE **已经补完**（`code_verifier` / `code_challenge`，用官方 SDK 的 hex SHA-256）
4. 联调时后端打日志确认：
   - 换 token 请求有没有发出去
   - TikTok 返回的 `error` / `error_description` / `log_id`
   - 收到的 `code` 长度（应为几十位字符）

---

## 11. 给后端的 Checklist

- [ ] 确认 TikTok 的 `passportType` 用什么值（前端现在发 `7`，`4` 已被 Facebook 占用）
- [ ] `POST /api/user/userAuthorization` 支持 TikTok 分支
- [ ] 接收 `code`、`redirectUri`、`codeVerifier`（前端已全部补齐）
- [ ] `client_secret` 存配置中心，不进代码库
- [ ] 调 `POST https://open.tiktokapis.com/v2/oauth/token/` 换 token
- [ ] 调 `GET https://open.tiktokapis.com/v2/user/info/` 读昵称头像
- [ ] 用 `open_id` 作为用户唯一标识落库
- [ ] 返回 `{code:200, msg:"success", data:{token, userId, nickName, userAvatar, ...}}`
- [ ] 失败时把 TikTok 的 `log_id` 记进日志
- [ ] `code` / `access_token` / `client_secret` 不打日志

---

## 12. 2026-11-03 联调：授权已通，卡在换 token（**后端必读**）

### 12.1 授权阶段已经通了

用沙盒 `client_key = sbaw17e7imyq8yhdd2` 在真机上走完整流程，
WebView 成功拿到 authorization code（len=261）：

```
[TiktokWebView] popup requested windowId=1
[TiktokWebView] page finished: https://accounts.google.com/signin/oauth/v3/consent
[TiktokWebView] page started: https://accounts.google.com/gsi/transform
[TiktokWebView] popup closed
[TiktokWebView] authorization code received (len=261)
```

也就是说**前端这一侧没有问题**：多窗口 WebView 已经能把 Google 登录弹窗
跑通，code 也拿到了。第 10 节里那些 TikTok 侧的配置阻塞（10002），
换成沙盒应用后不再出现——同账号、同设备、同 redirect_uri、同代码，
只有 client_key 不同，生产 key 报 10002、沙盒 key 直接发 code。

### 12.2 现在卡在这里

前端把 code 发给后端后：

```
class=com.qahwatv.shortplay.controller.UserController
method=userAuthorization
param={"code":"uJYl4vIt...K8FZtImK3eJySdOXvwJFP8e_SqQl6z-jux0Dh5dahghDeInP8pY90c*v!6361.u2",
       "passportName":"TikTok_access_token",
       "passportType":7}
result=ApiResponse{code=-500,msg=System error}
```

**注意后端打印的入参只有 3 个字段，`redirectUri` 不见了。**

前端代码是确实发了 4 个字段的：

```dart
data: {
  'passportType': PassportType.tiktok,   // 7
  'passportName': code,                  // 已从常量改为 code
  'code': code,
  if (redirectUri != null && redirectUri.isNotEmpty)
    'redirectUri': redirectUri,          // 非空，一定会带上
  ...
}
```

日志把 261 字符的 code 都完整打出来了，不是截断。所以最合理的解释是：
**后端 `userAuthorization` 的请求 DTO 里没有 `redirectUri` 字段，
Jackson 反序列化时把不认识的属性静默丢弃了。**

这足以单独造成 500：TikTok 换 token 时 `redirect_uri` 必填，且必须与
请求 code 时**逐字节一致**。后端拿不到就只能用配置里的默认值去猜，
一旦与前端实际用的值不同，TikTok 返回 `invalid_request`
（`Redirect_uri is not matched with the uri when requesting code.`），
后端再兜底成 `System error`。

### 12.3 后端需要确认/修改的三件事

**① DTO 必须接收 `redirectUri` 和 `codeVerifier`**

```java
public class UserAuthorizationReq {
    private Integer passportType;
    private String  passportName;
    private String  code;
    private String  redirectUri;    // ← 当前缺失
    private String  codeVerifier;   // ← 当前缺失（PKCE 时必传）
    private String  invitedCode;
    // getter / setter
}
```

并且换 token 时**优先用请求里带上来的 `redirectUri`**，配置里的值只做兜底：

```java
String redirectUri = StringUtils.hasText(req.getRedirectUri())
        ? req.getRedirectUri()
        : defaultRedirectUri;
```

**② `passportType=7` 是否真的有这个分支**

如果 `userAuthorization` 里只有 0/1/5/6 的 switch-case，收到 7 会落到
default 抛异常 → 同样表现为 `-500 System error`。
请确认：
- 后端约定的 TikTok 值是多少？不是 7 的话告诉前端，改一行常量
- 若是 7，确认分支已实现且能进入

**③ `passport_name` 的唯一性约定**

前端已把 `passportName` 从硬编码常量 `'TikTok_access_token'`
改成传 `code`（每次登录唯一）。原因：如果 `passport_name` 上有唯一索引
（Google 登录把 idToken 包成 JSON 塞进来，看起来就是为了满足这一点），
常量值会让第一个 TikTok 用户之后的每个人直接撞约束。

请确认 TikTok 分支对 `passportName` 的期望值。如果后端要求别的形式，
告知前端即可。

### 12.4 换 token 时请在日志里打出 TikTok 的原始错误

现在 500 是笼统的 `System error`，无法区分是「没走到换 token」还是
「换 token 被拒」。请在 catch 里把 TikTok 返回的
`error` / `error_description` / `log_id` 原样记进日志并透出到响应 msg，
否则前端和 TikTok 支持都无法定位。

### 12.5 沙盒联调注意

code 是签发给**沙盒 client** 的，后端必须用
`sbaw17e7imyq8yhdd2` 对应的 `client_key` + `client_secret` 才能换成功。
用生产凭据换沙盒 code 必然 `invalid_client`。联调期间两边要同时切。
