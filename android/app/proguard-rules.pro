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

# ShareSDK（sharesdk_plugin 调用 ShareSDK 镜像类）
-keep class cn.sharesdk.** { *; }
-keep interface cn.sharesdk.** { *; }
-keep class cn.sharesdk.framework.** { *; }
-keep class com.mob.tools.** { *; }
-keep class **.R$* { public static <fields>; }
-dontwarn cn.sharesdk.**
-dontwarn com.mob.tools.**

# Firebase（用反射和反射 Service Initializer）
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.plugins.firebasecore.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter plugin bridge
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**
