# 版本号与渠道标识方案

> 目的：web / platform / google 三个渠道各打各的包，**每个包都能一眼看出
> 是哪个渠道、哪个版本**，并且后端能按渠道区分更新。

---

## 1. 唯一真相源

**`pubspec.yaml` 的 `version` 字段**：

```yaml
version: 1.0.6+15
#       └──┬─┘ └┬┘
#     版本号  构建号
```

其它地方**不允许**再手写版本号。之前散落的三套已经收敛：

| 位置 | 改前 | 改后 |
|---|---|---|
| `pubspec.yaml` | `1.0.6+15` | **唯一要改的地方**（真相源） |
| `AppConfig.androidVersion` | `'1.0.9'` | **已删除** —— 见下面的「版本号只有一个源头」 |
| iOS `MARKETING_VERSION` | 走 `$(FLUTTER_BUILD_NAME)` | 不变，本来就自动同步 |

### 版本号只有一个源头

**改 `pubspec.yaml` 第 5 行就行，别的地方都不用动。**

```yaml
version: 1.0.8+2017
```

改完之后，这些地方全部自动跟着变：

| 地方 | 变成 | 来源 |
|---|---|---|
| 设置页显示 | `1.0.8-p` | dart-define `APP_VERSION` |
| 启动日志 | `1.0.8+2017.p` | `BuildInfo.fullVersion` |
| 请求头 `X-Client` 的 `version=` | `1.0.8` | `AppVersion.resolveBase()` |
| 请求头 `X-Client` 的 `build=` | `1.0.8+2017.p` | `AppVersion.resolveFull()` |
| APK / AAB 原生 `versionName` | `1.0.8-p` | Gradle 的 `flutter.versionName` |
| APK / AAB 原生 `versionCode` | `2017` | `flutter.versionCode`（= 构建号） |
| 产物文件名 | `KaffaReels-1.0.8-p-release.aab` | 构建脚本生成 |
| `web/version.json` | `1.0.8-w` / `2017` | 构建脚本生成 |

**代码里已经没有别的版本号常量了。** `AppConfig` 里的
`androidVersion` / `iOSVersion` / `appVersion` 都已删除 —— 它们当初
写死了 `'1.0.9'`，和实际发的包对不上，是线上排查的干扰源。

只剩一个 `AppConfig.fallbackVersion`，它连兜底都算不上：只有
「dart-define 没有 + 原生 versionName 也读不到」时才会用到，
正常流程永远走不到。

---

## 2. 三个渠道长什么样

| 渠道 | 版本号 | 完整标识 | Android applicationId |
|---|---|---|---|
| Google Play | `1.0.6-g` | `1.0.6+15.g` | `com.video.storydrama` |
| 自建平台 | `1.0.6-p` | `1.0.6+15.p` | `com.video.storydrama` |
| Web | `1.0.6-w` | `1.0.6+15.w` | — |

短码 `g` / `p` / `w` 定义在 `lib/core/config/build_flavor.dart`，
与 Android `productFlavors` 里的 `versionNameSuffix` 一一对应，
所以 Dart 侧算出来的字符串和 Android 原生 `versionName` 永远是同一个。

---

## 3. 怎么打包

**统一用 `tool/build.dart`**，不要手敲 `flutter build`：

```bash
dart tool/build.dart web                            # Web
dart tool/build.dart google --release               # Google Play
dart tool/build.dart platform --release --split-per-abi   # 自建平台
```

脚本做三件事：

1. 从 `pubspec.yaml` 读版本号，注入
   `--dart-define=APP_VERSION=1.0.6 --dart-define=APP_BUILD_NUMBER=15`；
2. Web 构建额外生成 `web/version.json`（见第 4 节）；
3. 打印出这次的版本号，方便和发布记录核对。

先看命令不执行：

```bash
dart tool/build.dart web --dry-run
```

