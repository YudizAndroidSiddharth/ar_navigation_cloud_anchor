import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/saved_location.dart';
import '../services/filtered_location_service.dart';
import '../utils/geo_utils.dart';

class PocNavigationScreen extends StatefulWidget {
  final SavedLocation target;
  const PocNavigationScreen({super.key, required this.target});

  @override
  State<PocNavigationScreen> createState() => _PocNavigationScreenState();
}

class _PocNavigationScreenState extends State<PocNavigationScreen> {
  static const double reachThresholdMeters = 10.0;

  final FilteredLocationService _service = FilteredLocationService();
  StreamSubscription<LatLng>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  LatLng? _current;
  double? _heading; // 0..360
  double? _distanceMeters;
  bool _shownSuccess = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _service.start();
    _posSub = _service.filteredPosition$.listen((p) {
      setState(() {
        _current = p;
        _distanceMeters = Geolocator.distanceBetween(
          p.lat,
          p.lng,
          widget.target.latitude,
          widget.target.longitude,
        );
      });
      _checkReached();
    });
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        _heading = event.heading; // can be null during calibration
      });
    });
  }

  void _checkReached() {
    if (_shownSuccess) return;
    final d = _distanceMeters;
    if (d != null && d <= reachThresholdMeters) {
      _shownSuccess = true;
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: Text('You have reached "${widget.target.name}".'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _service.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heading = _heading;
    final hasHeading = heading != null;
    final current = _current;

    double arrowRadians = 0.0;
    if (current != null && hasHeading) {
      final bearing = bearingBetween(
        current.lat,
        current.lng,
        widget.target.latitude,
        widget.target.longitude,
      );
      final relativeDeg = (bearing - heading + 360.0) % 360.0;
      arrowRadians = relativeDeg * (math.pi / 180.0);
    }

    final distanceText = _distanceMeters == null
        ? '--.- m away'
        : '${_distanceMeters!.toStringAsFixed(1)} m away';

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigate to ${widget.target.name}'),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0f2027), Color(0xFF203a43), Color(0xFF2c5364)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 48),
            Expanded(
              child: Center(
                child: Transform.rotate(
                  angle: arrowRadians,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.navigation,
                      size: 120,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Text(
                    distanceText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasHeading
                        ? 'Turn until the arrow points up, then walk forward.'
                        : 'Calibrating compass… move your phone in a figure-8.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
