import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/poc_navigation_controller.dart';
import '../../../utils/geo_utils.dart';

class MiniMapWidget extends StatelessWidget {
  final PocNavigationController controller;
  final String mapAssetPath;

  const MiniMapWidget({
    super.key,
    required this.controller,
    required this.mapAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 400,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mapSize = Size(constraints.maxWidth, constraints.maxHeight);

              return Obx(() {
                // Use locked bounds if available, otherwise calculate once
                // Destination stays fixed, only user position moves within bounds
                final route = controller.routePoints;
                debugPrint(
                  '🗺️ [MiniMapWidget] Rendering: routePoints count=${route.length}',
                );

                final bounds =
                    controller.mapBounds.value ??
                    controller.calculateMapBounds(
                      userPosition: controller.mapDisplayPosition.value,
                    );

                debugPrint(
                  '🗺️ [MiniMapWidget] MapBounds: minLat=${bounds.minLat.toStringAsFixed(6)}, maxLat=${bounds.maxLat.toStringAsFixed(6)}, minLng=${bounds.minLng.toStringAsFixed(6)}, maxLng=${bounds.maxLng.toStringAsFixed(6)}',
                );

                final destination = LatLng(
                  controller.target.latitude,
                  controller.target.longitude,
                );
                final destinationOffset = controller.latLngToPixel(
                  destination,
                  bounds,
                  mapSize,
                );
                debugPrint(
                  '🗺️ [MiniMapWidget] Destination pixel: dx=${destinationOffset.dx.toStringAsFixed(1)}, dy=${destinationOffset.dy.toStringAsFixed(1)}',
                );

                // Use fast-update path for near real-time map display.
                // Prefer snapped position on the route, fall back to fast-update position.
                final userPosition =
                    controller.snappedUserPositionFast ??
                    controller.mapDisplayPositionFast.value;
                final Offset? userOffset = userPosition != null
                    ? controller.latLngToPixel(userPosition, bounds, mapSize)
                    : null;
                if (userOffset != null) {
                  debugPrint(
                    '🗺️ [MiniMapWidget] User pixel: dx=${userOffset.dx.toStringAsFixed(1)}, dy=${userOffset.dy.toStringAsFixed(1)}',
                  );
                } else {
                  debugPrint('🗺️ [MiniMapWidget] User position is null');
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(mapAssetPath, fit: BoxFit.cover),
                    ),
                    // Draw the full route polyline and waypoint markers.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RoutePainter(
                          controller: controller,
                          bounds: bounds,
                          mapSize: mapSize,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.05),
                              Colors.black.withOpacity(0.35),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    _buildDestinationMarker(destinationOffset),
                    if (userOffset != null) _buildUserMarker(userOffset),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationMarker(Offset offset) {
    return Positioned(
      left: offset.dx - 12,
      top: offset.dy - 24,
      child: Icon(
        Icons.location_on,
        size: 32,
        color: Colors.redAccent.shade200,
      ),
    );
  }

  Widget _buildUserMarker(Offset offset) {
    return Positioned(
      left: offset.dx - 10,
      top: offset.dy - 10,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.blueAccent.shade200,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.shade100.withOpacity(0.6),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter for drawing the route polyline and waypoint markers.
class _RoutePainter extends CustomPainter {
  final PocNavigationController controller;
  final MapBounds bounds;
  final Size mapSize;

  _RoutePainter({
    required this.controller,
    required this.bounds,
    required this.mapSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final route = controller.routePoints;
    debugPrint(
      '🗺️ [_RoutePainter] paint() called: route.length=${route.length}, mapSize=${mapSize.width.toStringAsFixed(1)}x${mapSize.height.toStringAsFixed(1)}',
    );

    if (route.isEmpty) {
      debugPrint('🗺️ [_RoutePainter] Route has 0 points, skipping draw');
      return;
    }

    // Convert route points to pixel coordinates (used only for markers now).
    final points = route
        .map((p) => controller.latLngToPixel(p, bounds, mapSize))
        .toList();

    debugPrint(
      '🗺️ [_RoutePainter] Converted ${points.length} route points to pixels (markers only):',
    );
    for (var i = 0; i < points.length; i++) {
      debugPrint(
        '🗺️ [_RoutePainter] Point[$i]: pixel=(${points[i].dx.toStringAsFixed(1)}, ${points[i].dy.toStringAsFixed(1)}), lat=${route[i].lat.toStringAsFixed(6)}, lng=${route[i].lng.toStringAsFixed(6)}',
      );
    }

    // Draw markers only for waypoints (exclude destination - it has the location pin icon).
    // The last point in routePoints is the destination, so we skip it.
    for (var i = 0; i < points.length - 1; i++) {
      final p = points[i];
      final color = Colors.redAccent.shade200;
      const double radius = 7;

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(p, radius, fillPaint);
      canvas.drawCircle(p, radius, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.bounds != bounds ||
        oldDelegate.mapSize != mapSize;
  }
}

// Note: Mini-map currently shows only user & destination markers without
// a connecting line. If you want a path/line in future, add a CustomPainter
// similar to the previous implementation.