**渠道是怎么传进 Dart 的**：`flutter build --flavor google` 时，Flutter
**自动注入** `--dart-define=FLUTTER_APP_FLAVOR=google`
（flutter_tools 里的 `kAppFlavor`）。所以 `BuildFlavor` 不需要手动
`--dart-define=FLAVOR=`，脚本里那份只是兜底 + 给 Web 用。

---

## 4. 产物文件名也带版本号

构建完成后，脚本会把产物**复制**到 `build/artifacts/` 并改成带版本号的名字：

```
build/artifacts/
  KaffaReels-1.0.6-p-release.apk              ← platform 整包
  KaffaReels-1.0.6-p-release-arm64-v8a.apk    ← 按 ABI 拆分
  KaffaReels-1.0.6-p-release-armeabi-v7a.apk
  KaffaReels-1.0.6-p-release-x86_64.apk
  QahwaTV-1.0.6-g-release.apk                 ← google 渠道
  KaffaReels-1.0.6-w.zip                      ← web
```

命名规则：`<应用名>-<版本>-<渠道短码>[-<abi>]-<构建类型>.<ext>`

| 片段 | 来源 |
|---|---|
| 应用名 | 渠道对应的品牌名（google → `Qahwa TV`，其余 → `Kaffa Reels`），可用 `--app-name=` 覆盖 |
| 版本 | pubspec 的版本号 + 渠道短码，和设置页显示的一致 |
| abi | 仅在 `--split-per-abi` 时出现 |

**只复制不移动**：原始 APK 仍留在 `build/app/outputs/flutter-apk/`，因为
`check_apk.ps1` 这类脚本是按固定路径找原始文件的。

> ⚠️ `build/app/outputs/flutter-apk/` 是**累积**目录，历次构建的包都躺在
> 里面（google 渠道的 debug 包和 platform 渠道的 release 包会同时存在）。
> 脚本因此严格按「渠道 + 构建类型」筛选，再只保留**最新一批**（与最新文件时间相差 60 秒内，即同一次
> Gradle 产出），避免把上一轮的旧包混进产物目录、导致上传时挑错。

### 为什么文件名不能在 `flutter build` 时就带上版本号

Flutter 把 `app-<abi>-<flavor>-<mode>.apk` 这个名字**写死**在
`flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt` 里：

```kotlin
projectToAddTasksTo.copy {
    from(File("$outputDirectoryStr/${output.outputFileName}"))
    into(projectToAddTasksTo.layout.buildDirectory.dir("outputs/flutter-apk"))
    rename { "$filename.apk" }   // ← 名字在这里定死，没有扩展点
}
```

`rename { }` 闭包不接受任何外部输入，所以 Gradle 侧改 `outputFileName`
只能改中间目录 `build/app/outputs/apk/` 里的名字，**最终落到
`flutter-apk` 的名字改不了**。只能在构建之后重命名。

### 已经用 `flutter build` 手动打过包？

用 `--artifacts-only`，它跳过构建，只对已有产物做重命名：

```bash
flutter build apk --flavor platform --release --split-per-abi
dart tool/build.dart platform --artifacts-only
```

构建类型（release / debug）由脚本自动推断：取该渠道下最新产出的 APK
所属的类型。

### `build/artifacts/` 的两条规则

**① 旧版本会被自动清理。** 版本号一改，产物目录里很容易同时躺着 1.0.6 和
1.0.7，上传时挑错。脚本在写入前会删掉「同渠道 + 同构建类型 + 版本号更旧」
的产物：

| 文件 | 处理 |
|---|---|
| `KaffaReels-1.0.5-p-release.apk`（旧版本，同渠道同类型） | 删除 |
| `KaffaReels-1.0.6-p-release-arm64-v8a.apk`（当前版本） | 保留 |
| `KaffaReels-1.0.6-p-debug.apk`（同渠道但构建类型不同） | 保留 |
| `QahwaTV-1.0.5-g-release.apk`（渠道不同） | 保留 |

