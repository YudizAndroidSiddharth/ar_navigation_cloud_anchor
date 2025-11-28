import 'package:flutter/foundation.dart';
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
      // Get position with timeout to prevent hanging
      final position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 10),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('GPS timeout: Unable to get current position');
            },
          );

      // Validate position coordinates
      if (!position.latitude.isFinite || !position.longitude.isFinite) {
        throw Exception('Invalid GPS coordinates received');
      }

      // Validate coordinate ranges
      if (position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        throw Exception('GPS coordinates out of valid range');
      }

      // Validate accuracy if available
      if (position.accuracy.isFinite && position.accuracy > 100) {
        // Warn but don't fail - low accuracy is acceptable for some use cases
        debugPrint('⚠️ Low GPS accuracy: ${position.accuracy}m');
      }

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
      final errorMessage = e.toString().replaceAll('Exception: ', '');
      SnackBarUtil.showErrorSnackbar(
        context,
        'लोकेशन सेव नहीं हो पाया: $errorMessage',
      );
      debugPrint('❌ Error saving location: $e');
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
          child: Text(
            '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteLocation(loc),
        ),
      ),
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
