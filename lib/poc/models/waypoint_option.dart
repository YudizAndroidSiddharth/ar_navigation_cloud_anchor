/// Model representing a waypoint option for beacon broadcasting
class WaypointOption {
  final int number;
  final String label;
  final String uuid;

  const WaypointOption({
    required this.number,
    required this.label,
    required this.uuid,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaypointOption &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          label == other.label &&
          uuid == other.uuid;

  @override
  int get hashCode => number.hashCode ^ label.hashCode ^ uuid.hashCode;

  @override
  String toString() => 'WaypointOption(number: $number, label: $label, uuid: $uuid)';
}

