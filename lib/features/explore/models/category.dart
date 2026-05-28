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
    return locale.languageCode == 'ar' ? nameAr : nameEn;
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      nameEn: json['nameEn'] as String,
      nameAr: json['nameAr'] as String,
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
