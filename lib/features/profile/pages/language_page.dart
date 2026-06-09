import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/utils/app_restart.dart';
import '../../../l10n/app_localizations.dart';

class LanguagePage extends ConsumerStatefulWidget {
  const LanguagePage({super.key});

  @override
  ConsumerState<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends ConsumerState<LanguagePage> {
  late Locale _selectedLocale;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedLocale = ref.read(localeProvider);
  }

  Future<void> _saveLanguage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final languageCode = _selectedLocale.languageCode.toLowerCase() == 'ar'
          ? 'ar-SA'
          : 'en-US';
      await ref.read(authProvider.notifier).setLanguage(languageCode);
      await ref.read(localeProvider.notifier).setLocale(_selectedLocale);

      if (!mounted) return;
      context.go('/profile');
      unawaited(AppRestart.restart());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.chooseLanguage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          // fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _LanguageItem(
                      language: 'English',
                      isSelected: _selectedLocale.languageCode == 'en',
                      onTap: () =>
                          setState(() => _selectedLocale = const Locale('en')),
                    ),
                    const SizedBox(height: 14),
                    _LanguageItem(
                      language: 'العربية',
                      isSelected: _selectedLocale.languageCode == 'ar',
                      onTap: () =>
                          setState(() => _selectedLocale = const Locale('ar')),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
              child: GestureDetector(
                onTap: _isSaving ? null : _saveLanguage,
                child: Opacity(
                  opacity: _isSaving ? 0.7 : 1,
                  child: Container(
                    width: double.infinity,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              l10n.common_confirm,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageItem extends StatelessWidget {
  const _LanguageItem({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  final String language;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 65,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF3B3C45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Image.asset(
              isSelected
                  ? 'assets/images/checked_icon.png'
                  : 'assets/images/check_icon.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                language,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
