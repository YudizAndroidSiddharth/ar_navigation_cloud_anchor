import 'dart:async';

import 'package:ar_navigation_cloud_anchor/poc/screens/calibartion_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/saved_location.dart';
import '../../storage/location_storage.dart';
import '../poc_navigation_screen/poc_navigation_screen.dart';

/// Home screen for the POC:
/// - Save current location with a name
/// - List saved locations
/// - Start navigation to a selected location
class PocHomeScreen extends StatefulWidget {
  const PocHomeScreen({super.key});

  @override
  State<PocHomeScreen> createState() => _PocHomeScreenState();
}

class _PocHomeScreenState extends State<PocHomeScreen> {
  final LocationStorage _storage = LocationStorage();

  List<SavedLocation> _locations = const [];
  SavedLocation? _selected;

  bool _permissionDenied = false;
  bool _serviceDisabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _ensurePermission();
    await _loadLocations();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _serviceDisabled = true;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final denied =
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;

    if (!mounted) return;
    setState(() {
      _permissionDenied = denied;
      _serviceDisabled = false;
    });
  }

  Future<void> _loadLocations() async {
    final list = await _storage.getLocations();
    if (!mounted) return;
    setState(() {
      _locations = list;
      if (_selected == null && list.isNotEmpty) {
        _selected = list.first;
      }
    });
  }

  Future<void> _saveCurrentLocation() async {
    try {
      // Use bestForNavigation for more stable data if available
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      final name = await _askForName();
      if (!mounted || name == null) return;

      final trimmed = name.trim();
      if (trimmed.isEmpty) return;

      final loc = SavedLocation(
        name: trimmed,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      await _storage.addLocation(loc);
      await _loadLocations();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save location: $e')));
    }
  }

  Future<String?> _askForName() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Name this location'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'e.g. Barn 1'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _openAppSettings() {
    Geolocator.openAppSettings();
  }

  void _openLocationSettings() {
    Geolocator.openLocationSettings();
  }

  void _startNavigation() {
    final target = _selected;
    if (target == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PocNavigationScreen(target: target)),
    );
  }

  void _openBeaconMode() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BeaconCalibrationScreen()));
  }

  bool get _canSaveLocation => !_permissionDenied && !_serviceDisabled;

  bool get _canStartNavigation =>
      _selected != null && !_permissionDenied && !_serviceDisabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POC: Outdoor Navigation'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_serviceDisabled)
                      Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          leading: const Icon(
                            Icons.gps_off,
                            color: Colors.orange,
                          ),
                          title: const Text('Location services are disabled'),
                          subtitle: const Text('Enable GPS/location services'),
                          trailing: TextButton(
                            onPressed: _openLocationSettings,
                            child: const Text('Open Settings'),
                          ),
                        ),
                      ),
                    if (_permissionDenied && !_serviceDisabled)
                      Card(
                        color: Colors.red.shade50,
                        child: ListTile(
                          leading: const Icon(Icons.lock, color: Colors.red),
                          title: const Text('Location permission required'),
                          subtitle: const Text(
                            'Grant location permission to continue',
                          ),
                          trailing: TextButton(
                            onPressed: _openAppSettings,
                            child: const Text('Open Settings'),
                          ),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _canSaveLocation ? _saveCurrentLocation : null,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Save Current Location'),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _locations.isEmpty
                          ? const Center(child: Text('No saved locations yet'))
                          : ListView.separated(
                              itemCount: _locations.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final loc = _locations[index];
                                final selected = _selected == loc;
                                return ListTile(
                                  leading: Radio<SavedLocation>(
                                    value: loc,
                                    groupValue: _selected,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() => _selected = val);
                                    },
                                  ),
                                  title: Text(loc.name),
                                  subtitle: Text(
                                    '${loc.latitude.toStringAsFixed(6)}, '
                                    '${loc.longitude.toStringAsFixed(6)}',
                                  ),
                                  trailing: selected
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.green,
                                        )
                                      : null,
                                  onTap: () => setState(() => _selected = loc),
                                );
                              },
                            ),
                    ),

                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _canStartNavigation ? _startNavigation : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
