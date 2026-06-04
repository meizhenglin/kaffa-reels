import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_service.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../auth/providers/auth_provider.dart';

class PhotoSettingPage extends ConsumerStatefulWidget {
  const PhotoSettingPage({super.key, this.fromRegister = false});

  final bool fromRegister;

  @override
  ConsumerState<PhotoSettingPage> createState() => _PhotoSettingPageState();
}

class _PhotoSettingPageState extends ConsumerState<PhotoSettingPage> {
  List<String> _avatars = [];
  String? _selectedAvatar;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  Future<void> _loadAvatars() async {
    setState(() => _isLoading = true);
    final resp = await apiServiceProvider.getAvatarList();
    if (resp.isSuccess && resp.data != null) {
      final list = resp.data as List;
      setState(() {
        _avatars = list.map((e) => (e as Map<String, dynamic>)['iconUrl'] as String).toList();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _onSkip() {
    if (widget.fromRegister) {
      context.push('/change-name', extra: true);
    } else {
      context.go('/profile');
    }
  }

  void _onContinue() async {
    if (_selectedAvatar != null) {
      await ref.read(authProvider.notifier).updateAvatar(_selectedAvatar!);
    }

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null && mounted) {
        ref.read(authProvider.notifier).updateUserFromData(resp.data as Map<String, dynamic>);
      }
    } catch (_) {}

    if (!mounted) {
      return;
    }

    if (widget.fromRegister) {
      context.push('/change-name', extra: true);
    } else {
      context.go('/profile');
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
                      if (widget.fromRegister) {
                        final didPop = await Navigator.of(context).maybePop();
                        if (!context.mounted) {
                          return;
                        }
                        if (!didPop) {
                          context.go('/auth/login');
                        }
                      } else {
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
                      'Photo Setting',
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
            const SizedBox(height: 24),
            // 头像列表
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF8F4EFF)),
                    )
                  : _avatars.isEmpty
                      ? const Center(
                          child: Text(
                            'No avatars available',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: _avatars.length,
                          itemBuilder: (context, index) {
                            final url = _avatars[index];
                            final isSelected = _selectedAvatar == url;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedAvatar = url),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: const Color(0xFF8F4EFF),
                                          width: 3,
                                        )
                                      : null,
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFF3B3C45),
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Skip 按钮（仅注册流程显示）
            if (widget.fromRegister) ...[
              GestureDetector(
                onTap: _onSkip,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: const Color(0xFF8F4EFF), width: 1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Skip',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8F4EFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Continue 按钮
            GestureDetector(
              onTap: _selectedAvatar != null ? _onContinue : null,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _selectedAvatar != null
                      ? const LinearGradient(
                          colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                        )
                      : null,
                  color: _selectedAvatar == null
                      ? const Color(0xFF3B3C45)
                      : null,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'Continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _selectedAvatar != null
                        ? Colors.white
                        : Colors.white38,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
