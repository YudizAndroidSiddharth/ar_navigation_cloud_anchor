import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';
import 'package:ar_navigation_cloud_anchor/poc/widgets/custom_button.dart';

import '../../models/saved_location.dart';
import '../../storage/location_storage.dart';

class FeedingZoneScreen extends StatefulWidget {
  const FeedingZoneScreen({super.key});

  @override
  State<FeedingZoneScreen> createState() => _FeedingZoneScreenState();
}

class _FeedingZoneScreenState extends State<FeedingZoneScreen> {
  final LocationStorage _storage = LocationStorage();
  final List<String> _zones = const [
    'गोकुल',
    'वृन्दावन',
    'नंदगाँव',
    'बरसाना',
    'गोवर्धन',
    'रमन रीति',
    'खादिरवन',
    'मधुबन',
    'द्वारका',
    'गोलोक',
    'ब्रिज',
    'काम्यवन',
  ];

  List<SavedLocation> _locations = [];
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
    });
  }

  Future<bool> _saveLocation(String zone, String nickname) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      final trimmedNick = nickname.trim();
      final name = trimmedNick.isEmpty ? zone : '$zone - $trimmedNick';
      final location = SavedLocation(
        name: name,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _storage.addLocation(location);
      await _loadLocations();
      if (!mounted) return false;
      SnackBarUtil.showSuccessSnackbar(context, 'लोकेशन सेव हो गया');
      return true;
    } catch (e) {
      if (!mounted) return false;
      SnackBarUtil.showErrorSnackbar(context, 'लोकेशन सेव नहीं हो पाया: $e');
      return false;
    }
  }

  Future<void> _deleteLocation(SavedLocation location) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('लोकेशन हटाएँ'),
          content: Text('"${location.name}" को हटाना चाहते हैं?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('रद्द करें'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('हटाएँ'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    await _storage.removeLocation(location);
    await _loadLocations();
    if (!mounted) return;
    SnackBarUtil.showInfoSnackbar(context, 'लोकेशन हटाया गया');
  }

  Future<void> _openAddZoneSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _ZoneForm(
          zones: _zones,
          onSubmit: (zone, nickname) => _saveLocation(zone, nickname),
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

  bool get _canAddLocation => !_permissionDenied && !_serviceDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Feeding Zones',
          style: GoogleFonts.notoSansDevanagari(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_serviceDisabled)
                    _buildStatusCard(
                      color: Colors.orange.shade50,
                      icon: Icons.gps_off,
                      iconColor: Colors.orange,
                      title: 'Location services are disabled',
                      subtitle: 'Enable GPS/location services',
                      buttonText: 'Open Settings',
                      onPressed: _openLocationSettings,
                    ),
                  if (_permissionDenied && !_serviceDisabled)
                    _buildStatusCard(
                      color: Colors.red.shade50,
                      icon: Icons.lock,
                      iconColor: Colors.red,
                      title: 'Location permission required',
                      subtitle: 'Grant location permission to continue',
                      buttonText: 'Open Settings',
                      onPressed: _openAppSettings,
                    ),
                  Text(
                    'Saved Feeding Zones',
                    style: GoogleFonts.notoSansDevanagari(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F1F1F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_locations.isEmpty)
                    _buildEmptyState()
                  else
                    ..._locations.map(
                      (loc) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildLocationCard(loc, theme),
                      ),
                    ),
                  const SizedBox(height: 72),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _canAddLocation
            ? _openAddZoneSheet
            : () {
                SnackBarUtil.showWarningSnackbar(
                  context,
                  _serviceDisabled
                      ? 'कृपया GPS सेवा चालू करें'
                      : 'कृपया लोकेशन अनुमति प्रदान करें',
                );
              },
        backgroundColor: const Color(0xFF3C8C4E),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatusCard({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withOpacity(0.1),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3C8C4E).withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, color: Color(0xFF3C8C4E), size: 40),
          const SizedBox(height: 12),
          Text(
            'No feeding zones saved yet',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the + button to add a new zone',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(SavedLocation loc, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3C8C4E).withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _openRouteEditor(loc),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        title: Text(
          loc.name,
          style: GoogleFonts.notoSansDevanagari(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: const Color(0xFF1F1F1F),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              _buildRouteSummary(loc, theme),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteLocation(loc),
        ),
      ),
    );
  }

  Widget _buildRouteSummary(SavedLocation loc, ThemeData theme) {
    final waypoints = loc.routePoints
        .where((p) => p.type == RoutePointType.waypoint)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final destination = loc.routePoints
        .where((p) => p.type == RoutePointType.destination)
        .toList();

    if (waypoints.isEmpty && destination.isEmpty) {
      return Text(
        'No route configured',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
      );
    }

    final wpCount = waypoints.length;
    final hasDestination = destination.isNotEmpty;
    final parts = <String>[];
    if (wpCount > 0) {
      parts.add('$wpCount waypoint${wpCount == 1 ? '' : 's'}');
    }
    if (hasDestination) {
      parts.add('destination');
    }

    return Text(
      'Route: ${parts.join(' + ')}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: const Color(0xFF3C8C4E),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Future<void> _openRouteEditor(SavedLocation loc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return RouteEditorSheet(
          storage: _storage,
          initialLocation: loc,
          onUpdated: _loadLocations,
        );
      },
    );
  }
}

class _ZoneForm extends StatefulWidget {
  const _ZoneForm({required this.zones, required this.onSubmit});

  final List<String> zones;
  final Future<bool> Function(String zone, String nickname) onSubmit;

  @override
  State<_ZoneForm> createState() => _ZoneFormState();
}

