import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:ar_navigation_cloud_anchor/screens/admin/venue_detail_screen.dart';
import 'package:flutter/material.dart';
import '../../services/venue_service.dart';

class VenueCreationScreen extends StatefulWidget {
  final Venue? editVenue; // null for new venue, existing venue for editing

  VenueCreationScreen({this.editVenue});

  @override
  _VenueCreationScreenState createState() => _VenueCreationScreenState();
}

class _VenueCreationScreenState extends State<VenueCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueService = VenueService();

  bool _isLoading = false;
  bool get _isEditing => widget.editVenue != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.editVenue!.name;
      _descriptionController.text = widget.editVenue!.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Venue' : 'Create New Venue'),
        backgroundColor: Colors.orange[600],
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _showDeleteConfirmation,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Header Card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.business,
                          color: Colors.orange[600],
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Venue Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Venue Name *',
                        hintText: 'e.g., Central Office Building',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Venue name is required';
                        }
                        if (value.trim().length < 3) {
                          return 'Venue name must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Brief description of the venue',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Description is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Quick Setup Card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.rocket_launch,
                          color: Colors.blue[600],
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Quick Setup Options',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    _buildQuickSetupOption(
                      icon: Icons.auto_awesome,
                      title: 'Sample Venue',
                      description: 'Create with sample destinations and layout',
                      onTap: _createSampleVenue,
                    ),
                    SizedBox(height: 8),
                    _buildQuickSetupOption(
                      icon: Icons.create,
                      title: 'Custom Setup',
                      description:
                          'Create empty venue and add content manually',
                      onTap: _createCustomVenue,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Info Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[600]),
                        SizedBox(width: 8),
                        Text(
                          'Next Steps',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• After creating venue, you can add anchor points\n'
                      '• Set up destinations and navigation paths\n'
                      '• Test AR navigation in your physical space\n'
                      '• Refine and optimize anchor placement',
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32),

            // Action Buttons
            if (_isEditing) ...[
              ElevatedButton(
                onPressed: _isLoading ? null : _updateVenue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  padding: EdgeInsets.all(16),
                ),
                child: _isLoading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Updating...'),
                        ],
                      )
                    : Text('Update Venue', style: TextStyle(fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSetupOption({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[600]),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  Text(
                    description,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _createSampleVenue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use the VenueService method to create sample venue
      final venue = await _venueService.createSampleVenue(
        _nameController.text.trim(),
        _descriptionController.text.trim(),
      );

      _navigateToVenueDetail(venue);
    } catch (e) {
      _showErrorMessage('Error creating sample venue: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createCustomVenue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final venue = Venue(
        id: 'venue_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        destinations: [], // Empty - user will add manually
        anchors: [],
        origin: AnchorPosition(x: 0, y: 0),
      );

      final success = await _venueService.saveVenue(venue);

      if (success) {
        _navigateToVenueDetail(venue);
      } else {
        _showErrorMessage('Failed to create venue. Please try again.');
      }
    } catch (e) {
      _showErrorMessage('Error creating custom venue: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateVenue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedVenue = widget.editVenue!.copyWith(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        updatedAt: DateTime.now(),
      );

      final success = await _venueService.saveVenue(updatedVenue);

      if (success) {
        Navigator.pop(context, updatedVenue);
      } else {
        _showErrorMessage('Failed to update venue. Please try again.');
      }
    } catch (e) {
      _showErrorMessage('Error updating venue: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToVenueDetail(Venue venue) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => VenueDetailScreen(venue: venue)),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Venue'),
        content: Text(
          'Are you sure you want to delete "${widget.editVenue!.name}"? '
          'This will also delete all associated anchors and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _deleteVenue,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteVenue() async {
    Navigator.pop(context); // Close dialog

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _venueService.deleteVenue(widget.editVenue!.id);

      if (success) {
        Navigator.pop(context, 'deleted');
      } else {
        _showErrorMessage('Failed to delete venue. Please try again.');
      }
    } catch (e) {
      _showErrorMessage('Error deleting venue: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
