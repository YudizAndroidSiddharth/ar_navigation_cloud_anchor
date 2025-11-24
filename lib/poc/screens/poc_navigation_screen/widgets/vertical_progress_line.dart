import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/ble_waypoint.dart';

class VerticalProgressLine extends StatelessWidget {
  final controller;

  const VerticalProgressLine({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Obx(() {
          // Access observable variables directly to ensure Obx tracks them
          final reachedHistory = controller.reachedWaypointHistory;
          final signalStrength = controller.signalStrength;

          // Get waypoints list
          final sortedWaypoints = controller.orderedWaypoints;

          // Longer line for better spacing
          final lineHeight = constraints.maxHeight * 0.8; // Increased from 0.75
          final lineTop = (constraints.maxHeight - lineHeight) / 2;
          final lineLeftX = constraints.maxWidth * 0.15;

          // Calculate waypoint positions
          final segmentHeight = lineHeight / (sortedWaypoints.length + 1);

          return Stack(
            children: [
              // Main background line
              Positioned(
                left: lineLeftX - 3,
                top: lineTop,
                child: Container(
                  width: 6,
                  height: lineHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Progress indicators
              ..._buildProgressSegments(
                sortedWaypoints: sortedWaypoints,
                lineTop: lineTop,
                segmentHeight: segmentHeight,
                lineLeftX: lineLeftX,
                reachedHistory: reachedHistory,
                signalStrength: signalStrength,
              ),

              // Waypoint circles
              ..._buildWaypointCircles(
                sortedWaypoints: sortedWaypoints,
                lineTop: lineTop,
                segmentHeight: segmentHeight,
                lineLeftX: lineLeftX,
                reachedHistory: reachedHistory,
              ),

              // Labels
              // ..._buildSimpleLabels(
              //   sortedWaypoints: sortedWaypoints,
              //   lineTop: lineTop,
              //   segmentHeight: segmentHeight,
              //   lineLeftX: lineLeftX,
              // ),
            ],
          );
        });
      },
    );
  }

  List<Widget> _buildProgressSegments({
    required List<BleWaypoint> sortedWaypoints,
    required double lineTop,
    required double segmentHeight,
    required double lineLeftX,
    required List<String> reachedHistory,
    required Map<String, double> signalStrength,
  }) {
    List<Widget> segments = [];

    for (int i = 0; i < sortedWaypoints.length; i++) {
      final waypoint = sortedWaypoints[i];
      final reversedIndex = sortedWaypoints.length - 1 - i;

      // Segment position (from this waypoint to next)
      final segmentStartY = lineTop + segmentHeight * (reversedIndex + 1);
      final segmentEndY = lineTop + segmentHeight * reversedIndex;

      // Check if waypoint is reached using reachedHistory
      final isReached = reachedHistory.contains(waypoint.id);

      Color segmentColor = Colors.transparent;

      if (isReached) {
        // Waypoint is reached - show green segment
        segmentColor = Colors.green;
      } else if (i > 0 && reachedHistory.contains(sortedWaypoints[i - 1].id)) {
        // Previous waypoint reached, check for half-way progress to this one
        final strength = signalStrength[waypoint.id] ?? 0.0;
        if (strength > 15) {
          // Show half-way progress
          segmentColor = Colors.lightGreen.withOpacity(0.7);

          // Only fill part of the segment based on signal strength
          final progress = (strength / 100).clamp(0.0, 0.8);
          final partialHeight = (segmentStartY - segmentEndY) * progress;

          segments.add(
            Positioned(
              left: lineLeftX - 3,
              top: segmentStartY - partialHeight,
              child: Container(
                width: 6,
                height: partialHeight,
                decoration: BoxDecoration(
                  color: segmentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );
          continue;
        }
      }

      // Full segment coloring for reached waypoints
      if (segmentColor != Colors.transparent &&
          i < sortedWaypoints.length - 1) {
        segments.add(
          Positioned(
            left: lineLeftX - 3,
            top: segmentEndY,
            child: Container(
              width: 6,
              height: segmentStartY - segmentEndY,
              decoration: BoxDecoration(
                color: segmentColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }
    }

    return segments;
  }

  List<Widget> _buildWaypointCircles({
    required List<BleWaypoint> sortedWaypoints,
    required double lineTop,
    required double segmentHeight,
    required double lineLeftX,
    required List<String> reachedHistory,
  }) {
    return sortedWaypoints.asMap().entries.map((entry) {
      final index = entry.key;
      final waypoint = entry.value;
      final reversedIndex = sortedWaypoints.length - 1 - index;
      final waypointY = lineTop + segmentHeight * (reversedIndex + 1);

      // Simple status: Green if reached, Red if not
      final isReached = reachedHistory.contains(waypoint.id);

      return Positioned(
        left: lineLeftX - 12, // Reduced offset for smaller circles
        top: waypointY - 12,
        child: Container(
          width: 24, // Decreased from 30
          height: 24,
          decoration: BoxDecoration(
            color: isReached ? Colors.green : Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: (isReached ? Colors.green : Colors.red).withOpacity(0.4),
                blurRadius: 4, // Reduced shadow
                spreadRadius: 1,
              ),
            ],
          ),
          child: isReached
              ? const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 12, // Smaller icon
                )
              : null,
        ),
      );
    }).toList();
  }

  // List<Widget> _buildSimpleLabels({
  //   required List<BleWaypoint> sortedWaypoints,
  //   required double lineTop,
  //   required double segmentHeight,
  //   required double lineLeftX,
  // }) {
  //   return sortedWaypoints.asMap().entries.map((entry) {
  //     final index = entry.key;
  //     final waypoint = entry.value;
  //     final reversedIndex = sortedWaypoints.length - 1 - index;
  //     final waypointY = lineTop + segmentHeight * (reversedIndex + 1);

  //     final isReached = waypoint.reached;
  //     final currentRssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
  //     final isDetecting = currentRssi > -90.0;

  //     return Positioned(
  //       left: lineLeftX + 20,
  //       top: waypointY - 15,
  //       child: Container(
  //         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //         decoration: BoxDecoration(
  //           color: Colors.black.withOpacity(0.8),
  //           borderRadius: BorderRadius.circular(6),
  //           border: Border.all(
  //             color: isReached ? Colors.green : Colors.red.withOpacity(0.7),
  //             width: 1,
  //           ),
  //         ),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Text(
  //               waypoint.label,
  //               style: TextStyle(
  //                 color: isReached ? Colors.greenAccent : Colors.white,
  //                 fontSize: 12,
  //                 fontWeight: FontWeight.bold,
  //               ),
  //             ),

  //             // Debug RSSI only when detecting
  //             if (isDetecting)
  //               Text(
  //                 '${currentRssi.toStringAsFixed(0)} dBm',
  //                 style: const TextStyle(
  //                   color: Colors.blueAccent,
  //                   fontSize: 9,
  //                   fontFamily: 'monospace',
  //                 ),
  //               ),
  //           ],
  //         ),
  //       ),
  //     );
  //   }).toList();
  // }
}
