import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Simplified BLE Navigation Service for continuous scanning
/// Optimized for production use without restart complexity
class BleNavigationService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  bool _isScanning = false;
  bool _isDisposed = false;

  /// Start continuous BLE scanning
  /// No restart logic - keeps scanning until explicitly stopped
  Future<void> startContinuousScanning({
    required Function(List<ScanResult>) onScanResults,
    required Function(String) onError,
    required Function() onBluetoothStateChanged,
  }) async {
    if (_isDisposed) {
      throw Exception('Service is disposed');
    }

    try {
      // Stop any existing scan
      await stopScanning();

      // Ensure Bluetooth is ready
      await _ensureBluetoothReady();

      debugPrint('🚀 Starting continuous BLE scanning');

      // Start scan with no timeout (continuous)
      await FlutterBluePlus.startScan(
        timeout: null, // Continuous scanning
        continuousUpdates: true, // Critical for real-time updates
        continuousDivisor: 1, // Process all advertisements
        oneByOne: false, // Deduplicated list mode
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        onScanResults,
        onError: (error) {
          debugPrint('❌ BLE scan error: $error');
          onError('BLE scan error: $error');
        },
      );

      // Monitor Bluetooth adapter state
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state != BluetoothAdapterState.on) {
          debugPrint('🔵 Bluetooth state changed: $state');
          _isScanning = false;
          onBluetoothStateChanged();
        } else if (!_isScanning) {
          // Restart scanning when Bluetooth comes back
          _restartScanningInternal(onScanResults, onError);
        }
      });

      _isScanning = true;
      debugPrint('✅ Continuous BLE scanning started successfully');
    } catch (e) {
      debugPrint('❌ Failed to start BLE scanning: $e');
      onError('Failed to start scanning: $e');
      rethrow;
    }
  }

  /// Internal restart method for Bluetooth recovery
  Future<void> _restartScanningInternal(
    Function(List<ScanResult>) onScanResults,
    Function(String) onError,
  ) async {
    if (_isDisposed) return;

    try {
      debugPrint('🔄 Restarting BLE scanning after Bluetooth recovery');

      await FlutterBluePlus.startScan(
        timeout: null,
        continuousUpdates: true,
        continuousDivisor: 1,
        oneByOne: false,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
        withServices: [Guid('1a957d0f-78c2-4c95-bfdf-bf483e7b67ac')],
      );

      _isScanning = true;
      debugPrint('✅ BLE scanning restarted successfully');
    } catch (e) {
      debugPrint('❌ Failed to restart BLE scanning: $e');
      onError('Failed to restart scanning: $e');
    }
  }

  /// Ensure Bluetooth is ready for scanning
  Future<void> _ensureBluetoothReady() async {
    final adapterState = await FlutterBluePlus.adapterState.first;

    if (adapterState != BluetoothAdapterState.on) {
      if (adapterState == BluetoothAdapterState.off) {
        debugPrint('📱 Turning on Bluetooth...');
        await FlutterBluePlus.turnOn();
      }

      // Wait for Bluetooth to be ready (with timeout)
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Bluetooth did not turn on'),
          );

      debugPrint('✅ Bluetooth is ready');
    }
  }

  /// Stop scanning and cleanup
  Future<void> stopScanning() async {
    debugPrint('🛑 Stopping BLE scanning');

    try {
      // Always cancel subscription, even if _isScanning is false
      // This ensures cleanup works even if state is inconsistent
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      // Stop the scan if it's running
      if (_isScanning) {
        await FlutterBluePlus.stopScan();
        _isScanning = false;
      }

      debugPrint('✅ BLE scanning stopped');
    } catch (e) {
      debugPrint('⚠️ Error stopping BLE scan: $e');
    }
  }

  /// Check if currently scanning
  bool get isScanning => _isScanning;

  /// Check if service is disposed
  bool get isDisposed => _isDisposed;

  /// Get current Bluetooth adapter state
  Future<BluetoothAdapterState> get bluetoothState async {
    return await FlutterBluePlus.adapterState.first;
  }

  /// Dispose service and cleanup all resources
  Future<void> dispose() async {
    if (_isDisposed) {
      debugPrint('⚠️ BLE service already disposed, skipping');
      return;
    }

    debugPrint('🗑️ Disposing BLE navigation service');

    _isDisposed = true;

    // Cancel adapter subscription first to prevent restart attempts
    try {
      await _adapterSubscription?.cancel();
      _adapterSubscription = null;
      debugPrint('✅ BLE adapter subscription cancelled');
    } catch (e) {
      debugPrint('⚠️ Error cancelling adapter subscription: $e');
    }

    // Stop scanning and cancel scan subscription
    try {
      await stopScanning();
      debugPrint('✅ BLE scanning stopped');
    } catch (e) {
      debugPrint('⚠️ Error stopping BLE scan: $e');
    }

    debugPrint('✅ BLE navigation service disposed');
  }
}

/// Exception thrown when BLE operations fail
class BleNavigationException implements Exception {
  final String message;
  final dynamic originalError;

  const BleNavigationException(this.message, [this.originalError]);

  @override
  String toString() {
    if (originalError != null) {
      return 'BleNavigationException: $message (Original: $originalError)';
    }
    return 'BleNavigationException: $message';
  }
}
