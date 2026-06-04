import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../auth/providers/auth_provider.dart';

class ChangeNamePage extends ConsumerStatefulWidget {
  const ChangeNamePage({super.key, this.fromRegister = false});

  final bool fromRegister;

  @override
  ConsumerState<ChangeNamePage> createState() => _ChangeNamePageState();
}

class _ChangeNamePageState extends ConsumerState<ChangeNamePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _newNameController;

  @override
  void initState() {
    super.initState();
    final currentName = ref.read(authProvider).user?.userNickname ?? '';
    _nameController = TextEditingController(text: currentName);
    _newNameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final newName = _newNameController.text.trim();
    if (newName.isEmpty) return;
    ref.read(authProvider.notifier).updateNickname(newName);
    if (widget.fromRegister) {
      context.go('/auth/login');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // 游客直接跳转登录
    if (auth.user == null || auth.user!.isTourist) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/auth/login');
      });
      return const SizedBox.shrink();
    }

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final didPop = await Navigator.of(context).maybePop();
                      if (!context.mounted) {
                        return;
                      }
                      if (!didPop) {
                        context.go('/profile');
                      }
                    },
                    child: Image.asset(
                      'assets/images/back.png',
                      width: 24,
                      height: 24,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Change Nickname',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // 改名表单
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Name',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    enabled: false,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'New Name',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Enter new nickname',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Confirm 按钮
                  GestureDetector(
                    onTap: _onConfirm,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8F4EFF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text(
                        'Confirm',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