**② `flutter clean` 会把整个 `build/` 删掉，`build/artifacts/` 一并消失。**
它只是构建产物，不是发布存档。要长期保留某个版本，打完包后把文件复制到
`build/` 外面去。

### ⚠️ 改完代码重新打包，APK 里可能还是旧代码

这是比版本号管理更要命的问题，**不限于用不用构建脚本** —— 直接敲
`flutter build apk` 同样会中招。

**现象**：改了 pubspec 的版本号（或改了任何 Dart 代码）重新打包，
装到手机上跑，版本号/代码还是上一次的。

**根因**：Flutter 重新编译 Dart 代码后，
`build/app/intermediates/flutter/<变体>/jniLibs/<abi>/libapp.so` 确实更新了，
但 AGP 的 `mergePlatformReleaseJniLibFolders` 任务仍被判定为
**UP-TO-DATE** —— 它没有跟踪 Flutter 的 jniLibs 输入。连带
`mergePlatformReleaseNativeLibs`、`stripPlatformReleaseDebugSymbols`
一起跳过，最终打出来的 APK 里烧的是**上一次的 Dart 代码**。

实测（连续两次构建，只改 `--dart-define=APP_VERSION`）：

| 环节 | 第 1 次（5.5.5） | 第 2 次（6.6.6） |
|---|---|---|
| `flutter/.../jniLibs/arm64-v8a/libapp.so` | 12:48:27 | **12:50:05** ✅ 新 |
| `merged_jni_libs/.../out/arm64-v8a/libapp.so` | 12:48:27 | **12:48:27** ❌ 没重跑 |
| `merged_native_libs/.../out/lib/arm64-v8a/libapp.so` | 12:48:27 | **12:48:27** ❌ 没重跑 |
| `stripped_native_libs/.../out/lib/arm64-v8a/libapp.so` | 12:48:28 | **12:48:28** ❌ 没重跑 |
| `flutter-apk/*.apk` | 12:48:53 | 12:50:07（重新复制了，但内容是旧的） |

最终 APK 里是 `5.5.5`，不是 `6.6.6`。

**解法**：把 AGP 的原生库合并/剥离产物整个删掉，逼它们重算：

```bash
rm -rf build/app/intermediates/merged_jni_libs \
       build/app/intermediates/merged_native_libs \
       build/app/intermediates/stripped_native_libs
```

`tool/build.dart` 已经在每次 Android 构建前自动做这件事（见
`_invalidateNativeLibCache()`），所以**用构建脚本就不会踩到**。

> 如果坚持用 `flutter build apk` 手动打包，**改完版本号重新打包后，
> 一定要执行上面那三行 `rm -rf`**，否则装上去的还是旧版本。
> 或者直接 `flutter clean`（代价是全量重建，慢很多）。

**怎么确认打对了**：把 APK 里的 `libapp.so` 解出来搜版本号字符串，
或者直接装到手机上看设置页显示的版本。

### 上传 Google Play：AAB 还是拆分 APK

**结论：上传用 AAB。**

```bash
dart tool/build.dart platform --release --appbundle   # → KaffaReels-1.0.8-p-release.aab
dart tool/build.dart google   --release --appbundle   # → QahwaTV-1.0.8-g-release.aab
```

**为什么不用拆分 APK 上传**

`--split-per-abi` 打出来的多个 APK，versionCode 是不一样的（实测）：

```
KaffaReels-1.0.8-p-release-arm64-v8a.apk    versionCode=2016
KaffaReels-1.0.8-p-release-armeabi-v7a.apk  versionCode=1016
```

Google Play 要求**每一次上传的 versionCode 都比之前所有上传的都大**，
所以拆分的 APK 只能「从大到小」依次上传（先 2016 再 1016），反过来的话
第二个会被拒。而且这还要求两个渠道的 versionCode 完全错开，否则第二个
渠道的包同样传不上去。

**AAB 就没有这个问题**：

