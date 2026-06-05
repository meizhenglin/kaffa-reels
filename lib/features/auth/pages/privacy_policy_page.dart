import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../profile/pages/system_config_content_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SystemConfigContentPage(
      configId: 6,
      title: AppLocalizations.of(context).privacyPolicy,
    );
  }
}
