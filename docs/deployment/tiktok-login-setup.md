# TikTok Login Kit 部署与配置清单

> 最后更新：2026-10-23
> 适用：`lib/features/auth/services/tiktok_auth_service.dart`（应用内 WebView 方案）
>
> ⚠️ **本文档描述的是旧的 WebView 方案。**
> 现在 Android 端已改为**官方 TikTok OpenSDK 2.4.0 原生流程**，
> 请以 **[`tiktok-native-sdk.md`](./tiktok-native-sdk.md)** 为准。
> 本文档的**服务器部署部分（§2 之后）仍然有效**。

---

## 1. 现状诊断（真机实测结论）

在真机（Xiaomi 2312DRA50C，Android）上用受控 A/B 探测得到：

| 探测项 | 结果 |
|---|---|
| `client_key=awy65nxalrzf8a76` | ✅ TikTok 认识（`enter_from=dev_awy65nxalrzf8a76`） |
| `scope=user.info.basic` | ✅ 通过（能渲染 "Authorize with TikTok" 同意页） |
| redirect URI `https://tv.qahwatv.com/tiktok-callback/index.html` | ✅ **已注册**（对照组 `https://example.com/cb` 会返回 `&error=invalid_request`，你的不会） |
| Android App Links 验证 | ✅ `pm get-app-links` → 两个域名均 `1024`（verified） |
| 授权页点击 Authorize 后 | ❌ 渲染 TikTok 错误页（`auth_error_clientkey_body1`） |

### 关键结论

**redirect URI 本身是对的**。真正的差异在于：

TikTok Portal 的「登录工具包」按 **Web / Desktop / Android / iOS 四个独立标签页** 分别维护
redirect URI 白名单，**互相不通用**。

而原代码发出的请求是一个"纯 Web"请求（只有 `client_key` / `response_type` / `scope` /
`redirect_uri` / `state`），TikTok 会按 **Web 标签页**的白名单去校验。
但你只在 **Web 标签页**配了 URI，而实际设备构建是 Android ——
TikTok 在登录后按移动端规则校验时，命中不了。

官方 Android SDK 的请求会额外带：

```
device_platform=android
sdk_name=tiktok_sdk_auth
certificate=<SHA256 指纹，去冒号>
app_identity=<SHA256(packageName)>
```

带上这组参数，TikTok 才会把请求识别为 **Android 平台授权**，
从而按 **Android 标签页**的白名单校验 redirect_uri。

> 本次改动已在 `tiktok_auth_service.dart` 中补齐这组参数
> （`app_identity` 用纯 Dart 实现的 SHA-256，已用官方
> `d6cefddad948772ab2901efcaba23ba38f8627843381c5a99cf51eee88aea2b4` 校验一致）。

---

## 2. TikTok Developer Portal 必须做的配置

进入 <https://developers.tiktok.com> → 你的应用 **QahwatTV** → **Products → Login Kit**。

### 2.1 四个平台标签页，全部要配 redirect URI

以下 **3 个** URI 请在 **Web / Android / iOS** 三个标签页**各自**添加一遍：

```
https://tv.qahwatv.com/tiktok-callback/index.html
https://qahwatv.com/tiktok-callback/index.html
https://qahwatv.com/tiktok-callback
```

- 每个标签页最多 10 个 URI。
- 必须 `https` 开头、**静态**（不能带 query / fragment）、长度 < 512。
- **逐字符完全一致**（`tv.` 子域、`/index.html`、尾斜杠都不能差）。

### 2.2 Android 平台信息

在 **Android** 标签页填：

| 字段 | 值 |
|---|---|
| Package name | `com.video.storydrama` |
| Signing key (MD5) | `0f959fd73223a9161386058a3f659e36` |
| Signature (SHA-256) | `D5:E1:0C:FC:E8:02:22:E6:8A:62:77:C4:49:B6:EC:31:C1:10:1E:32:E5:FA:61:44:51:B8:21:7F:F4:4B:C0:64` |
| Play Store URL | 你的商店链接 |

> MD5 取法：
> ```bash
> keytool -exportcert -keystore android/app/qahwatv-drama.jks -alias qahwatv -file rel.cer
> # 然后对 rel.cer 取 MD5
> ```

### 2.3 iOS 平台信息

| 字段 | 值 |
|---|---|
| Bundle ID | `com.playlet.qahwatvshorts` |
| App Store URL | 你的商店链接 |

### 2.4 Scopes

确认 `user.info.basic` 已勾选，且 **"Included in Login Kit"** 打开。

### 2.5 提交审核（重要！）

- 应用已是 **Live** 状态。改动 redirect URI 属于配置变更，
  **必须** `Create Revision` → 改 → `Submit for review` → 等审核通过。
- 在 **Draft** 或 **In review** 状态下，Portal 里配的 URI **对线上不生效**。
- 审核需要上传**完整端到端演示视频**（登录 → 授权 → 回到 App）。

### 2.6 URL 属主验证（URL properties）

点右上角 **URL properties** → `Verify properties`，验证
`tv.qahwatv.com` / `qahwatv.com`（Domain 或 URL prefix 都行）。
应用创建于 2024-09-09 之后，**Web / Desktop URL 必须验证**。

---

## 3. 服务器部署

