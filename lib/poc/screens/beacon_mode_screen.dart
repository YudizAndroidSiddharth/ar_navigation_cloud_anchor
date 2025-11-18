import 'dart:async';
import 'dart:io';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Screen that turns the device into a BLE beacon to act as a waypoint.
///
/// - Each waypoint broadcasts a unique UUID so the navigation phone can
///   differentiate checkpoints.
/// - Uses `beacon_broadcast` for BLE advertising and `wakelock_plus`
///   to keep the screen awake while broadcasting.
class BeaconModeScreen extends StatefulWidget {
  const BeaconModeScreen({super.key});

  @override
  State<BeaconModeScreen> createState() => _BeaconModeScreenState();
}

class _WaypointOption {
  final int number;
  final String label;
  final String uuid;

  const _WaypointOption({
    required this.number,
    required this.label,
    required this.uuid,
  });
}

class _BeaconModeScreenState extends State<BeaconModeScreen> {
  static const List<_WaypointOption> _waypointOptions = [
    _WaypointOption(
      number: 1,
      label: 'Waypoint 1',
      uuid: '00000001-0000-0000-0000-000000000001',
    ),
    _WaypointOption(
      number: 2,
      label: 'Waypoint 2',
      uuid: '00000002-0000-0000-0000-000000000002',
    ),
    _WaypointOption(
      number: 3,
      label: 'Waypoint 3',
      uuid: '00000003-0000-0000-0000-000000000003',
    ),
  ];

  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();

