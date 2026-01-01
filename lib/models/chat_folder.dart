class ChatFolder {
  final String id;
  final String title;
  final String? emoji;
  final List<int>? include;
  final List<dynamic> filters;
  final bool hideEmpty;
  final List<ChatFolderWidget> widgets;
  final List<String>? favorites;
  final Map<String, dynamic>? filterSubjects;
  final List<int>? options;

  ChatFolder({
    required this.id,
    required this.title,
    this.emoji,
    this.include,
    required this.filters,
    required this.hideEmpty,
    required this.widgets,
    this.favorites,
    this.filterSubjects,
    this.options,
  });

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: json['id'],
      title: json['title'],
      emoji: json['emoji'],
      include: json['include'] != null ? List<int>.from(json['include']) : null,
      filters: json['filters'] != null
          ? List<dynamic>.from(json['filters'])
          : [],
      hideEmpty: json['hideEmpty'] ?? false,
      widgets:
          (json['widgets'] as List<dynamic>?)
              ?.map((widget) => ChatFolderWidget.fromJson(widget))
              .toList() ??
          [],
      favorites: json['favorites'] != null
          ? List<String>.from(json['favorites'])
          : null,
      filterSubjects: json['filterSubjects'],
      options: json['options'] != null ? List<int>.from(json['options']) : null,
    );
  }
}

class ChatFolderWidget {
  final int id;
  final String name;
  final String description;
  final String? iconUrl;
  final String? url;
  final String? startParam;
  final String? background;
  final int? appId;

  ChatFolderWidget({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.url,
    this.startParam,
    this.background,
    this.appId,
  });

  factory ChatFolderWidget.fromJson(Map<String, dynamic> json) {
    return ChatFolderWidget(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      iconUrl: json['iconUrl'],
      url: json['url'],
      startParam: json['startParam'],
      background: json['background'],
      appId: json['appId'],
    );
  }
}
