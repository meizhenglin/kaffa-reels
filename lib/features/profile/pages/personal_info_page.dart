import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/preload_network_image.dart';
import '../../../components/rtl_back_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';

class PersonalInfoPage extends ConsumerWidget {
  const PersonalInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final user = auth.user;

    if (user == null || user.isTourist) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/auth/login?back=/profile');
      });
      return const SizedBox.shrink();
    }

    final avatarUrl = user.photoURL ?? user.avatar;
    final email = user.email?.trim().isNotEmpty == true ? user.email!.trim() : '-';

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                textDirection: Directionality.of(context),
                children: [
                  RtlBackButton(
                    onPressed: () async {
                      final didPop = await Navigator.of(context).maybePop();
                      if (!context.mounted) {
                        return;
                      }
                      if (!didPop) {
                        context.go('/profile');
                      }
                    },
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                  Expanded(
                    child: Text(
                      l10n.personalInfo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Opacity(
                    opacity: 0,
                    child: RtlBackButton(
                      onPressed: null,
                      constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () => context.push('/auth/photo-setting'),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: ClipOval(
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? PreloadNetworkImage(
                                    imageUrl: avatarUrl,
                                    preloadAsset: 'assets/images/small_preload_bg.png',
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[800],
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.person,
                                      size: 48,
                                      color: Colors.white54,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _InfoItem(title: 'ID', value: user.id),
                    const SizedBox(height: 16),
                    _InfoItem(title: l10n.nameField, value: user.userNickname ?? '-',
                      trailing: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0, 1.0),
                        child: Image.asset('assets/images/to.png', width: 20, height: 20),
                      ),
                      onTap: () => context.push('/change-name'),
                    ),
                    const SizedBox(height: 16),
                    _InfoItem(title: l10n.email, value: email),
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

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.title,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final valueTextAlign = textDirection == TextDirection.rtl ? TextAlign.start : TextAlign.end;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF3B3C45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          textDirection: textDirection,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: valueTextAlign,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
