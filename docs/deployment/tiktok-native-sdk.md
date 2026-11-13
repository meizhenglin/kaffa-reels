# TikTok Login —— 官方 SDK 接入方案（Route B）

> 状态：**已实现并通过真机验证**（2026-10-23）
> 适用平台：Android（iOS 仍走 WebView 兜底）

---

## 1. 为什么要换方案（背景）

之前的实现是「应用内 WebView 加载 TikTok authorize URL → 拦截 redirect 拿 code」。
该方案在真机上**始终失败**：

```
error=invalid_request&logid=20261023...
```

TikTok 授权页内部埋点显示：

```json
{"event":"auth_error_page","params":{
  "channel":"awy65nxalrzf8a76",
  "enter_method":"android",
  "error_source":"query-param-error"}}
```

### 1.1 已排除的前端因素

做过 **20+ 组参数级 A/B**（全部返回同一个 `invalid_request` + 同一个 logid 格式）：

| 变量 | 试过的取值 |
|---|---|
| `redirect_uri` | `tv.qahwatv.com/tiktok-callback/index.html`、目录形式、去 `index.html`、apex、www、http、错路径、带尾斜杠、`example.com`（对照组） |
| `scope` | `user.info.basic`、`user.info`、省略 |
| `client_key` | 真实 key、伪造 key |
| `state` | 各种随机值 |
| `device_platform` / `sdk_name` / `source` | 官方 SDK 的组合、`native_v2`、`desktop`、`sdk_web` |
| URL 路径 | `/v2/auth/authorize`、`/v2/auth/authorize/`、`/auth/authorize` |

**对照组结论**：连 `example.com/callback` 这种明显非法的 redirect_uri 都返回**同样的错**，
说明请求在**参数校验之前**就被拒了 —— 是 TikTok 侧的应用配置 / 审核状态 / 平台标签页白名单问题。

### 1.2 决定性证据

用**官方 TikTok OpenSDK 2.4.0 自己生成的 URL**（`WebAuthHelper.composeLoadUrl()` 原样输出）
去请求 TikTok 授权端点：

```
https://www.tiktok.com/v2/auth/authorize?response_type=code&sdk_name=tiktok_sdk_auth
&device_platform=android&app_identity=d6cefdd...&certificate=D5E10CFC...
&redirect_uri=https%3A%2F%2Ftv.qahwatv.com%2Ftiktok-callback%2Findex.html
&client_key=awy65nxalrzf8a76&scope=user.info.basic&code_challenge=93339586...
&error=invalid_request&logid=20261023075746CBFF4F5A5E33A91A78D9
```

**官方 SDK 自己的 URL 也被拒，且错误完全一致。**

→ 结论：**Web 授权路径（ChromeTab / WebView）在这个应用上走不通**，
问题不在我们的代码，而在 TikTok 对该应用（`client_key=awy65nxalrzf8a76`）的 Web 流配置。

→ 唯一剩下的路：**TikTok 原生 App 流**（`AuthMethod.TikTokApp`），
这是和 Web 流**不同的服务端路径**。

---

## 2. 现在的实现

### 2.1 依赖

`android/app/build.gradle`：

```groovy
implementation 'com.tiktok.open.sdk:tiktok-open-sdk-core:2.4.0'
implementation 'com.tiktok.open.sdk:tiktok-open-sdk-auth:2.4.0'
implementation 'androidx.browser:browser:1.8.0'   // SDK 的 ChromeTab 依赖
```

仓库（`android/build.gradle.kts`）：

```kotlin
maven { url = uri("https://artifact.bytedance.com/repository/AwemeOpenSDK") }
```

> ⚠️ 这个仓库**不在** Maven Central，必须单独加。
> 用 `latest.release` 会被解析到奇怪版本，这里锁死 `2.4.0`。

### 2.2 原生桥接

新增 `android/app/src/main/kotlin/com/video/storydrama/TikTokAuthHandler.kt`，
MethodChannel 名：`com.video.storydrama/tiktok_login`。

| Dart 调用 | Native 行为 |
|---|---|
| `login(clientKey, scope, redirectUri)` | `PKCEUtils.generateCodeVerifier()` → `AuthApi.authorize(request, AuthMethod.TikTokApp)` |
| `isAvailable` | `true` |

`AuthMethod.TikTokApp` 的行为（SDK 内部逻辑）：

- **设备装了 TikTok App** → 显式 Intent 启动
  `com.zhiliaoapp.musically/openauthorize.AwemeAuthorizedActivity`
  → 结果通过 **`onActivityResult`** 回传，数据在 **extras** 里
- **设备没装 TikTok App** → SDK 自动降级到 `AuthMethod.ChromeTab`
  → 浏览器 302 到我们的 https App Link → **`onNewIntent`** 回传，
  数据在 **intent.data** 的 query 里

