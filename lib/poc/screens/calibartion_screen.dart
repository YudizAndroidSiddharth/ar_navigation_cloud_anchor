import 'dart:async';
import 'dart:io';

import 'package:ar_navigation_cloud_anchor/poc/services/ble_navigation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class CalibrationSample {
  final DateTime timestamp;
  final String deviceId;
  final int rawRssi;
  final double smoothedRssi;
  final String distanceLabel;
  final String manufacturerData;
  final List<String> serviceUuids;

  CalibrationSample({
    required this.timestamp,
    required this.deviceId,
    required this.rawRssi,
    required this.smoothedRssi,
    required this.distanceLabel,
    required this.manufacturerData,
    required this.serviceUuids,
  });

  /// CSV style line – easy to paste into a file later.
  String toCsv() {
    final ts = timestamp.toIso8601String();
    final services = serviceUuids.join('|');
    final manuf = manufacturerData.replaceAll(',', ';');
    return '$ts,$deviceId,$distanceLabel,$rawRssi,'
        '${smoothedRssi.toStringAsFixed(1)},$manuf,$services';
  }

  /// Log line for console
  String toLogLine() {
    return '[CALIB] ${timestamp.toIso8601String()} '
        'dev=$deviceId dist=$distanceLabel '
        'raw=$rawRssi smooth=${smoothedRssi.toStringAsFixed(1)} '
        'manuf=$manufacturerData services=${serviceUuids.join('|')}';
  }
}

class BeaconCalibrationScreen extends StatefulWidget {
  const BeaconCalibrationScreen({super.key});

  @override
  State<BeaconCalibrationScreen> createState() =>
      _BeaconCalibrationScreenState();
}

class _BeaconCalibrationScreenState extends State<BeaconCalibrationScreen> {
  final BleNavigationService _bleService = BleNavigationService();

  final List<CalibrationSample> _samples = [];
  final Map<String, double> _smoothedRssi = {};
  final TextEditingController _labelController = TextEditingController(
    text: '0m',
  );

  bool _isScanning = false;
  String _currentLabel = '0m';
  int _scanCycleCount = 0;

  /// Optional: restrict to specific beacon MAC addresses
  /// (fill this once you know your beacon IDs, e.g. "AA:BB:CC:DD:EE:01")
  final Set<String> _allowedDevices = {
    '6B:14:28:14:EF:C5',
    // 'AA:BB:CC:DD:EE:02',
  };

