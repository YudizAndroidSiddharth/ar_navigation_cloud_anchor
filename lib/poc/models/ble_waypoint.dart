/// Model representing a BLE-based waypoint beacon
/// 
/// Each waypoint corresponds to a physical BLE beacon device (phone)
/// placed along the navigation path. The waypoint is considered "reached"
/// when the user's device detects a strong enough RSSI signal from the beacon.
class BleWaypoint {
  /// Unique identifier for the beacon (e.g., device ID, MAC address, UUID, or name)
  final String id;

  /// Human-readable label for this waypoint
  final String label;

  /// Order/sequence of this waypoint (1, 2, 3...)
  final int order;

  /// Whether this waypoint has been reached
  bool reached;

  /// Last received RSSI value (in dBm) from this beacon
  /// null if beacon hasn't been detected yet
  int? lastRssi;

  /// Smoothed RSSI value using exponential moving average
  /// This helps reduce jitter in signal strength display
  double? _smoothedRssi;

  /// Counter for consecutive strong RSSI readings
  /// Used to ensure stability before marking as reached
  int _strongRssiCount = 0;

  BleWaypoint({
    required this.id,
    required this.label,
    required this.order,
    this.reached = false,
    this.lastRssi,
  });

  /// Update RSSI and check if waypoint should be marked as reached
  /// 
  /// [rssi] - Signal strength in dBm (typically negative, e.g., -65)
  /// [thresholdStrong] - RSSI threshold to consider "strong" (e.g., -65 dBm)
  /// [stableSamplesRequired] - Number of consecutive strong readings needed
  /// 
  /// Returns true if waypoint was just marked as reached (was false, now true)
  bool updateRssi(int rssi, int thresholdStrong, int stableSamplesRequired) {
    // Apply exponential smoothing to RSSI for smoother updates
    const alpha = 0.3; // Smoothing factor (0 < alpha < 1)
    if (_smoothedRssi == null) {
      _smoothedRssi = rssi.toDouble();
    } else {
      _smoothedRssi = alpha * rssi + (1 - alpha) * _smoothedRssi!;
    }
    
    // Update lastRssi with smoothed value (rounded to nearest integer)
    lastRssi = _smoothedRssi!.round();

    // Check if waypoint should be marked as reached (only if not already reached)
    if (!reached) {
      if (rssi >= thresholdStrong) {
        _strongRssiCount++;
        if (_strongRssiCount >= stableSamplesRequired) {
          reached = true;
          return true; // Just reached
        }
      } else {
        // Reset counter if signal is not strong enough
        _strongRssiCount = 0;
      }
    }

    return false;
  }
  
  /// Get smoothed RSSI value for display
  int? get displayRssi => lastRssi;

  /// Reset the waypoint (useful for testing or restarting navigation)
  void reset() {
    reached = false;
    lastRssi = null;
    _smoothedRssi = null;
    _strongRssiCount = 0;
  }
}


