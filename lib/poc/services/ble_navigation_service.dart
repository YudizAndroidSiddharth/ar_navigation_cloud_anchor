import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE navigation helper service responsible only for orchestrating
/// low-level scan operations and timers. All business logic lives
/// inside the controller via callbacks.
class BleNavigationService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanRestartTimer;
  Timer? _deviceTimeoutTimer;

  StreamSubscription<List<ScanResult>>? get scanSubscription =>
      _scanSubscription;

  Timer? get scanRestartTimer => _scanRestartTimer;

  Timer? get deviceTimeoutTimer => _deviceTimeoutTimer;

  Future<void> startOptimizedBleScanning({
    required bool permissionsGranted,
    required Future<void> Function() ensurePermissions,
    required Future<void> Function() ensureBluetoothEnabled,
    required Duration scanRestartInterval,
    required Duration timeoutTickInterval,
    required void Function(List<ScanResult>) onScanResults,
    required VoidCallback onRestart,
    required VoidCallback onTimeoutTick,
  }) async {
    if (!permissionsGranted) {
      await ensurePermissions();
    }

    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      throw Exception('BLE not supported on this device');
    }

    await ensureBluetoothEnabled();
    await _resetAndStartScanning(onScanResults);

    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer.periodic(scanRestartInterval, (
      Timer timer,
    ) async {
      onRestart();
      await _resetAndStartScanning(onScanResults);
    });

    _deviceTimeoutTimer?.cancel();
    _deviceTimeoutTimer = Timer.periodic(
      timeoutTickInterval,
      (_) => onTimeoutTick(),
    );
  }

  Future<void> _resetAndStartScanning(
    void Function(List<ScanResult>) onScanResults,
  ) async {
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 200));

    await FlutterBluePlus.startScan(
      timeout: null,
      androidUsesFineLocation: true,
    );

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        onScanResults(results);
      }
    });
  }

  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanRestartTimer?.cancel();
    _deviceTimeoutTimer?.cancel();
  }

  Future<void> dispose() async {
    await stopScanning();
  }
}
