import 'package:latlong2/latlong.dart';

class GeoPoint {
  final double latitud;
  final double longitud;
  final DateTime tiempo;

  GeoPoint({
    required this.latitud,
    required this.longitud,
    required this.tiempo,
  });

  LatLng toLatLng() => LatLng(latitud, longitud);

  @override
  String toString() =>
      'Lat: ${latitud.toStringAsFixed(5)}, Lng: ${longitud.toStringAsFixed(5)} @ ${tiempo.hour}:${tiempo.minute}:${tiempo.second}';
}
