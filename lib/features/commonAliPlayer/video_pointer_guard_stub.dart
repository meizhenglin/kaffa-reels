/// 非 web 平台：视频渲染成 Texture / PlatformView，不参与 DOM 命中测试，
/// Flutter 的手势系统本来就收得到点击，这里什么都不用做。
void allowVideoTapThrough() {}
