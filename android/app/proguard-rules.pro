# 保持所有类不被混淆
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes JavascriptInterface
-keepattributes SourceFile,LineNumberTable

# 阿里云
-keep class com.alivc.** { *; }
-keep class com.aliyun.** { *; }
-keep class com.cicada.** { *; }
-dontwarn com.alivc.**
-dontwarn com.aliyun.**
-dontwarn com.cicada.**

# MobSDK / MobCommon
-keep class com.mob.** { *; }
-keep interface com.mob.** { *; }
-dontwarn com.mob.**

# ShareSDK
-keep class cn.sharesdk.** { *; }
-keep interface cn.sharesdk.** { *; }
-keep class cn.sharesdk.framework.** { *; }
-keep class com.mob.tools.** { *; }
-keep class **.R$* { public static <fields>; }
-dontwarn cn.sharesdk.**
-dontwarn com.mob.tools.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.plugins.firebasecore.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter embedding
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# WebView Flutter - 完整保护
-keep class com.flutter_webview_plugin.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class io.flutter.webviewflutter.** { *; }
-keep class * extends io.flutter.plugins.webviewflutter.WebViewFlutterPlugin { *; }
-keep class * extends io.flutter.plugins.webviewflutter.FlutterWebViewPlugin { *; }
-dontwarn io.flutter.plugins.webviewflutter.**
-dontwarn io.flutter.webviewflutter.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.ads.**

# 保持所有 native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}
