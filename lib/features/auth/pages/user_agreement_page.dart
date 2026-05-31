import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    GestureDetector(
                      onTap: () {
                        final navigator = Navigator.of(context);
                        if (navigator.canPop()) {
                          navigator.pop();
                        } else {
                          context.push('/auth/register/email');
                        }
                      },
                      child: Image.asset(
                        'assets/images/back.png',
                        width: 20,
                        height: 20,
                        color: Colors.white,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'User Agreement',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: const Text(
                      '''User Agreement

Last updated: May 2026

1. Acceptance of Terms
By accessing and using StoryDrama, you agree to be bound by these Terms of Service and all applicable laws and regulations.

2. Use of Service
You agree to use the service only for lawful purposes and in accordance with these Terms.

3. User Accounts
You are responsible for maintaining the confidentiality of your account and password.

4. Content
All content provided on StoryDrama is for personal, non-commercial use only.

5. Privacy
Your use of StoryDrama is also governed by our Privacy Policy.

6. Intellectual Property
All trademarks, service marks, and trade names are property of StoryDrama.

7. Limitation of Liability
StoryDrama shall not be liable for any indirect, incidental, special, consequential, or punitive damages.

8. Changes to Terms
We reserve the right to modify these terms at any time.''',
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