| | 拆分 APK | AAB |
|---|---|---|
| versionCode | 每个 ABI 一个（2016 / 1016） | 只有一个（= 构建号，16） |
| 上传顺序 | 必须从大到小 | 无所谓 |
| 体积 | 2 × ~41 MB | 78.6 MB（含全部 ABI） |
| Play 分发 | 你自己决定给谁哪个包 | Play 自己按设备选 |

AAB 的 versionCode 就是 `pubspec.yaml` 里的构建号，没有 ABI 偏移 ——
实测从 AAB 的 `BundleConfig.pb` 里读出来就是 `16`。

> `tool/build.dart` 的 `--appbundle` 和 `--split-per-abi` 互斥：
> 给了 `--appbundle` 就用 `flutter build appbundle`，不会加
> `--split-per-abi`，也不会加 `--target-platform`（AAB 里带全部 ABI）。

### ⚠️ 从拆分 APK 切到 AAB，versionCode 会「倒退」

实测（pubspec 是 `1.0.8+16`）：

| 产物 | versionCode |
|---|---|
| `KaffaReels-1.0.8-p-release.aab` | **16** |
| `QahwaTV-1.0.8-g-release.aab` | **16** |
| `*-release-arm64-v8a.apk`（拆分 APK） | **2016** |
| `*-release-armeabi-v7a.apk`（拆分 APK） | **1016** |

拆分 APK 的 versionCode 是「构建号 + 2000 / + 1000」（按 ABI 偏移），
AAB 则是「就是构建号」。所以从拆分 APK 切到 AAB，versionCode 会**变小**。

Google Play 要求每次上传的 versionCode 都大于之前所有上传过的，所以：

- 如果 Play 上之前传过拆分 APK（最高记的是 2016），直接传 versionCode=16
  的 AAB **会被拒**；
- 如果没传过，或者传的是 AAB，16 就够。

**查一下就知道**：Play 后台 → 应用 → 正式版 → 最后一个版本，看
versionCode 是多少。

**解决办法：把 pubspec.yaml 的构建号提到 2017 以上。**

```yaml
# pubspec.yaml
version: 1.0.8+2017
```

**构建号就是 Android 的 versionCode**（对 AAB 而言），所以改完这一行，
命令就回到最简形式，不用每次手打参数：

```bash
dart tool/build.dart google --release --appbundle
```

它同时改三处，保证一致：

| 位置 | 值 |
|---|---|
| APK / AAB 的原生 `versionCode` | 2017 |
| 请求头 `X-Client` 的 `build=` | `1.0.8+2017.g` |
| 产物文件名里的版本 | `1.0.8-g` |

**以后每次发版，只改 pubspec.yaml 那一行**，构建号 +1：

```yaml
version: 1.0.9+2018
```

`--version-code=N` 保留作为临时覆盖（比如连续发两个包只想临时跳一个号），
平时不用加。

**脚本会自动检查版本号有没有倒退。** 每次构建成功后，它把该渠道用过的
versionCode 记到 `build/.version-code.json`；下次构建时如果发现新值不大于
旧值，会直接提醒：

```
  ⚠️ versionCode 没有递增：
     上一次 google 用的是 2017，这次是 2010。
     Google Play 要求每次上传的 versionCode 更大，
     传上去会被直接拒掉。
     把 pubspec.yaml 的 version 改成 2018 以上，
     或者用 --version-code=2018 覆盖。
```

> 记录文件在 `build/` 里，不进版本库。`flutter clean` 之后会丢，
> 丢了只是不再提醒，不影响正确性 —— 但要知道 Play 后台的真实记录。

**AAB 不能解决的两个渠道撞号问题**

两个渠道的 `applicationId` 都是 `com.video.storydrama`
（`applicationIdSuffix` 都是 `""`），AAB 的 versionCode 也一样（都是 16）。
所以：

