import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../profile/pages/system_config_content_page.dart';

class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SystemConfigContentPage(
      configId: 5,
      title: AppLocalizations.of(context).userAgreement,
    );
  }
}
