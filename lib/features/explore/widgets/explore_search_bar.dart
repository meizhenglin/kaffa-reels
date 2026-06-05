import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/models/home_card_layout.dart';

class ExploreSearchBar extends StatelessWidget {
  const ExploreSearchBar({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: HomeCardLayout.scaled(context, 34),
            child: GestureDetector(
              onTap: onTap,
              child: AbsorbPointer(
                child: TextField(
                  readOnly: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    prefixIcon: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: HomeCardLayout.scaled(context, 14),
                        end: HomeCardLayout.scaled(context, 6),
                      ),
                      child: Image(
                        image: const AssetImage('assets/images/searchPage_icon.png'),
                        width: HomeCardLayout.scaled(context, 14),
                        height: HomeCardLayout.scaled(context, 14),
                      ),
                    ),
                    prefixIconConstraints: BoxConstraints(
                      minWidth: HomeCardLayout.scaled(context, 34),
                      minHeight: HomeCardLayout.scaled(context, 34),
                    ),
                    filled: true,
                    fillColor: const Color(0x1AFFFFFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HomeCardLayout.scaled(context, 50)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HomeCardLayout.scaled(context, 50)),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HomeCardLayout.scaled(context, 50)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: HomeCardLayout.scaled(context, 16),
                    ),
                    hintStyle: TextStyle(
                      color: const Color(0x80FFFFFF),
                      fontSize: HomeCardLayout.scaled(context, 14),
                    ),
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: HomeCardLayout.scaled(context, 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