- 传到**同一个 Play 列表** → 第二个渠道的 AAB 会被拒（同包名 + 同 versionCode）；
- 想让两个渠道各自成一个 Play 列表 → 必须给它们不同的 `applicationId`。

这是遗留问题，见下面第 7 节。

### APK 体积

release 整包的构成（1.0.6 实测，拆解 APK 得到）：

| 组成 | 体积 | 说明 |
|---|---|---|
| `lib/` | 37.8 MB | arm64-v8a + armeabi-v7a 的 libflutter.so + libapp.so |
| `classes*.dex` | 34.5 MB | **4 个 dex 文件**，R8 完全没开，全是未裁剪的原始体积 |
| `assets/` | 10.9 MB | 含 `audience_network.dex` 3.41 MB（Meta SDK 自带）+ PNG 8 MB |
| `res/` | 1.2 MB | |

**已经做的优化：release 不再打 x86_64。**

`flutter build apk` 默认会带上 `android-x64`，于是 libflutter.so 和
libapp.so 各多一份 x86_64 副本，整包多占约 21 MB。Google Play 只要求
arm64-v8a / armeabi-v7a，x86_64 只有模拟器用得上。

构建脚本现在自动加 `--target-platform android-arm,android-arm64`
（debug 仍保留三个，方便跑 x86 模拟器）：

| | 改之前 | 改之后 |
|---|---|---|
| 整包 | 82.3 MB | **61.0 MB**（-26%） |
| 拆分包 | 3 个（多一个 44.7 MB 的 x86_64） | 2 个 |

> ⚠️ **改了 `--target-platform` 后必须清残留**。Flutter 的 Gradle 任务只
> 为目标 ABI 建目录，**不会删旧 ABI 的目录**；而 AGP 的 merge 任务在输入
> 没变时会被判定为 up-to-date，不会重新计算。于是 x86_64 的 .so 会沿着
>
>   `intermediates/flutter/<变体>/x86_64/`
>   → `merged_jni_libs/.../out/x86_64/`
>   → `merged_native_libs/.../out/lib/x86_64/`
>   → `stripped_native_libs/.../out/lib/x86_64/`
>
> 一路被带进下一个包。构建脚本因此会在构建前清理
> `build/app/intermediates/flutter/` 下所有多余 ABI 的目录。
>
> 注意别去删 `merged_jni_libs` / `merged_native_libs` /
> `stripped_native_libs` 里的单个 ABI 子目录 —— 那是 AGP 自己的任务输出，
> 删了会破坏 Gradle 的 up-to-date 判断（见上面那节）。要作废整条链路，
> 就把这三个目录**整个**删掉。

**还能优化的（没做，需要先评估）**：

1. **开 R8**：`android/app/build.gradle` 里 release 的 `minifyEnabled false`、
   `shrinkResources false`、`flutter.minifierEnabled false` 三处把 R8
   完全关掉了，dex 的 34.5 MB 是未裁剪体积，开 R8 通常能砍掉三到四成。
   **风险**：MobSDK / Firebase / AdMob / 阿里云播放器大量使用反射，缺
   keep 规则会在运行时崩（登录、支付、播放、广告都可能挂），必须补 keep
   规则并做真机回归。
2. **图片资源**：`assets/` 里 PNG 共 8 MB，其中 `recharge_icon1.png` 单个
   就 3.2 MB。转 WebP 或降分辨率能省好几 MB。
3. **`audience_network.dex`（3.41 MB）**是 Meta Audience Network 自带的，
   除非去掉这个 SDK，否则动不了。

不需要产物重命名时加 `--no-artifacts`。

---

## 5. 各端怎么读到版本号

### Android / iOS

`lib/core/config/build_info.dart`：

```dart
BuildInfo.displayVersion   // '1.0.6-p'
BuildInfo.fullVersion      // '1.0.6+15.p'
```

