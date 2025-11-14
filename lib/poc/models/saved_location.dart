import 'dart:convert';

class SavedLocation {
  final String name;
  final double latitude;
  final double longitude;

  const SavedLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    return SavedLocation(
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  static String encodeList(List<SavedLocation> locations) {
    final list = locations.map((l) => l.toJson()).toList();
    return jsonEncode(list);
  }

  static List<SavedLocation> decodeList(String jsonString) {
    final raw = jsonDecode(jsonString) as List<dynamic>;
    return raw
        .map((item) => SavedLocation.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}


