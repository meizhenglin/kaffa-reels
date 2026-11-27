import Flutter
import UIKit
import StoreKit

/// StoreKit2 商品查询桥（只负责「商品列表查询」，不碰购买/收据链路）。
///
/// 【为什么需要】in_app_purchase 插件的 iOS 商品查询走 SK1 的
/// SKProductsRequest（delegate 回调模式），在沙盒环境下高频挂死——请求
/// 发出后委托回调永远不来，客户端只能超时放弃，而插件没有取消 API，
/// 挂死的请求还会拖累后续查询（实测反复「15 秒无响应」）。
/// SK2 的 Product.products(for:) 是 async/await 语义：要么返回要么抛错，
/// 没有委托挂死问题。Dart 侧失败/超时自动回退 SK1 现有路径。
@available(iOS 15.0, *)
class StoreKit2QueryBridge {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "kaffa/storekit2_query",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "queryProducts",
            let ids = call.arguments as? [String],
            !ids.isEmpty else {
        result([])
        return
      }
      Task {
        do {
          let products = try await Product.products(for: Set(ids))
          let payload: [[String: Any]] = products.map { product in
            [
              "id": product.id,
              "displayName": product.displayName,
              "description": product.description,
              "displayPrice": product.displayPrice,
              "price": "\(product.price)",
              "currencyCode": product.priceFormatStyle.currencyCode,
            ]
          }
          await MainActor.run { result(payload) }
        } catch {
          await MainActor.run {
            result(
              FlutterError(
                code: "sk2_query_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // 【SK2 查询桥】window 尚未就绪时注册不了 → Dart 侧收到
    // MissingPluginException 自动回退 SK1，行为与旧版一致。
    if #available(iOS 15.0, *),
       let controller = window?.rootViewController as? FlutterViewController {
      StoreKit2QueryBridge.register(with: controller.binaryMessenger)
    }
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
