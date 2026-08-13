/**
 * Qahwa JS API - 外部项目调用的登录接口
 * 用法:
 *   QahwaJS.init({ apiBaseUrl, platformId, platformAppId, appVersion,
 *                  osName, language, adConfig,
 *                  onLogin, onLogout, onTokenExpired });
 *
 *   // 登录（打开登录弹窗）
 *   QahwaJS.login().then(user => console.log(user));
 *
 *   // 游客登录（无需交互，自动获取/创建 deviceId 并调用 guestLogin）
 *   QahwaJS.guestLogin().then(user => console.log(user));
 *
 *   // 邮箱密码登录
 *   QahwaJS.loginWithEmail('user@example.com', 'password').then(user => ...);
 *
 *   // 邮箱验证码登录 / 注册
 *   QahwaJS.sendEmailCode(email, type).then(...);   // type: 0=登录 1=注册
 *   QahwaJS.verifyEmailCode(email, code).then(...);
 *   QahwaJS.registerWithEmail(email, password).then(...);
 *
 *   // Google 登录（外部传入 GIS idToken）
 *   QahwaJS.loginWithGoogle({ idToken, email, name, picture }).then(...);
 *
 *   // 注销账号（调 /api/user/cancelAccount）
 *   QahwaJS.cancelAccount().then(...);
 *
 *   // 用户中心
 *   QahwaJS.getUserCenter().then(info => ...);   // /api/user/userPersonalCenter
 *
 *   // 登出 / 状态查询
 *   QahwaJS.logout();
 *   QahwaJS.getUserInfo();
 *   QahwaJS.isLoggedIn();
 *
 *   // 充值
 *   QahwaJS.recharge(amount).then(order => ...);
 *
 *   // 激励广告（通过 Google Ad Placement API，浏览器/原生 WebView 都支持）
 *   // 浏览器环境 → AdSense 真实广告
 *   // 原生 WebView 环境（已调用 MobileAds.registerWebView）→ AdMob 真实广告
 *   QahwaJS.isRewardedAdReady();                                  // API 是否已加载
 *   QahwaJS.checkRewardedAdReady();                               // Promise 版本
 *   QahwaJS.showAd({                                              // 触发真实激励广告
 *     onRewardEarned: (reward) => {},
 *     onNotReady:    (reason)  => {},
 *     onClose:       ()        => {},
 *     onError:       (err)     => {}
 *   }).then(reward => console.log(reward));
 *
 *   // 菜单
 *   QahwaJS.showMenu();
 */

