import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../core/utils/app_restart.dart';

class LanguagePage extends ConsumerStatefulWidget {
  const LanguagePage({super.key});

  @override
  ConsumerState<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends ConsumerState<LanguagePage> {
  late Locale _selectedLocale;

  @override
  void initState() {
    super.initState();
    _selectedLocale = ref.read(localeProvider);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Image.asset(
                      'assets/images/back_icon.png',
                      width: 20,
                      height: 20,
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Choose Language',
                        style: TextStyle(
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
                    const SizedBox(height: 10),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: GestureDetector(
                onTap: () async {
                  await ref.read(localeProvider.notifier).setLocale(_selectedLocale);
                  AppRestart.restart();
                },
                child: Container(
                  width: double.infinity,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'Confirm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
          color: const Color(0xFF464950),
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