class _ZoneFormState extends State<_ZoneForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nicknameController = TextEditingController();
  String? _selectedZone;
  bool _isSaving = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final success = await widget.onSubmit(
      _selectedZone!,
      _nicknameController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'नई फीडिंग ज़ोन जोड़ें',
              style: GoogleFonts.notoSansDevanagari(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Choose zone',
                border: OutlineInputBorder(),
              ),
              value: _selectedZone,
              items: widget.zones
                  .map(
                    (zone) => DropdownMenuItem(value: zone, child: Text(zone)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedZone = value),
              validator: (value) =>
                  value == null ? 'कृपया कोई ज़ोन चुनें' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: CustomButton(
                    text: 'Save',
                    onPressed: _submit,
                    isLoading: _isSaving,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that lets user configure waypoints and destination
/// for a particular Feeding Zone using the current GPS position.
class RouteEditorSheet extends StatefulWidget {
  const RouteEditorSheet({
    required this.storage,
    required this.initialLocation,
    required this.onUpdated,
    super.key,
  });

  final LocationStorage storage;
  final SavedLocation initialLocation;
  final Future<void> Function() onUpdated;

  @override
  State<RouteEditorSheet> createState() => _RouteEditorSheetState();
}

class _RouteEditorSheetState extends State<RouteEditorSheet> {
  late SavedLocation _location;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
  }

  List<RoutePoint> get _sortedWaypoints {
    final list = _location.routePoints
        .where((p) => p.type == RoutePointType.waypoint)
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  RoutePoint? get _destination {
    for (final p in _location.routePoints) {
      if (p.type == RoutePointType.destination) {
        return p;
      }
    }
    return null;
  }

  Future<void> _addOrUpdateWaypoint() async {
    if (_isSaving) return;

    final controller = TextEditingController();
    final waypointNumber = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Which waypoint number is this?'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Waypoint number (1, 2, 3, ...)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  SnackBarUtil.showErrorSnackbar(
                    context,
                    'Please enter a valid positive number',
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (waypointNumber == null) return;

    await _saveCurrentPositionAsPoint(
      type: RoutePointType.waypoint,
      order: waypointNumber,
    );
  }

  Future<void> _setDestination() async {
    if (_isSaving) return;
    await _saveCurrentPositionAsPoint(
      type: RoutePointType.destination,
      order: _sortedWaypoints.length + 1,
      alsoUpdateLocationLatLng: true,
    );
  }

  Future<void> _saveCurrentPositionAsPoint({
    required RoutePointType type,
    required int order,
    bool alsoUpdateLocationLatLng = false,
  }) async {
    setState(() => _isSaving = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      final updatedPoints = List<RoutePoint>.from(_location.routePoints);

      if (type == RoutePointType.destination) {
        // Ensure we only ever have a single destination.
        updatedPoints.removeWhere(
          (p) => p.type == RoutePointType.destination,
        );
      }

      final existingIndex = updatedPoints.indexWhere(
        (p) => p.type == type && p.order == order,
      );
      final newPoint = RoutePoint(
        type: type,
        order: order,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (existingIndex >= 0) {
        updatedPoints[existingIndex] = newPoint;
      } else {
        updatedPoints.add(newPoint);
      }

      // Optionally synchronise the SavedLocation's own destination
      // coordinates so that arrow navigation continues to work even
      // without reading the route.
      final updatedLocation = SavedLocation(
        name: _location.name,
        latitude: alsoUpdateLocationLatLng
            ? position.latitude
            : _location.latitude,
        longitude: alsoUpdateLocationLatLng
            ? position.longitude
            : _location.longitude,
        routePoints: updatedPoints,
      );

      await widget.storage.upsertLocationByName(updatedLocation);
      await widget.onUpdated();

      if (!mounted) return;
      setState(() {
        _location = updatedLocation;
        _isSaving = false;
      });

      SnackBarUtil.showSuccessSnackbar(
        context,
        type == RoutePointType.destination
            ? 'Destination saved for this zone'
            : 'Waypoint $order saved for this zone',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      SnackBarUtil.showErrorSnackbar(
        context,
        'Unable to save location: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final waypoints = _sortedWaypoints;
    final destination = _destination;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Configure Route for "${_location.name}"',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (waypoints.isEmpty && destination == null)
            Text(
              'No route points yet.\nAdd waypoints first, then set destination.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansDevanagari(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waypoints.isNotEmpty)
                  Text(
                    'Waypoints:',
                    style: GoogleFonts.notoSansDevanagari(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (waypoints.isNotEmpty) const SizedBox(height: 8),
                ...waypoints.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Waypoint ${p.order}: '
                      '${p.latitude.toStringAsFixed(6)}, '
                      '${p.longitude.toStringAsFixed(6)}',
                      style: GoogleFonts.notoSansDevanagari(fontSize: 14),
                    ),
                  ),
                ),
                if (destination != null) ...[
                  if (waypoints.isNotEmpty) const SizedBox(height: 12),
                  Text(
                    'Destination:',
                    style: GoogleFonts.notoSansDevanagari(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${destination.latitude.toStringAsFixed(6)}, '
                    '${destination.longitude.toStringAsFixed(6)}',
                    style: GoogleFonts.notoSansDevanagari(fontSize: 14),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CustomButton(
                  text: 'Add waypoint',
                  onPressed: _addOrUpdateWaypoint,
                  isLoading: _isSaving,
                  width: double.infinity,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomButton(
                  text: 'Set destination',
                  onPressed: _setDestination,
                  isLoading: _isSaving,
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
