import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';

class RechargeAgreementPage extends StatelessWidget {
  const RechargeAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Image.asset('assets/images/back_icon.png', width: 20, height: 20),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'User Recharge Agreement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Recharge Agreement content goes here...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