> **决策：只用 `tv.qahwatv.com`**，`qahwatv.com`（apex）和 `www.qahwatv.com` 全部不用。
> 详细执行清单见 [`tiktok-deploy-tv-only.md`](./tiktok-deploy-tv-only.md)。

### 3.1 关键坑：`tv.qahwatv.com` 的 CDN 会 403 掉 `.well-known` 目录

实测：

| URL | 状态 |
|---|---|
| `https://tv.qahwatv.com/.well-known/assetlinks.json` | **403** ❌ |
| `https://tv.qahwatv.com/.well-known/anything` | **403** ❌ |
| `https://tv.qahwatv.com/assetlinks.json` | 200 ✅ |
| `https://qahwatv.com/.well-known/assetlinks.json` | 200（但内容是旧包名）❌ |

`tv.` 子域走的是 openresty/CCDN，**把以 `.` 开头的目录全部拦掉了**。

**解决办法（二选一）**：

**方案 A（推荐）**：在 CDN/Nginx 上给 `tv.qahwatv.com` 放行 `/.well-known/`，让它
返回 `deploy/assetlinks.json`（Content-Type 必须是 `application/json`）。

**方案 B（兜底）**：Android 侧改用**根域名** `qahwatv.com` 作为 redirect URI，
因为 `https://qahwatv.com/.well-known/assetlinks.json` 是通的。
→ 改 `app_config.dart` 的 `tiktokRedirectUriCandidates`，把 `qahwatv.com/...` 放第一位。

> ⚠️ **本项目已决定不用这个方案**（2026-10-23）：统一走 `tv.qahwatv.com`，
> apex / www 全部弃用。详见 `tiktok-deploy-tv-only.md`。

> 注意：`https://qahwatv.com/.well-known/assetlinks.json` 当前返回的
> `Content-Type` 是 `text/plain`，Android 要求 `application/json`。
> 请一并修正。

### 3.2 要部署的文件

| 文件 | 目标位置 |
|---|---|
| `deploy/assetlinks.json` | `https://tv.qahwatv.com/.well-known/assetlinks.json` ← **关键，必须 200** |
| `deploy/assetlinks.json` | `https://tv.qahwatv.com/assetlinks.json`（兜底，已可用） |
| `deploy/apple-app-site-association` | `https://tv.qahwatv.com/.well-known/apple-app-site-association`（iOS，无扩展名、无 `.json`） |
| `deploy/tiktok-callback/index.html` | `https://tv.qahwatv.com/tiktok-callback/index.html` |

### 3.3 assetlinks.json 内容（`deploy/assetlinks.json`）

只包含**当前这个 App**：

- `com.video.storydrama` + 指纹 `D5:E1:0C:...:C0:64`

> 旧的 `com.video.qahwatvshort` 已移除 —— 那个包名对应的 App 已不再发布，
> 留着只会让 Android 装到旧包时也能认领这个域名。

### 3.4 iOS apple-app-site-association（`deploy/apple-app-site-association`）

```json
{
  "applinks": {
    "apps": [],
    "details": [
      { "appID": "C96YS2CU93.com.playlet.qahwatvshorts", "paths": ["/tiktok-callback/*"] },
      { "appID": "C96YS2CU93.com.playlet.qahwatvshorts", "paths": ["/*"] }
    ]
  }
}
```

> iOS Bundle ID 是 `com.playlet.qahwatvshorts`（Team ID `C96YS2CU93`），
> 注意**不是** Android 的 `com.video.storydrama`。

---

## 4. 代码侧配置位置

`lib/core/config/app_config.dart`：

```dart
static const String tiktokClientKey = 'awy65nxalrzf8a76';
static const String tiktokAndroidPackageName = 'com.video.storydrama';
static const String tiktokAndroidCertFingerprint = 'D5:E1:0C:...';
static const String tiktokAndroidSigningKey = '0f959fd73223a9161386058a3f659e36';
static const String tiktokScope = 'user.info.basic';

static const List<String> tiktokRedirectUriCandidates = [
  'https://tv.qahwatv.com/tiktok-callback/index.html',
  'https://qahwatv.com/tiktok-callback/index.html',
  'https://qahwatv.com/tiktok-callback',
];
```

---

## 5. 验收步骤

1. 部署完第 3 节的文件后，验证：
   ```bash
   curl -i https://tv.qahwatv.com/.well-known/assetlinks.json
   curl -i https://qahwatv.com/.well-known/assetlinks.json
   # 两者都应是 200 + Content-Type: application/json + 包含 com.video.storydrama
   ```

2. 强制重新验证 App Links：
   ```bash
   adb shell pm set-app-links --package com.video.storydrama 0 all
   adb shell pm verify-app-links --re-verify com.video.storydrama
   adb shell pm get-app-links com.video.storydrama
   # 两个域名都应显示 1024
   ```

3. 跑 App，点 TikTok 登录，看 logcat：
   ```
   [TiktokWebView] navigation: https://www.tiktok.com/v2/auth/authorize/?...device_platform=android...
   [TiktokWebView] got auth code via App Link   ← 成功
   [TikTokLoginFlow] backend sync completed        ← 后端换 token 成功
   ```

4. 若仍失败，看有没有 `tiktok-authorize-rejected` / `tiktok-redirect-uri-mismatch`，
   里面会写清楚是哪个环节被拒。
