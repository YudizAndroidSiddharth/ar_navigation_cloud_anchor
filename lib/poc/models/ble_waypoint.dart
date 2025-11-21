/// Optimized BLE Waypoint model for production navigation
/// Handles waypoint state management with graceful degradation
class BleWaypoint {
  final String id;
  final String label;
  final int order;

  bool _reached = false;
  int _stableCount = 0;

  BleWaypoint({required this.id, required this.label, required this.order});

  /// Whether this waypoint has been reached
  bool get reached => _reached;
  set reached(bool value) => _reached = value;

  /// Current stable sample count
  int get stableCount => _stableCount;

  /// Update RSSI and check if waypoint should be marked as reached
  /// Returns true if waypoint was just reached
  bool updateRssi(int rssi, int threshold, int requiredSamples) {
    final wasReached = _reached;

    if (rssi >= threshold) {
      _stableCount++;

      if (_stableCount >= requiredSamples && !_reached) {
        _reached = true;
        return true; // Just reached
      }
    } else {
      // Gentle reduction instead of hard reset
      reduceCounterGently();
    }

    return false;
  }

  /// Gently reduce counter instead of hard reset
  /// Provides forgiveness for temporary signal loss
  void reduceCounterGently() {
    if (_stableCount > 0) {
      _stableCount = (_stableCount * 0.8).floor(); // Reduce by 20%
      _stableCount = _stableCount.clamp(0, 10); // Keep reasonable bounds
    }
  }

  /// Reset waypoint state completely
  void reset() {
    _reached = false;
    _stableCount = 0;
  }

  /// Reset only the counter, keep reached state
  void resetCounter() {
    _stableCount = 0;
  }

  @override
  String toString() {
    return 'BleWaypoint{id: $id, label: $label, order: $order, reached: $_reached, stableCount: $_stableCount}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleWaypoint && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
