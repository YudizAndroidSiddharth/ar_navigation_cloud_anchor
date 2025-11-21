import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/ble_waypoint.dart';

class SignalAnalyticsCard extends StatelessWidget {
  final controller;

  const SignalAnalyticsCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      if (!controller.permissionsGranted.value) {
        return _buildPermissionCard(theme);
      }

      final signals = _getActiveSignals();
      if (signals.isEmpty) {
        return _buildNoSignalCard(theme);
      }

      final strongest = signals.first;
      final color = controller.signalColorFor(strongest.id);
      final percent = controller.signalPercentFor(strongest.id);
      final distance = _getSignalDistance(strongest.id);
      final qualityLabel = controller.signalQualityLabelFor(strongest.id);

      return Card(
        color: Colors.black.withOpacity(0.5),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bluetooth, color: color, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Continuous BLE Analytics ⚡',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strongest.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          qualityLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                          ),
                        ),
                        // Direction indicator for optimized controller
                        if (controller.isMovingBackward.value)
                          Text(
                            '⬅️ Moving backward',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$percent%',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        distance,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'RSSI: ${(controller.smoothedRssi[strongest.id] ?? -100).toStringAsFixed(1)} dBm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ),
                  Text(
                    'Strength: ${(controller.signalStrength[strongest.id] ?? 0).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detections: ${controller.detectionCount[strongest.id] ?? 0} | Total: ${controller.totalDetections.value}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  // Real-time continuous scanning indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: controller.isScanning.value
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: controller.isScanning.value
                            ? Colors.green
                            : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      controller.isScanning.value ? 'LIVE' : 'INIT',
                      style: TextStyle(
                        color: controller.isScanning.value
                            ? Colors.green
                            : Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              // Last seen timestamp for debugging real-time updates
              if (controller.lastSeen[strongest.id] != null)
                Text(
                  'Last seen: ${DateTime.now().difference(controller.lastSeen[strongest.id]!).inMilliseconds}ms ago',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              // Real-time signal strength indicator
              if (controller.signalStrength[strongest.id] != null &&
                  controller.signalStrength[strongest.id]! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Text(
                        'Real-time strength: ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${controller.signalStrength[strongest.id]!.toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _getStrengthColor(
                            controller.signalStrength[strongest.id]!,
                          ),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Live update indicator
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              if (signals.length > 1)
                ..._buildAdditionalSignals(signals.skip(1)),
            ],
          ),
        ),
      );
    });
  }

  /// Get active signals from the optimized controller
  List<BleWaypoint> _getActiveSignals() {
    final waypoints = controller.orderedWaypoints;
    final filtered = waypoints.where((BleWaypoint waypoint) {
      final rssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
      final strength = controller.signalStrength[waypoint.id] ?? 0.0;

      // Show waypoints with decent signal or if reached
      final hasSignal = rssi > -95.0 || strength > 10.0;
      return hasSignal || waypoint.reached;
    }).toList();

    // Use explicit comparator function to avoid type inference issues
    int compareWaypoints(BleWaypoint a, BleWaypoint b) {
      // Sort by signal strength, reached waypoints first
      if (a.reached && !b.reached) return -1;
      if (!a.reached && b.reached) return 1;

      final strengthA = controller.signalStrength[a.id] ?? 0.0;
      final strengthB = controller.signalStrength[b.id] ?? 0.0;
      return strengthB.compareTo(strengthA);
    }

    filtered.sort(compareWaypoints);

    return filtered;
  }

  /// Calculate signal distance estimation
  String _getSignalDistance(String waypointId) {
    final rssi = controller.smoothedRssi[waypointId] ?? -100.0;
    if (rssi >= -65) return '< 0.5m';
    if (rssi >= -70) return '≈ 0.5-1m';
    if (rssi >= -75) return '≈ 1-2m';
    if (rssi >= -80) return '≈ 2-3m';
    if (rssi >= -85) return '≈ 3-5m';
    if (rssi >= -90) return '≈ 5-8m';
    return '> 8m';
  }

  Color _getStrengthColor(double strength) {
    if (strength >= 85) return Colors.green;
    if (strength >= 65) return Colors.lightGreen;
    if (strength >= 45) return Colors.orange;
    if (strength >= 25) return Colors.deepOrange;
    return Colors.red;
  }

  List<Widget> _buildAdditionalSignals(Iterable<BleWaypoint> signals) {
    return [
      const SizedBox(height: 16),
      const Divider(color: Colors.white24, height: 1),
      const SizedBox(height: 8),
      Row(
        children: [
          Text(
            'Other Beacons',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Real-time scanning indicator
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: controller.isScanning.value
                      ? Colors.green
                      : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                controller.isScanning.value ? 'SCANNING' : 'STOPPED',
                style: TextStyle(
                  color: controller.isScanning.value
                      ? Colors.green
                      : Colors.orange,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...signals.map((waypoint) {
        final color = controller.signalColorFor(waypoint.id);
        final percent = controller.signalPercentFor(waypoint.id);
        final distance = _getSignalDistance(waypoint.id);
        final rssi = controller.smoothedRssi[waypoint.id] ?? -100.0;
        final isRecentlySeen =
            controller.lastSeen[waypoint.id] != null &&
            DateTime.now()
                    .difference(controller.lastSeen[waypoint.id]!)
                    .inSeconds <
                2;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  waypoint.label,
                  style: TextStyle(
                    color: isRecentlySeen ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: isRecentlySeen
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (isRecentlySeen)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                distance,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(width: 8),
              // Show real-time RSSI for other beacons
              if (rssi > -95)
                Text(
                  '${rssi.toStringAsFixed(0)}dBm',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
            ],
          ),
        );
      }),
    ];
  }

  Widget _buildPermissionCard(ThemeData theme) {
    return Card(
      color: Colors.orange.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.warning, color: Colors.orange, size: 32),
            const SizedBox(height: 12),
            const Text(
              'BLE Permissions Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Continuous BLE navigation requires location and Bluetooth permissions for real-time beacon detection.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // Note: Controller should expose a public method for permission check
                // You may need to add: Future<void> requestPermissions() async { await _checkPermissions(); }
                // For now, this will attempt to call the method if it exists
                if (controller.runtimeType.toString().contains(
                  'PocNavigationController',
                )) {
                  // Call any available permission method or show settings dialog
                  controller
                      .restartScanning(); // This will trigger permission check if needed
                }
              },
              icon: const Icon(Icons.security),
              label: const Text('Grant Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSignalCard(ThemeData theme) {
    return Card(
      color: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.bluetooth_searching,
                  color: Colors.white54,
                  size: 48,
                ),
                // Animated scanning indicator - only when actively scanning
                if (controller.isScanning.value)
                  Positioned(
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green.withOpacity(0.5),
                        ),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              controller.isScanning.value
                  ? 'Scanning for BLE Beacons...'
                  : 'Initializing BLE Scanner...',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              controller.isScanning.value
                  ? 'Continuous scanning active ⚡'
                  : 'Starting up...',
              style: TextStyle(
                color: controller.isScanning.value
                    ? Colors.green
                    : Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total detections: ${controller.totalDetections.value}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            // Show waypoint progress instead of walking
            if (controller.completedWaypoints.value > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '📍 Waypoints: ${controller.completedWaypoints.value}/${controller.orderedWaypoints.length}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
