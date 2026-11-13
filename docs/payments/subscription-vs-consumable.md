# 会员（订阅）vs K币（一次性消耗）：整体逻辑与修复记录

## 设计目标

| 业务 | Play 商品类型 | 客户端语义 | 结算方式 |
| --- | --- | --- | --- |
| 开通会员（月卡/季卡/年卡） | 订阅 `subs` | 订阅 | `buyNonConsumable` + acknowledge，后端按订阅周期给 VIP |
| 购买 K币（平台币） | 一次性商品 `inapp` | 消耗品 | `buyConsumable`（插件自动 consume），后端按笔加币 |

**方向是对的**，但原来的实现里这两条链路是纠缠的，有几个真 bug。

## 原来的问题

### 1. K币 的后端回调从来没发出去

`RechargePurchaseHandler.handlePurchaseSuccess()` 是死代码 —— 全项目没有任何地方调用它。
它本来该做的事（consume → POST `api/pay/callback/google` 带 `payConfigType=1` → 刷新余额）
一步都没执行。**钱付了，币不会到账。**

### 2. 两条链路共用一个全局回调，互相串味

`PaymentService` 是单例，只有一个 `_onPurchaseComplete`，被会员链路独占。
买 K币时 purchaseStream 推回来的事件也进了会员处理器：

- 会员处理器要求 `state.pendingOrderId` 非空 → K币 购买没有订单 → 抛 `StateError`
- → 用户买完币看到「Failed to process purchase」
- 如果用户从没进过会员页（`memberStateProvider` 没初始化），回调是 null → 事件被静默丢弃

### 3. 一次性商品被当成订阅去 acknowledge

`PaymentService._handlePurchaseUpdate` 对所有 `purchased` 都调 `completePurchase`。
Android 插件的 `completePurchase` 实际执行的是 `acknowledgePurchase`，而
`buyConsumable` 已经在把 purchase 投递给 stream 之前自动 consume 掉了。
对已消费的 token 再 acknowledge 会失败（错误被 catch 吞掉），语义也是错的。

### 4. `buyConsumable` 返回 true 只代表「弹窗打开了」

`launchBillingFlow` 立刻返回 OK，真实结果要等 purchaseStream。
所以 `coin_recharge_page` 会在用户还没确认支付时就弹「购买成功」，
用户点了取消也一样弹。

### 5. 从解锁面板买会员时后端回调必然失败

`unlock_bottom_sheet._performVipByGooglePlay` 建了订单，但没把 orderId 登记到
`memberStateProvider`，purchaseStream 回来时拿不到 orderId → 回调失败。

### 6. 恢复购买 / 自动恢复会报「支付失败」

App 重启后 Play 会把已有订阅重新推回来，此时本地没有 pendingOrderId，
原来的代码直接抛 StateError → 弹「Failed to process purchase」。

### 7. 两份重复实现

`membership_provider.dart` 和 `recharge_provider.dart` 各有一份
`RechargePurchaseHandler` + `rechargePurchaseHandlerProvider`，
`coin_recharge_page.dart` 和 `recharge_page.dart` 分别 import 了不同的那份。

另外还有两份 `coinBalanceProvider`（都基于 SharedPreferences 的本地余额），
和真正在用的服务端余额 `coinBalanceInfoProvider` 并存。

## 已做的修复

| 文件 | 改动 |
| --- | --- |
| `services/payment_service.dart` | 新增顶层 `PlayProductKind` 枚举；购买时登记商品用途（订阅 / 一次性）；purchaseStream 按用途分流：一次性商品走自己的回调且**不** acknowledge，订阅照旧 acknowledge 后交给会员链路；`purchaseConsumable` 改成等待真实购买结果（带超时和并发闸），支持 `onComplete` 回调 |
| `providers/recharge_provider.dart` | `RechargePurchaseHandler` 重写：查商品 → 建订单 → 买 → 购买成功后 POST `api/pay/callback/google`（`payConfigType=1`，参数结构与会员链路一致，带 orderId）→ 最多重试 3 次 → 刷新服务端余额；去掉本地加币（避免和服务端重复记账） |
| `providers/membership_provider.dart` | 删掉重复的 `RechargePurchaseHandler`；新增 `setPendingOrder()` 供外部入口登记订单；恢复购买场景改成刷新用户信息而不是报「支付失败」 |
| `widgets/unlock_bottom_sheet.dart` | 买会员时把 orderId 登记到 `memberStateProvider`；订单建失败直接返回并提示 |
| `pages/coin_recharge_page.dart` | 改为 import `recharge_provider.dart`，消除双实现的歧义 |
| `services/unified_payment_handler.dart` | 注明 Google Play 的充值要走 `RechargePurchaseHandler`（它才发后端回调） |
| `widgets/web_native_exit_dialog.dart` | 修掉一个已存在的编译错误（`String?` 传给 `registerViewFactory`） |

## 现在的流程

### 买会员（订阅）

```
membership_page / unlock_bottom_sheet
  → 查 Play 商品（requireSubscriptionOnAndroid = true，只认 subs）
  → createOrder(payConfigId = goodsId) → orderId
  → 登记 pendingOrderId（会员页在 provider 里登记，解锁面板调 setPendingOrder）
  → PaymentService.purchase() → buyNonConsumable
  → 等 purchaseStream
  → completePurchase（acknowledge）
  → MemberStateNotifier._handlePurchaseComplete
      → POST api/pay/callback/google（带 orderId / purchaseToken / verificationData）
      → 刷新用户信息 → isVipProvider 生效
```

### 买 K币（一次性消耗）

```
coin_recharge_page / recharge_page / unlock_bottom_sheet
  → RechargePurchaseHandler.purchase()
      → 查 Play 商品（不限制类型）
      → createOrder(payConfigId = goodsId) → orderId
      → PaymentService.purchaseConsumable(onComplete: ...)
          → buyConsumable（插件自动 consume，同一个币包可以反复买）
          → 等 purchaseStream 拿到真实结果
  → purchaseStream 事件按用途分流到 onComplete
      → POST api/pay/callback/google（payConfigType = 1，带 orderId）
      → 刷新服务端余额 coinBalanceInfoProvider
```

## 还需要确认的事

1. **Play 后台的商品类型**：会员必须是订阅（subs），K币 必须是一次性商品（inapp）。
   Play 的 `ProductType` 只分 `inapp` / `subs`，区分不出「一次性消耗」和
   「一次性买断」，所以一次性商品的行为完全靠客户端登记的用途来决定 ——
   后台如果把 K币 配成了订阅，客户端会按消耗品去 consume 一个订阅，行为就不对了。
2. **后端回调参数**：`payConfigType=1` 表示 K币 充值、`payConfigType=0`（缺省）表示会员订阅，
   这个约定需要后端确认。参数结构已经和会员链路统一成同一份。
3. **本地余额 provider**：`coinBalanceProvider`（SharedPreferences）还在，
   但充值不再往它上面加币了。余额以服务端的 `coinBalanceInfoProvider` 为准。
   这两个本地 provider 建议后面清理掉，避免有人再用到。
