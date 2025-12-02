import 'dart:convert';

/// Route point type for Feeding Zone navigation.
/// Stored as a lowercase string in JSON for backward compatible persistence.
enum RoutePointType {
  waypoint,
  destination;

  String get jsonValue {
    switch (this) {
      case RoutePointType.waypoint:
        return 'waypoint';
      case RoutePointType.destination:
        return 'destination';
    }
  }

  static RoutePointType fromJsonValue(String value) {
    switch (value) {
      case 'destination':
        return RoutePointType.destination;
      case 'waypoint':
      default:
        return RoutePointType.waypoint;
    }
  }
}

/// A single point on the route for a Feeding Zone.
///
/// - [type]       : waypoint or destination
/// - [order]      : 1,2,3,... for waypoints; destination is usually last
/// - [latitude]   : point latitude
/// - [longitude]  : point longitude
class RoutePoint {
  final RoutePointType type;
  final int order;
  final double latitude;
  final double longitude;

  const RoutePoint({
    required this.type,
    required this.order,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'type': type.jsonValue,
        'order': order,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      type: RoutePointType.fromJsonValue(
        (json['type'] as String?) ?? 'waypoint',
      ),
      order: (json['order'] as num?)?.toInt() ?? 1,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

/// Saved Feeding Zone location.
///
/// Historically this only stored a single [latitude]/[longitude]. We now
/// optionally attach an ordered list of [routePoints] that describes the
/// full navigation route (waypoints + destination) for this zone.
///
/// Backward compatibility:
/// - old JSON without `routePoints` still decodes correctly (empty list)
/// - existing latitude/longitude remain the main destination fallback
class SavedLocation {
  final String name;
  final double latitude;
  final double longitude;

  /// Optional full route for this zone.
  /// May be empty, may contain only a destination, or waypoints + destination.
  final List<RoutePoint> routePoints;

  const SavedLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.routePoints = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      // Only persist routePoints key when we actually have data.
      if (routePoints.isNotEmpty)
        'routePoints': routePoints.map((p) => p.toJson()).toList(),
    };
  }

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    final rawRoutePoints = json['routePoints'];
    List<RoutePoint> routePoints = const [];
    if (rawRoutePoints is List) {
      routePoints = rawRoutePoints
          .whereType<Map<String, dynamic>>()
          .map(RoutePoint.fromJson)
          .toList();
    }

    return SavedLocation(
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      routePoints: routePoints,
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