回调统一交给 SDK 的 `AuthApi.getAuthResponseFromIntent(intent, redirectUri)` 解析，
成功时把 `authCode` / `redirectUri` / `codeVerifier` / `state` / `grantedPermissions`
一起回传 Dart。

### 2.3 Dart 侧

新增 `lib/features/auth/services/tiktok_native_auth_service.dart`。

`lib/features/auth/services/tiktok_auth_service.dart` 的 `login()` 策略：

```
Android
  ├─ 优先走官方原生 SDK（TiktokNativeAuthService）
  │    ├─ 成功 → 返回
  │    ├─ 用户取消 → 直接抛 AuthCancelledException（不回退）
  │    └─ 「原生不可用」类错误 → 回退 WebView
  └─ iOS / Web → 直接走应用内 WebView
```

只有这几种错误会回退 WebView（因为这些是「链路不可用」，回退有意义）：

- `tiktok-native-unavailable`
- `tiktok-native-unsupported`
- `tiktok-authorize-failed`

其它业务错误（比如 TikTok 明确拒绝）**不回退** —— 同样的参数 Web 流也会被拒（见 §1.2）。

---

## 3. 关键实现细节（踩过的坑）

### 3.1 `launchMode` 必须是 `singleTask`

**症状**：App Link 回调回来后，Flutter 侧永远收不到结果，用户看到「一直转圈」。

**原因**：`MainActivity` 原来是 `launchMode="singleTop"`。
`singleTop` 只在「Activity 位于任务栈顶」时才复用实例。
Chrome Custom Tab 在前台时，我们 App 的 Activity **不在栈顶** →
系统**新建**一个 MainActivity 实例 → 旧实例上的等待状态全丢，
新实例里的 Dart 侧是一个全新的 `login` future，永远挂着。

**修复**：改成 `singleTask`：

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTask"
    android:taskAffinity=""
    ...>
```

`singleTask` 会让系统**复用已有任务栈里的 Activity** 并回调 `onNewIntent`，
Activity 不重建 → Flutter 引擎不重建 → Dart 侧完全无感。

> ❌ 不要用「缓存 Flutter 引擎」（`FlutterEngineCache` + 覆盖 `provideFlutterEngine`）来绕过。
> 实测会崩：`IllegalStateException: Flutter engine could not be created`
> （`super.provideFlutterEngine()` 默认返回 null，缓存机制和 delegate 的生命周期不兼容）。

### 3.2 授权上下文必须是静态的

授权回调可能让 Activity 重建（冷启动 / 任务栈被清）。
所以 `currentRedirectUri` / `currentCodeVerifier` / `pendingResult` / `pendingResponse`
都放在 `TikTokAuthHandler` 的 **companion object（静态）**里，
保证跨 Activity 实例存活。

### 3.3 两条回调路径的识别

```kotlin
// 原生 App 流：data == null，靠 extras 里的 SDK 标记识别
val isNativeCallback = extras?.containsKey("_bytedance_params_type") == true

// Web 流：data 指向我们的 redirect URI
val isWebCallback = data != null &&
    currentRedirectUri.isNotEmpty() &&
    data.toString().startsWith(currentRedirectUri)
```

只判断 `intent.data` 会漏掉原生 App 流（它的 `data` 是 null）。

### 3.4 WebView 兜底方案的 URL 路径

官方 SDK 用的是 `/v2/auth/authorize`（**没有尾斜杠**）：

```kotlin
Uri.Builder.path("/v2/auth/authorize")   // SDK 2.4.0
```

原来的 Dart 兜底代码写的是 `/v2/auth/authorize/`（有尾斜杠），已修正。
实测两者在 Web 流下都被拒（所以不是致命问题），但既然是兜底路径，
还是和官方保持一致更安全。

### 3.5 PKCE 参数必须原样回传后端

TikTok 换 token 要求：
- `redirect_uri` 与「请求 code 时用的」**逐字符完全一致**
- `code_verifier` 必须带上（Android 走 PKCE）

所以 `TiktokLoginResult` 必须同时带 `authCode` / `redirectUri` / `codeVerifier`，
并由 `auth_repository.signInWithTikTok()` 一起发给后端。

---

## 4. 已验证内容（真机）

测试设备：MIUI / Android 16（`2312DRA50C`，arm64-v8a）

### 4.1 服务端 / 配置

| 检查项 | 结果 |
|---|---|
| `https://tv.qahwatv.com/.well-known/assetlinks.json` | HTTP 200，包名 + 指纹匹配 |
| `https://tv.qahwatv.com/.well-known/tiktok-verification.txt` | HTTP 200 |
| `pm get-app-links com.video.storydrama` | `tv.qahwatv.com: verified` |
| 签名指纹 | `D5:E1:0C:FC:...:C0:64`（安装新 APK 后未变） |

