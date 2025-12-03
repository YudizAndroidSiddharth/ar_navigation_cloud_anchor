import 'dart:convert';

import 'package:ar_navigation_cloud_anchor/poc/screens/poc_navigation_screen/poc_navigation_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ar_navigation_cloud_anchor/poc/models/saved_location.dart';
import 'package:ar_navigation_cloud_anchor/poc/storage/location_storage.dart';
import 'package:ar_navigation_cloud_anchor/poc/utils/pref_utiles.dart';
import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';
import 'package:ar_navigation_cloud_anchor/poc/utils/geo_utils.dart';

class SelectFeedingZoneScreen extends StatefulWidget {
  const SelectFeedingZoneScreen({super.key});

  @override
  State<SelectFeedingZoneScreen> createState() =>
      _SelectFeedingZoneScreenState();
}

class _SelectFeedingZoneScreenState extends State<SelectFeedingZoneScreen> {
  final LocationStorage _storage = LocationStorage();
  final TextEditingController _searchController = TextEditingController();

  List<SavedLocation> _allLocations = [];
  List<SavedLocation> _filteredLocations = [];
  SavedLocation? _selectedLocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadLocations() async {
    final locations = await _storage.getLocations();
    final selectedRaw = PrefUtils().getSelectedPlatform();
    SavedLocation? selected;
    if (selectedRaw != null && selectedRaw.isNotEmpty) {
      try {
        final data = jsonDecode(selectedRaw) as Map<String, dynamic>;
        final name = data['name'] as String?;
        final latitude = (data['latitude'] as num?)?.toDouble();
        final longitude = (data['longitude'] as num?)?.toDouble();
        if (name != null && latitude != null && longitude != null) {
          for (final loc in locations) {
            if (loc.name == name &&
                loc.latitude == latitude &&
                loc.longitude == longitude) {
              selected = loc;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _allLocations = locations;
      _filteredLocations = List.from(locations);
      _selectedLocation = selected;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredLocations = List.from(_allLocations);
      } else {
        _filteredLocations = _allLocations
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _onSelectLocation(SavedLocation location) {
    setState(() => _selectedLocation = location);
  }

  Future<void> _onNextPressed() async {
    if (_selectedLocation == null) {
      SnackBarUtil.showErrorSnackbar(context, 'कृपया पहले एक प्लेटफॉर्म चुनें');
      return;
    }
    final payload = jsonEncode({
      'name': _selectedLocation!.name,
      'latitude': _selectedLocation!.latitude,
      'longitude': _selectedLocation!.longitude,
    });
    await PrefUtils().setSelectedPlatform(payload);
    if (!mounted) return;
    SnackBarUtil.showSuccessSnackbar(context, 'प्लेटफॉर्म चुना गया');
    final routePoints = _buildRoutePoints(_selectedLocation!);
    debugPrint('🗺️ [SelectFeedingZone] Navigating to PocNavigationScreen with ${routePoints.length} routePoints');
    navigator?.push(
      MaterialPageRoute(
        builder: (context) => PocNavigationScreen(
          target: _selectedLocation!,
          routePoints: routePoints,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildTopBar(context),
                  _buildSearchBar(),
                  Expanded(
                    child: _filteredLocations.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: _filteredLocations.length,
                            itemBuilder: (context, index) {
                              final item = _filteredLocations[index];
                              final isSelected = _selectedLocation == item;
                              return _buildLocationCard(item, isSelected);
                            },
                          ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _renderBottomButton(context),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, statusBarHeight + 8, 8, 12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: const Color(0xFF3C8C4E),
          ),
          Expanded(
            child: Text(
              'प्लेटफॉर्म चुने',
              style: GoogleFonts.notoSansDevanagari(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F1F1F),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu, color: Color(0xFF3C8C4E)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(30),
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'खोजें',
            hintStyle: GoogleFonts.notoSansDevanagari(color: Colors.grey[600]),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF3C8C4E)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: GoogleFonts.notoSansDevanagari(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'कोई प्लेटफॉर्म उपलब्ध नहीं है',
        style: GoogleFonts.notoSansDevanagari(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildLocationCard(SavedLocation item, bool isSelected) {
    return GestureDetector(
      onTap: () => _onSelectLocation(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? const Color(0xFF3C8C4E) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF3C8C4E).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on, color: Color(0xFF3C8C4E)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.name,
                style: GoogleFonts.notoSansDevanagari(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F1F1F),
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => _onSelectLocation(item),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3C8C4E)
                      : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the ordered navigation route from the selected Feeding Zone.
  ///
  /// Priority:
  /// 1. If routePoints exist: waypoints (sorted by order) + destination.
  /// 2. If no routePoints: fall back to a simple route with just destination.
  List<LatLng> _buildRoutePoints(SavedLocation location) {
    debugPrint('🗺️ [SelectFeedingZone] Building route for zone: ${location.name}');
    debugPrint('🗺️ [SelectFeedingZone] Total routePoints in SavedLocation: ${location.routePoints.length}');
    
    if (location.routePoints.isNotEmpty) {
      final waypoints = location.routePoints
          .where((p) => p.type == RoutePointType.waypoint)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final destinations = location.routePoints
          .where((p) => p.type == RoutePointType.destination)
          .toList();

      debugPrint('🗺️ [SelectFeedingZone] Found ${waypoints.length} waypoints, ${destinations.length} destinations');

      final points = <LatLng>[];
      for (final wp in waypoints) {
        points.add(LatLng(wp.latitude, wp.longitude));
        debugPrint('🗺️ [SelectFeedingZone] Added waypoint ${wp.order}: lat=${wp.latitude.toStringAsFixed(6)}, lng=${wp.longitude.toStringAsFixed(6)}');
      }

      if (destinations.isNotEmpty) {
        final dest = destinations.first;
        points.add(LatLng(dest.latitude, dest.longitude));
        debugPrint('🗺️ [SelectFeedingZone] Added destination: lat=${dest.latitude.toStringAsFixed(6)}, lng=${dest.longitude.toStringAsFixed(6)}');
      } else {
        // Always add destination at the end, even if not explicitly set in routePoints.
        // This ensures waypoints connect to a final destination.
        // Use SavedLocation coordinates as the destination fallback.
        points.add(LatLng(location.latitude, location.longitude));
        debugPrint('🗺️ [SelectFeedingZone] Added destination (fallback from SavedLocation): lat=${location.latitude.toStringAsFixed(6)}, lng=${location.longitude.toStringAsFixed(6)}');
      }

      if (points.isNotEmpty) {
        debugPrint('🗺️ [SelectFeedingZone] Final routePoints count: ${points.length}');
        for (var i = 0; i < points.length; i++) {
          debugPrint('🗺️ [SelectFeedingZone] Route[$i]: lat=${points[i].lat.toStringAsFixed(6)}, lng=${points[i].lng.toStringAsFixed(6)}');
        }
        return points;
      }
    }

    // Backward compatible fallback: only the final destination.
    debugPrint('🗺️ [SelectFeedingZone] No routePoints found, using fallback destination only');
    final fallback = [
      LatLng(location.latitude, location.longitude),
    ];
      debugPrint('🗺️ [SelectFeedingZone] Fallback route[0]: lat=${fallback[0].lat.toStringAsFixed(6)}, lng=${fallback[0].lng.toStringAsFixed(6)}');
    return fallback;
  }

  Widget _renderBottomButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _onNextPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3C8C4E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
            elevation: 0,
          ),
          child: Text(
            'आगे बढ़ें',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
