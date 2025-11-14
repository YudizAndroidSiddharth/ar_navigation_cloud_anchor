import 'dart:math' as math;

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

double _degToRad(double deg) => deg * (math.pi / 180.0);
double _radToDeg(double rad) => rad * (180.0 / math.pi);

double bearingBetween(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final phi1 = _degToRad(lat1);
  final phi2 = _degToRad(lat2);
  final dLon = _degToRad(lon2 - lon1);

  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  final bearingRad = math.atan2(y, x);
  final bearingDeg = (_radToDeg(bearingRad) + 360.0) % 360.0;
  return bearingDeg;
}

LatLng lerpLatLng(LatLng a, LatLng b, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  return LatLng(
    a.lat + (b.lat - a.lat) * clampedT,
    a.lng + (b.lng - a.lng) * clampedT,
  );
}