`BuildInfo.baseVersion` 来自 `APP_VERSION` 这个 dart-define。
没走脚本构建时（比如在 Android Studio 里直接 Run），define 是空的，
`BuildInfo.hasVersion` 为 `false`，界面回退到 `package_info_plus`
读原生 `versionName` —— 那个值已经带 `-g` / `-p` 后缀，结果一致。

### Web

`package_info_plus` 在 Web 上是去**站点根目录**取 `version.json` 的，
Flutter 自己不会生成这个文件，缺了它 Web 版设置页的版本号就是空的。

`tool/build.dart web` 会生成：

```json
{
  "app_name": "Kaffa Reels",
  "version": "1.0.6-w",
  "build_number": "15",
  "package_name": "com.video.storydrama"
}
```

该文件已加进 `.gitignore`（构建产物），每次 Web 构建都会重写。

---

## 6. 上报给后端

`X-Client` 请求头的格式不变，但 `version=` 的取值改成**跟随
`pubspec.yaml`**：

```
platformId=2;platformAppId=2002;version=1.0.6;osName=Android;x-lang=ar-SA;
channel=platform;build=1.0.6+15.p
```

| 字段 | 含义 |
|---|---|
| `version` | `AppVersion.resolveBase()` → `BuildInfo.baseVersion`，即 pubspec 的版本号 |
| `channel` | `google` / `platform` / `web`，后端据此决定给哪个渠道的下载地址 |
| `build` | 真实构建标识 `1.0.6+15.p`，同一个 version 的不同构建靠它区分 |

**为什么把 `version=` 也联动起来**

之前 `AppConfig.androidVersion` 写死成 `'1.0.9'`，而实际发出去的包是
1.0.6 —— 请求头里带着一个**比真实版本更高**的号。后端看到 `version=1.0.9`
会以为客户端比实际新，可能据此下发只适用于 1.0.9+ 的逻辑或更新包，
和用户实际装的包对不上。

现在的取值链路：

```
pubspec.yaml (version: 1.0.6+15)
   │  tool/build.dart 拆成两个 dart-define
   ├─→ APP_VERSION=1.0.8 ──→ BuildInfo.baseVersion ──→ AppVersion.resolveBase()
   │                                                          └──→ X-Client 的 version=
   └─→ APP_BUILD_NUMBER=15 ─→ BuildInfo.buildNumber ──→ X-Client 的 build=
```

这样「设置页显示的版本号」「APK 原生 `versionName`」「请求头里的
`version=`」三者永远同源。

**兜底**：没有 dart-define 时（Android Studio 里直接 Run），走
`package_info_plus` 读原生 `versionName` —— 它同样来自 `pubspec.yaml`，
只是多了渠道后缀。连原生也读不到时才用 `AppConfig.fallbackVersion`。

> ⚠️ 后端如果对 `version=` 做过「等于某个固定值」的判断，需要同步确认
> 一下 —— 之前这个字段一直是 1.0.9，现在会跟着 pubspec 变成 1.0.6。

### 请求头只有一个构造入口

`X-Client` 现在由 `lib/core/network/x_client_header.dart` 里的
`XClientHeader.build()` 统一构造，`api_service.dart` 和
`dio_client.dart` 都调它。

**为什么必须统一**：之前这两个文件各写了一份，而且内容**不一样**：

| 文件 | 格式 |
|---|---|
| `api_service.dart` | `...;version=1.0.6;...;channel=platform;build=1.0.6+15.p` |
| `dio_client.dart` | `...;version=1.0.6;...` ← **没有 channel / build** |

Dio 的执行顺序是「先合并 `Options.headers`，**再**跑拦截器」，而
`dio_client` 的拦截器无条件写 `options.headers['X-Client']` —— 它是最后
写的那一个。所以**实际发出去的一直是少了 `channel` / `build` 的那份**，
这两个字段从来没到过后端。

> ⚠️ 如果后端已经在按 `channel` 分流，现在才真正开始生效；
> 如果之前靠别的手段区分渠道（比如 URL 参数），要检查会不会重复处理。

