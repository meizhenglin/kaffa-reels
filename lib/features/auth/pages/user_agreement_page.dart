import 'package:flutter/material.dart';

import '../../profile/pages/system_config_content_page.dart';

class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SystemConfigContentPage(
      configId: 5,
      title: 'User Agreement',
    );
  }
}
