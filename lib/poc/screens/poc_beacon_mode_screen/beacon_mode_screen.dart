import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller/poc_beacon_mode_controller.dart';

/// Screen that turns the device into a BLE beacon to act as a waypoint.
///
/// Uses GetX MVC pattern:
/// - Controller: All business logic and state management
/// - View: UI rendering only
class PocBeaconModeScreen extends GetView<PocBeaconModeController> {
  const PocBeaconModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize controller if not already bound
    Get.put(PocBeaconModeController());

    return Scaffold(appBar: _renderAppBar(), body: _renderBody(context));
  }

  /// Render app bar
  PreferredSizeWidget _renderAppBar() {
    return AppBar(title: const Text('Beacon Mode'));
  }

  /// Render main body
  Widget _renderBody(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select waypoint to broadcast',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _renderWaypointSelector(theme),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: _renderBroadcastInsights(theme),
              ),
            ),
            const SizedBox(height: 16),
            _renderActionButtons(),
          ],
        ),
      ),
    );
  }

  /// Render waypoint selector dropdown
  Widget _renderWaypointSelector(ThemeData theme) {
    return Obx(
      () => DropdownButtonFormField<int>(
        decoration: const InputDecoration(
          labelText: 'Waypoint',
          border: OutlineInputBorder(),
        ),
        value: controller.selectedWaypoint.value,
        items: PocBeaconModeController.waypointOptions
            .map(
              (option) => DropdownMenuItem(
                value: option.number,
                child: Text(option.label),
              ),
            )
            .toList(),
        onChanged: controller.isBusy.value
            ? null
            : (value) {
                if (value != null) {
                  controller.selectWaypoint(value);
                }
              },
      ),
    );
  }

  /// Render broadcast insights card
  Widget _renderBroadcastInsights(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Broadcast health', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _renderStatusIndicator(theme),
            const SizedBox(height: 16),
            Divider(color: Colors.black.withOpacity(0.1)),
            const SizedBox(height: 12),
            _renderWaypointDetails(theme),
            const SizedBox(height: 16),
            Divider(color: Colors.black.withOpacity(0.1)),
            const SizedBox(height: 12),
            _renderPermissionStatus(theme),
          ],
        ),
      ),
    );
  }

  /// Render status indicator
  Widget _renderStatusIndicator(ThemeData theme) {
    return Obx(() {
      final isActive = controller.isAdvertising.value;
      final statusColor = controller.broadcastStatusColor;
      final statusLabel = controller.broadcastStatusLabel;
      final statusDetail = controller.statusMessage.value;

      return Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: statusColor, width: 3),
              color: statusColor.withOpacity(0.1),
            ),
            alignment: Alignment.center,
            child: Text(
              isActive ? '100%' : '0%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(statusDetail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// Render waypoint details
  Widget _renderWaypointDetails(ThemeData theme) {
    return Obx(() {
      final waypoint = controller.currentWaypoint;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Waypoint', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            waypoint.label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text('UUID', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(
            waypoint.uuid,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    });
  }

  /// Render permission status
  Widget _renderPermissionStatus(ThemeData theme) {
    return Obx(
      () => Row(
        children: [
          Icon(
            controller.permissionsGranted.value
                ? Icons.check_circle
                : Icons.warning,
            color: controller.permissionsGranted.value
                ? Colors.green
                : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.permissionsGranted.value
                  ? 'All permissions granted'
                  : 'Permissions required',
              style: theme.textTheme.bodySmall?.copyWith(
                color: controller.permissionsGranted.value
                    ? Colors.green
                    : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!controller.permissionsGranted.value)
            TextButton(
              onPressed: controller.checkAndRequestPermissions,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }

  /// Render action buttons
  Widget _renderActionButtons() {
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: controller.canStart
                ? controller.startBroadcasting
                : null,
            child: Text(
              controller.isBusy.value && !controller.isAdvertising.value
                  ? 'Starting...'
                  : 'Start Broadcasting',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: controller.canStop ? controller.stopBroadcasting : null,
            child: Text(
              controller.isBusy.value && controller.isAdvertising.value
                  ? 'Stopping...'
                  : 'Stop Broadcasting',
            ),
          ),
        ],
      ),
    );
  }
}
