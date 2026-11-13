# TikTok 登录 —— 只用 `tv.qahwatv.com` 的执行清单

> 决定：**只用 `tv.qahwatv.com`**，`qahwatv.com`（apex）和 `www.qahwatv.com` 全部不用。
> 实测时间：2026-10-23

---

## 一、现状（实测）

| URL | 状态 | 说明 |
|-----|------|------|
| `https://tv.qahwatv.com/.well-known/assetlinks.json` | **403** ❌ | CDN 目录级拦截，TikTok 只认这个路径 |
| `https://tv.qahwatv.com/assetlinks.json` | 200 ✅ | 内容已正确（Android 兜底路径能用，TikTok 不认） |
| `https://tv.qahwatv.com/.well-known/apple-app-site-association` | **403** ❌ | 同一个拦截规则 |
| `https://tv.qahwatv.com/apple-app-site-association` | 200 但内容是 HTML 404 页 ❌ | 不是 JSON |
| `https://tv.qahwatv.com/tiktok-callback/index.html` | 200 但内容是旧版 ❌ | 还带 JS 跳 apex |
| `https://tv.qahwatv.com/tiktok-callback` | 301 → `/tiktok-callback/` | 目录形式也可用 |

**403 是 CDN 拦的，不是文件问题**（已实测排除）：
- 连不存在的文件也 403：`/.well-known/anything-xyz-123` → 403
- 所有路径写法都 403：双斜杠、`%2e` 编码、`.WELL-KNOWN` 大小写、加 query string
- 响应头：`Server: openresty` + `via: EA-SGP-EDGE7-CACHE9` + `X-CCDN-CacheTTL: 86400`
  → **阿里云 CDN 的「以点开头的目录」拦截规则**
- 直连源站 IP 也一样 403（说明是 CDN 边缘规则，不是源站 nginx）

---

## 二、要做的事（3 步，按顺序）

### 步骤 1：CDN 放行 `.well-known/`（**必做，否则下面传了也没用**）

阿里云 CDN 控制台 → 域名 `tv.qahwatv.com` → 访问控制 / 回源配置 → 找到
**拦截以 `.` 开头目录**的那条规则 → 删掉或加例外 `/.well-known/*`。

验证（必须 200）：

```bash
curl -I https://tv.qahwatv.com/.well-known/assetlinks.json
# 期望: HTTP/2 200 + Content-Type: application/json
```

> 如果这条规则在**宝塔/Nginx 源站**而不是 CDN，也要同步改源站。
> 直连源站 IP 测出来还是 403，建议**两边都查**。

### 步骤 2：传 3 个文件

| 本地文件 | 传到 | 说明 |
|---------|------|------|
| `deploy/assetlinks.json` | `https://tv.qahwatv.com/.well-known/assetlinks.json` | Android App Links 验证 |
| `deploy/assetlinks.json` | `https://tv.qahwatv.com/assetlinks.json` | 兜底（已是新的，可不重传） |
| `deploy/apple-app-site-association` | `https://tv.qahwatv.com/.well-known/apple-app-site-association` | iOS，**无扩展名** |
| `deploy/tiktok-callback/index.html` | `https://tv.qahwatv.com/tiktok-callback/index.html` | 去掉旧的自动跳转 |

**Content-Type 必须是 `application/json`**（`assetlinks.json`）。
如果 Nginx 认不出扩展名，加：

```nginx
location = /.well-known/assetlinks.json {
    default_type application/json;
}

location = /.well-known/apple-app-site-association {
    default_type application/json;
}
```

`apple-app-site-association` **必须没有 `.json` 后缀**，且 Content-Type 也要 `application/json`。

验证：

```bash
curl -I https://tv.qahwatv.com/.well-known/assetlinks.json
curl -I https://tv.qahwatv.com/.well-known/apple-app-site-association
# 两条都要 200 + application/json
```

### 步骤 3：TikTok Developer Portal 配置

| 项目 | 填什么 |
|------|--------|
| Android 标签页 → Redirect URI | `https://tv.qahwatv.com/tiktok-callback/index.html` |
| iOS 标签页 → Redirect URI | `https://tv.qahwatv.com/tiktok-callback/index.html` |
| URL properties | `tv.qahwatv.com` → **Verify properties** |
| 域名归属 | TikTok 给的 `tiktok-verification.txt` 传到 `https://tv.qahwatv.com/.well-known/tiktok-verification.txt` |

⚠️ **改了 redirect URI 属于配置变更**，必须
**Create Revision → Submit for review → 等审核通过**才生效。
不审核的话，Portal 里看着配好了，实际不生效。

---

## 三、代码侧已经改好的部分

| 文件 | 改动 |
|------|------|
| `lib/core/config/app_config.dart` | 候选列表只剩 `tv.qahwatv.com` 两个（`index.html` + 目录形式），apex/www 全删 |
| `android/app/src/main/AndroidManifest.xml` | 删掉 `qahwatv.com` 的 TikTok intent-filter，只留 `tv.qahwatv.com` |
| `lib/features/auth/services/tiktok_auth_service.dart` | PKCE（hex SHA-256，对齐官方 SDK）、`clearWebViewState` 修复、回传 `redirectUri` |
| `lib/core/network/api_service.dart` | 透传 `redirectUri` / `codeVerifier` 给后端 |
| `lib/core/model/api_endpoints.dart` | `PassportType.tiktok` 改成 `7`（`4` 已被 Facebook 占用），**待后端确认** |
| `ios/Runner/Runner.entitlements` | 已有 `applinks:tv.qahwatv.com` ✅ |

---

## 四、⚠️ 上面三步做完**不一定**能登录通

真机实测过完整对照矩阵，**用一个完全瞎编的 `client_key`**，TikTok 返回的错误和
你的真 key **完全一样**（都是 `invalid_request`）：

| # | 请求 | 结果 |
|---|------|------|
| A | 官方 SDK 精确格式（无尾斜杠 + 全参数 + PKCE hex challenge） | `invalid_request` |
| B | 去掉 `redirect_uri` | `param_error` / `error_type=redirect_uri` |
| F | **完全瞎编的 16 位 `client_key`** | `invalid_request` |
| G | 真 key 但去掉全部 Android 参数 | `invalid_request` |
| H | 真 key 但用旧 App 的证书指纹 | `invalid_request` |

- B 证明 `redirect_uri` 传到了、格式没被拒
- **F 是瞎编的 key，错误却一模一样** → TikTok 在校验 `client_key` 之前就拒了
  → **问题在 TikTok 侧的应用配置**，不在 redirect_uri / 证书 / PKCE / assetlinks

TikTok 授权页现在的文案是：
> **出错了** — 无法通过 TikTok 进行登录。这可能是特定应用设置所致。

所以上面三步做完如果还是这个错，**去 Portal 查这几项**：

- [ ] `client_key awy65nxalrzf8a76` 是否还有效、是否属于正确的那个应用
- [ ] Login Kit 是否**审核通过**（未通过时授权页就长这样）
- [ ] redirect URI 是否配在**当前生效的 revision**（改过要重新提交审核）
- [ ] 沙箱 / 生产环境是否搞混
- [ ] 该应用是否还在「未发布 / Draft」状态

相关文档：
- [`tiktok-login-backend.md`](./tiktok-login-backend.md) —— 后端要做什么
- [`tiktok-login-setup.md`](./tiktok-login-setup.md) —— 完整配置说明
