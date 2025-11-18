import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/ble_waypoint.dart';
import '../controller/poc_navigation_controller.dart';

class VerticalProgressLine extends StatelessWidget {
  final PocNavigationController controller;

  const VerticalProgressLine({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Obx(() {
          final sortedWaypoints = controller.orderedWaypoints;
          final lineHeight = constraints.maxHeight * 0.6;
          final lineTop = (constraints.maxHeight - lineHeight) / 2;
          final lineLeftX = constraints.maxWidth * 0.15;

          final progress = controller.calculateUserPositionOnLineReversed(
            sortedWaypoints: sortedWaypoints,
            lineHeight: lineHeight,
            lineTop: lineTop,
          );

          return Stack(
            children: [
              Positioned(
                left: lineLeftX - 2,
                top: lineTop,
                child: Container(
                  width: 4,
                  height: lineHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (progress.completedHeight > 0)
                Positioned(
                  left: lineLeftX - 2,
                  top: lineTop + (lineHeight - progress.completedHeight),
                  child: Container(
                    width: 4,
                    height: progress.completedHeight,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ..._buildWaypointIndicators(
                sortedWaypoints: sortedWaypoints,
                lineTop: lineTop,
                lineHeight: lineHeight,
                lineLeftX: lineLeftX,
              ),
              ..._buildWaypointLabels(
                sortedWaypoints: sortedWaypoints,
                lineTop: lineTop,
                lineHeight: lineHeight,
                lineLeftX: lineLeftX,
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                left: lineLeftX - 16,
                top: progress.currentY - 16,
                child: _buildUserIndicator(),
              ),
            ],
          );
        });
      },
    );
  }

  List<Widget> _buildWaypointIndicators({
    required List<BleWaypoint> sortedWaypoints,
    required double lineTop,
    required double lineHeight,
    required double lineLeftX,
  }) {
    return sortedWaypoints.asMap().entries.map((entry) {
      final index = entry.key;
      final waypoint = entry.value;
      final reversedIndex = sortedWaypoints.length - 1 - index;
      final waypointPosition =
          lineTop +
          (lineHeight / (sortedWaypoints.length + 1)) * (reversedIndex + 1);

      return Positioned(
        left: lineLeftX - 12,
        top: waypointPosition - 12,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: waypoint.reached ? Colors.green : Colors.red,
            shape: BoxShape.circle,
            border: Border.all(
              color: waypoint.reached ? Colors.greenAccent : Colors.redAccent,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: (waypoint.reached ? Colors.green : Colors.red)
                    .withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: waypoint.reached
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null,
        ),
      );
    }).toList();
  }

  List<Widget> _buildWaypointLabels({
    required List<BleWaypoint> sortedWaypoints,
    required double lineTop,
    required double lineHeight,
    required double lineLeftX,
  }) {
    return sortedWaypoints.asMap().entries.map((entry) {
      final index = entry.key;
      final waypoint = entry.value;
      final reversedIndex = sortedWaypoints.length - 1 - index;
      final waypointPosition =
          lineTop +
          (lineHeight / (sortedWaypoints.length + 1)) * (reversedIndex + 1);
      final pointNumber = waypoint.order.toString().padLeft(4, '0');
      final smoothed = controller.smoothedRssi[waypoint.id] ?? -100.0;

      return Positioned(
        left: lineLeftX + 20,
        top: waypointPosition - 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: waypoint.reached ? Colors.green : Colors.white24,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pointNumber,
                style: TextStyle(
                  color: waypoint.reached ? Colors.greenAccent : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                waypoint.label,
                style: TextStyle(
                  color: waypoint.reached ? Colors.greenAccent : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (smoothed > -95.0 && !waypoint.reached)
                Text(
                  '${smoothed.toStringAsFixed(0)} dBm',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildUserIndicator() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blueAccent, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.6),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 18),
    );
  }
}
