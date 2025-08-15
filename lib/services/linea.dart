import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Linea {
  final String id;
  LatLng puntoInicio;
  LatLng puntoFin;
  String nombre;
  Color color;

  Linea({
    required this.id,
    required this.puntoInicio,
    required this.puntoFin,
    required this.nombre,
    this.color = Colors.red,
  });

  /// Divide en segmentos de (distanciaMetros) y devuelve lista de puntos con su índice
  List<SubWaypoint> dividirEnSegmentos(double distanciaMetros) {
    final distancia = const Distance();
    final total = distancia(puntoInicio, puntoFin);
    final pasos = (total / distanciaMetros).floor();

    List<SubWaypoint> puntos = [];
    for (int i = 0; i <= pasos; i++) {
      double t = i / pasos;
      double lat = puntoInicio.latitude + t * (puntoFin.latitude - puntoInicio.latitude);
      double lng = puntoInicio.longitude + t * (puntoFin.longitude - puntoInicio.longitude);
      puntos.add(
        SubWaypoint(
          index: i,
          posicion: LatLng(lat, lng),
          esInicio: i == 0,
          esFinal: i == pasos,
        ),
      );
    }
    return puntos;
  }
}

class SubWaypoint {
  final int index;
  final LatLng posicion;
  final bool esInicio;
  final bool esFinal;
  bool visitado;

  SubWaypoint({
    required this.index,
    required this.posicion,
    this.esInicio = false,
    this.esFinal = false,
    this.visitado = false,
  });
}