### 版本号的取值顺序

`AppVersion.resolveBase()` / `resolveFull()`（`lib/core/config/app_version.dart`）
按这个顺序取版本号：

1. **dart-define**（`APP_VERSION` / `APP_BUILD_NUMBER`）—— 发布包走
   `tool/build.dart`，一定有；
2. **原生 `versionName`**（`package_info_plus`）—— Android Studio 里
   直接 Run 时没有 define，走这条；这个值同样来自 `pubspec.yaml`，
   只是多了渠道后缀（`1.0.6-p`），解析时会剥掉；
3. **兜底常量** `AppConfig.fallbackVersion` —— 以上都拿不到时。

所以不管是打发布包还是调试运行，**只要改了 `pubspec.yaml` 的版本号，
请求头里的 `version=` 和 `build=` 就跟着变**。

---

## 7. 已知遗留问题

### ① Android 两个 flavor 共用 applicationId

`android/app/build.gradle` 里 `google` 和 `platform` 的
`applicationIdSuffix` 都是 `""`，包名都是 `com.video.storydrama`：

- 好处：和商店里已上架的包一致，不会因为换包名导致更新装不上；
- 代价：**两个渠道的包不能同时装在一台设备上**，后装的会覆盖先装的；
  调试时要来回 `adb install`。

如果需要同机并存，把其中一方的 `applicationIdSuffix` 改成
`".platform"` 之类（**会改变包名，上架前必须和商店后台对齐**）。

`versionCode` 同理：两个渠道共用一个包名时 `versionCode` 都是 15。
若它们上架在不同的商店，versionCode 各自独立，无需处理；若将来要进
同一个商店，必须给一方加 `versionCodeOffset`。

### ② iOS 没有 flavor scheme

`ios/Runner.xcodeproj/xcshareddata/xcschemes/` 下只有 `Runner.xcscheme`，
没有 `Runner-google` / `Runner-platform`。也就是说：

- **iOS 目前只有一个包**，无法像 Android 那样区分渠道；
- iOS 的版本号走 `Info.plist` 的 `$(FLUTTER_BUILD_NAME)`，
  会自动等于 pubspec 的 `1.0.6`，但**没有渠道后缀**。

要支持 iOS 分渠道，需要补 Xcode scheme，并让 `BuildFlavor` 从
scheme 名解析出渠道（Flutter 对 iOS 也支持 `--flavor`，
它会解析 scheme 名并注入 `FLUTTER_APP_FLAVOR`）。

### ③ 更新检查接口 `checkUpdate` 是死代码

`lib/core/network/api_service.dart` 里的 `checkUpdate()` 定义了完整的
`queryVersionInfo` 请求，但**全项目没有任何地方调用它**，App 里也没有
更新提示弹窗。

真正要做「按渠道更新」时，需要：

1. 在 App 里调用 `checkUpdate()`；
2. 请求体里的 `platformId` 按渠道给不同值（后端约定，目前默认 `'002'`）；
3. `deviceType` 按平台给 `0`(Android) / `1`(iOS)，Web 需要新约定；
4. 后端按 `channel` 返回对应渠道的安装包地址。

这一步依赖后端确认 `platformId` 与渠道的映射关系。

---

## 8. 速查

```dart
import '../../../core/config/build_flavor.dart';
import '../../../core/config/build_info.dart';

BuildFlavor.current        // 'google' | 'platform' | 'web'
BuildFlavor.isGoogle       // bool
BuildFlavor.shortCode      // 'g' | 'p' | 'w'
BuildFlavor.label          // 'Google' | 'Platform' | 'Web'

BuildInfo.hasVersion       // 是否拿到了 dart-define
BuildInfo.baseVersion      // '1.0.6'
BuildInfo.buildNumber      // '15'
BuildInfo.displayVersion   // '1.0.6-p'
BuildInfo.fullVersion      // '1.0.6+15.p'
```
