import 'package:flutter/material.dart';

import '../../profile/pages/system_config_content_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SystemConfigContentPage(
      configId: 6,
      title: 'Privacy Policy',
    );
  }
}
