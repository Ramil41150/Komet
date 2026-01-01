class Contact {
  final int id;
  final String name;
  final String firstName;
  final String lastName;
  final String? description;
  final String? photoBaseUrl;
  final bool isBlocked;
  final bool isBlockedByMe;
  final int accountStatus;
  final String? status;
  final List<String> options;

  Contact({
    required this.id,
    required this.name,
    required this.firstName,
    required this.lastName,
    this.description,
    this.photoBaseUrl,
    this.isBlocked = false,
    this.isBlockedByMe = false,
    this.accountStatus = 0,
    this.status,
    this.options = const [],
  });

  bool get isBot => options.contains('BOT');

  bool get isUserBlocked => isBlockedByMe || isBlocked;

  factory Contact.fromJson(Map<String, dynamic> json) {
    final nameData = json['names']?[0];
    final userId = json['id'] as int;

    String finalFirstName = '';
    String finalLastName = '';
    String finalName = 'ID $userId';

    if (nameData != null) {
      finalFirstName = nameData['firstName'] ?? '';
      finalLastName = nameData['lastName'] ?? '';
      final fullName = '$finalFirstName $finalLastName'.trim();
      finalName = fullName.isNotEmpty
          ? fullName
          : (nameData['name'] ?? 'ID $userId');
    }

    final status = json['status'];
    final isBlocked = status == 'BLOCKED';

    final isBlockedByMe = status == 'BLOCKED';

    return Contact(
      id: json['id'],
      name: finalName,
      firstName: finalFirstName,
      lastName: finalLastName,
      description: json['description'],
      photoBaseUrl: json['baseUrl'],
      isBlocked: isBlocked,
      isBlockedByMe: isBlockedByMe,
      accountStatus: json['accountStatus'] ?? 0,
      status: json['status'],
      options: List<String>.from(json['options'] ?? []),
    );
  }
}
