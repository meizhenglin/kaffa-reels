import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../auth/providers/auth_provider.dart';

class PhotoSettingPage extends ConsumerStatefulWidget {
  const PhotoSettingPage({super.key});

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
        _avatars = list.map((e) => e.toString()).toList();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _onSkip() {
    context.go('/change-name');
  }

  void _onContinue() {
    if (_selectedAvatar != null) {
      ref.read(authProvider.notifier).updateAvatar(_selectedAvatar!);
    }
    context.go('/change-name');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final currentAvatarUrl = user?.photoURL ?? user?.avatar;

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
                    onTap: () => context.go('/auth/login'),
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
            const SizedBox(height: 8),
            // 当前头像预览
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3B3C45),
                image: _selectedAvatar != null
                    ? DecorationImage(
                        image: NetworkImage(_selectedAvatar!),
                        fit: BoxFit.cover,
                      )
                    : (currentAvatarUrl != null && currentAvatarUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(currentAvatarUrl),
                            fit: BoxFit.cover,
                          )
                        : null),
              ),
              child: _selectedAvatar == null &&
                      (currentAvatarUrl == null || currentAvatarUrl.isEmpty)
                  ? const Center(
                      child: Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.white54,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              _selectedAvatar != null
                  ? 'Choose your avatar'
                  : 'Please select an avatar',
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 14,
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
                                    errorBuilder: (_, __, ___) => Container(
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
            // Skip 按钮
            GestureDetector(
              onTap: _onSkip,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 32),
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
            // Continue 按钮
            GestureDetector(
              onTap: _selectedAvatar != null ? _onContinue : null,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 32),
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
