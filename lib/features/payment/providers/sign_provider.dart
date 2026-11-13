import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../app/providers/app_providers.dart';
import '../../payment/providers/coin_record_provider.dart';
import '../models/sign_model.dart';

/// Sign state provider
final signStateProvider =
    StateNotifierProvider<SignStateNotifier, SignState>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return SignStateNotifier(ref, apiService);
});

class SignStateNotifier extends StateNotifier<SignState> {
  SignStateNotifier(this._ref, this._apiService) : super(const SignState());

  final Ref _ref;
  final ApiService _apiService;

  /// Load sign configuration
  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Load sign config (this includes sign-in status)
      final configResp = await _apiService.getSignConfig();
      SignConfig? config;
      if (configResp.isSuccess && configResp.data != null) {
        config = SignConfig.fromJson(configResp.data as Map<String, dynamic>);
      }

      state = state.copyWith(
        isLoading: false,
        config: config,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load sign info',
      );
    }
  }

  /// Perform sign-in
  Future<bool> sign() async {
    if (state.isLoading) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Get the signGoodsId for today's reward
      final todayGoodsId = _getTodayGoodsId();

      final resp = await _apiService.setUserSign(signGoodsId: todayGoodsId);

      if (resp.isSuccess) {
        final configResp = await _apiService.getSignConfig();
        SignConfig? config;
        int todayRewardCoins = 0;
        if (configResp.isSuccess) {
          config = SignConfig.fromJson(configResp.data as Map<String, dynamic>);
          if (config.rewards.isNotEmpty) {
            final dayIndex = config.isTodaySigned ? config.continueDay : config.continueDay + 1;
            if (dayIndex > 0 && dayIndex <= config.rewards.length) {
              todayRewardCoins = config.rewards[dayIndex - 1].coins;
            }
          }
        }
        state = state.copyWith(config: config, isLoading: false, todayRewardCoins: todayRewardCoins);

        // 【合并请求】签到后余额和用户信息都变了，但两者在同一个
        // /api/user/userPersonalCenter 响应里：只请求一次，同时喂给
        // coinBalanceInfo 和 authProvider（以前是 load() + refreshUserInfo()
        // 连打两次同一个接口）。
        try {
          final userCenter = await _apiService.getUserCenter();
          if (userCenter.isSuccess && userCenter.data != null) {
            final data = userCenter.data as Map<String, dynamic>;
            _ref.read(coinBalanceInfoProvider.notifier).updateFromData(data);
            await _ref.read(authProvider.notifier).updateUserFromData(data);
          }
        } catch (_) {
          // 刷新失败不影响签到结果：余额/用户信息下次进页面会重新加载。
        }
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: resp.error ?? 'Sign failed',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign failed',
      );
      return false;
    }
  }

  /// Refresh sign config
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Reload config only (user requested)
      final configResp = await _apiService.getSignConfig();
      SignConfig? config;
      if (configResp.isSuccess && configResp.data != null) {
        config = SignConfig.fromJson(configResp.data as Map<String, dynamic>);
      }

      state = state.copyWith(
        isLoading: false,
        config: config,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh sign info',
      );
    }
  }

  int _getTodayGoodsId() {
    final config = state.config;
    if (config == null || config.rewards.isEmpty) return 0;
    final dayIndex = config.isTodaySigned ? config.continueDay : config.continueDay + 1;
    if (dayIndex <= 0 || dayIndex > config.rewards.length) return 0;
    return config.rewards[dayIndex - 1].signGoodsId;
  }
}
