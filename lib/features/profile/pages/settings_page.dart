import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../app/router/router_config.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/config/build_flavor.dart';
import '../../../core/config/build_info.dart';
import '../../../core/utils/app_restart.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import 'language_page.dart';
import 'message_settings_page.dart';
import 'delete_account_page.dart';
import 'system_config_content_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final Future<String> _appVersionFuture = _loadAppVersion();

  /// 设置页显示的版本号。
  ///
  /// Android / Web：格式 `1.0.6-p · Platform` / `1.0.6-g · Google` / `1.0.6-w · Web`。
  /// iOS：显示 iOS 专属身份 `1.0.6-i · iOS` —— iOS 包实际走 platform 渠道
  /// （支付、HaiPay 开关都按 platform 渠道跑），但这个「渠道」概念对用户
  /// 没有意义，展示层换成 iOS 身份更直观。**只改展示**，X-Client 的
  /// channel= / build= 上报和构建逻辑不受影响。
  ///
  /// 优先用构建脚本注入的 dart-define —— 它和打包产物严格一致。
  /// 没有 define（在 Android Studio 里直接 Run）时回退到原生 versionName：
  /// Android/iOS 上 Gradle 已经加了 `-g` / `-p` 后缀，Web 上读的是站点
  /// 根目录的 `version.json`（由 `tool/build.dart` 生成）。
  Future<String> _loadAppVersion() async {
    var version = BuildInfo.hasVersion ? BuildInfo.displayVersion : '';
    if (version.isEmpty) {
      try {
        version = (await PackageInfo.fromPlatform()).version.trim();
      } catch (_) {
        version = '';
      }
    }
    if (version.isEmpty) version = BuildInfo.baseVersion;

    // 【iOS 专属展示】把渠道短码换成 -i，label 显示 iOS。
    if (!kIsWeb && Platform.isIOS) {
      final iosVersion = version.replaceFirst(RegExp(r'-(g|p|w)$'), '-i');
      return '$iosVersion · iOS';
    }
    return '$version · ${BuildFlavor.label}';
  }

  Future<void> _handleLogout() async {
    final l10n = AppLocalizations.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(
          AppLocalizations.of(dialogContext).logoutTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.logoutConfirm,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.logout,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;

    final rootNavigator = rootNavigatorKey.currentState;
    while (rootNavigator != null && rootNavigator.canPop()) {
      rootNavigator.pop();
    }

    await AppRestart.restart();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.watch(localeProvider);
    final currentLanguageLabel =
        currentLocale.languageCode.toLowerCase() == 'ar' ? l10n.arabic : l10n.english;
    // 监听 authProvider，游客状态变化时自动刷新 UI
    final auth = ref.watch(authProvider);

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              child: Row(
                children: [
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.settings,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Opacity(
                    opacity: 0,
                    child: RtlBackButton(
                      onPressed: null,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // Change Language
                    _SettingsItem(
                      title: l10n.changeLanguage,
                      trailing: Text(
                        currentLanguageLabel,
                        style: const TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 15,
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LanguagePage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // User Agreement
                    _SettingsItem(
                      title: l10n.userAgreement,
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SystemConfigContentPage(
                              configId: 5,
                              title: l10n.userAgreement,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Privacy Policy
                    _SettingsItem(
                      title: l10n.privacyPolicy,
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SystemConfigContentPage(
                              configId: 6,
                              title: l10n.privacyPolicy,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // User Recharge Agreement
                    _SettingsItem(
                      title: l10n.userRechargeAgreement,
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SystemConfigContentPage(
                              configId: 9,
                              title: l10n.userRechargeAgreement,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Message Settings
                    _SettingsItem(
                      title: l10n.messageSettings,
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MessageSettingsPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Version Number
                    FutureBuilder<String>(
                      future: _appVersionFuture,
                      builder: (context, snapshot) {
                        final versionText = snapshot.data ?? '...';
                        return _SettingsItem(
                          title: l10n.versionNumber,
                          trailing: Text(
                            versionText,
                            style: const TextStyle(
                              fontSize: 15,
                            ),
                          ),
                          onTap: () {},
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    if (!(auth.user?.isTourist ?? true)) ...[
                      // Delete account
                      _SettingsItem(
                        title: 'Delete account',
                        trailing: const _ArrowIcon(),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DeleteAccountPage(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),
                    ] else
                      const SizedBox(height: 32),

                    // Log out / Login Now
                    GestureDetector(
                        onTap: () {
                        if (auth.user != null && auth.user!.isTourist) {
                          context.push('/auth/login?redirect=/profile&back=/profile');
                        } else {
                          _handleLogout();
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF464950),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            auth.user != null && auth.user!.isTourist
                                ? 'Login Now'
                                : 'Log out',
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.copyrightLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      l10n.copyrightLicense,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      l10n.copyrightNotice,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF3B3C45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child:               Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ArrowIcon extends StatelessWidget {
  const _ArrowIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_right, color: Color(0xFF999999), size: 22);
  }
}
