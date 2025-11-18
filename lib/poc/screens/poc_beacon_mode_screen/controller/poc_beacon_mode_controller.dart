import 'dart:async';
import 'dart:io';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/waypoint_option.dart';

/// Controller for Beacon Mode Screen
/// Handles all business logic: beacon broadcasting, permissions, and state management
class PocBeaconModeController extends GetxController {
  // ========== Constants ==========
  static const List<WaypointOption> waypointOptions = [
    WaypointOption(
      number: 1,
      label: 'Waypoint 1',
      uuid: '00000001-0000-0000-0000-000000000001',
    ),
    WaypointOption(
      number: 2,
      label: 'Waypoint 2',
      uuid: '00000002-0000-0000-0000-000000000002',
    ),
    WaypointOption(
      number: 3,
      label: 'Waypoint 3',
      uuid: '00000003-0000-0000-0000-000000000003',
    ),
  ];

  // ========== Observable State Variables ==========
  final selectedWaypoint = 1.obs;
  final isAdvertising = false.obs;
  final isBusy = false.obs;
  final statusMessage = 'Not broadcasting'.obs;
  final permissionsGranted = false.obs;

  // ========== Private Dependencies ==========
  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();
  StreamSubscription<bool>? _advertisingSub;

  // ========== Computed Properties ==========
  WaypointOption get currentWaypoint => waypointOptions.firstWhere(
    (option) => option.number == selectedWaypoint.value,
  );

  bool get canStart =>
      !isAdvertising.value && !isBusy.value && permissionsGranted.value;
  bool get canStop => isAdvertising.value && !isBusy.value;

  Color get broadcastStatusColor {
    if (isAdvertising.value) {
      return Colors.greenAccent.shade400;
    }
    if (isBusy.value) {
      return Colors.orangeAccent;
    }
    return Colors.redAccent;
  }

  String get broadcastStatusLabel =>
      isAdvertising.value ? 'Broadcasting' : 'Idle';

  // ========== Lifecycle Methods ==========
  @override
  void onInit() {
    super.onInit();
    _initializeAdvertisingSubscription();
    checkPermissionsStatus();
  }

  @override
  void onClose() {
    _advertisingSub?.cancel();
    _beaconBroadcast.stop();
    WakelockPlus.disable();
    super.onClose();
  }

