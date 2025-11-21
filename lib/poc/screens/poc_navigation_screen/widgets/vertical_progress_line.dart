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
              // Main progress line background
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
              // Completed progress line
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
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
              // Real-time user indicator with smooth animation
              AnimatedPositioned(
                duration: const Duration(
                  milliseconds: 100,
                ), // Fast animation for real-time
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

      // Real-time signal strength indicator from optimized controller
      final signalStrength = controller.signalStrength[waypoint.id] ?? 0.0;
      final currentRssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
      final isDetecting = currentRssi > -95.0;
      final isRecentlySeen =
          controller.lastSeen[waypoint.id] != null &&
          DateTime.now()
                  .difference(controller.lastSeen[waypoint.id]!)
                  .inSeconds <
              3;

      return Positioned(
        left: lineLeftX - 12,
        top: waypointPosition - 12,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Signal strength ring for active beacons
            if (isDetecting)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.blue.withOpacity(signalStrength / 100),
                    width: 2,
                  ),
                ),
              ),
            // Recently seen pulse effect
            if (isRecentlySeen && !waypoint.reached)
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.2),
                ),
              ),
            // Main waypoint indicator
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: waypoint.reached
                    ? Colors.green
                    : (isDetecting ? Colors.blue : Colors.red),
                shape: BoxShape.circle,
                border: Border.all(
                  color: waypoint.reached
                      ? Colors.greenAccent
                      : (isDetecting ? Colors.blueAccent : Colors.redAccent),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (waypoint.reached
                                ? Colors.green
                                : (isDetecting ? Colors.blue : Colors.red))
                            .withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: waypoint.reached
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : isDetecting
                  ? const Icon(Icons.bluetooth, color: Colors.white, size: 12)
                  : null,
            ),
          ],
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

      // Real-time data from optimized controller
      final currentRssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
      final signalStrength = controller.signalStrength[waypoint.id] ?? 0.0;
      final isDetecting = currentRssi > -95.0;
      final isRecentlySeen =
          controller.lastSeen[waypoint.id] != null &&
          DateTime.now()
                  .difference(controller.lastSeen[waypoint.id]!)
                  .inSeconds <
              2;

      return Positioned(
        left: lineLeftX + 20,
        top: waypointPosition - 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: waypoint.reached
                  ? Colors.green
                  : (isDetecting ? Colors.blue : Colors.white24),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pointNumber,
                    style: TextStyle(
                      color: waypoint.reached
                          ? Colors.greenAccent
                          : (isDetecting ? Colors.blueAccent : Colors.white70),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isRecentlySeen && !waypoint.reached)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                waypoint.label,
                style: TextStyle(
                  color: waypoint.reached
                      ? Colors.greenAccent
                      : (isDetecting ? Colors.white : Colors.white70),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Real-time signal info
              if (isDetecting && !waypoint.reached) ...[
                Text(
                  '${currentRssi.toStringAsFixed(0)} dBm',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 10,
                  ),
                ),
                if (signalStrength > 10)
                  Text(
                    '${signalStrength.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: _getStrengthColor(signalStrength),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
              // Direction indicator instead of walking
              if (isDetecting &&
                  controller.isMovingBackward.value &&
                  !waypoint.reached)
                Text(
                  '⬅️ Backward',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _getStrengthColor(double strength) {
    if (strength >= 80) return Colors.green;
    if (strength >= 60) return Colors.lightGreen;
    if (strength >= 40) return Colors.orange;
    if (strength >= 20) return Colors.deepOrange;
    return Colors.red;
  }

  Widget _buildUserIndicator() {
    return Obx(() {
      final isScanning = controller.isScanning.value;
      final isMovingBackward = controller.isMovingBackward.value;
      final hasActiveSignal = _hasAnyActiveSignal();

      return Stack(
        alignment: Alignment.center,
        children: [
          // Active signal pulse effect
          if (hasActiveSignal)
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.2),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.5),
                  width: 2,
                ),
              ),
            ),
          // Scanning indicator ring
          if (isScanning && !hasActiveSignal)
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.blue.withOpacity(0.5),
                  width: 2,
                ),
              ),
            ),
          // Main user indicator
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: hasActiveSignal
                  ? Colors.blue
                  : (isScanning ? Colors.green : Colors.grey),
              shape: BoxShape.circle,
              border: Border.all(
                color: hasActiveSignal
                    ? Colors.blueAccent
                    : (isScanning ? Colors.greenAccent : Colors.white),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (hasActiveSignal
                              ? Colors.blue
                              : (isScanning ? Colors.green : Colors.grey))
                          .withOpacity(0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              hasActiveSignal ? Icons.bluetooth : Icons.person,
              color: Colors.white,
              size: 18,
            ),
          ),
          // Direction indicator
          if (isMovingBackward)
            Positioned(
              bottom: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⬅️',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // Scanning status
          if (!hasActiveSignal && isScanning)
            Positioned(
              bottom: -12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SCAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  /// Check if any beacon has active signal
  bool _hasAnyActiveSignal() {
    for (final BleWaypoint waypoint in controller.orderedWaypoints) {
      final rssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
      if (rssi > -90.0) {
        return true;
      }
    }
    return false;
  }
}
