import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:ar_navigation_cloud_anchor/screens/admin/create_venue_screen.dart';
import 'package:flutter/material.dart';
import '../../services/venue_service.dart';
import 'ar_camera_screen.dart';

class VenueDetailScreen extends StatefulWidget {
  final Venue venue;

  VenueDetailScreen({required this.venue});

  @override
  _VenueDetailScreenState createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  final VenueService _venueService = VenueService();
  late Venue _currentVenue;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentVenue = widget.venue;
    _loadLatestVenueData();
  }

  Future<void> _loadLatestVenueData() async {
    try {
      final venue = await _venueService.getVenueById(widget.venue.id);
      if (venue != null) {
        setState(() {
          _currentVenue = venue;
        });
      }
    } catch (e) {
      print('Error loading venue data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentVenue.name),
        backgroundColor: Colors.orange[600],
        actions: [
          IconButton(icon: Icon(Icons.edit), onPressed: _editVenue),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Export Data'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text(
                    'Delete Venue',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLatestVenueData,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Venue Info Card
                _buildVenueInfoCard(),

                SizedBox(height: 16),

                // Quick Actions
                _buildQuickActionsCard(),

                SizedBox(height: 16),

                // Anchors Section
                _buildAnchorsSection(),

                SizedBox(height: 16),

                // Destinations Section
                _buildDestinationsSection(),

                SizedBox(height: 16),

                // Statistics Card
                _buildStatisticsCard(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAnchorOptions,
        backgroundColor: Colors.blue[600],
        icon: Icon(Icons.add),
        label: Text('Add Anchor'),
      ),
    );
  }

  Widget _buildVenueInfoCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business, color: Colors.orange[600], size: 24),
                SizedBox(width: 8),
                Text(
                  'Venue Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              _currentVenue.description,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  'Updated ${_formatDate(_currentVenue.updatedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _addAnchor(AnchorType.entrance),
                    icon: Icon(Icons.login),
                    label: Text('Add Entrance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _addAnchor(AnchorType.destination),
                    icon: Icon(Icons.place),
                    label: Text('Add Destination'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testNavigation,
                    icon: Icon(Icons.navigation),
                    label: Text('Test Navigation'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _viewMap,
                    icon: Icon(Icons.map),
                    label: Text('View Map'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnchorsSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.anchor, color: Colors.blue[600]),
                    SizedBox(width: 8),
                    Text(
                      'Cloud Anchors (${_currentVenue.anchors.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _showAddAnchorOptions,
                  child: Text('Add More'),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (_currentVenue.anchors.isEmpty)
              _buildEmptyAnchorsState()
            else
              Column(
                children: _currentVenue.anchors.map((anchor) {
                  return _buildAnchorTile(anchor);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAnchorsState() {
    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.anchor, size: 48, color: Colors.grey[400]),
          SizedBox(height: 12),
          Text(
            'No Cloud Anchors Yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Create your first anchor to enable AR navigation in this venue',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _addAnchor(AnchorType.entrance),
            icon: Icon(Icons.add),
            label: Text('Create First Anchor'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAnchorTile(CloudAnchorPoint anchor) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getAnchorTypeColor(anchor.type).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getAnchorTypeIcon(anchor.type),
            color: _getAnchorTypeColor(anchor.type),
          ),
        ),
        title: Text(anchor.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(anchor.description),
            SizedBox(height: 4),
            Row(
              children: [
                _buildStatusChip(anchor.status),
                SizedBox(width: 8),
                if (anchor.quality > 0) _buildQualityChip(anchor.quality),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleAnchorAction(action, anchor),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
            ),
            PopupMenuItem(
              value: 'test',
              child: ListTile(
                leading: Icon(Icons.play_circle_outline),
                title: Text('Test'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationsSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.green[600]),
                SizedBox(width: 8),
                Text(
                  'Destinations (${_currentVenue.destinations.length})',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (_currentVenue.destinations.isEmpty)
              Text('No destinations defined yet')
            else
              Column(
                children: _currentVenue.destinations.take(3).map((dest) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.place, color: Colors.green[600]),
                    title: Text(dest.name),
                    subtitle: Text(dest.category),
                  );
                }).toList(),
              ),
            if (_currentVenue.destinations.length > 3)
              TextButton(
                onPressed: () {
                  // Show all destinations
                },
                child: Text(
                  'View all ${_currentVenue.destinations.length} destinations',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final stats = _calculateStatistics();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Active Anchors',
                    '${stats['activeAnchors']}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Draft Anchors',
                    '${stats['draftAnchors']}',
                    Icons.edit,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Avg Quality',
                    '${(stats['avgQuality'] * 100).toInt()}%',
                    Icons.star,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Coverage',
                    _calculateCoverage(),
                    Icons.wifi,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildStatusChip(AnchorStatus status) {
    Color color;
    String text;

    switch (status) {
      case AnchorStatus.active:
        color = Colors.green;
        text = 'Active';
        break;
      case AnchorStatus.draft:
        color = Colors.orange;
        text = 'Draft';
        break;
      case AnchorStatus.failed:
        color = Colors.red;
        text = 'Failed';
        break;
      case AnchorStatus.uploading:
        color = Colors.blue;
        text = 'Uploading';
        break;
      case AnchorStatus.inactive:
        color = Colors.grey;
        text = 'Inactive';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQualityChip(double quality) {
    final percentage = (quality * 100).toInt();
    Color color;

    if (percentage >= 80) {
      color = Colors.green;
    } else if (percentage >= 60) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$percentage% quality',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showAddAnchorOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Cloud Anchor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Select the type of anchor you want to create:',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            ...AnchorType.values.map((type) {
              return ListTile(
                leading: Icon(
                  _getAnchorTypeIcon(type),
                  color: _getAnchorTypeColor(type),
                ),
                title: Text(_getAnchorTypeLabel(type)),
                subtitle: Text(_getAnchorTypeDescription(type)),
                onTap: () {
                  Navigator.pop(context);
                  _addAnchor(type);
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Future<void> _addAnchor(AnchorType type) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ARCameraScreen(venue: _currentVenue, anchorType: type),
      ),
    );

    if (result != null) {
      // Refresh venue data
      await _loadLatestVenueData();
    }
  }

  void _handleAnchorAction(String action, CloudAnchorPoint anchor) {
    switch (action) {
      case 'edit':
        // TODO: Implement anchor editing
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Anchor editing coming soon')));
        break;
      case 'test':
        // TODO: Implement anchor testing
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Anchor testing coming soon')));
        break;
      case 'delete':
        _deleteAnchor(anchor);
        break;
    }
  }

  Future<void> _deleteAnchor(CloudAnchorPoint anchor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Anchor'),
        content: Text('Are you sure you want to delete "${anchor.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await _venueService.deleteAnchorFromVenue(
          _currentVenue.id,
          anchor.id,
        );

        if (success) {
          await _loadLatestVenueData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Anchor deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception('Failed to delete anchor');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete anchor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _editVenue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VenueCreationScreen(editVenue: _currentVenue),
      ),
    ).then((result) {
      if (result != null && result != 'deleted') {
        _loadLatestVenueData();
      } else if (result == 'deleted') {
        Navigator.pop(context);
      }
    });
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'refresh':
        _loadLatestVenueData();
        break;
      case 'export':
        // TODO: Implement data export
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export feature coming soon')));
        break;
      case 'delete':
        // TODO: Implement venue deletion
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Use edit mode to delete venue')),
        );
        break;
    }
  }

  void _testNavigation() {
    // TODO: Implement navigation testing
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Navigation testing coming soon')));
  }

  void _viewMap() {
    // TODO: Implement map view
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Map view coming soon')));
  }

  Map<String, dynamic> _calculateStatistics() {
    final activeAnchors = _currentVenue.anchors
        .where((a) => a.status == AnchorStatus.active)
        .length;
    final draftAnchors = _currentVenue.anchors
        .where((a) => a.status == AnchorStatus.draft)
        .length;
    final avgQuality = _currentVenue.anchors.isEmpty
        ? 0.0
        : _currentVenue.anchors.map((a) => a.quality).reduce((a, b) => a + b) /
              _currentVenue.anchors.length;

    return {
      'activeAnchors': activeAnchors,
      'draftAnchors': draftAnchors,
      'avgQuality': avgQuality,
    };
  }

  String _calculateCoverage() {
    if (_currentVenue.anchors.isEmpty) return '0%';

    // Simple coverage calculation based on anchor count
    // In a real implementation, this would consider spatial distribution
    final coverage = (_currentVenue.anchors.length * 20).clamp(0, 100);
    return '$coverage%';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'today';
    } else if (difference == 1) {
      return 'yesterday';
    } else {
      return '$difference days ago';
    }
  }

  // Helper methods for anchor types
  Color _getAnchorTypeColor(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return Colors.orange;
      case AnchorType.intersection:
        return Colors.blue;
      case AnchorType.destination:
        return Colors.green;
      case AnchorType.waypoint:
        return Colors.purple;
      case AnchorType.emergency:
        return Colors.red;
    }
  }

  IconData _getAnchorTypeIcon(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return Icons.login;
      case AnchorType.intersection:
        return Icons.call_split;
      case AnchorType.destination:
        return Icons.place;
      case AnchorType.waypoint:
        return Icons.navigation;
      case AnchorType.emergency:
        return Icons.emergency;
    }
  }

  String _getAnchorTypeLabel(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return 'Entrance';
      case AnchorType.intersection:
        return 'Intersection';
      case AnchorType.destination:
        return 'Destination';
      case AnchorType.waypoint:
        return 'Waypoint';
      case AnchorType.emergency:
        return 'Emergency Exit';
    }
  }

  String _getAnchorTypeDescription(AnchorType type) {
    switch (type) {
      case AnchorType.entrance:
        return 'Main access points and doorways';
      case AnchorType.intersection:
        return 'Corridor junctions and decision points';
      case AnchorType.destination:
        return 'Important locations and POIs';
      case AnchorType.waypoint:
        return 'Navigation guidance points';
      case AnchorType.emergency:
        return 'Emergency exits and safety points';
    }
  }
}
