import 'package:equatable/equatable.dart';

enum SearchSuggestionType {
  recent,
  hot,
}

class SearchSuggestion extends Equatable {
  const SearchSuggestion({
    required this.keyword,
    required this.type,
  });

  final String keyword;
  final SearchSuggestionType type;

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) {
    return SearchSuggestion(
      keyword: json['keyword'] as String,
      type: SearchSuggestionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SearchSuggestionType.hot,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'type': type.name,
      };

  @override
  List<Object?> get props => [keyword, type];
}
