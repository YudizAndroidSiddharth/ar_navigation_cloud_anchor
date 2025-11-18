import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/ble_waypoint.dart';
import '../controller/poc_navigation_controller.dart';

class SignalAnalyticsCard extends StatelessWidget {
  final PocNavigationController controller;

  const SignalAnalyticsCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      if (!controller.permissionsGranted.value) {
        return _buildPermissionCard(theme);
      }

      final signals = controller.sortedActiveSignals;
      if (signals.isEmpty) {
        return _buildNoSignalCard(theme);
      }

      final strongest = signals.first;
      final color = controller.signalColorFor(strongest.id);
      final percent = controller.signalPercentFor(strongest.id);
      final distance = controller.signalDistanceFor(strongest.id);
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
                  Icon(Icons.bluetooth_connected, color: color, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Beacon Signal Analytics',
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
                    'Quality: ${((controller.signalQuality[strongest.id] ?? 0) * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              Text(
                'Detections: ${controller.detectionCount[strongest.id] ?? 0} | Cycle: ${controller.scanCycleCount.value}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
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

  List<Widget> _buildAdditionalSignals(Iterable<BleWaypoint> signals) {
    return [
      const SizedBox(height: 16),
      const Divider(color: Colors.white24, height: 1),
      const SizedBox(height: 8),
      Text(
        'Other Beacons',
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      ...signals.map((waypoint) {
        final color = controller.signalColorFor(waypoint.id);
        final percent = controller.signalPercentFor(waypoint.id);
        final distance = controller.signalDistanceFor(waypoint.id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  waypoint.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
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
              const SizedBox(width: 12),
              Text(
                distance,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
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
              'Bluetooth Permissions Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'BLE navigation requires location and Bluetooth permissions for beacon detection.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: controller.checkAndRequestPermissions,
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
            const Icon(
              Icons.bluetooth_searching,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Scanning for Beacons...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan cycle: ${controller.scanCycleCount.value} | Total detections: ${controller.totalDetections.value}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
