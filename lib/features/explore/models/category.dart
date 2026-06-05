import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.nameAr,
  });

  final String id;
  final String name;
  final String nameEn;
  final String nameAr;

  String localizedName(Locale locale) {
    if (locale.languageCode == 'ar') {
      return nameAr.isNotEmpty ? nameAr : nameEn;
    }
    return nameEn.isNotEmpty ? nameEn : name;
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    final rawI18n = json['videoLabelNameI18n'] ?? json['nameI18n'];
    Map<String, dynamic> i18n = const {};
    if (rawI18n is String && rawI18n.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawI18n);
        if (decoded is Map<String, dynamic>) {
          i18n = decoded;
        }
      } catch (_) {}
    } else if (rawI18n is Map<String, dynamic>) {
      i18n = rawI18n;
    }

    final id = (json['videoLabelId'] ?? json['id'] ?? '').toString();
    final fallbackName = (json['videoLabelName'] ?? json['name'] ?? '').toString();
    final isAllCategory = id == '-1';

    return Category(
      id: id,
      name: isAllCategory ? 'All' : fallbackName,
      nameEn: (i18n['en-US'] ?? i18n['en'] ?? (isAllCategory ? 'All' : fallbackName))
          .toString(),
      nameAr: (i18n['ar-SA'] ?? i18n['ar'] ?? (isAllCategory ? 'الكل' : fallbackName))
          .toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameEn': nameEn,
        'nameAr': nameAr,
      };

  @override
  List<Object?> get props => [id, name, nameEn, nameAr];
}
