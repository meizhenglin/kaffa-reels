# Google Play 订阅买不了：排查记录与代码改动

## 现象

Android 包（`com.video.storydrama`）上点「购买会员」，Google Play 弹不出购买框。

日志表现：

```
[Purchase] Step 2: Found 0 products
[Purchase] WARNING: No products found from Google Play!
[Purchase] This means the product ID "com.qahwa.vip2" is not configured in Google Play Console
[Purchase] Looking for product ID: "com.qahwa.vip2"
[Purchase] Step 3 returned false
```

同时日志里出现过多次：

```
[PaymentService] Purchase timeout after 120s
[Purchase] Step 3 returned false
```

## 两个独立问题

### 问题一：商品 ID 疑似写错（根因）

后台下发的商品 ID 是 **`com.qahwa.vip2`**（没有点号），
而代码里的兜底列表写的是 **`com.qahwa.vip.2`**（有点号）：

```dart
// lib/features/payment/models/subscription_product.dart
static const _googlePlayBase = 'com.qahwa.vip';
googlePlayId: '$_googlePlayBase.2',   // → com.qahwa.vip.2
```

Play Console 里这两个是**完全不同的商品 ID**，查不到 `com.qahwa.vip2` 就会返回
`error == null` + 空 `productDetails`——也就是日志里那个「0 商品」。

对照证据：日志里 `Step 3: Purchase flow returned` 出现过 4 次而
`Step 3: Starting` 一次都没有，说明**有 4 次购买流程确实拿到了商品**。
那些次用的很可能就是带点号的 ID（Play 能查到），但购买弹窗仍然打不开——
这跟「包没上传 Play / 账号不是 license tester / 商品状态是草稿」是吻合的。

**结论：商品 ID 和包名需要逐字符核对；并且 license 状态也需要确认。**

### 问题二：并发购买 + 失败无提示（代码 bug，已修）

1. `PaymentService.purchase()` 没有并发闸。用户连点 5 次会创建 5 个
   `Completer`，但 `_handlePurchaseUpdate` 只认最后一个
   `_pendingPurchaseProductId`，前 4 个永远等不到结果，各自跑满 120 秒超时。
   这就是日志里多条 timeout + 多条 `Step 3 returned false` 的来源。

2. 超时后 `_pendingPurchaseCompleter` 没有被清空，导致后续购买被闸门挡住。

3. `MemberStateNotifier.purchase()` 失败时只清了 `isLoading`，
   **没有设置 `errorMessage`**。结果用户点完购买干等两分钟，屏幕上什么提示都没有。

4. 查商品排在建订单之后，商品不存在时会留下一条永远不会被支付的「孤儿订单」。

## 已做的代码改动

| 文件 | 改动 |
| --- | --- |
| `lib/features/payment/services/payment_service.dart` | 购买加并发闸；超时后清理 pending 状态；购买结束立刻取消超时定时器；超时文案更明确；**商品查不到时调用诊断探针，打印 Play 原始响应码** |
| `lib/features/payment/services/play_billing_probe.dart` | **新增**。取回 Play 原始 `BillingResult`（响应码 / debugMessage / unfetched 列表），并把响应码翻译成「到底为什么失败」 |
| `lib/features/payment/providers/membership_provider.dart` | 改成**先查商品、再建订单**；失败时写入 `errorMessage`（用户能看到提示）；查不到商品时打印后台 ID 与兜底 ID 的对照（**不再断言是商品 ID 的问题**） |
| `lib/features/payment/widgets/unlock_bottom_sheet.dart` | 同样改成先查商品再建订单 |
| `lib/features/payment/pages/membership_page.dart` | 同一条错误不再弹两次 SnackBar；`clearError` 替代 `errorMessage: null`，保证重复的错误也能再次提示 |

## 还需要你在 Play Console 确认的事

按顺序排查：

1. **商品 ID 逐字符核对**：`com.qahwa.vip2` 和 `com.qahwa.vip.2` 是两个不同的商品。
   后台 `rechargeGoodsConfig` 下发的 `goodsGoogleId` 到底是哪个？Play 后台建的又是哪个？
   两边必须完全一致（含点号、下划线、大小写）。
2. **商品类型**：必须是**订阅（subs）**。一次性商品（inapp）会被
   `requireSubscriptionOnAndroid: true` 过滤掉。
