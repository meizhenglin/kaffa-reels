# Google Play 商品「查不到」诊断手册

## 一、结论（本项目实测，2026-11-10）

测试设备：`2312DRA50C`（Android 16），Play 结算国家 `MO`（澳门），
包名 `com.video.storydrama`（google flavor）。

原生探针输出：

```
setup: code=0 / 结算国家=MO
· subs:  code=0 found=com.qahwa.vip1
                  unfetched=com.qahwa.vip2(NO_ELIGIBLE_OFFER),
                             com.qahwa.vip3(NO_ELIGIBLE_OFFER)
· inapp: code=0 found=-
                  unfetched=com.qahwa.vip1(PRODUCT_NOT_FOUND),
                             com.qahwa.vip2(PRODUCT_NOT_FOUND),
                             com.qahwa.vip3(PRODUCT_NOT_FOUND)
→ 商品存在但当前账号/国家没有可购买的 offer: com.qahwa.vip2, com.qahwa.vip3
```

**`com.qahwa.vip2` / `com.qahwa.vip3` 在 Play 里是存在的**，状态码是
`NO_ELIGIBLE_OFFER`（4），不是 `PRODUCT_NOT_FOUND`（3）。
所以「去 Play Console 建商品」是错的方向。

### 两个状态码的区别

| statusCode | 名称 | 含义 | 修法 |
| --- | --- | --- | --- |
| 3 | `PRODUCT_NOT_FOUND` | 商品在**当前 Play 应用**下不存在 | 建商品 / 改商品类型 / 改 ID / 确认没建在别的 Play 应用下 |
| 4 | `NO_ELIGIBLE_OFFER` | 商品**存在**，但当前账号/国家没有可购买的 offer | 激活基础方案、给该国家配价、开放区域、确认账号是测试人员 |

### `NO_ELIGIBLE_OFFER` 的常见成因

1. 订阅的**基础方案（base plan）没激活**（新建的方案默认不激活）。
2. 基础方案**没有给结算国家配价**。Play 会把「该国家无价格」当成无可用 offer。
3. 方案**还没对新国家开放**（新增国家后需要等待同步）。
4. 设备上的 **Play 账号所在国家**与商品开放区域不匹配（本次是 `MO`）。
5. 账号**没加入 license tester**，或 Play 商店登录的是另一个账号。

对应到本次：`vip1` 能取到（标题 `VIP Monthly Card (QahwaTV)`），`vip2/vip3` 取不到，
说明 vip1 的基础方案是好的，问题在 vip2/vip3 的基础方案配置或区域开放范围。

---

## 二、为什么 App 里一直查不出原因

`in_app_purchase_android` 0.5.2 在 `Translator.fromUnfetchedProduct` 里
只保留了 `productId`，把 `UnfetchedProduct.getStatusCode()` 丢掉了：

```kotlin
fun fromUnfetchedProduct(unfetchedProduct: UnfetchedProduct): PlatformUnfetchedProduct {
    return PlatformUnfetchedProduct(productId = unfetchedProduct.productId)
}
```

Dart 侧的 `UnfetchedProductWrapper` 同样只有 `productId`，
所以 App 里只能看到「unfetched」，**分不清是「不存在」还是「买不了」**。

---

## 三、本项目新增的工具

### 1. 原生探针

- `android/app/src/main/java/com/video/storydrama/BillingProbe.java`
- MethodChannel：`com.video.storydrama/billing_probe`，方法 `probe`，参数 `productIds`。

它新开一条结算连接，直接读 `UnfetchedProduct.getStatusCode()`，
并额外用 `getBillingConfigAsync` 取回**结算国家**。

返回结构：

```json
{
  "setupCode": 0,
  "setupDebugMessage": null,
  "countryCode": "MO",
  "queries": [
    {
      "type": "subs",
      "responseCode": 0,
      "debugMessage": "",
      "found": [{ "productId": "...", "title": "...", "productType": "subs" }],
      "unfetched": [{ "productId": "...", "statusCode": 4, "statusName": "NO_ELIGIBLE_OFFER", "productType": "subs" }]
    }
  ]
}
```

### 2. Dart 封装

`lib/features/payment/services/play_billing_native_probe.dart`

- `PlayUnfetchedStatus`：状态码常量与语义。
- `PlayNativeProbeResult.notFoundIds`：**真的不存在**的商品。
- `PlayNativeProbeResult.noEligibleOfferIds`：**存在但买不了**的商品。
- `PlayNativeBillingProbe.runStartupProbe()`：启动时跑一次（需编译期开关）。

### 3. 判定规则（重要）

Play 对「用 `inapp` 类型去查一个订阅商品」同样返回 `PRODUCT_NOT_FOUND`。
所以**不能只看单次查询**，必须跨类型合并：

- 只要在**任意一次**查询里 found → 商品存在，忽略它；
- 只要有**任意一次**返回 `NO_ELIGIBLE_OFFER` → 商品存在（买不了）；
- 两次查询都是 `PRODUCT_NOT_FOUND` → 商品真的不存在；
- 状态是 `UNKNOWN` → 不下结论（归到「原因不明」）。

### 4. 启动探针开关

```bash
flutter run --flavor google \
  --dart-define=PLAY_PROBE_IDS=com.qahwa.vip1,com.qahwa.vip2,com.qahwa.vip3
```

App 启动后会把结果打到 logcat：

```bash
adb logcat -s flutter:I | grep -A3 PlayProbe
```

注意 `debugPrint` 一次会输出多行，grep 时要用 `-A` 把后续行也带出来。

### 5. 自动接入

`PaymentService._logPlayDiagnosis` 现在会额外跑原生探针，
并据此给出稳定失败码：

| 失败码 | 含义 | 会员页提示 |
| --- | --- | --- |
| `play-item-not-found` | 商品真的不存在 | 「该订阅当前不可用」 |
| `play-no-eligible-offer` | 商品存在但当前账号/国家买不了 | 「该套餐存在于 Google Play，但对你的账号/国家暂不可用」 |

只有 `play-item-not-found` 才会触发
`MembershipProductsNotifier._hidePlansMissingFromPlay` 隐藏套餐；
`play-no-eligible-offer` 的套餐**继续显示**，因为它在商店里是真实存在的，
Play Console 修好后会自动恢复可购买。

---

## 四、排查清单

1. 跑启动探针，确认是 `PRODUCT_NOT_FOUND` 还是 `NO_ELIGIBLE_OFFER`。
2. 看 `countryCode`（Play 账号所在国家）。
3. `PRODUCT_NOT_FOUND` → 去 Play Console 确认商品建在**哪个应用**下
   （`com.video.storydrama` 和 `com.video.storydrama.platform` 是两个独立的
   Play 应用，商品互不可见），并确认商品类型是「订阅」。
4. `NO_ELIGIBLE_OFFER` → 去 Play Console 打开对应订阅的**基础方案**：
   - 方案是否**激活**；
   - 是否给 `countryCode` 对应国家**配了价格**；
   - 是否**新国家**已开放。
5. 确认设备上的 Play 商店账号是 **license tester**。