  StreamSubscription<bool>? _advertisingSub;
  int _selectedWaypoint = _waypointOptions.first.number;
  bool _isAdvertising = false;
  bool _isBusy = false;
  String _statusMessage = 'Not broadcasting';
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _advertisingSub = _beaconBroadcast.getAdvertisingStateChange().listen((
      isAdvertising,
    ) {
      if (!mounted) return;
      setState(() {
        _isAdvertising = isAdvertising;
        _statusMessage = isAdvertising ? 'Broadcasting...' : 'Not broadcasting';
      });

      if (isAdvertising) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }

      print('[BeaconMode] Advertising state changed -> $isAdvertising');
    });

    // Check permissions when screen loads
    _checkPermissionsStatus();
  }

  /// Check permission status without requesting
  Future<void> _checkPermissionsStatus() async {
    final permissions = _getRequiredPermissions();
    bool allGranted = true;

    for (final perm in permissions) {
      final status = await perm.status;
      if (!status.isGranted) {
        allGranted = false;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _permissionsGranted = allGranted;
      });
    }
  }

  /// Get list of required permissions for this platform
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

  @override
  void dispose() {
    _advertisingSub?.cancel();
    // Ensure advertising is stopped and wakelock released.
    unawaited(_beaconBroadcast.stop());
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _startBroadcasting() async {
    if (_isBusy || _isAdvertising) return;
    final waypoint = _waypointOptions.firstWhere(
      (option) => option.number == _selectedWaypoint,
    );

    setState(() {
      _isBusy = true;
      _statusMessage = 'Starting broadcast...';
    });

    try {
      print('=== BEACON BROADCAST DEBUG START ===');
      print(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );

      // Log all permission statuses
      final permissions = [
        Permission.locationWhenInUse,
        if (Platform.isAndroid) ...[
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.bluetoothAdvertise,
        ] else
          Permission.bluetooth,
      ];

      print('Permission Status:');
      for (final perm in permissions) {
        final status = await perm.status;
        print('  ${perm.value}: $status');
      }

      await _ensurePermissions();

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

      setState(() {
        _statusMessage = 'Broadcasting ${waypoint.uuid}';
      });

      // Wait for advertising state to change
      bool advertisingStarted = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_isAdvertising) {
          advertisingStarted = true;
          print('[BeaconMode] ✅ Advertising state confirmed: $_isAdvertising');
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
        print('[BeaconMode] Current _isAdvertising state: $_isAdvertising');
      }

      // Additional verification after delay
      await Future.delayed(const Duration(seconds: 2));
      print('[BeaconMode] Final advertising state: $_isAdvertising');
      print(
        '[BeaconMode] Broadcast status for ${waypoint.label}: ${_isAdvertising ? "ACTIVE" : "INACTIVE"}',
      );

      // Log expected AltBeacon format (what beacon_broadcast library actually uses)
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
      if (advertisingStarted && mounted) {
        _runSelfScanTest(waypoint);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to start broadcasting: $e';
      });
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
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _stopBroadcasting() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _statusMessage = 'Stopping broadcast...';
    });

    try {
      await _beaconBroadcast.stop();
      await WakelockPlus.disable();
      setState(() {
        _statusMessage = 'Not broadcasting';
        _isAdvertising = false;
      });
      print('[BeaconMode] Broadcast stopped');
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to stop: $e';
      });
      print('[BeaconMode] Failed to stop broadcasting: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _ensurePermissions() async {
    final permissionsToRequest = _getRequiredPermissions();
    final deniedPermissions = <Permission>[];

    // First, check all permissions
    for (final permission in permissionsToRequest) {
      final status = await permission.status;
      if (status.isGranted) {
        continue;
      }

      // Request permission
      final result = await permission.request();
      if (!result.isGranted) {
        deniedPermissions.add(permission);
      }
    }

    // If any permissions were denied, show user-friendly dialog
    if (deniedPermissions.isNotEmpty) {
      final permissionNames = deniedPermissions
          .map((p) => _getPermissionDisplayName(p))
          .join(', ');

      if (mounted) {
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: Text(
              'The following permissions are required to broadcast as a beacon:\n\n'
              '$permissionNames\n\n'
              'Some permissions may have been permanently denied. '
              'Would you like to open app settings to grant them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );

        if (shouldOpenSettings == true) {
          await openAppSettings();
          // Re-check permissions after returning from settings
          await Future.delayed(const Duration(milliseconds: 500));
          await _checkPermissionsStatus();

          // Check again if all permissions are now granted
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
      } else {
        throw Exception('Permission denied: $permissionNames');
      }
    }

    // Update permission status
    if (mounted) {
      setState(() {
        _permissionsGranted = true;
      });
    }
  }

  /// Get user-friendly name for permission
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

  _WaypointOption get _currentWaypoint => _waypointOptions.firstWhere(
    (option) => option.number == _selectedWaypoint,
  );

  /// Alternative broadcasting method using FlutterBluePlus directly
  /// This is a fallback if beacon_broadcast library fails
  Future<void> _startAlternativeBroadcast() async {
    print('🔄 Trying alternative broadcast method...');

    try {
      final waypoint = _currentWaypoint;

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

      // Note: FlutterBluePlus doesn't have direct stopAdvertising method
      // The alternative method will be used as fallback only

      // Build iBeacon manufacturer data
      final manufacturerData = _buildIBeaconData(waypoint);

      print('Alternative broadcast attempt:');
      print('  Name: BEACON_${waypoint.number}');
      print('  Service UUID: ${waypoint.uuid}');
      print(
        '  Manufacturer Data: ${manufacturerData[0x004C]?.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      // Note: FlutterBluePlus doesn't support direct advertising in the same way
      // This alternative method is a placeholder - the beacon_broadcast library
      // should be the primary method. If it fails, we log the error but can't
      // use FlutterBluePlus as a direct replacement.
      print('⚠️ FlutterBluePlus doesn\'t support direct iBeacon advertising');
      print('   Please ensure beacon_broadcast library is working correctly');

      // We can't actually start advertising with FlutterBluePlus directly
      // This is just for logging purposes
      throw Exception(
        'Alternative broadcast method not available - FlutterBluePlus doesn\'t support direct advertising',
      );
    } catch (e) {
      print('❌ Alternative broadcast failed: $e');
      rethrow;
    }
  }

  /// Helper to log beacon details during self-scan test
  void _logBeaconDetails(
    ScanResult result,
    List<int> data,
    _WaypointOption waypoint,
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

  /// Run a self-scan test to verify the device is broadcasting
  Future<void> _runSelfScanTest(_WaypointOption waypoint) async {
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

  /// Build proper iBeacon manufacturer data
  Map<int, List<int>> _buildIBeaconData(_WaypointOption waypoint) {
    // Build proper iBeacon manufacturer data
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

  Widget _renderBroadcastInsights(ThemeData theme) {
    final waypoint = _currentWaypoint;
    final isActive = _isAdvertising;
    final statusColor = _broadcastStatusColor(isActive);
    final statusLabel = isActive ? 'Broadcasting' : 'Idle';
    final statusDetail = _statusMessage;

    return Card(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Broadcast health', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
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
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.black.withOpacity(0.1)),
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            Divider(color: Colors.black.withOpacity(0.1)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _permissionsGranted ? Icons.check_circle : Icons.warning,
                  color: _permissionsGranted ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _permissionsGranted
                        ? 'All permissions granted'
                        : 'Permissions required',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _permissionsGranted ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_permissionsGranted)
                  TextButton(
                    onPressed: _checkAndRequestPermissions,
                    child: const Text('Grant'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Check and request permissions proactively
  Future<void> _checkAndRequestPermissions() async {
    try {
      await _ensurePermissions();
      // Re-check status after granting
      await _checkPermissionsStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All permissions granted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Re-check status even on error (user might have granted some)
      await _checkPermissionsStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _broadcastStatusColor(bool isActive) {
    if (isActive) {
      return Colors.greenAccent.shade400;
    }
    if (_isBusy) {
      return Colors.orangeAccent;
    }
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canStart = !_isAdvertising && !_isBusy && _permissionsGranted;
    final canStop = _isAdvertising && !_isBusy;

    return Scaffold(
      appBar: AppBar(title: const Text('Beacon Mode')),
      body: SafeArea(
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
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Waypoint',
                  border: OutlineInputBorder(),
                ),
                value: _selectedWaypoint,
                items: _waypointOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.number,
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
                onChanged: _isBusy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedWaypoint = value;
                        });
                      },
              ),
              const SizedBox(height: 24),
              _renderBroadcastInsights(theme),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: canStart ? _startBroadcasting : null,
                    child: Text(
                      _isBusy && !_isAdvertising
                          ? 'Starting...'
                          : 'Start Broadcasting',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: canStop ? _stopBroadcasting : null,
                    child: Text(
                      _isBusy && _isAdvertising
                          ? 'Stopping...'
                          : 'Stop Broadcasting',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
