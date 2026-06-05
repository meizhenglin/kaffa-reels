import 'package:flutter/widgets.dart';

bool isArabicLocale(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

String localizedHomeVipBadgeAsset(BuildContext context) =>
    isArabicLocale(context)
        ? 'assets/images/a_home_vip_icon.png'
        : 'assets/images/home_vip_icon.png';

String localizedTopRankBadgeAsset(BuildContext context, int rank) =>
    isArabicLocale(context)
        ? 'assets/images/a_top_${rank}_icon.png'
        : 'assets/images/top_${rank}_icon.png';