3. **商品状态**：必须是 Active。草稿/未发布的商品查不到。
4. **包名**：Play 后台的商品要挂在 `com.video.storydrama` 这个包下。
5. **账号**：手机上登录的 Google 账号必须是 **license tester**。
6. **测试轨道**：如果商品在 internal/alpha 轨道，账号得加入该轨道的测试名单，
   并且需要从 Play 商店的测试链接安装应用才能走通内购。

## 新日志怎么读

再次复现时看这几行：

```
[PaymentService] notFoundIDs (Play could not fetch): xxx
[Purchase] 商品 ID 与代码兜底列表不一致，请确认 Play 后台用的是哪个：
[Purchase]   后台下发的 ID : "com.qahwa.vip2"
[Purchase]   代码兜底 ID   : com.qahwa.vip.1, com.qahwa.vip.2, com.qahwa.vip.3
```

`notFoundIDs` 非空 = Play 明确说「这个 ID 我没有」，
说明是**配置/状态问题**，不是网络问题。

## ⚠️ 上面这句话是错的（2026-11-10 更正）

`notFoundIDs` **不能**用来判断「Play 说了这个 ID 我没有」。

`notFoundIDs` 是插件用 `请求的 ID 集合 - 成功取到的 ID 集合` 算出来的差集
（见 `in_app_purchase_android_platform.dart` 的 `queryProductDetails`）。
当整次请求**根本没被 Play 受理**时，成功取到的集合是空的，
差集就等于「全部请求过的 ID」——`notFoundIDs` 会把所有 ID 都列出来，
看起来和「Play 说这些 ID 我没有」一模一样。

实际上这两种情况在插件的公开 API 里长得完全一样：
`error == null` + `productDetails` 为空 + `notFoundIDs` = 全部 ID。
插件把 `BillingResult` 丢掉了（flutter/flutter#194177），
所以我们此前只能靠猜——这正是「后台没有这个商品」这个误判的来源。

## 现在怎么判断真实原因

新增 `lib/features/payment/services/play_billing_probe.dart`：
复用插件自己的 `BillingClient` 连接，直接把 Play 的原始
`BillingResult`（响应码 + debugMessage + unfetchedProductList）取回来。

商品查不到时，日志会多打这一段：

```
[PaymentService] ── Google Play 原始响应 ──────────────────
[PaymentService]   · inapp: code=2 (serviceUnavailable) found=- unfetched=-
[PaymentService]       debugMessage: ...
[PaymentService]       → Play 服务不可用。请求根本没被 Play 受理，商品 ID 是否正确无关。
[PaymentService]   · subs: code=2 (serviceUnavailable) found=- unfetched=-
[PaymentService] ────────────────────────────────────────────
```

对照表：

| 原始响应码 | 含义 | 该查什么 |
| --- | --- | --- |
| `code=2` (SERVICE_UNAVAILABLE) | Play 根本没受理请求 | 手机 Google 账号的授权 / license tester 身份 / Play 商店登录的账号 / Play 商店版本。**与商品 ID 无关** |
| `code=0` (OK) + `unfetched` 含该 ID | Play 受理了，但说「没这个 ID」 | 商品 ID 拼写、类型（subs vs inapp）、商品状态（是否 Active） |
| `code=3` (BILLING_UNAVAILABLE) | 设备上没有 Play 商店或版本过旧 | 装 / 更新 Play 商店 |
| `code=4` (ITEM_UNAVAILABLE) | 商品存在但当前不可购买 | 区域限制、是否已下架 |
| `code=5` (DEVELOPER_ERROR) | 请求参数非法 | 商品类型传错了 |
| `code=9` (NETWORK_ERROR) | 设备到 Play 网络不通 | 网络 |

> 响应码用的是 **Play 官方数值**（`ok=0`、`serviceUnavailable=2`……）。
> 插件内部的 pigeon 枚举序号和这个数值不是一回事，
> 所以 `play_billing_probe.dart` 里有一张显式的换算表。

### 关于 `com.qahwa.vip1` 和 `com.qahwa.vip.1`

这两个是**不同的商品 ID**（一个有点一个没点），Play Console 里是两个商品。
但要注意：只有在原始响应码是 `code=0` 且 `unfetched` 里出现该 ID 时，
才能据此断定是 ID 写错了。如果响应码是 `code=2`，
那 Play 压根没去看这个 ID，改成哪个写法都一样查不到。
