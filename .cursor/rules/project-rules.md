# 阿拉伯短剧 App 项目规范

## 项目基本信息
- 项目名称: Arab Drama App
- 目标市场: 阿拉伯地区（沙特、阿联酋、埃及等）
- 支持语言: 阿拉伯语（ar）、英语（en）
- 支持平台: iOS、Android

## 技术栈
- Flutter 3.x (最新稳定版)
- 状态管理: Riverpod
- 路由: go_router
- 网络请求: dio + retrofit
- 播放器: 阿里云播放器 SDK (flutter_aliplayer)
- 支付: google_play_billing + in_app_purchase
- 登录: google_sign_in + sign_in_with_apple + firebase_auth

## 目录结构规范
lib/
├── main.dart                 # 应用入口
├── app/                      # 应用级配置
│   ├── providers/            # 全局 Provider
│   ├── router/               # 路由配置
│   └── theme/                # 主题配置
├── core/                     # 核心模块
│   ├── constants/            # 常量
│   ├── utils/                # 工具类
│   ├── network/              # 网络层
│   └── storage/              # 本地存储
├── features/                 # 功能模块
│   ├── auth/                 # 登录模块
│   ├── home/                 # 首页
│   ├── recommend/            # 推荐页
│   ├── explore/              # 探索页
│   ├── profile/              # 个人中心
│   ├── games/                # 游戏页
│   ├── player/               # 播放器
│   └── payment/              # 支付会员
├── l10n/                     # 多语言文件
└── assets/                   # 资源文件
    ├── images/
    ├── fonts/
    └── animations/

## 命名规范
- 文件: snake_case (如: login_page.dart)
- 类: PascalCase (如: LoginPage)
- 变量/函数: camelCase (如: isLoggedIn)
- 常量: UPPER_SNAKE_CASE (如: API_BASE_URL)

## RTL 支持要点
- 所有布局必须兼容 RTL
- 图标需要考虑翻转（使用 Transform.scale 或 icon 库的 matchTextDirection）
- 使用 Row 时注意 mainAxisAlignment 的 RTL 行为

## 阿里云播放器集成
- 使用 flutter_aliplayer 包
- 需要配置 License Key
- Android 需要网络权限和屏幕方向配置
- iOS 需要配置后台播放权限

## 支付集成注意
- 先调通沙箱环境
- 订阅型商品需要服务端验证
- iOS 需要配置 App Store Connect 产品

## 代码生成要求
1. 每次生成代码前，先确认需要的文件是否已存在
2. 新增功能时，按 feature 模块划分，代码放在 features/ 对应目录
3. 路由自动注册到 router_config.dart
4. 多语言文本自动添加到 l10n/ 文件
5. 遇到报错时，我会提供错误日志，你分析后给出修复代码


alwaysApply: true