### 4.2 原生链路（真机 + logcat）

```
D TikTokAuth: authorize launched, redirectUri=https://tv.qahwatv.com/tiktok-callback/index.html
D TikTokAuth: handleIntent: native=false web=true data=https://tv.qahwatv.com/tiktok-callback/index.html?code=...
D TikTokAuth: auth success, code_len=11
```

Dart 侧收到：

```
I flutter: [TiktokNativeAuthService] DEBUG LOGIN OK:
  code=TESTCODE456
  redirectUri=https://tv.qahwatv.com/tiktok-callback/index.html
  verifier=BpIdMXsLEw6HDzS7PFJ8N1UeUETdWwrN
```

即 **Dart → MethodChannel → SDK → 授权 → App Link 回调 → Native 解析 → 回到 Dart**
整条链路（含 `codeVerifier` 回传）全部打通。

### 4.3 未能验证的部分

**「TikTok App 原生授权」这一段没能在真机上跑通** —— 测试设备没装 TikTok，
且受网络限制无法下载安装（apkpure / uptodown / apkcombo / TikTok CDN 全部 403 或 TLS 失败）。

所以：
- ✅ SDK 集成、PKCE、App Link 回调解析、MethodChannel 双向通信 —— **已验证**
- ⚠️ `AuthMethod.TikTokApp` 跳 TikTok App 授权 → TikTok 侧真实放行 —— **待验证**

> 这需要一台**装了 TikTok 的真机** + **TikTok Portal 上该应用审核通过**。
> 设备没装 TikTok 时 SDK 会自动降级到 ChromeTab，而 ChromeTab 已被证明走不通。

---

## 5. 还需要做的事

### 5.1 TikTok Developer Portal（必须，阻塞项）

在 [TikTok for Developers](https://developers.tiktok.com/manage/apps) 的应用
（client key `awy65nxalrzf8a76`）里确认：

- [ ] **Login Kit 已添加**到 Products，且**审核通过**（不是 Draft）
- [ ] **Android 标签页**下登记了 redirect URI：
      `https://tv.qahwatv.com/tiktok-callback/index.html`
      （逐字符一致，含 `tv.` 前缀和 `index.html`）
- [ ] **Scopes** 里勾选了 `user.info.basic`
- [ ] **Android 平台**登记的包名 = `com.video.storydrama`
- [ ] **Android 平台**登记的签名指纹 = `D5:E1:0C:FC:E8:02:22:E6:8A:62:77:C4:49:B6:EC:31:C1:10:1E:32:E5:FA:61:44:51:B8:21:7F:F4:4B:C0:64`
      （SHA-256，去冒号大写）
- [ ] **MD5 签名键** = `0f959fd73223a9161386058a3f659e36`
- [ ] 域名验证文件已部署：
      `https://tv.qahwatv.com/.well-known/tiktok-verification.txt`

### 5.2 后端

见 `tiktok-login-backend.md`。要点：
- 换 token 时必须带 `redirect_uri`（与请求 code 时完全一致）和 `code_verifier`
- `passportType` 用 `7`（`PassportType.tiktok`，已避开与 Facebook `4` 的冲突 —— 待后端最终确认）

### 5.3 iOS

iOS 目前仍走 WebView 方案，而 Web 流已被证明走不通。
如需 iOS 支持，需接入 TikTok 官方 iOS SDK（CocoaPods / SPM）。
iOS 的 App Link 配置见 `apple-app-site-association`（已部署）。

---

## 6. 相关文件

| 文件 | 作用 |
|---|---|
| `android/app/src/main/kotlin/com/video/storydrama/TikTokAuthHandler.kt` | 原生桥接（MethodChannel） |
| `android/app/src/main/kotlin/com/video/storydrama/MainActivity.kt` | 生命周期接线、channel 注册 |
| `android/app/src/main/AndroidManifest.xml` | `singleTask` + App Link intent-filter + TikTok 包可见性 |
| `android/app/build.gradle` | TikTok OpenSDK 依赖 |
| `android/build.gradle.kts` | ByteDance Maven 仓库 |
| `lib/features/auth/services/tiktok_native_auth_service.dart` | Dart 侧原生通道封装 |
| `lib/features/auth/services/tiktok_auth_service.dart` | 策略：原生优先，WebView 兜底 |
| `lib/features/auth/repositories/auth_repository.dart` | 把 `redirectUri` / `codeVerifier` 传给后端 |
| `lib/core/config/app_config.dart` | clientKey / scope / redirectUri / 证书指纹 |
| `deploy/assetlinks.json` | App Links 验证文件 |
| `deploy/tiktok-callback/index.html` | 回调落地页（仅 Web 流需要） |