  @override
  void dispose() {
    _bleService.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _samples.clear();
      _smoothedRssi.clear();
      _scanCycleCount = 0;
      _currentLabel = _labelController.text.trim().isEmpty
          ? 'unknown'
          : _labelController.text.trim();
      _isScanning = true;
    });

    try {
      // await _bleService.startOptimizedBleScanning(
      //   // we always let the service call our permission helper:
      //   permissionsGranted: false,
      //   ensurePermissions: _ensurePermissions,
      //   ensureBluetoothEnabled: _ensureBluetoothEnabled,
      //   scanRestartInterval: const Duration(seconds: 15),
      //   timeoutTickInterval: const Duration(seconds: 5),
      //   onScanResults: _handleScanResults,
      //   onRestart: () {
      //     setState(() => _scanCycleCount++);
      //   },
      //   onTimeoutTick: () {
      //     // you could also log a timeout tick if you want
      //   },
      // );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('BLE scan failed: $e')));
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _stopScan() async {
    await _bleService.stopScanning();
    if (!mounted) return;
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _clearSamples() async {
    setState(() {
      _samples.clear();
      _smoothedRssi.clear();
      _scanCycleCount = 0;
    });
  }

  Future<void> _copyCsvToClipboard() async {
    if (_samples.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln(
      'timestamp,deviceId,distanceLabel,rawRssi,smoothedRssi,manufacturerData,serviceUuids',
    );
    for (final s in _samples) {
      buffer.writeln(s.toCsv());
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calibration data copied to clipboard')),
    );
  }

  Future<void> _ensurePermissions() async {
    final permissions = <Permission>[
      Permission.locationWhenInUse,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ],
    ];

    final denied = <Permission>[];

    for (final p in permissions) {
      final status = await p.status;
      if (status.isGranted) continue;

      final result = await p.request();
      if (!result.isGranted) {
        denied.add(p);
      }
    }

    if (denied.isNotEmpty && mounted) {
      final names = denied.join(', ');
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Permissions required'),
            content: Text(
              'Please grant these permissions to run calibration:\n\n$names',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _ensureBluetoothEnabled() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 15));
    }
  }

  void _handleScanResults(List<ScanResult> results) {
    final now = DateTime.now();

    for (final r in results) {
      final deviceId = r.device.remoteId.toString();

      // Optional filter for just your beacons
      if (_allowedDevices.isNotEmpty && !_allowedDevices.contains(deviceId)) {
        continue;
      }

      final raw = r.rssi;
      const alpha = 0.3; // smoothing factor
      final prev = _smoothedRssi[deviceId];
      final smooth = prev == null
          ? raw.toDouble()
          : alpha * raw + (1 - alpha) * prev;
      _smoothedRssi[deviceId] = smooth;

      final adv = r.advertisementData;
      final manuf = _formatManufacturerData(adv.manufacturerData);

      final sample = CalibrationSample(
        timestamp: now,
        deviceId: deviceId,
        rawRssi: raw,
        smoothedRssi: smooth,
        distanceLabel: _currentLabel,
        manufacturerData: manuf,
        serviceUuids: adv.serviceUuids.map((uuid) => uuid.toString()).toList(),
      );

      _samples.add(sample);
      // Print to console for easy raw capture (flutter logs)
      debugPrint(sample.toLogLine());
    }

    if (mounted) {
      setState(() {});
    }
  }

  String _formatManufacturerData(Map<int, List<int>> data) {
    if (data.isEmpty) return '';
    final entries = <String>[];
    data.forEach((id, bytes) {
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      entries.add('$id:$hex');
    });
    return entries.join('|');
  }

  @override
  Widget build(BuildContext context) {
    final deviceCount = _smoothedRssi.keys.length; // how many distinct devices

    return Scaffold(
      appBar: AppBar(title: const Text('Beacon Calibration')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '1. Enter the actual distance from the beacon (e.g. 0m, 0.5m, 1m, 2m, 3m).\n'
                  '2. Tap "Start scan". Keep phone at that distance for ~30–60s.\n'
                  '3. Tap "Stop" and then "Copy CSV" to export.\n'
                  '4. Repeat for other distances.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'Distance label',
                      hintText: 'e.g. 0m, 0.5m, 1m, 2m, 3m',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      setState(() {
                        _currentLabel = _labelController.text.trim().isEmpty
                            ? 'unknown'
                            : _labelController.text.trim();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Current: $_currentLabel',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start scan'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? _stopScan : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _samples.isEmpty ? null : _copyCsvToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy CSV'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _samples.isEmpty ? null : _clearSamples,
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Status: ${_isScanning ? 'Scanning…' : 'Stopped'}  '
                '| Samples: ${_samples.length}  '
                '| Devices: $deviceCount  '
                '| Scan cycles: $_scanCycleCount',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _samples.isEmpty
                  ? const Center(child: Text('No samples yet – start a scan.'))
                  : ListView.builder(
                      itemCount: _samples.length.clamp(0, 200),
                      itemBuilder: (context, index) {
                        // show last up to 200 samples
                        final sample = _samples[_samples.length - 1 - index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            'dev: ${sample.deviceId}  dist: ${sample.distanceLabel}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            'raw=${sample.rawRssi}  '
                            'smooth=${sample.smoothedRssi.toStringAsFixed(1)}\n'
                            'manuf=${sample.manufacturerData}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
