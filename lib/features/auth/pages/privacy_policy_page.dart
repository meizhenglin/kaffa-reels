import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../components/rtl_back_button.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF1A1A2A)),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 18),
                Row(
                  children: [
                    RtlBackButton(
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        if (navigator.canPop()) {
                          navigator.pop();
                        } else {
                          context.push('/auth/register/email');
                        }
                      },
                      color: Colors.white,
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const Opacity(
                      opacity: 0,
                      child: RtlBackButton(
                        onPressed: null,
                        color: Colors.white,
                        constraints: BoxConstraints(minWidth: 20, minHeight: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: const Text(
                      '''Privacy Policy

Last updated: May 2026

1. Information We Collect
We collect information you provide directly, including registration information, content you create, and usage data.

2. How We Use Your Information
We use the information we collect to provide, maintain, and improve our services.

3. Information Sharing
We do not sell your personal information. We may share information with your consent or as required by law.

4. Data Security
We implement appropriate security measures to protect your personal information.

5. Your Rights
You have the right to access, correct, or delete your personal information.

6. Cookies
We use cookies and similar technologies to provide and support our services.

7. Children's Privacy
Our service is not intended for users under the age of 13.

8. Changes to Policy
We may update this policy from time to time. We will notify you of significant changes.''',
                      style: TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
