import 'dart:ui';

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
                // Get or calculate map bounds only once – controller locks them
                // after the initial samples so the destination stays fixed
                // and the user moves within those bounds.
                final bounds =
                    controller.mapBounds.value ??
                    controller.calculateMapBounds(
                      userPosition: controller.mapDisplayPosition.value,
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

                // Always use the smoothed mapDisplayPosition for the user.
                final userPosition = controller.mapDisplayPosition.value;
                final Offset? userOffset = userPosition != null
                    ? controller.latLngToPixel(userPosition, bounds, mapSize)
                    : null;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(mapAssetPath, fit: BoxFit.cover),
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

// Note: Mini-map currently shows only user & destination markers without
// a connecting line. If you want a path/line in future, add a CustomPainter
// similar to the previous implementation.
