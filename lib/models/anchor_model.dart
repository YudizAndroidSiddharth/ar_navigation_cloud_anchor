import 'dart:math' as math;

class CloudAnchorPoint {
  final String id;
  final String? cloudAnchorId; // null until uploaded to cloud
  final String name;
  final String description;
  final AnchorPosition position;
  final AnchorType type;
  final DateTime createdAt;
  final double quality;
  final AnchorStatus status;

  CloudAnchorPoint({
    required this.id,
    this.cloudAnchorId,
    required this.name,
    required this.description,
    required this.position,
    required this.type,
    DateTime? createdAt,
    this.quality = 0.0,
    this.status = AnchorStatus.draft,
  }) : createdAt = createdAt ?? DateTime.now();

  // For now, we'll use Map<String, dynamic> instead of JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cloudAnchorId': cloudAnchorId,
      'name': name,
      'description': description,
      'position': position.toMap(),
      'type': type.toString(),
      'createdAt': createdAt.toIso8601String(),
      'quality': quality,
      'status': status.toString(),
    };
  }

  factory CloudAnchorPoint.fromMap(Map<String, dynamic> map) {
    return CloudAnchorPoint(
      id: map['id'],
      cloudAnchorId: map['cloudAnchorId'],
      name: map['name'],
      description: map['description'],
      position: AnchorPosition.fromMap(map['position']),
      type: AnchorType.values.firstWhere(
        (e) => e.toString() == map['type'],
        orElse: () => AnchorType.waypoint,
      ),
      createdAt: DateTime.parse(map['createdAt']),
      quality: map['quality'] ?? 0.0,
      status: AnchorStatus.values.firstWhere(
        (e) => e.toString() == map['status'],
        orElse: () => AnchorStatus.draft,
      ),
    );
  }
}

class AnchorPosition {
  final double x;
  final double y;
  final double z;
  final int floor;
  final double orientation;

  AnchorPosition({
    required this.x,
    required this.y,
    this.z = 0.0,
    this.floor = 0,
    this.orientation = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {'x': x, 'y': y, 'z': z, 'floor': floor, 'orientation': orientation};
  }

  factory AnchorPosition.fromMap(Map<String, dynamic> map) {
    return AnchorPosition(
      x: map['x']?.toDouble() ?? 0.0,
      y: map['y']?.toDouble() ?? 0.0,
      z: map['z']?.toDouble() ?? 0.0,
      floor: map['floor'] ?? 0,
      orientation: map['orientation']?.toDouble() ?? 0.0,
    );
  }

  double distanceTo(AnchorPosition other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

enum AnchorType {
  entrance, // Main entrances - Orange
  intersection, // Corridor junctions - Blue
  destination, // Near POIs - Green
  waypoint, // Path guidance - Purple
  emergency, // Emergency exits - Red
}

enum AnchorStatus {
  draft, // Created but not uploaded
  uploading, // Currently being uploaded
  active, // Successfully uploaded and active
  failed, // Upload failed
  inactive, // Temporarily disabled
}

class Destination {
  final String id;
  final String name;
  final String description;
  final String category;
  final AnchorPosition position;
  final String? imageUrl;
  final bool isActive;

  Destination({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.position,
    this.imageUrl,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'position': position.toMap(),
      'imageUrl': imageUrl,
      'isActive': isActive,
    };
  }

  factory Destination.fromMap(Map<String, dynamic> map) {
    return Destination(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      category: map['category'],
      position: AnchorPosition.fromMap(map['position']),
      imageUrl: map['imageUrl'],
      isActive: map['isActive'] ?? true,
    );
  }
}

class Venue {
  final String id;
  final String name;
  final String description;
  final List<CloudAnchorPoint> anchors;
  final List<Destination> destinations;
  final AnchorPosition origin;
  final DateTime createdAt;
  final DateTime updatedAt;

  Venue({
    required this.id,
    required this.name,
    required this.description,
    this.anchors = const [],
    this.destinations = const [],
    AnchorPosition? origin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : origin = origin ?? AnchorPosition(x: 0, y: 0),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'anchors': anchors.map((a) => a.toMap()).toList(),
      'destinations': destinations.map((d) => d.toMap()).toList(),
      'origin': origin.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Venue.fromMap(Map<String, dynamic> map) {
    return Venue(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      anchors:
          (map['anchors'] as List?)
              ?.map((a) => CloudAnchorPoint.fromMap(a))
              .toList() ??
          [],
      destinations:
          (map['destinations'] as List?)
              ?.map((d) => Destination.fromMap(d))
              .toList() ??
          [],
      origin: map['origin'] != null
          ? AnchorPosition.fromMap(map['origin'])
          : AnchorPosition(x: 0, y: 0),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}

extension VenueCopyWith on Venue {
  Venue copyWith({
    String? id,
    String? name,
    String? description,
    List<CloudAnchorPoint>? anchors,
    List<Destination>? destinations,
    AnchorPosition? origin,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Venue(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      anchors: anchors ?? this.anchors,
      destinations: destinations ?? this.destinations,
      origin: origin ?? this.origin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
