class ComplaintType {
  final int typeId;
  final List<ComplaintReason> reasons;

  ComplaintType({required this.typeId, required this.reasons});

  factory ComplaintType.fromJson(Map<String, dynamic> json) {
    return ComplaintType(
      typeId: json['typeId'],
      reasons: (json['reasons'] as List)
          .map((reason) => ComplaintReason.fromJson(reason))
          .toList(),
    );
  }
}

class ComplaintReason {
  final String reasonTitle;
  final int reasonId;

  ComplaintReason({required this.reasonTitle, required this.reasonId});

  factory ComplaintReason.fromJson(Map<String, dynamic> json) {
    return ComplaintReason(
      reasonTitle: json['reasonTitle'],
      reasonId: json['reasonId'],
    );
  }
}

class ComplaintData {
  final List<ComplaintType> complainTypes;
  final int complainSync;

  ComplaintData({required this.complainTypes, required this.complainSync});

  factory ComplaintData.fromJson(Map<String, dynamic> json) {
    return ComplaintData(
      complainTypes: (json['complains'] as List)
          .map((type) => ComplaintType.fromJson(type))
          .toList(),
      complainSync: json['complainSync'],
    );
  }
}
