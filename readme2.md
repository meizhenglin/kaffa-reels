lib/features 功能模块一览
1. auth — 认证 / 用户注册登录
登录、邮箱登录、注册、忘记密码、用户协议、隐私政策

pages:  login_page, login_email_page, register_page, register_email_page,
        forgot_password_page, user_agreement_page, privacy_policy_page
models: user_model
repositories: auth_repository
providers: auth_provider
widgets: auth_text_field, social_sign_in_button
2. home — 首页框架
底部导航栏、主页面框架、首页 Tab、剧集列表页

pages:  main_page, home_tab, drama_list_page
widgets: bottom_nav_bar, placeholder_tab_page, rtl_aware_icon
providers: tab_scroll_provider
models: navigation_item
mixins: tab_scroll_mixin
3. recommend — 推荐 / 短剧列表（最核心的功能模块）
首页推荐 feed、短视频、轮播 banner、剧集卡片、选集弹层

pages:  recommend_tab, recommendPage, drama_info, ali_player_preload, short_video_util,
        demo_constants, sp_manager
widgets: recommend_waterfall_grid, mini_player_widget, short_video_item,
         hot_drama_section, banner_carousel, drama_card, episode_selection_sheet,
         mini_player_controller
models: banner, drama, drama_badge, drama_list_type, video_info, recommend_feed
providers: recommend_provider, csv_data_provider
data: recommend_repository, csv_data_service
utils: drama_navigation
4. detail — 剧集详情页
pages: detail_page
5. player — 视频播放器
AliPlayer 播放器控制、播放状态管理、选集浮层、测试页

presentation: player_page, player_widget, episode_sheet, test_player_page,
              player_controller
domain: player_state
6. explore — 发现 / 搜索
探索 Tab、搜索页、分类筛选

pages: explore_tab, explore_page
providers: explore_provider, search_provider
models: category, search_suggestion
widgets: explore_drama_grid_card, explore_search_bar, search_suggestions_panel,
         category_chips_bar
data: search_history_storage
7. search — 搜索（独立页面）
pages: search_page
providers: search_page_provider
8. games — 活动 / 小游戏
游戏 Tab、每日签到、连连看、对对碰

pages: games_tab, games_page, daily_signin, guess_line_game, matching_game
providers: games_provider
widgets: game_entry_card
9. payment — 会员 / 支付
会员中心、VIP 付费墙、订阅扣款验证

pages: membership_page
widgets: vip_paywall_overlay
providers: membership_provider
services: payment_service, receipt_verification
models: subscription_product
docs: subscription_config_guide
10. profile — 个人中心 / 设置
个人资料页、历史记录、收藏、消息设置、关于页面、充值协议

pages: profile_tab, profile_page, history_page, watch_history_page,
        favorites_page, settings_page, about_page, chat_page,
        change_name_page, message_settings_page, recharge_agreement_page
providers: history_provider
profile.dart (主入口)
11. splash — 启动页
pages: splash_page
12. commonAliPlayer — 公共播放器组件（跨模块复用）
短视频播放页、滑动窗口播放器、播放器预加载

short_video_page, ali_sliding_window, short_video_item, ali_player_preload
整体是一个典型的 短剧类 App 架构：推荐 feed → 详情 → 播放器，辅以搜索、游戏、会员、个人中心。commonAliPlayer 是播放器核心组件，被 recommend 和 detail 等模块共用