class Channel {
  final int id;
  final String name;
  final String? description;
  final String? photoBaseUrl;
  final String? link;
  final String? webApp;
  final List<String> options;
  final int updateTime;

  Channel({
    required this.id,
    required this.name,
    this.description,
    this.photoBaseUrl,
    this.link,
    this.webApp,
    required this.options,
    required this.updateTime,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    final names = json['names'] as List<dynamic>?;
    final nameData = names?.isNotEmpty == true ? names![0] : null;
    final channelId = json['id'] as int;

    return Channel(
      id: channelId,
      name: nameData?['name'] as String? ?? 'ID $channelId',
      description: nameData?['description'] as String?,
      photoBaseUrl: json['baseUrl'] as String?,
      link: json['link'] as String?,
      webApp: json['webApp'] as String?,
      options: List<String>.from(json['options'] ?? []),
      updateTime: json['updateTime'] as int? ?? 0,
    );
  }
}
