import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/geopoint.dart';

class ZonaColoreada {
  final LatLng centro;
  final List<GeoPoint> puntos;
  final Color color;
  final int numeroZona;
  final String id;

  ZonaColoreada({
    required this.centro,
    required this.puntos,
    required this.color,
    required this.numeroZona,
    required this.id,
  });

  @override
  String toString() {
    return 'Zona $numeroZona: ${puntos.length} puntos, centro: ${centro.latitude.toStringAsFixed(6)}, ${centro.longitude.toStringAsFixed(6)}';
  }
}

class VisualizadorZonas {
  static const List<Color> _coloresBase = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.amber,
    Colors.pink,
    Colors.lime,
    Colors.indigo,
    Colors.teal,
    Colors.brown,
    Colors.deepOrange,
    Colors.lightBlue,
    Colors.deepPurple,
  ];

  bool _estaActivo = false;
  List<ZonaColoreada> _zonasColoreadas = [];
  double _radioZona = 10.0;
  final Distance _distance = const Distance();

  // Getters
  bool get estaActivo => _estaActivo;
  List<ZonaColoreada> get zonasColoreadas => List.unmodifiable(_zonasColoreadas);
  int get numeroDeZonas => _zonasColoreadas.length;
  int get totalPuntos => _zonasColoreadas.fold(0, (sum, zona) => sum + zona.puntos.length);

  // Configuración
  void configurarRadioZona(double nuevoRadio) {
    _radioZona = nuevoRadio;
  }

  // Toggle principal
  bool toggle(List<GeoPoint> historialGlobal) {
    _estaActivo = !_estaActivo;

    if (_estaActivo) {
      analizarZonas(historialGlobal);
    } else {
      limpiar();
    }

    return _estaActivo;
  }

  // Análisis principal de zonas
  void analizarZonas(List<GeoPoint> historialGlobal) {
    _zonasColoreadas.clear();

    if (historialGlobal.isEmpty) {
      return;
    }

    List<List<GeoPoint>> gruposZonas = _agruparPuntosPorZonas(historialGlobal);
    _crearZonasColoreadas(gruposZonas);

    debugPrint('🎨 VisualizadorZonas: Analizadas $numeroDeZonas zonas con $totalPuntos puntos totales');
  }

  // Agrupar puntos por proximidad geográfica
  List<List<GeoPoint>> _agruparPuntosPorZonas(List<GeoPoint> puntos) {
    List<List<GeoPoint>> grupos = [];

    for (final punto in puntos) {
      bool agregadoAGrupoExistente = false;

      // Buscar si pertenece a alguna zona existente
      for (int i = 0; i < grupos.length; i++) {
        final grupo = grupos[i];
        final centroGrupo = _calcularCentroide(grupo);

        final distancia = _distance(
          LatLng(punto.latitud, punto.longitud),
          centroGrupo,
        );

        if (distancia <= _radioZona) {
          grupo.add(punto);
          agregadoAGrupoExistente = true;
          break;
        }
      }

      // Si no pertenece a ninguna zona, crear nueva
      if (!agregadoAGrupoExistente) {
        grupos.add([punto]);
      }
    }

    return grupos;
  }

  // Crear zonas coloreadas a partir de grupos
  void _crearZonasColoreadas(List<List<GeoPoint>> grupos) {
    for (int i = 0; i < grupos.length; i++) {
      final grupo = grupos[i];
      final centro = _calcularCentroide(grupo);
      final color = _generarColor(i);
      final id = 'zona_${DateTime.now().millisecondsSinceEpoch}_$i';

      _zonasColoreadas.add(ZonaColoreada(
        centro: centro,
        puntos: grupo,
        color: color,
        numeroZona: i + 1,
        id: id,
      ));
    }
  }

  // Calcular centroide de un grupo de puntos
  LatLng _calcularCentroide(List<GeoPoint> puntos) {
    if (puntos.isEmpty) return const LatLng(0, 0);

    double latSum = 0;
    double lngSum = 0;

    for (final punto in puntos) {
      latSum += punto.latitud;
      lngSum += punto.longitud;
    }

    return LatLng(latSum / puntos.length, lngSum / puntos.length);
  }

  // Generar color único para cada zona
  Color _generarColor(int indiceZona) {
    if (indiceZona < _coloresBase.length) {
      return _coloresBase[indiceZona];
    } else {
      // Reutilizar colores con opacidad diferente
      final colorBase = _coloresBase[indiceZona % _coloresBase.length];
      final ciclo = (indiceZona / _coloresBase.length).floor();
      final opacidad = max(0.3, 1.0 - (ciclo * 0.2));
      return colorBase.withOpacity(opacidad);
    }
  }

  // Limpiar datos
  void limpiar() {
    _zonasColoreadas.clear();
    _estaActivo = false;
  }

  // Obtener markers para el mapa
  List<Marker> obtenerMarkers() {
    if (!_estaActivo) return [];

    return _zonasColoreadas.expand((zona) {
      return zona.puntos.map((punto) => Marker(
        point: LatLng(punto.latitud, punto.longitud),
        width: 16,
        height: 16,
        child: Container(
          decoration: BoxDecoration(
            color: zona.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${zona.numeroZona}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ));
    }).toList();
  }

  // Obtener círculos para mostrar áreas de zonas
  List<CircleMarker> obtenerCirculos() {
    if (!_estaActivo) return [];

    return _zonasColoreadas.map((zona) => CircleMarker(
      point: zona.centro,
      radius: _radioZona,
      useRadiusInMeter: true,
      color: zona.color.withOpacity(0.1),
      borderColor: zona.color.withOpacity(0.5),
      borderStrokeWidth: 1,
    )).toList();
  }

  // Obtener estadísticas
  Map<String, dynamic> obtenerEstadisticas() {
    if (!_estaActivo || _zonasColoreadas.isEmpty) {
      return {
        'activo': false,
        'zonas': 0,
        'puntos_totales': 0,
        'zona_mas_grande': null,
        'zona_mas_pequeña': null,
      };
    }

    final puntosPorZona = _zonasColoreadas.map((z) => z.puntos.length).toList();
    puntosPorZona.sort();

    return {
      'activo': true,
      'zonas': _zonasColoreadas.length,
      'puntos_totales': totalPuntos,
      'zona_mas_grande': puntosPorZona.last,
      'zona_mas_pequeña': puntosPorZona.first,
      'promedio_puntos_por_zona': (totalPuntos / _zonasColoreadas.length).round(),
    };
  }

  // Buscar zona por posición
  ZonaColoreada? encontrarZonaCercana(LatLng posicion, {double tolerancia = 5.0}) {
    if (!_estaActivo) return null;

    for (final zona in _zonasColoreadas) {
      final distancia = _distance(posicion, zona.centro);
      if (distancia <= tolerancia) {
        return zona;
      }
    }
    return null;
  }

  // Obtener información de zona específica
  String obtenerInfoZona(int numeroZona) {
    if (numeroZona < 1 || numeroZona > _zonasColoreadas.length) {
      return 'Zona no encontrada';
    }

    final zona = _zonasColoreadas[numeroZona - 1];
    return 'Zona ${zona.numeroZona}: ${zona.puntos.length} puntos\n'
        'Centro: ${zona.centro.latitude.toStringAsFixed(6)}, ${zona.centro.longitude.toStringAsFixed(6)}\n'
        'Radio: ${_radioZona}m';
  }

  // Exportar datos de zonas
  Map<String, dynamic> exportarDatos() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'activo': _estaActivo,
      'radio_zona': _radioZona,
      'total_zonas': _zonasColoreadas.length,
      'total_puntos': totalPuntos,
      'zonas': _zonasColoreadas.map((zona) => {
        'numero': zona.numeroZona,
        'centro_lat': zona.centro.latitude,
        'centro_lng': zona.centro.longitude,
        'cantidad_puntos': zona.puntos.length,
        'color': zona.color.value,
        'puntos': zona.puntos.map((p) => {
          'lat': p.latitud,
          'lng': p.longitud,
          'tiempo': p.tiempo.toIso8601String(),
        }).toList(),
      }).toList(),
    };
  }
}