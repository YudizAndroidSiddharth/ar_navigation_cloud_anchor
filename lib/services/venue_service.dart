import 'package:ar_navigation_cloud_anchor/models/anchor_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VenueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _venuesCollection = 'venues';
  static const String _anchorsSubCollection = 'anchors';
  static const String _destinationsSubCollection = 'destinations';

  // Get all venues
  Future<List<Venue>> getAllVenues() async {
    try {
      final querySnapshot = await _firestore
          .collection(_venuesCollection)
          .orderBy('updatedAt', descending: true)
          .get();

      List<Venue> venues = [];

      for (var doc in querySnapshot.docs) {
        final venue = await _buildVenueFromDocument(doc);
        venues.add(venue);
      }

      return venues;
    } catch (e) {
      print('Error loading venues: $e');
      throw Exception('Failed to load venues: $e');
    }
  }

  // Get venue by ID with all subcollections
  Future<Venue?> getVenueById(String id) async {
    try {
      final doc = await _firestore.collection(_venuesCollection).doc(id).get();

      if (!doc.exists) {
        return null;
      }

      return await _buildVenueFromDocument(doc);
    } catch (e) {
      print('Error loading venue: $e');
      return null;
    }
  }

  // Save or update venue
  Future<bool> saveVenue(Venue venue) async {
    try {
      final venueRef = _firestore.collection(_venuesCollection).doc(venue.id);

      // Save main venue data
      await venueRef.set({
        'id': venue.id,
        'name': venue.name,
        'description': venue.description,
        'origin': venue.origin.toMap(),
        'createdAt': venue.createdAt.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // Save anchors as subcollection
      final anchorsRef = venueRef.collection(_anchorsSubCollection);
      for (var anchor in venue.anchors) {
        await anchorsRef.doc(anchor.id).set(anchor.toMap());
      }

      // Save destinations as subcollection
      final destinationsRef = venueRef.collection(_destinationsSubCollection);
      for (var destination in venue.destinations) {
        await destinationsRef.doc(destination.id).set(destination.toMap());
      }

      return true;
    } catch (e) {
      print('Error saving venue: $e');
      return false;
    }
  }

  // Delete venue and all subcollections
  Future<bool> deleteVenue(String venueId) async {
    try {
      final venueRef = _firestore.collection(_venuesCollection).doc(venueId);

      // Delete all anchors
      final anchorsSnapshot = await venueRef
          .collection(_anchorsSubCollection)
          .get();

      for (var doc in anchorsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete all destinations
      final destinationsSnapshot = await venueRef
          .collection(_destinationsSubCollection)
          .get();

      for (var doc in destinationsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete main venue document
      await venueRef.delete();

      return true;
    } catch (e) {
      print('Error deleting venue: $e');
      return false;
    }
  }

  // Add anchor to venue
  Future<bool> addAnchorToVenue(String venueId, CloudAnchorPoint anchor) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_anchorsSubCollection)
          .doc(anchor.id)
          .set(anchor.toMap());

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error adding anchor to venue: $e');
      return false;
    }
  }

  // Update anchor in venue
  Future<bool> updateAnchorInVenue(
    String venueId,
    CloudAnchorPoint anchor,
  ) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_anchorsSubCollection)
          .doc(anchor.id)
          .set(anchor.toMap(), SetOptions(merge: true));

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error updating anchor in venue: $e');
      return false;
    }
  }

  // Delete anchor from venue
  Future<bool> deleteAnchorFromVenue(String venueId, String anchorId) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_anchorsSubCollection)
          .doc(anchorId)
          .delete();

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error deleting anchor from venue: $e');
      return false;
    }
  }

  // Add destination to venue
  Future<bool> addDestinationToVenue(
    String venueId,
    Destination destination,
  ) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_destinationsSubCollection)
          .doc(destination.id)
          .set(destination.toMap());

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error adding destination to venue: $e');
      return false;
    }
  }

  // Update destination in venue
  Future<bool> updateDestinationInVenue(
    String venueId,
    Destination destination,
  ) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_destinationsSubCollection)
          .doc(destination.id)
          .set(destination.toMap(), SetOptions(merge: true));

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error updating destination in venue: $e');
      return false;
    }
  }

  // Delete destination from venue
  Future<bool> deleteDestinationFromVenue(
    String venueId,
    String destinationId,
  ) async {
    try {
      await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_destinationsSubCollection)
          .doc(destinationId)
          .delete();

      // Update venue timestamp
      await _updateVenueTimestamp(venueId);

      return true;
    } catch (e) {
      print('Error deleting destination from venue: $e');
      return false;
    }
  }

  // Get all anchors for a venue
  Future<List<CloudAnchorPoint>> getVenueAnchors(String venueId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_anchorsSubCollection)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => CloudAnchorPoint.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error loading venue anchors: $e');
      return [];
    }
  }

  // Get all destinations for a venue
  Future<List<Destination>> getVenueDestinations(String venueId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_venuesCollection)
          .doc(venueId)
          .collection(_destinationsSubCollection)
          .orderBy('name')
          .get();

      return querySnapshot.docs
          .map((doc) => Destination.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error loading venue destinations: $e');
      return [];
    }
  }

  // Stream venue updates
  Stream<Venue?> streamVenue(String venueId) {
    return _firestore
        .collection(_venuesCollection)
        .doc(venueId)
        .snapshots()
        .asyncMap((doc) async {
          if (!doc.exists) return null;
          return await _buildVenueFromDocument(doc);
        });
  }

  // Stream all venues
  Stream<List<Venue>> streamAllVenues() {
    return _firestore
        .collection(_venuesCollection)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          List<Venue> venues = [];

          for (var doc in snapshot.docs) {
            final venue = await _buildVenueFromDocument(doc);
            venues.add(venue);
          }

          return venues;
        });
  }

  // Helper method to build venue with subcollections
  Future<Venue> _buildVenueFromDocument(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    // Load anchors
    final anchorsSnapshot = await doc.reference
        .collection(_anchorsSubCollection)
        .get();

    final anchors = anchorsSnapshot.docs
        .map((anchorDoc) => CloudAnchorPoint.fromMap(anchorDoc.data()))
        .toList();

    // Load destinations
    final destinationsSnapshot = await doc.reference
        .collection(_destinationsSubCollection)
        .get();

    final destinations = destinationsSnapshot.docs
        .map((destDoc) => Destination.fromMap(destDoc.data()))
        .toList();

    return Venue(
      id: data['id'],
      name: data['name'],
      description: data['description'],
      anchors: anchors,
      destinations: destinations,
      origin: AnchorPosition.fromMap(data['origin']),
      createdAt: DateTime.parse(data['createdAt']),
      updatedAt: DateTime.parse(data['updatedAt']),
    );
  }

  // Helper method to update venue timestamp
  Future<void> _updateVenueTimestamp(String venueId) async {
    await _firestore.collection(_venuesCollection).doc(venueId).update({
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  // Get venue statistics
  Future<Map<String, dynamic>> getVenueStats(String venueId) async {
    try {
      final anchors = await getVenueAnchors(venueId);
      final destinations = await getVenueDestinations(venueId);

      final activeAnchors = anchors
          .where((a) => a.status == AnchorStatus.active)
          .length;
      final draftAnchors = anchors
          .where((a) => a.status == AnchorStatus.draft)
          .length;
      final failedAnchors = anchors
          .where((a) => a.status == AnchorStatus.failed)
          .length;

      return {
        'totalAnchors': anchors.length,
        'activeAnchors': activeAnchors,
        'draftAnchors': draftAnchors,
        'failedAnchors': failedAnchors,
        'totalDestinations': destinations.length,
        'averageAnchorQuality': anchors.isEmpty
            ? 0.0
            : anchors.map((a) => a.quality).reduce((a, b) => a + b) /
                  anchors.length,
      };
    } catch (e) {
      print('Error getting venue stats: $e');
      return {};
    }
  }

  // Search venues by name
  Future<List<Venue>> searchVenues(String searchTerm) async {
    try {
      final querySnapshot = await _firestore
          .collection(_venuesCollection)
          .where('name', isGreaterThanOrEqualTo: searchTerm)
          .where('name', isLessThanOrEqualTo: searchTerm + '\uf8ff')
          .get();

      List<Venue> venues = [];

      for (var doc in querySnapshot.docs) {
        final venue = await _buildVenueFromDocument(doc);
        venues.add(venue);
      }

      return venues;
    } catch (e) {
      print('Error searching venues: $e');
      return [];
    }
  }

  // Create sample venue for testing
  Future<Venue> createSampleVenue(String name, String description) async {
    final sampleVenue = Venue(
      id: 'venue_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      anchors: [],
      destinations: [
        Destination(
          id: 'reception',
          name: 'Reception Desk',
          description: 'Main reception and visitor check-in',
          category: 'Services',
          position: AnchorPosition(x: 5, y: 2),
        ),
        Destination(
          id: 'meeting_room_a',
          name: 'Meeting Room A',
          description: 'Conference room for 10 people',
          category: 'Rooms',
          position: AnchorPosition(x: 15, y: 8),
        ),
        Destination(
          id: 'kitchen',
          name: 'Kitchen',
          description: 'Office kitchen and break area',
          category: 'Facilities',
          position: AnchorPosition(x: 25, y: 5),
        ),
        Destination(
          id: 'ceo_office',
          name: 'CEO Office',
          description: 'Executive office',
          category: 'Offices',
          position: AnchorPosition(x: 30, y: 15),
        ),
      ],
      origin: AnchorPosition(x: 0, y: 0),
    );

    final success = await saveVenue(sampleVenue);
    if (!success) {
      throw Exception('Failed to create sample venue');
    }

    return sampleVenue;
  }
}