  // ========== Initialization ==========
  void _initializeAdvertisingSubscription() {
    _advertisingSub = _beaconBroadcast.getAdvertisingStateChange().listen((
      isAdvertisingState,
    ) {
      isAdvertising.value = isAdvertisingState;
      statusMessage.value = isAdvertisingState
          ? 'Broadcasting...'
          : 'Not broadcasting';

      if (isAdvertisingState) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }

      print('[BeaconMode] Advertising state changed -> $isAdvertisingState');
    });
  }

  // ========== Permission Management ==========
  List<Permission> _getRequiredPermissions() {
    return [
      Permission.locationWhenInUse,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ] else
        Permission.bluetooth,
    ];
  }

  String _getPermissionDisplayName(Permission permission) {
    switch (permission) {
      case Permission.locationWhenInUse:
        return 'Location (When In Use)';
      case Permission.bluetoothScan:
        return 'Bluetooth Scan';
      case Permission.bluetoothConnect:
        return 'Bluetooth Connect';
      case Permission.bluetoothAdvertise:
        return 'Bluetooth Advertise';
      case Permission.bluetooth:
        return 'Bluetooth';
      default:
        return permission.value.toString();
    }
  }

  /// Check permission status without requesting
  Future<void> checkPermissionsStatus() async {
    final permissions = _getRequiredPermissions();
    bool allGranted = true;

    for (final perm in permissions) {
      final status = await perm.status;
      if (!status.isGranted) {
        allGranted = false;
        break;
      }
    }

    permissionsGranted.value = allGranted;
  }

  /// Ensure all required permissions are granted
  Future<void> ensurePermissions() async {
    final permissionsToRequest = _getRequiredPermissions();
    final deniedPermissions = <Permission>[];

    // Check and request each permission
    for (final permission in permissionsToRequest) {
      final status = await permission.status;
      if (status.isGranted) {
        continue;
      }

      final result = await permission.request();
      if (!result.isGranted) {
        deniedPermissions.add(permission);
      }
    }

    // Handle denied permissions
    if (deniedPermissions.isNotEmpty) {
      final permissionNames = deniedPermissions
          .map((p) => _getPermissionDisplayName(p))
          .join(', ');

      final shouldOpenSettings = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Permissions Required'),
          content: Text(
            'The following permissions are required to broadcast as a beacon:\n\n'
            '$permissionNames\n\n'
            'Some permissions may have been permanently denied. '
            'Would you like to open app settings to grant them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
        await Future.delayed(const Duration(milliseconds: 500));
        await checkPermissionsStatus();

        // Verify permissions after returning from settings
        bool allGranted = true;
        for (final perm in deniedPermissions) {
          final status = await perm.status;
          if (!status.isGranted) {
            allGranted = false;
            break;
          }
        }

        if (!allGranted) {
          throw Exception(
            'Please grant all required permissions in app settings',
          );
        }
      } else {
        throw Exception('Permission denied: $permissionNames');
      }
    }

    permissionsGranted.value = true;
  }

  /// Check and request permissions proactively
  Future<void> checkAndRequestPermissions() async {
    try {
      await ensurePermissions();
      await checkPermissionsStatus();
      Get.snackbar(
        'Success',
        'All permissions granted!',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      await checkPermissionsStatus();
      Get.snackbar(
        'Error',
        'Permission error: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ========== Beacon Broadcasting ==========
  /// Start broadcasting as a beacon
  Future<void> startBroadcasting() async {
    if (isBusy.value || isAdvertising.value) return;

    final waypoint = currentWaypoint;

    isBusy.value = true;
    statusMessage.value = 'Starting broadcast...';

    try {
      print('=== BEACON BROADCAST DEBUG START ===');
      print(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );

      // Log all permission statuses
      final permissions = _getRequiredPermissions();
      print('Permission Status:');
      for (final perm in permissions) {
        final status = await perm.status;
        print('  ${perm.value}: $status');
      }

      await ensurePermissions();

      await _beaconBroadcast.stop();
      await Future.delayed(const Duration(milliseconds: 500));

      print(
        '[BeaconMode] Starting beacon broadcast:\n'
        '  • Format: AltBeacon (beacon_broadcast library default)\n'
        '  • UUID: ${waypoint.uuid}\n'
        '  • Identifier: ${waypoint.label}\n'
        '  • Major: ${waypoint.number}\n'
        '  • Minor: ${waypoint.number}\n'
        '  • TxPower: -59 dBm\n'
        '  • AdvertiseMode: ${AdvertiseMode.lowLatency}',
      );

      // Configure beacon
      _beaconBroadcast
          .setUUID(waypoint.uuid)
          .setIdentifier(waypoint.label)
          .setMajorId(waypoint.number)
          .setMinorId(waypoint.number)
          .setTransmissionPower(-59)
          .setAdvertiseMode(AdvertiseMode.lowLatency);

      print('[BeaconMode] Configuration complete, starting broadcast...');

      // Start broadcasting
      await _beaconBroadcast.start();

      print('[BeaconMode] start() called, waiting for state change...');

      statusMessage.value = 'Broadcasting ${waypoint.uuid}';

      // Wait for advertising state to change
      bool advertisingStarted = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (isAdvertising.value) {
          advertisingStarted = true;
          print(
            '[BeaconMode] ✅ Advertising state confirmed: ${isAdvertising.value}',
          );
          break;
        }
        print(
          '[BeaconMode] Waiting for advertising state... (attempt ${i + 1}/10)',
        );
      }

      if (!advertisingStarted) {
        print(
          '[BeaconMode] ⚠️ WARNING: Advertising state not confirmed after 5 seconds!',
        );
        print(
          '[BeaconMode] Current _isAdvertising state: ${isAdvertising.value}',
        );
      }

      // Additional verification after delay
      await Future.delayed(const Duration(seconds: 2));
      print('[BeaconMode] Final advertising state: ${isAdvertising.value}');
      print(
        '[BeaconMode] Broadcast status for ${waypoint.label}: ${isAdvertising.value ? "ACTIVE" : "INACTIVE"}',
      );

      // Log expected AltBeacon format
      print(
        '[BeaconMode] Expected AltBeacon format (beacon_broadcast library):',
      );
      print('  • Header: 0xBE 0xAC (AltBeacon)');
      print('  • UUID: ${waypoint.uuid}');
      print('  • Major: ${waypoint.number}');
      print('  • Minor: ${waypoint.number}');
      print('  • TxPower: -59 dBm');
      print(
        '  • Total length: 24 bytes (2 header + 16 UUID + 2 Major + 2 Minor + 1 TxPower + 1 Reserved)',
      );
      print(
        '[BeaconMode] Note: Scanner now supports BOTH iBeacon and AltBeacon formats',
      );

      print('=== BEACON BROADCAST DEBUG END ===\n');

      // If advertising started, offer to run self-scan test
      if (advertisingStarted) {
        runSelfScanTest(waypoint);
      }
    } catch (e) {
      statusMessage.value = 'Failed to start broadcasting: $e';
      await WakelockPlus.disable();
      print('[BeaconMode] BEACON ERROR: $e');
      print('=== BEACON BROADCAST DEBUG END (ERROR) ===\n');

      // Try alternative method on error
      print('🔄 Attempting alternative broadcast method...');
      try {
        await _startAlternativeBroadcast();
      } catch (altError) {
        print('❌ Alternative broadcast also failed: $altError');
      }
    } finally {
      isBusy.value = false;
    }
  }

  /// Stop broadcasting
  Future<void> stopBroadcasting() async {
    if (isBusy.value) return;

    isBusy.value = true;
    statusMessage.value = 'Stopping broadcast...';

    try {
      await _beaconBroadcast.stop();
      await WakelockPlus.disable();
      statusMessage.value = 'Not broadcasting';
      isAdvertising.value = false;
      print('[BeaconMode] Broadcast stopped');
    } catch (e) {
      statusMessage.value = 'Failed to stop: $e';
      print('[BeaconMode] Failed to stop broadcasting: $e');
    } finally {
      isBusy.value = false;
    }
  }

  // ========== Alternative Broadcasting (Fallback) ==========
  Future<void> _startAlternativeBroadcast() async {
    print('🔄 Trying alternative broadcast method...');

    try {
      final waypoint = currentWaypoint;

      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        print('❌ BLE not supported on this device');
        return;
      }

      // Turn on Bluetooth if off
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        print('Turning on Bluetooth...');
        await FlutterBluePlus.turnOn();
        await FlutterBluePlus.adapterState
            .where((state) => state == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 15));
        print('Bluetooth turned on');
      }

      // Build iBeacon manufacturer data
      final manufacturerData = _buildIBeaconData(waypoint);

      print('Alternative broadcast attempt:');
      print('  Name: BEACON_${waypoint.number}');
      print('  Service UUID: ${waypoint.uuid}');
      print(
        '  Manufacturer Data: ${manufacturerData[0x004C]?.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      print('⚠️ FlutterBluePlus doesn\'t support direct iBeacon advertising');
      print('   Please ensure beacon_broadcast library is working correctly');

      throw Exception(
        'Alternative broadcast method not available - FlutterBluePlus doesn\'t support direct advertising',
      );
    } catch (e) {
      print('❌ Alternative broadcast failed: $e');
      rethrow;
    }
  }

  Map<int, List<int>> _buildIBeaconData(WaypointOption waypoint) {
    final uuid = waypoint.uuid.replaceAll('-', '');
    final uuidBytes = <int>[];
    for (int i = 0; i < uuid.length; i += 2) {
      uuidBytes.add(int.parse(uuid.substring(i, i + 2), radix: 16));
    }

    final data = <int>[
      0x02, 0x15, // iBeacon header
      ...uuidBytes, // UUID (16 bytes)
      (waypoint.number >> 8) & 0xFF, waypoint.number & 0xFF, // Major (2 bytes)
      (waypoint.number >> 8) & 0xFF, waypoint.number & 0xFF, // Minor (2 bytes)
      0xC5, // TX Power (-59 dBm)
    ];

    return {0x004C: data}; // Apple manufacturer ID
  }

  // ========== Self-Scan Test ==========
  /// Run a self-scan test to verify the device is broadcasting
  Future<void> runSelfScanTest(WaypointOption waypoint) async {
    print('\n🔍 === SELF-SCAN TEST START ===');
    print('[BeaconMode] Testing if device can detect its own broadcast...');

    try {
      // Check if BLE is supported
      if (await FlutterBluePlus.isSupported == false) {
        print('[BeaconMode] ❌ BLE not supported for self-scan test');
        return;
      }

      // Turn on Bluetooth if needed
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        print('[BeaconMode] Turning on Bluetooth for self-scan...');
        await FlutterBluePlus.turnOn();
        await Future.delayed(const Duration(seconds: 2));
      }

      print('[BeaconMode] Starting 10-second scan to detect own broadcast...');
      print('[BeaconMode] Looking for UUID: ${waypoint.uuid}');
      print(
        '[BeaconMode] Checking for both iBeacon (0x02 0x15) and AltBeacon (0xBE 0xAC) formats...',
      );

      final foundDevices = <ScanResult>[];
      StreamSubscription? scanSub;

      scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final adv = result.advertisementData;

          // Check for iBeacon (Apple manufacturer data)
          if (adv.manufacturerData.containsKey(0x004C)) {
            final data = adv.manufacturerData[0x004C]!;
            if (data.length >= 2 && data[0] == 0x02 && data[1] == 0x15) {
              print('[BeaconMode] ✅ Found iBeacon with correct header!');
              _logBeaconDetails(result, data, waypoint, 'iBeacon');
              foundDevices.add(result);
            }
          }

          // Check for AltBeacon (any manufacturer data with BE AC header)
          for (final entry in adv.manufacturerData.entries) {
            final data = entry.value;
            if (data.length >= 2 && data[0] == 0xBE && data[1] == 0xAC) {
              print(
                '[BeaconMode] ✅ Found AltBeacon with correct header! (Company: 0x${entry.key.toRadixString(16)})',
              );
              _logBeaconDetails(result, data, waypoint, 'AltBeacon');
              foundDevices.add(result);
              break; // Found AltBeacon, no need to check other manufacturer data
            }
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      await scanSub.cancel();

      print('[BeaconMode] Self-scan test complete');
      if (foundDevices.isEmpty) {
        print('[BeaconMode] ❌ No beacon with correct header found!');
        print(
          '[BeaconMode] Expected: AltBeacon (0xBE 0xAC) or iBeacon (0x02 0x15)',
        );
        print(
          '[BeaconMode] This suggests the beacon_broadcast library may not be broadcasting correctly.',
        );
      } else {
        print(
          '[BeaconMode] ✅ Found ${foundDevices.length} beacon(s) with correct header',
        );
      }

      print('=== SELF-SCAN TEST END ===\n');
    } catch (e) {
      print('[BeaconMode] ❌ Self-scan test error: $e');
      print('=== SELF-SCAN TEST END (ERROR) ===\n');
    }
  }

  void _logBeaconDetails(
    ScanResult result,
    List<int> data,
    WaypointOption waypoint,
    String format,
  ) {
    print('[BeaconMode]   Device ID: ${result.device.remoteId}');
    print('[BeaconMode]   RSSI: ${result.rssi} dBm');
    print('[BeaconMode]   Data length: ${data.length} bytes');
    print('[BeaconMode]   Format: $format');

    // Try to extract UUID (works for both iBeacon and AltBeacon)
    int uuidStartOffset = format == 'iBeacon' ? 2 : 2; // Both start at offset 2
    if (data.length >= uuidStartOffset + 16) {
      final uuidBytes = data.sublist(uuidStartOffset, uuidStartOffset + 16);
      final buffer = StringBuffer();
      for (int i = 0; i < uuidBytes.length; i++) {
        buffer.write(uuidBytes[i].toRadixString(16).padLeft(2, '0'));
      }
      final raw = buffer.toString();
      final formatted =
          '${raw.substring(0, 8)}-'
          '${raw.substring(8, 12)}-'
          '${raw.substring(12, 16)}-'
          '${raw.substring(16, 20)}-'
          '${raw.substring(20)}';
      print('[BeaconMode]   UUID: ${formatted.toUpperCase()}');

      if (formatted.toUpperCase() == waypoint.uuid.toUpperCase()) {
        print('[BeaconMode]   ✅ UUID MATCHES! This is our beacon!');
      } else {
        print(
          '[BeaconMode]   ⚠️ UUID does not match (expected: ${waypoint.uuid})',
        );
      }
    }
  }

  // ========== Waypoint Selection ==========
  void selectWaypoint(int waypointNumber) {
    if (!isBusy.value) {
      selectedWaypoint.value = waypointNumber;
    }
  }
}