(function(global) {
  'use strict';

  // ==================== 常量（对齐项目 PassportType）====================

  /**
   * Passport types for different login methods
   * Must match the backend PassportType enum + QahwaGameSDK.PASSPORT_TYPE
   */
  const PASSPORT_TYPE = {
    GUEST:   0,  // 游客
    EMAIL:   1,  // 邮箱
    WECHAT:  2,
    DOUYIN:  3,
    GOOGLE:  5,
    APPLE:   6
  };

  /**
   * API 端点（对齐 lib/core/model/api_endpoints.dart）
   */
  const ENDPOINTS = {
    USER_AUTHORIZATION:    'api/user/userAuthorization',     // 主登录接口（所有登录方式走这里）
    GOOGLE_ID_TOKEN:       'api/user/googleIdToken',
    SEND_CODE:             'api/user/sendCode',              // 发邮箱验证码（type=0登录 1注册）
    VERIFY_CODE:           'api/user/verifyCode',            // 校验邮箱验证码
    MAIL_REGISTER:         'api/user/mailRegister',          // 邮箱注册
    USER_PERSONAL_CENTER:  'api/user/userPersonalCenter',    // 个人中心
    CANCEL_ACCOUNT:        'api/user/cancelAccount',        // 注销账号
    AD_REWARD:             'api/ad/reward'                   // 激励广告奖励
  };

  /**
   * 业务错误码（对齐 ApiErrorCode）
   */
  const ERROR_CODE = {
    SUCCESS:       0,
    TOKEN_EXPIRED: 23,
    NETWORK_ERROR: -1
  };

  /**
   * Storage key
   */
  const STORAGE_KEYS = {
    DEVICE_ID: 'qahwa_device_id',
    USER_INFO: 'qahwa_user',
    TOKEN:     'qahwa_token'
  };

  const QahwaJS = {
    _loginModal: null,
    _userInfo: null,
    _token: null,
    _onLoginCallback: null,
    _onLogoutCallback: null,
    _onTokenExpiredCallback: null,
    _apiBaseUrl: 'https://tvapi.qahwatv.com/',
    _platformId: 2,
    _platformAppId: 2002,
    _appVersion: '1.0.0',
    _osName: 'Web',
    _language: 'en-US',
    _deviceId: null,

    // ============ 广告配置（Google Ad Placement API）============
    _rewardedAdUnitId: 'ca-app-pub-3738458657290827/6345591075',
    _interstitialAdUnitId: 'ca-app-pub-3738458657290827/9060380177',
    _adsenseClient: 'ca-pub-3738458657290827',
    _adTestMode: false,
    _adPlacementApiLoaded: false,
    _adPlacementApiLoadFailed: false,

    /**
     * 注入 Google Ad Placement API script tag（必须在 H5 页面加载）
     *
     * - 浏览器环境 → 走 AdSense 真实激励广告
     * - 原生 WebView 环境 → 如果已注册 MobileAds.registerWebView，会自动走 AdMob
     *
     * 由 init() 自动调用一次。
     * @private
     */
    _loadAdPlacementApi: function() {
      var self = this;
      if (self._adPlacementApiLoaded) return;
      if (typeof window === 'undefined') return;

      // 初始化 adsbygoogle queue（必须在加载 script 之前，否则 adBreak() 调用会被丢弃）
      window.adsbygoogle = window.adsbygoogle || [];
      window.adBreak = window.adBreak || function(o) { window.adsbygoogle.push(o); };
      window.adConfig = window.adConfig || function(o) { window.adsbygoogle.push(o); };

      var client = self._adsenseClient;
      var rewardedSlot = self._rewardedAdUnitId;
      var interstitialSlot = self._interstitialAdUnitId;
      var testMode = self._adTestMode ? 'on' : null;

      // ⚠️ 重要：file:// 协议或缺少 cookie/localStorage 时浏览器会拒绝加载此脚本
      // ← 拒绝后 script.onerror 触发，但 adBreak/adConfig 队列已初始化
      // ← 此时调用 adBreak({...}) 会被 push 到队列里，但永远不会被消费
      // ← adBreakDone 永远不会被调用 → 上层无响应
      // ← 调用方需要监听 _adPlacementApiLoadFailed 事件
      var script = document.createElement('script');
      script.async = true;
      script.crossOrigin = 'anonymous';
      // 拼接 query：data-ad-client + data-admob-*-slot
      var src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' + encodeURIComponent(client);
      if (rewardedSlot) script.setAttribute('data-admob-rewarded-slot', rewardedSlot);
      if (interstitialSlot) script.setAttribute('data-admob-interstitial-slot', interstitialSlot);
      if (testMode) script.setAttribute('data-adbreak-test', testMode);
      script.src = src;

      script.onload = function() {
        self._adPlacementApiLoaded = true;
        self._adPlacementApiLoadFailed = false;
        console.log('[QahwaJS] Ad Placement API loaded successfully');
      };
      script.onerror = function() {
        self._adPlacementApiLoaded = false;
        self._adPlacementApiLoadFailed = true;
        console.error('[QahwaJS] Failed to load Ad Placement API. ' +
          'Possible causes: ' +
          '(1) file:// protocol — must serve via http:// (e.g. python -m http.server); ' +
          '(2) invalid client ID ' + client + '; ' +
          '(3) network blocked / mixed-content.');
      };

      // 插入到 head
      document.head.appendChild(script);
    },

    /**
     * 真实激励广告播放
     *
     * 优先级：
     * 1. 原生桥接 (QahwaNative) - App WebView 中使用 Flutter AdManager
     * 2. Google Ad Placement API (adBreak) - 浏览器中使用 AdSense
     *
     * @param {Object} [options]
     * @param {Function} [options.onRewardEarned] - 用户完整观看获得奖励时回调（必传）
     * @param {Function} [options.onNotReady] - 没有可用的激励广告（用于上层降级）
     * @param {Function} [options.onClose] - 用户主动关闭广告（未看完）
     * @param {Function} [options.onError] - 广告播放失败
     * @returns {Promise<Object>} { success, coins, totalCoins }
     */
    showAd: function(options) {
      var self = this;
      options = options || {};
      var callbacks = {
        onRewardEarned: options.onRewardEarned,
        onNotReady: options.onNotReady,
        onClose: options.onClose,
        onError: options.onError
      };

      // ========== 优先级 1：使用原生桥接（App WebView）==========
      if (this._isNativeBridgeAvailable()) {
        return this._showAdViaNativeBridge(callbacks);
      }

      // ========== 优先级 2：使用 Ad Placement API（浏览器）==========
      return this._showAdViaAdPlacementApi(callbacks);
    },

    /**
     * 通过原生桥接显示广告（App WebView 环境）
     * @private
     */
    _showAdViaNativeBridge: function(callbacks) {
      var self = this;
      var requestId = 'ad_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

      return new Promise(function(resolve, reject) {
        // 注册回调
        self._adCallbacks = self._adCallbacks || {};
        self._adCallbacks[requestId] = {
          resolve: resolve,
          reject: reject,
          callbacks: callbacks,
          timeoutId: null
        };

        // 30秒超时
        var timeoutId = setTimeout(function() {
          delete self._adCallbacks[requestId];
          console.warn('[QahwaJS] Ad timeout 30s');
          if (callbacks.onNotReady) callbacks.onNotReady('timeout');
          reject(new Error('Ad timeout: no response after 30s'));
        }, 30000);
        self._adCallbacks[requestId].timeoutId = timeoutId;

        // 发送消息给原生
        console.log('[QahwaJS] Native bridge available, sending ad request...');
        window.QahwaNative.postMessage(JSON.stringify({
          action: 'showRewardedAd',
          requestId: requestId,
          data: {
            adUnitId: self._rewardedAdUnitId
          }
        }));
      });
    },

    /**
     * 处理原生广告回调（由原生端调用）
     * @param {string} requestId
     * @param {Object} result
     * @private
     */
    _handleAdCallback: function(requestId, result) {
      var self = this;
      var callbacks = self._adCallbacks && self._adCallbacks[requestId];
      if (!callbacks) return;

      clearTimeout(callbacks.timeoutId);
      delete self._adCallbacks[requestId];

      if (result.success) {
        // 广告成功显示并完成
        self._doAdReward()
          .then(function(reward) {
            if (callbacks.callbacks.onRewardEarned) callbacks.callbacks.onRewardEarned(reward);
            callbacks.resolve({
              success: true,
              coins: reward.coins,
              totalCoins: reward.totalCoins
            });
          })
          .catch(function(err) {
            // 后端记账失败：仍然算用户已看完广告
            console.warn('[QahwaJS] Reward backend error (不影响用户奖励):', err.message);
            if (callbacks.callbacks.onRewardEarned) callbacks.callbacks.onRewardEarned({ coins: 0, totalCoins: 0 });
            callbacks.resolve({ success: true, coins: 0, totalCoins: 0 });
          });
      } else if (result.dismissed) {
        // 用户关闭广告
        if (callbacks.callbacks.onClose) callbacks.callbacks.onClose();
        callbacks.reject(new Error('Ad dismissed by user'));
      } else {
        // 广告未就绪或其他错误
        if (callbacks.callbacks.onNotReady) callbacks.callbacks.onNotReady(result.reason || 'not_ready');
        callbacks.reject(new Error(result.reason || 'Ad not ready'));
      }
    },

    /**
     * 注册原生回调接收器
     * @private
     */
    _registerNativeCallback: function() {
      var self = this;
      // 监听来自原生端的消息
      if (window.QahwaNative && window.QahwaNative.onMessage) {
        window.QahwaNative.onMessage(function(message) {
          console.log('[QahwaJS] Received native message:', message);
          try {
            var data = typeof message === 'string' ? JSON.parse(message) : message;
            if (data.action === 'adCallback' && data.requestId) {
              self._handleAdCallback(data.requestId, data.result || {});
            }
          } catch (e) {
            console.error('[QahwaJS] Error parsing native message:', e);
          }
        });
      }

      // 也支持直接调用 _handleAdCallback（游戏 HTML 可以直接调用）
      window.QahwaNative = window.QahwaNative || {};
      window.QahwaNative._onAdResult = function(requestId, result) {
        self._handleAdCallback(requestId, result);
      };
    },

    /**
     * 通过 Google Ad Placement API 显示广告（浏览器环境）
     * @private
     */
    _showAdViaAdPlacementApi: function(callbacks) {
      var self = this;

      return new Promise(function(resolve, reject) {
        // 1. Ad Placement API script 加载失败
        if (self._adPlacementApiLoadFailed) {
          var loadErr = new Error(
            'Ad Placement API script failed to load. ' +
            'Make sure this page is served via http:// (not file://) and that AdSense client ID is valid.'
          );
          if (callbacks.onError) callbacks.onError(loadErr);
          reject(loadErr);
          return;
        }

        // 2. Ad Placement API 还在加载
        if (typeof window.adBreak !== 'function') {
          var notReadyErr = new Error('Ad Placement API not loaded yet');
          if (callbacks.onNotReady) callbacks.onNotReady('initializing');
          reject(notReadyErr);
          return;
        }

        var timedOut = false;
        var timeoutId = setTimeout(function() {
          timedOut = true;
          console.warn('[QahwaJS] adBreak timeout 30s');
          if (callbacks.onNotReady) callbacks.onNotReady('timeout');
          reject(new Error('Ad timeout: no adBreakDone after 30s'));
        }, 30000);

        try {
          window.adBreak({
            type: 'reward',
            name: 'qahwa-rewarded-ad',

            beforeReward: function(showAdFn) {
              if (timedOut) return;
              console.log('[QahwaJS] Rewarded ad available, showing...');
              showAdFn();
            },

            adViewed: function() {
              if (timedOut) return;
              clearTimeout(timeoutId);
              console.log('[QahwaJS] User viewed rewarded ad');
              self._doAdReward()
                .then(function(reward) {
                  if (callbacks.onRewardEarned) callbacks.onRewardEarned(reward);
                  resolve({ success: true, coins: reward.coins, totalCoins: reward.totalCoins });
                })
                .catch(function(err) {
                  console.warn('[QahwaJS] Reward backend error:', err.message);
                  if (callbacks.onRewardEarned) callbacks.onRewardEarned({ coins: 0, totalCoins: 0 });
                  resolve({ success: true, coins: 0, totalCoins: 0 });
                });
            },

            adDismissed: function() {
              if (timedOut) return;
              clearTimeout(timeoutId);
              console.log('[QahwaJS] User dismissed ad');
              if (callbacks.onClose) callbacks.onClose();
              reject(new Error('Ad dismissed by user'));
            },

            adBreakDone: function(placementInfo) {
              if (timedOut) return;
              clearTimeout(timeoutId);
              console.log('[QahwaJS] adBreakDone:', placementInfo);
              if (placementInfo && placementInfo.breakStatus === 'frequencyCapped') {
                if (callbacks.onNotReady) callbacks.onNotReady('frequency_capped');
                reject(new Error('Ad frequency capped'));
              } else if (placementInfo && placementInfo.breakStatus === 'other') {
                if (callbacks.onNotReady) callbacks.onNotReady('not_ready');
                reject(new Error('Ad not ready'));
              }
            }
          });
        } catch (e) {
          clearTimeout(timeoutId);
          console.error('[QahwaJS] adBreak error:', e);
          if (callbacks.onError) callbacks.onError(e);
          reject(e);
        }
      });
    },

    /**
     * 激励广告是否已准备好
     * 同时检测：原生桥接（App WebView）或 Ad Placement API（浏览器）
     * @returns {boolean}
     */
    isRewardedAdReady: function() {
      // 1. 原生桥接可用（App WebView - AdMob）
      if (this._isNativeBridgeAvailable()) {
        return true;
      }
      // 2. Ad Placement API 可用（浏览器 - AdSense）
      return typeof window !== 'undefined' && typeof window.adBreak === 'function';
    },

    /**
     * 异步查询激励广告是否已准备好
     * @returns {Promise<boolean>}
     */
    checkRewardedAdReady: function() {
      var self = this;
      return new Promise(function(resolve) {
        resolve(self.isRewardedAdReady());
      });
    },

    /**
     * 初始化 API
     * @param {Object} options
     * @param {string} [options.apiBaseUrl] - 后端 API 地址
     * @param {number} [options.platformId] - 平台 ID（2=Android, 3=iOS）
     * @param {number} [options.platformAppId] - 平台 App ID（2002=Android, 3001=iOS）
     * @param {string} [options.appVersion] - App 版本
     * @param {string} [options.osName] - 系统名称
     * @param {string} [options.language] - 语言 (en-US / ar-SA)
     * @param {Object} [options.adConfig] - 广告配置
     * @param {string} [options.adConfig.rewardedAdUnitId] - 激励广告单元 ID（AdMob）
     * @param {string} [options.adConfig.interstitialAdUnitId] - 插屏广告单元 ID（AdMob）
     * @param {string} [options.adConfig.adsenseClient] - AdSense 客户 ID（浏览器环境使用）
     * @param {boolean} [options.adConfig.testMode] - 测试模式（避免真实计费）
     * @param {Function} [options.onLogin] - 登录成功回调
     * @param {Function} [options.onLogout] - 登出回调
     * @param {Function} [options.onTokenExpired] - token 过期回调（code=23）
     */
    init: function(options = {}) {
      if (options.apiBaseUrl) this._apiBaseUrl = options.apiBaseUrl;
      if (options.platformId) this._platformId = options.platformId;
      if (options.platformAppId) this._platformAppId = options.platformAppId;
      if (options.appVersion) this._appVersion = options.appVersion;
      if (options.osName) this._osName = options.osName;
      if (options.language) this._language = options.language;
      if (options.adConfig) {
        if (options.adConfig.rewardedAdUnitId) this._rewardedAdUnitId = options.adConfig.rewardedAdUnitId;
        if (options.adConfig.interstitialAdUnitId) this._interstitialAdUnitId = options.adConfig.interstitialAdUnitId;
        if (options.adConfig.adsenseClient) this._adsenseClient = options.adConfig.adsenseClient;
        if (typeof options.adConfig.testMode === 'boolean') this._adTestMode = options.adConfig.testMode;
      }

      if (typeof options.onLogin === 'function') this._onLoginCallback = options.onLogin;
      if (typeof options.onLogout === 'function') this._onLogoutCallback = options.onLogout;
      if (typeof options.onTokenExpired === 'function') this._onTokenExpiredCallback = options.onTokenExpired;

      // 注册 window.QahwaNative._onAdResult 回调接收器（向后兼容，无操作）
      this._registerNativeCallback();

      // 设备 ID（持久化，对齐 AuthService._getOrCreateDeviceId）
      this._deviceId = this._getOrCreateDeviceId();

      // 加载已有登录状态（userInfo + token）
      this._loadUserFromStorage();

      // 注入 Google Ad Placement API（核心：浏览器 → AdSense / WebView → AdMob）
      this._loadAdPlacementApi();

      return this;
    },

    /**
     * 获取或创建设备 ID（对齐 AuthService._getOrCreateDeviceId）
     * @private
     */
    _getOrCreateDeviceId: function() {
      try {
        var deviceId = localStorage.getItem(STORAGE_KEYS.DEVICE_ID);
        if (deviceId) return deviceId;
        deviceId = 'h5_' + this._generateUUID();
        localStorage.setItem(STORAGE_KEYS.DEVICE_ID, deviceId);
        return deviceId;
      } catch (e) {
        return 'h5_' + this._generateUUID();
      }
    },

    /**
     * 生成 UUID
     * @private
     */
    _generateUUID: function() {
      return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0;
        var v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },

    /**
     * 构建 X-Client 头（对齐 ApiService._buildXClientHeader / QahwaGameSDK._buildXClient）
     * @private
     */
    _buildXClient: function() {
      return [
        'platformId=' + this._platformId,
        'platformAppId=' + this._platformAppId,
        'version=' + this._appVersion,
        'osName=' + this._osName,
        'x-lang=' + this._language
      ].join(';');
    },

    /**
     * 统一请求方法（对齐 ApiService.request）
     * 自动携带 X-Client、token、client_params，统一处理 code=23（Token 过期）
     *
     * @param {string} endpoint - 接口路径（不带 baseUrl）
     * @param {Object} [options]
     * @param {Object} [options.body] - 请求体
     * @param {string} [options.method] - HTTP 方法，默认 POST
     * @param {boolean} [options.isForm] - 是否使用 form-urlencoded
     * @param {boolean} [options.noAuth] - 是否不带 token（游客/验证码等接口）
     * @returns {Promise<{isSuccess: boolean, isExpired: boolean, data: any, error: string, code: number}>}
     * @private
     */
    _request: function(endpoint, options) {
      var self = this;
      options = options || {};

      var method = (options.method || 'POST').toUpperCase();
      var body = options.body || {};
      var isForm = !!options.isForm;
      var noAuth = !!options.noAuth;

      var headers = {
        'X-Client': this._buildXClient()
      };

      if (isForm) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      } else {
        headers['Content-Type'] = 'application/json';
      }

      if (!noAuth && this._token) {
        headers['token'] = this._token;
      }

      var url = this._apiBaseUrl + endpoint;

      console.log('[QahwaJS] REQUEST[' + method + '] => ' + url, body);

      return fetch(url, {
        method: method,
        headers: headers,
        body: isForm ? this._encodeForm(body) : (method !== 'GET' ? JSON.stringify(body) : undefined)
      })
        .then(function(response) {
          return response.json().then(function(data) {
            return { httpStatus: response.status, data: data };
          });
        })
        .then(function(result) {
          console.log('[QahwaJS] RESPONSE[' + endpoint + '] =>', result.data);

          if (result.httpStatus !== 200) {
            return {
              isSuccess: false,
              isExpired: false,
              data: null,
              error: 'HTTP ' + result.httpStatus,
              code: result.httpStatus
            };
          }

          var body = result.data || {};
          var code = body.code;
          var msg = body.msg || 'Request failed';

          if (code === ERROR_CODE.SUCCESS) {
            return {
              isSuccess: true,
              isExpired: false,
              data: body.data,
              error: null,
              code: code
            };
          }

          if (code === ERROR_CODE.TOKEN_EXPIRED) {
            // 触发 token_expired 回调（对齐 ApiService.expired）
            self._clearUser();
            if (self._onTokenExpiredCallback) self._onTokenExpiredCallback(msg);
            return {
              isSuccess: false,
              isExpired: true,
              data: null,
              error: msg,
              code: code
            };
          }

          return {
            isSuccess: false,
            isExpired: false,
            data: null,
            error: msg,
            code: code
          };
        })
        .catch(function(err) {
          console.error('[QahwaJS] Network error:', err);
          return {
            isSuccess: false,
            isExpired: false,
            data: null,
            error: err.message || 'Network error',
            code: ERROR_CODE.NETWORK_ERROR
          };
        });
    },

    /**
     * 将对象编码为 form-urlencoded 字符串
     * @private
     */
    _encodeForm: function(obj) {
      return Object.keys(obj || {})
        .filter(function(k) { return obj[k] !== undefined && obj[k] !== null; })
        .map(function(k) { return encodeURIComponent(k) + '=' + encodeURIComponent(obj[k]); })
        .join('&');
    },

    /**
     * 打开登录弹窗（默认邮箱密码登录）
     * 用户可在弹窗内切换 Tab：Email / Register / Guest
     * @returns {Promise<Object>} 登录成功返回用户信息
     */
    login: function() {
      var self = this;
      return new Promise(function(resolve, reject) {
        if (self._userInfo) {
          resolve(self._userInfo);
          return;
        }
        self._showLoginModal({
          onSuccess: function(user) { resolve(user); },
          onError:   function(err) { reject(err); },
          onClose:   function()    { reject(new Error('Login cancelled')); }
        });
      });
    },

    /**
     * 游客登录（对齐 AuthService.ensureGuestLogin / ApiService.guestLogin）
     * - 已有 user_token 时直接返回缓存
     * - 否则调用 /api/user/userAuthorization (passportType=0) 自动登录
     * @returns {Promise<Object>}
     */
    guestLogin: function() {
      var self = this;
      return new Promise(function(resolve, reject) {
        if (self._userInfo && self._token) {
          resolve(self._userInfo);
          return;
        }
        self._doGuestLogin()
          .then(function(user) { resolve(user); })
          .catch(reject);
      });
    },

    /**
     * 邮箱密码登录（对齐 ApiService.login）
     * @param {string} email
     * @param {string} password
     * @returns {Promise<Object>}
     */
    loginWithEmail: function(email, password) {
      return this._doEmailLogin(email, password);
    },

    /**
     * 发送邮箱验证码（对齐 ApiService.sendEmailCode）
     * @param {string} email
     * @param {number} [type] - 0=登录 1=注册，默认 0
     * @returns {Promise<{success: boolean, message: string}>}
     */
    sendEmailCode: function(email, type) {
      var self = this;
      return this._request(ENDPOINTS.SEND_CODE, {
        body: { email: email, type: type || 0 },
        isForm: true,
        noAuth: true
      }).then(function(res) {
        if (res.isSuccess) {
          return { success: true, message: 'Code sent' };
        }
        var err = new Error(res.error || 'Failed to send code');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 校验邮箱验证码（对齐 ApiService.checkEmailCode）
     * @param {string} email
     * @param {string} code
     * @returns {Promise<{success: boolean, verified: boolean}>}
     */
    verifyEmailCode: function(email, code) {
      var self = this;
      return this._request(ENDPOINTS.VERIFY_CODE, {
        body: { email: email, code: code },
        isForm: true,
        noAuth: true
      }).then(function(res) {
        if (res.isSuccess) {
          return { success: true, verified: true };
        }
        var err = new Error(res.error || 'Invalid code');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 邮箱注册（对齐 ApiService.register / AuthService.register）
     * 注册成功不自动登录，由调用方决定是否引导用户登录
     * @param {string} email
     * @param {string} password
     * @returns {Promise<{success: boolean, token?: string, message?: string}>}
     */
    registerWithEmail: function(email, password) {
      var self = this;
      return this._request(ENDPOINTS.MAIL_REGISTER, {
        body: { email: email, passportPassword: password }
      }).then(function(res) {
        if (res.isSuccess) {
          var data = res.data || {};
          // 注册成功后保存 token（如有），并自动登录态
          if (data.token) {
            self._saveUserFromLogin(data, PASSPORT_TYPE.EMAIL);
          }
          return {
            success: true,
            token: data.token || null,
            uuid: data.uuid || null
          };
        }
        var err = new Error(res.error || 'Registration failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * Google 登录（对齐 ApiService.googleLogin）
     * 依赖：业务方自行集成 Google Identity Services，
     *       把获取到的 google.accounts.id.result 传入本方法。
     *
     * @param {Object} googleUser
     * @param {string} googleUser.idToken - Google ID token
     * @param {string} [googleUser.accessToken]
     * @param {string} [googleUser.email]
     * @param {string} [googleUser.name]
     * @param {string} [googleUser.picture]
     * @returns {Promise<Object>}
     */
    loginWithGoogle: function(googleUser) {
      var self = this;
      if (!googleUser || !googleUser.idToken) {
        return Promise.reject(new Error('Google ID token is required'));
      }

      var passportName = JSON.stringify({
        idToken: googleUser.idToken,
        code: 0,
        message: 'Sign in successful'
      });

      return this._request(ENDPOINTS.USER_AUTHORIZATION, {
        body: {
          passportType: PASSPORT_TYPE.GOOGLE,
          passportName: passportName,
          idToken: googleUser.idToken,
          email: googleUser.email || '',
          nickName: googleUser.name || '',
          userAvatar: googleUser.picture || ''
        }
      }).then(function(res) {
        if (res.isSuccess) {
          return self._saveUserFromLogin(res.data, PASSPORT_TYPE.GOOGLE);
        }
        var err = new Error(res.error || 'Google login failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * Apple 登录（对齐 ApiService.appleLogin）
     * 依赖：业务方自行集成 Sign in with Apple JS，把 identityToken/authorizationCode 传入。
     *
     * @param {Object} appleUser
     * @param {string} appleUser.identityToken
     * @param {string} appleUser.authorizationCode
     * @param {string} [appleUser.fullName]
     * @returns {Promise<Object>}
     */
    loginWithApple: function(appleUser) {
      var self = this;
      if (!appleUser || !appleUser.identityToken || !appleUser.authorizationCode) {
        return Promise.reject(new Error('Apple identityToken and authorizationCode are required'));
      }
      return this._request(ENDPOINTS.USER_AUTHORIZATION, {
        body: {
          passportType: PASSPORT_TYPE.APPLE,
          idToken: appleUser.identityToken,
          authorizationCode: appleUser.authorizationCode,
          fullName: appleUser.fullName || ''
        }
      }).then(function(res) {
        if (res.isSuccess) {
          return self._saveUserFromLogin(res.data, PASSPORT_TYPE.APPLE);
        }
        var err = new Error(res.error || 'Apple login failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 注销账号（对齐 ApiService.cancelAccount）
     * 后端注销后自动清理本地登录态
     * @returns {Promise<void>}
     */
    cancelAccount: function() {
      var self = this;
      return this._request(ENDPOINTS.CANCEL_ACCOUNT, { method: 'POST' })
        .then(function(res) {
          self._clearUser();
          if (self._onLogoutCallback) self._onLogoutCallback();
          if (res.isSuccess) return;
          var err = new Error(res.error || 'Cancel account failed');
          err.code = res.code;
          throw err;
        });
    },

    /**
     * 获取个人中心信息（对齐 ApiService.getUserCenter → /api/user/userPersonalCenter）
     * @returns {Promise<Object>}
     */
    getUserCenter: function() {
      var self = this;
      return this._request(ENDPOINTS.USER_PERSONAL_CENTER, { method: 'POST' })
        .then(function(res) {
          if (res.isSuccess) {
            var userInfo = self._parseUserInfo(res.data);
            self._saveUserInfo(userInfo);
            return userInfo;
          }
          var err = new Error(res.error || 'Failed to fetch user center');
          err.code = res.code;
          throw err;
        });
    },

    /**
     * 登出（清理本地 userInfo + token）
     */
    logout: function() {
      this._clearUser();
      if (this._onLogoutCallback) this._onLogoutCallback();
    },

    /**
     * 获取当前用户信息
     */
    getUserInfo: function() {
      return this._userInfo;
    },

    /**
     * 获取当前 token
     */
    getToken: function() {
      return this._token;
    },

    /**
     * 检查是否已登录
     */
    isLoggedIn: function() {
      return this._userInfo !== null && this._token !== null;
    },

    /**
     * 打开充值弹窗
     * @param {number} amount - 充值金额（美元）
     * @returns {Promise} 支付成功返回订单信息
     */
    recharge: function(amount) {
      if (!this._userInfo) {
        return Promise.reject(new Error('Please login first'));
      }

      return new Promise((resolve, reject) => {
        this._showRechargeModal(amount, {
          onSuccess: (order) => resolve(order),
          onError: (err) => reject(err),
          onClose: () => reject(new Error('Recharge cancelled'))
        });
      });
    },

    /**
     * 检测原生桥是否可用（保留作为兼容检查，已不推荐使用）
     * 现在 H5 通过 Google Ad Placement API 直接展示广告，无需 JS Bridge
     * @private
     */
    _isNativeBridgeAvailable: function() {
      return typeof window !== 'undefined'
        && window.QahwaNative
        && typeof window.QahwaNative.postMessage === 'function';
    },

    /**
     * 提交广告奖励到后端（对齐 _tryUnlockWithRewardedAd 调用后端接口的模式）
     * 后端返回 { code: 0, data: { coins, totalCoins } }
     * @private
     */
    _doAdReward: function() {
      if (!this._userInfo) {
        return Promise.reject(new Error('Not logged in'));
      }
      return this._request(ENDPOINTS.AD_REWARD, {
        body: {
          adUnitId: this._rewardedAdUnitId,
          deviceId: this._deviceId,
          platformId: this._platformId,
          platformAppId: this._platformAppId,
          timestamp: Date.now()
        }
      }).then(function(res) {
        if (res.isSuccess) {
          var data = res.data || {};
          return {
            coins: data.coins || 0,
            totalCoins: data.totalCoins || 0
          };
        }
        var err = new Error(res.error || 'Reward failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 显示用户菜单
     * 包含：用户中心、退出登录
     */
    showMenu: function() {
      if (!this._userInfo) {
        this.login();
        return;
      }

      this._showUserMenu();
    },

    // ============ 私有方法 ============

    _showLoginModal: function(callbacks) {
      // 移除已存在的弹窗
      this._closeLoginModal();

      // 当前激活的 tab：'login' | 'register' | 'guest'
      let activeTab = 'login';

      // 创建弹窗 DOM
      const modal = document.createElement('div');
      modal.id = 'qahwa-login-modal';
      modal.innerHTML = `
        <style>
          #qahwa-login-modal {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.6);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 999999;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          }
          #qahwa-login-modal .qahwa-modal-content {
            background: white;
            border-radius: 16px;
            padding: 28px 32px 32px;
            width: 90%;
            max-width: 420px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            position: relative;
            max-height: 90vh;
            overflow-y: auto;
          }
          #qahwa-login-modal .qahwa-close-btn {
            position: absolute;
            top: 16px;
            right: 16px;
            width: 32px;
            height: 32px;
            border: none;
            background: #f0f0f0;
            border-radius: 50%;
            cursor: pointer;
            font-size: 18px;
            display: flex;
            align-items: center;
            justify-content: center;
          }
          #qahwa-login-modal .qahwa-close-btn:hover { background: #e0e0e0; }
          #qahwa-login-modal h2 {
            margin: 0 0 16px;
            color: #333;
            font-size: 22px;
            text-align: center;
          }
          #qahwa-login-modal .qahwa-tabs {
            display: flex;
            border-bottom: 1px solid #eee;
            margin-bottom: 20px;
          }
          #qahwa-login-modal .qahwa-tab {
            flex: 1;
            padding: 10px 0;
            text-align: center;
            color: #888;
            cursor: pointer;
            font-size: 14px;
            border-bottom: 2px solid transparent;
            transition: all 0.2s;
          }
          #qahwa-login-modal .qahwa-tab.active {
            color: #667eea;
            border-bottom-color: #667eea;
            font-weight: 600;
          }
          #qahwa-login-modal .qahwa-form-group {
            margin-bottom: 14px;
          }
          #qahwa-login-modal label {
            display: block;
            margin-bottom: 6px;
            color: #555;
            font-weight: 500;
            font-size: 14px;
          }
          #qahwa-login-modal input {
            width: 100%;
            padding: 11px 14px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 15px;
            box-sizing: border-box;
          }
          #qahwa-login-modal input:focus {
            outline: none;
            border-color: #667eea;
          }
          #qahwa-login-modal .qahwa-code-row {
            display: flex;
            gap: 8px;
          }
          #qahwa-login-modal .qahwa-code-row input {
            flex: 1;
          }
          #qahwa-login-modal .qahwa-send-code-btn {
            padding: 0 14px;
            background: #f0f0f0;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            color: #667eea;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            white-space: nowrap;
          }
          #qahwa-login-modal .qahwa-send-code-btn:hover { background: #e8e8e8; }
          #qahwa-login-modal .qahwa-send-code-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
          }
          #qahwa-login-modal .qahwa-btn-primary {
            width: 100%;
            padding: 13px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            margin-top: 6px;
          }
          #qahwa-login-modal .qahwa-btn-primary:hover { opacity: 0.9; }
          #qahwa-login-modal .qahwa-btn-primary:disabled {
            opacity: 0.6;
            cursor: not-allowed;
          }
          #qahwa-login-modal .qahwa-btn-guest {
            width: 100%;
            padding: 13px;
            background: white;
            color: #667eea;
            border: 2px solid #667eea;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            margin-top: 6px;
          }
          #qahwa-login-modal .qahwa-btn-guest:hover { background: #f8f5ff; }
          #qahwa-login-modal .qahwa-error {
            color: #dc3545;
            font-size: 13px;
            margin-top: 8px;
            text-align: center;
          }
          #qahwa-login-modal .qahwa-loading {
            text-align: center;
            padding: 20px;
            color: #666;
          }
          #qahwa-login-modal .qahwa-switch-link {
            text-align: center;
            margin-top: 14px;
            font-size: 13px;
            color: #888;
          }
          #qahwa-login-modal .qahwa-switch-link a {
            color: #667eea;
            cursor: pointer;
            text-decoration: none;
          }
          #qahwa-login-modal .qahwa-divider {
            display: flex;
            align-items: center;
            margin: 16px 0;
            color: #ccc;
            font-size: 12px;
          }
          #qahwa-login-modal .qahwa-divider::before,
          #qahwa-login-modal .qahwa-divider::after {
            content: '';
            flex: 1;
            height: 1px;
            background: #eee;
          }
          #qahwa-login-modal .qahwa-divider span {
            padding: 0 12px;
          }
        </style>
        <div class="qahwa-modal-content">
          <button class="qahwa-close-btn" id="qahwa-close-btn">&times;</button>
          <h2>Welcome to Qahwa</h2>

          <div class="qahwa-tabs">
            <div class="qahwa-tab active" data-tab="login">Login</div>
            <div class="qahwa-tab" data-tab="register">Register</div>
            <div class="qahwa-tab" data-tab="guest">Guest</div>
          </div>

          <!-- 邮箱密码登录 -->
          <form id="qahwa-login-form">
            <div class="qahwa-form-group">
              <label for="qahwa-email">Email</label>
              <input type="email" id="qahwa-email" placeholder="Enter your email" autocomplete="email" required>
            </div>
            <div class="qahwa-form-group">
              <label for="qahwa-password">Password</label>
              <input type="password" id="qahwa-password" placeholder="Enter your password" autocomplete="current-password" required>
            </div>
            <div id="qahwa-error-msg" class="qahwa-error" style="display: none;"></div>
            <button type="submit" class="qahwa-btn-primary" id="qahwa-submit-btn">Login</button>
            <div id="qahwa-loading" class="qahwa-loading" style="display: none;">Logging in...</div>
          </form>

          <!-- 邮箱验证码注册（默认隐藏） -->
          <form id="qahwa-register-form" style="display: none;">
            <div class="qahwa-form-group">
              <label for="qahwa-register-email">Email</label>
              <input type="email" id="qahwa-register-email" placeholder="Enter your email" autocomplete="email" required>
            </div>
            <div class="qahwa-form-group">
              <label for="qahwa-register-code">Verification Code</label>
              <div class="qahwa-code-row">
                <input type="text" id="qahwa-register-code" placeholder="6-digit code" maxlength="6" required>
                <button type="button" class="qahwa-send-code-btn" id="qahwa-send-code-btn">Send Code</button>
              </div>
            </div>
            <div class="qahwa-form-group">
              <label for="qahwa-register-password">Password</label>
              <input type="password" id="qahwa-register-password" placeholder="Set a password (min 6 chars)" autocomplete="new-password" required>
            </div>
            <div id="qahwa-register-error" class="qahwa-error" style="display: none;"></div>
            <button type="submit" class="qahwa-btn-primary" id="qahwa-register-btn">Create Account</button>
            <div id="qahwa-register-loading" class="qahwa-loading" style="display: none;">Creating account...</div>
          </form>

          <!-- 游客模式（默认隐藏） -->
          <div id="qahwa-guest-pane" style="display: none;">
            <p style="color: #666; font-size: 14px; text-align: center; line-height: 1.6;">
              Continue as guest.<br>
              Some features may be limited.
            </p>
            <div id="qahwa-guest-error" class="qahwa-error" style="display: none;"></div>
            <button type="button" class="qahwa-btn-guest" id="qahwa-guest-btn">Continue as Guest</button>
            <div id="qahwa-guest-loading" class="qahwa-loading" style="display: none;">Connecting...</div>
          </div>
        </div>
      `;

      document.body.appendChild(modal);
      this._loginModal = modal;

      // 元素引用
      const closeBtn = modal.querySelector('#qahwa-close-btn');
      const tabEls = modal.querySelectorAll('.qahwa-tab');
      const loginForm = modal.querySelector('#qahwa-login-form');
      const registerForm = modal.querySelector('#qahwa-register-form');
      const guestPane = modal.querySelector('#qahwa-guest-pane');

      const closeModal = () => {
        this._closeLoginModal();
        if (callbacks.onClose) callbacks.onClose();
      };

      closeBtn.onclick = closeModal;
      modal.onclick = (e) => {
        if (e.target === modal) closeModal();
      };

      // ==================== Tab 切换 ====================
      const switchTab = (tab) => {
        activeTab = tab;
        tabEls.forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
        loginForm.style.display    = tab === 'login'    ? 'block' : 'none';
        registerForm.style.display = tab === 'register' ? 'block' : 'none';
        guestPane.style.display    = tab === 'guest'    ? 'block' : 'none';
      };

      tabEls.forEach(t => {
        t.onclick = () => switchTab(t.dataset.tab);
      });

      // ==================== Email 密码登录 ====================
      const loginError = loginForm.querySelector('#qahwa-error-msg');
      const loginLoading = loginForm.querySelector('#qahwa-loading');
      const loginSubmitBtn = loginForm.querySelector('#qahwa-submit-btn');

      loginForm.onsubmit = async (e) => {
        e.preventDefault();
        const email = loginForm.querySelector('#qahwa-email').value.trim();
        const password = loginForm.querySelector('#qahwa-password').value;

        if (!email || !password) {
          loginError.textContent = 'Please enter email and password';
          loginError.style.display = 'block';
          return;
        }

        loginForm.querySelector('#qahwa-email').style.display = 'none';
        loginForm.querySelector('#qahwa-password').parentElement.style.display = 'none';
        loginSubmitBtn.style.display = 'none';
        loginError.style.display = 'none';
        loginLoading.style.display = 'block';

        try {
          const user = await this._doEmailLogin(email, password);
          this._closeLoginModal();
          if (callbacks.onSuccess) callbacks.onSuccess(user);
        } catch (err) {
          loginForm.querySelector('#qahwa-email').style.display = 'block';
          loginForm.querySelector('#qahwa-password').parentElement.style.display = 'block';
          loginSubmitBtn.style.display = 'block';
          loginLoading.style.display = 'none';
          loginError.textContent = err.message || 'Login failed';
          loginError.style.display = 'block';
          if (callbacks.onError) callbacks.onError(err);
        }
      };

      // ==================== 注册（验证码 + 密码）====================
      const regError = registerForm.querySelector('#qahwa-register-error');
      const regLoading = registerForm.querySelector('#qahwa-register-loading');
      const regBtn = registerForm.querySelector('#qahwa-register-btn');
      const sendCodeBtn = registerForm.querySelector('#qahwa-send-code-btn');

      // 发送验证码（type=1 注册）
      let codeCountdown = 0;
      let codeTimer = null;

      sendCodeBtn.onclick = async () => {
        const email = registerForm.querySelector('#qahwa-register-email').value.trim();
        if (!email) {
          regError.textContent = 'Please enter your email first';
          regError.style.display = 'block';
          return;
        }
        if (codeCountdown > 0) return;

        sendCodeBtn.disabled = true;
        sendCodeBtn.textContent = 'Sending...';
        try {
          await this.sendEmailCode(email, 1);
          regError.style.display = 'none';
          codeCountdown = 60;
          sendCodeBtn.textContent = codeCountdown + 's';
          codeTimer = setInterval(() => {
            codeCountdown--;
            if (codeCountdown <= 0) {
              clearInterval(codeTimer);
              sendCodeBtn.textContent = 'Send Code';
              sendCodeBtn.disabled = false;
            } else {
              sendCodeBtn.textContent = codeCountdown + 's';
            }
          }, 1000);
        } catch (err) {
          sendCodeBtn.textContent = 'Send Code';
          sendCodeBtn.disabled = false;
          regError.textContent = err.message || 'Failed to send code';
          regError.style.display = 'block';
        }
      };

      registerForm.onsubmit = async (e) => {
        e.preventDefault();
        const email    = registerForm.querySelector('#qahwa-register-email').value.trim();
        const code     = registerForm.querySelector('#qahwa-register-code').value.trim();
        const password = registerForm.querySelector('#qahwa-register-password').value;

        if (!email || !code || !password) {
          regError.textContent = 'Please fill in all fields';
          regError.style.display = 'block';
          return;
        }
        if (password.length < 6) {
          regError.textContent = 'Password must be at least 6 characters';
          regError.style.display = 'block';
          return;
        }

        registerForm.querySelectorAll('input').forEach(i => i.disabled = true);
        sendCodeBtn.disabled = true;
        regBtn.style.display = 'none';
        regError.style.display = 'none';
        regLoading.style.display = 'block';

        try {
          // 1. 校验验证码
          await this.verifyEmailCode(email, code);
          // 2. 注册
          await this.registerWithEmail(email, password);
          // 3. 自动登录
          const user = await this._doEmailLogin(email, password);
          this._closeLoginModal();
          if (callbacks.onSuccess) callbacks.onSuccess(user);
        } catch (err) {
          registerForm.querySelectorAll('input').forEach(i => i.disabled = false);
          sendCodeBtn.disabled = false;
          regBtn.style.display = 'block';
          regLoading.style.display = 'none';
          regError.textContent = err.message || 'Registration failed';
          regError.style.display = 'block';
          if (callbacks.onError) callbacks.onError(err);
        }
      };

      // ==================== 游客登录 ====================
      const guestError = guestPane.querySelector('#qahwa-guest-error');
      const guestLoading = guestPane.querySelector('#qahwa-guest-loading');
      const guestBtn = guestPane.querySelector('#qahwa-guest-btn');

      guestBtn.onclick = async () => {
        guestBtn.style.display = 'none';
        guestError.style.display = 'none';
        guestLoading.style.display = 'block';

        try {
          const user = await this._doGuestLogin();
          this._closeLoginModal();
          if (callbacks.onSuccess) callbacks.onSuccess(user);
        } catch (err) {
          guestBtn.style.display = 'block';
          guestLoading.style.display = 'none';
          guestError.textContent = err.message || 'Guest login failed';
          guestError.style.display = 'block';
          if (callbacks.onError) callbacks.onError(err);
        }
      };
    },

    _closeLoginModal: function() {
      if (this._loginModal) {
        this._loginModal.remove();
        this._loginModal = null;
      }
    },

    // ============ 私有登录方法（对齐 ApiService.guestLogin / login）============

    /**
     * 游客登录
     * @private
     */
    _doGuestLogin: function() {
      var self = this;
      return this._request(ENDPOINTS.USER_AUTHORIZATION, {
        body: {
          passportType: PASSPORT_TYPE.GUEST,
          passportName: this._deviceId
        },
        noAuth: true
      }).then(function(res) {
        if (res.isSuccess) {
          return self._saveUserFromLogin(res.data, PASSPORT_TYPE.GUEST);
        }
        var err = new Error(res.error || 'Guest login failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 邮箱密码登录
     * @private
     */
    _doEmailLogin: function(email, password) {
      var self = this;
      if (!email || !password) {
        return Promise.reject(new Error('Email and password are required'));
      }
      return this._request(ENDPOINTS.USER_AUTHORIZATION, {
        body: {
          passportType: PASSPORT_TYPE.EMAIL,
          email: email.trim(),
          passportPassword: password
        },
        noAuth: true
      }).then(function(res) {
        if (res.isSuccess) {
          return self._saveUserFromLogin(res.data, PASSPORT_TYPE.EMAIL);
        }
        var err = new Error(res.error || 'Login failed');
        err.code = res.code;
        throw err;
      });
    },

    /**
     * 统一登录成功处理：保存 token + userInfo，触发 onLogin 回调
     * 对齐 QahwaGameSDK._handleLoginResponse
     * @private
     */
    _saveUserFromLogin: function(data, passportType) {
      var token = data && data.token;
      if (!token) {
        return Promise.reject(new Error('Login succeeded but token is missing'));
      }

      this._saveToken(token);

      var userInfo = this._parseUserInfo(Object.assign({}, data, { passportType: passportType }));
      this._saveUserInfo(userInfo);

      if (this._onLoginCallback) this._onLoginCallback(userInfo);

      return {
        success: true,
        token: token,
        userInfo: userInfo
      };
    },

    /**
     * 从 /api/user/userPersonalCenter 返回的数据解析用户信息
     * 对齐 QahwaGameSDK._parseUserInfo
     * @private
     */
    _parseUserInfo: function(data) {
      if (!data) return null;
      return {
        userId:      data.userId || data.id || '',
        email:       data.email || '',
        nickName:    data.nickName || data.nickname || '',
        userAvatar:  data.userAvatar || data.avatar || '',
        passportType: data.passportType,
        isVip:       data.isVip === 1 || data.isVip === true,
        vipEndTime:  data.vipEndTime || null
      };
    },

    /**
     * 持久化 userInfo
     * @private
     */
    _saveUserInfo: function(userInfo) {
      this._userInfo = userInfo;
      try {
        localStorage.setItem(STORAGE_KEYS.USER_INFO, JSON.stringify(userInfo));
      } catch (e) {
        console.warn('[QahwaJS] Failed to save userInfo:', e);
      }
    },

    /**
     * 持久化 token
     * @private
     */
    _saveToken: function(token) {
      this._token = token;
      try {
        localStorage.setItem(STORAGE_KEYS.TOKEN, token);
      } catch (e) {
        console.warn('[QahwaJS] Failed to save token:', e);
      }
    },

    /**
     * 从本地存储恢复登录态
     * @private
     */
    _loadUserFromStorage: function() {
      try {
        var savedUser = localStorage.getItem(STORAGE_KEYS.USER_INFO);
        var savedToken = localStorage.getItem(STORAGE_KEYS.TOKEN);
        if (savedUser) this._userInfo = JSON.parse(savedUser);
        if (savedToken) this._token = savedToken;
      } catch (e) {
        console.warn('[QahwaJS] Failed to load user from storage:', e);
      }
    },

    /**
     * 清空登录态（用户主动登出 / token 过期 / 注销账号）
     * @private
     */
    _clearUser: function() {
      this._userInfo = null;
      this._token = null;
      try {
        localStorage.removeItem(STORAGE_KEYS.USER_INFO);
        localStorage.removeItem(STORAGE_KEYS.TOKEN);
      } catch (e) {
        console.warn('[QahwaJS] Failed to clear storage:', e);
      }
    },

    _showRechargeModal: function(amount, callbacks) {
      this._closeLoginModal();

      const modal = document.createElement('div');
      modal.id = 'qahwa-login-modal';
      modal.innerHTML = `
        <div class="qahwa-modal-content" style="max-width: 360px;">
          <button class="qahwa-close-btn" id="qahwa-close-btn">&times;</button>
          <h2>Recharge</h2>
          <div style="text-align: center; margin-bottom: 20px;">
            <div style="font-size: 32px; font-weight: bold; color: #667eea;">$${amount}</div>
            <div style="color: #666; font-size: 14px;">${amount * 7} Coins</div>
          </div>
          <div class="qahwa-form-group">
            <label>Payment Method</label>
            <div style="display: flex; gap: 10px;">
              <label style="flex: 1; text-align: center; padding: 12px; border: 2px solid #667eea; border-radius: 10px; cursor: pointer; background: #f8f5ff;">
                <input type="radio" name="payment" value="stripe" checked style="margin-right: 6px;">Stripe
              </label>
              <label style="flex: 1; text-align: center; padding: 12px; border: 2px solid #e0e0e0; border-radius: 10px; cursor: pointer;">
                <input type="radio" name="payment" value="paypal" style="margin-right: 6px;">PayPal
              </label>
            </div>
          </div>
          <button class="qahwa-btn-primary" id="qahwa-pay-btn">Pay $${amount}</button>
          <div id="qahwa-error-msg" class="qahwa-error" style="display: none;"></div>
          <div id="qahwa-loading" class="qahwa-loading" style="display: none;">Processing...</div>
        </div>
      `;

      document.body.appendChild(modal);

      const closeBtn = modal.querySelector('#qahwa-close-btn');
      const payBtn = modal.querySelector('#qahwa-pay-btn');
      const errorMsg = modal.querySelector('#qahwa-error-msg');
      const loading = modal.querySelector('#qahwa-loading');

      const closeModal = () => {
        modal.remove();
        if (callbacks.onClose) callbacks.onClose();
      };

      closeBtn.onclick = closeModal;
      modal.onclick = (e) => {
        if (e.target === modal) closeModal();
      };

      // 支付方式选择
      modal.querySelectorAll('input[name="payment"]').forEach(radio => {
        radio.onchange = () => {
          modal.querySelectorAll('input[name="payment"]').forEach(r => {
            r.parentElement.style.borderColor = '#e0e0e0';
            r.parentElement.style.background = 'white';
          });
          radio.parentElement.style.borderColor = '#667eea';
          radio.parentElement.style.background = '#f8f5ff';
        };
      });

      payBtn.onclick = async () => {
        const paymentMethod = modal.querySelector('input[name="payment"]:checked').value;

        payBtn.style.display = 'none';
        loading.style.display = 'block';

        try {
          const order = await this._doRecharge(amount, paymentMethod);
          modal.remove();
          if (callbacks.onSuccess) callbacks.onSuccess(order);
        } catch (err) {
          payBtn.style.display = 'block';
          loading.style.display = 'none';
          errorMsg.textContent = err.message || 'Payment failed';
          errorMsg.style.display = 'block';
          if (callbacks.onError) callbacks.onError(err);
        }
      };
    },

    _doRecharge: async function(amount, paymentMethod) {
      const response = await fetch(this._apiBaseUrl + 'api/pay/create', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + (this._userInfo?.token || '')
        },
        body: JSON.stringify({
          amount: amount,
          currency: 'USD',
          payType: paymentMethod === 'stripe' ? 1 : 2
        })
      });

      const result = await response.json();

      if (result.code !== 0) {
        throw new Error(result.msg || 'Recharge failed');
      }

      return {
        orderId: result.data.orderId,
        amount: result.data.amount,
        status: result.data.status
      };
    },

    _showUserMenu: function() {
      this._closeLoginModal();

      const modal = document.createElement('div');
      modal.id = 'qahwa-login-modal';
      modal.innerHTML = `
        <style>
          #qahwa-menu-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            z-index: 999999;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          }
          #qahwa-menu-container {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: white;
            border-radius: 24px 24px 0 0;
            padding: 20px;
            max-width: 500px;
            margin: 0 auto;
            animation: slideUp 0.3s ease;
          }
          @keyframes slideUp {
            from { transform: translateY(100%); }
            to { transform: translateY(0); }
          }
          #qahwa-menu-container .qahwa-menu-header {
            display: flex;
            align-items: center;
            padding: 16px;
            border-radius: 16px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            margin-bottom: 20px;
          }
          #qahwa-menu-container .qahwa-menu-avatar {
            width: 60px;
            height: 60px;
            border-radius: 50%;
            background: rgba(255,255,255,0.3);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 28px;
            margin-right: 16px;
          }
          #qahwa-menu-container .qahwa-menu-user-info h3 {
            margin: 0;
            font-size: 18px;
          }
          #qahwa-menu-container .qahwa-menu-user-info p {
            margin: 4px 0 0;
            font-size: 14px;
            opacity: 0.8;
          }
          #qahwa-menu-container .qahwa-menu-item {
            display: flex;
            align-items: center;
            padding: 16px;
            border-radius: 12px;
            cursor: pointer;
            transition: background 0.2s;
          }
          #qahwa-menu-container .qahwa-menu-item:hover {
            background: #f5f5f5;
          }
          #qahwa-menu-container .qahwa-menu-item-icon {
            width: 40px;
            height: 40px;
            border-radius: 10px;
            background: #f0f0f0;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
            margin-right: 16px;
          }
          #qahwa-menu-container .qahwa-menu-item-text {
            flex: 1;
          }
          #qahwa-menu-container .qahwa-menu-item-text h4 {
            margin: 0;
            font-size: 16px;
            color: #333;
          }
          #qahwa-menu-container .qahwa-menu-item-text p {
            margin: 4px 0 0;
            font-size: 12px;
            color: #999;
          }
          #qahwa-menu-container .qahwa-menu-item-arrow {
            color: #ccc;
          }
          #qahwa-menu-container .qahwa-menu-divider {
            height: 1px;
            background: #f0f0f0;
            margin: 8px 0;
          }
          #qahwa-menu-container .qahwa-menu-item.logout {
            color: #dc3545;
          }
          #qahwa-menu-container .qahwa-menu-item.logout .qahwa-menu-item-icon {
            background: #ffe6e6;
          }
          #qahwa-menu-container .qahwa-menu-item.logout h4 {
            color: #dc3545;
          }
          #qahwa-menu-container .qahwa-menu-close {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            background: #f5f5f5;
            border: none;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
            cursor: pointer;
            margin: 0 auto 16px;
          }
          #qahwa-menu-container .qahwa-menu-close:hover {
            background: #e0e0e0;
          }
        </style>
        <div id="qahwa-menu-overlay">
          <div id="qahwa-menu-container">
            <button class="qahwa-menu-close" id="qahwa-menu-close">✕</button>
            <div class="qahwa-menu-header">
              <div class="qahwa-menu-avatar">👤</div>
              <div class="qahwa-menu-user-info">
                <h3>${this._userInfo?.nickName || 'User'}</h3>
                <p>${this._userInfo?.email || ''}</p>
              </div>
            </div>
            <div class="qahwa-menu-item" id="qahwa-user-center">
              <div class="qahwa-menu-item-icon">👤</div>
              <div class="qahwa-menu-item-text">
                <h4>User Center</h4>
                <p>View profile and settings</p>
              </div>
              <span class="qahwa-menu-item-arrow">›</span>
            </div>
            <div class="qahwa-menu-divider"></div>
            <div class="qahwa-menu-item logout" id="qahwa-logout-btn">
              <div class="qahwa-menu-item-icon">🚪</div>
              <div class="qahwa-menu-item-text">
                <h4>Logout</h4>
                <p>Sign out of your account</p>
              </div>
              <span class="qahwa-menu-item-arrow">›</span>
            </div>
          </div>
        </div>
      `;

      document.body.appendChild(modal);

      const closeBtn = modal.querySelector('#qahwa-menu-close');
      const overlay = modal.querySelector('#qahwa-menu-overlay');
      const userCenter = modal.querySelector('#qahwa-user-center');
      const logoutBtn = modal.querySelector('#qahwa-logout-btn');

      const closeModal = () => modal.remove();

      closeBtn.onclick = closeModal;
      overlay.onclick = (e) => {
        if (e.target === overlay) closeModal();
      };

      userCenter.onclick = () => {
        alert('User Center: ' + JSON.stringify(this._userInfo, null, 2));
      };

      logoutBtn.onclick = () => {
        this.logout();
        closeModal();
      };
    }
  };

  // 导出到全局
  global.QahwaJS = QahwaJS;

})(typeof window !== 'undefined' ? window : this);
