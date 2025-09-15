import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/geopoint.dart';
import '../services/archivo_gps.dart';
import '../services/comparador_precision_gps.dart';
import '../services/recorrido_service.dart';
import '../services/visualizador_zonas.dart';

/// Servicio encargado de procesar y gestionar todos los datos GPS
class DataProcessingService {
  // Servicios
  final ArchivoGPS _archivoGPS = ArchivoGPS();
  final ComparadorPrecisionGPS _comparadorPrecision = ComparadorPrecisionGPS();
  final VisualizadorZonas _visualizadorZonas = VisualizadorZonas();
  final Distance _distance = Distance();

  // Estado interno
  LatLng _posicion = const LatLng(17.5515346, -99.5006322);
  GeoPoint? _puntoAdafruit;
  GeoPoint? _puntoNeo6m;
  GeoPoint? _puntoC;
  GeoPoint? _puntoZona;
  RecorridoService? _recorridoService;

  // Historiales
  final List<GeoPoint> _historial = [];
  final List<GeoPoint> _historialAdafruit = [];
  final List<GeoPoint> _historialNeo6m = [];
  final List<GeoPoint> _historialPromedio = [];
  final List<GeoPoint> _historialZona = [];
  final List<GeoPoint> _historialGlobal = [];

  // Configuración
  static const double minDistanceMeters = 0.1;
  static const double _radioZona = 10.0;
  static const int _maxPuntosZona = 20000;
  static const int maxHistorial = 20000;
  static const int maxPuntosGlobales = 20000;

  // Callbacks para notificar cambios
  Function(LatLng)? onPositionChanged;
  Function()? onDataUpdated;

  // Getters
  LatLng get posicion => _posicion;
  GeoPoint? get puntoAdafruit => _puntoAdafruit;
  GeoPoint? get puntoNeo6m => _puntoNeo6m;
  GeoPoint? get puntoC => _puntoC;
  List<GeoPoint> get historial => List.unmodifiable(_historial);
  List<GeoPoint> get historialAdafruit => List.unmodifiable(_historialAdafruit);
  List<GeoPoint> get historialNeo6m => List.unmodifiable(_historialNeo6m);
  List<GeoPoint> get historialPromedio => List.unmodifiable(_historialPromedio);
  List<GeoPoint> get historialGlobal => List.unmodifiable(_historialGlobal);
  VisualizadorZonas get visualizadorZonas => _visualizadorZonas;
  ComparadorPrecisionGPS get comparadorPrecision => _comparadorPrecision;
  RecorridoService? get recorridoService => _recorridoService;

  /// Configura el servicio de recorrido
  void configurarRecorrido(RecorridoService? servicio) {
    _recorridoService = servicio;
  }
  /// Procesa datos de Bluetooth parseados
  Future<void> procesarDatosBluetooth(GeoPoint punto, String dataOriginal) async {
    // Actualizar posición actual
    _posicion = LatLng(punto.latitud, punto.longitud);
    onPositionChanged?.call(_posicion);

    // Procesar el punto en el sistema de zonas
    _procesarPunto(punto);

    // Actualizar historial principal
    _historial.clear();
    _historial.addAll(_historialGlobal);

    // Log periódico del estado
    if (_historialGlobal.length % 10 == 0) {
      _imprimirEstadoHistorial();
    }

    // Procesar según el tipo de dato (A, N, C)
    await _procesarSegunTipo(punto, dataOriginal);

    // Guardar en archivo
    final linea = '${punto.tiempo.toIso8601String()},${punto.latitud},${punto.longitud}';
    await _archivoGPS.guardar(linea);

    // Notificar cambios
    onDataUpdated?.call();
  }

  /// Procesa el punto según su tipo (Adafruit, Neo6m, Combinado)
  Future<void> _procesarSegunTipo(GeoPoint punto, String data) async {
    final posicionLatLng = LatLng(punto.latitud, punto.longitud);

    if (data.startsWith("A")) {
      await _procesarPuntoAdafruit(punto, posicionLatLng);
    } else if (data.startsWith("N")) {
      await _procesarPuntoNeo6m(punto, posicionLatLng);
    } else if (data.startsWith("C")) {
      await _procesarPuntoCombinado(punto, posicionLatLng);
    }
  }

  /// Procesa punto Adafruit
  Future<void> _procesarPuntoAdafruit(GeoPoint punto, LatLng posicionLatLng) async {
    if (_puntoAdafruit == null ||
        _distance(_puntoAdafruit!.toLatLng(), posicionLatLng) >= minDistanceMeters) {

      _puntoAdafruit = punto;
      _historialAdafruit.add(punto);
      _comparadorPrecision.agregarPuntoAdafruit(punto);
      _recorridoService?.procesarPosicion(posicionLatLng);

      if (_historialAdafruit.length > maxHistorial) {
        _historialAdafruit.removeAt(0);
      }
    }
  }

  /// Procesa punto Neo6m
  Future<void> _procesarPuntoNeo6m(GeoPoint punto, LatLng posicionLatLng) async {
    if (_puntoNeo6m == null ||
        _distance(_puntoNeo6m!.toLatLng(), posicionLatLng) >= minDistanceMeters) {

      _puntoNeo6m = punto;
      _historialNeo6m.add(punto);
      _comparadorPrecision.agregarPuntoNeo6m(punto);
      _recorridoService?.procesarPosicion(posicionLatLng);

      if (_historialNeo6m.length > maxHistorial) {
        _historialNeo6m.removeAt(0);
      }
    }
  }
  /// Procesa punto combinado
  Future<void> _procesarPuntoCombinado(GeoPoint punto, LatLng posicionLatLng) async {
    if (_puntoC == null ||
        _distance(_puntoC!.toLatLng(), posicionLatLng) >= minDistanceMeters) {

      _puntoC = punto;
      _historialPromedio.add(punto);
      _comparadorPrecision.agregarPuntoPromedio(punto);
      _recorridoService?.procesarPosicion(posicionLatLng);

      if (_historialPromedio.length > maxHistorial) {
        _historialPromedio.removeAt(0);
      }
    }
  }
  /// Determina si un punto está en la misma zona
  bool _estaEnMismaZona(GeoPoint nuevoPunto) {
    if (_puntoZona == null) return false;
    final p1 = LatLng(_puntoZona!.latitud, _puntoZona!.longitud);
    final p2 = LatLng(nuevoPunto.latitud, nuevoPunto.longitud);
    return _distance(p1, p2) <= _radioZona;
  }
  /// Procesa un punto en el sistema de zonas
  void _procesarPunto(GeoPoint punto) {
    if (_puntoZona == null || !_estaEnMismaZona(punto)) {
      // Nueva zona
      _puntoZona = punto;
      _historialZona.clear();
      _historialZona.add(punto);
      _historialGlobal.add(punto);

      print('🆕 Nueva zona iniciada. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
    } else {
      // Misma zona
      _historialGlobal.add(punto);
      if (_historialZona.length < _maxPuntosZona) {
        _historialZona.add(punto);
        print('➕ Agregado a zona. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
      } else {
        // Buffer circular
        _historialZona.removeAt(0);
        _historialZona.add(punto);
        print('🔄 Buffer circular. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length} (máx: $_maxPuntosZona)');
      }
    }
    _limpiarHistorialAntiguo();
  }

  /// Limpia el historial antiguo para evitar problemas de memoria
  void _limpiarHistorialAntiguo() {
    if (_historialGlobal.length > maxPuntosGlobales) {
      final puntosAEliminar = _historialGlobal.length - maxPuntosGlobales;
      _historialGlobal.removeRange(0, puntosAEliminar);
    }
  }
  /// Imprime el estado actual del historial para debugging
  void _imprimirEstadoHistorial() {
    print('=' * 50);
    print('📊 ESTADO DEL HISTORIAL:');
    print('🌍 Historial Global: ${_historialGlobal.length} puntos');
    print('📍 Historial Zona: ${_historialZona.length} puntos (máx: $_maxPuntosZona)');
    if (_puntoZona != null) {
      print('🎯 Zona actual centrada en: ${_puntoZona!.latitud}, ${_puntoZona!.longitud}');
      print('📏 Radio de zona: $_radioZona metros');
    }
    print('=' * 50);
  }
  /// Limpia todo el historial
  void limpiarHistorialGlobal() {
    _historialGlobal.clear();
    _historial.clear();
    _historialZona.clear();
    _historialAdafruit.clear();
    _historialNeo6m.clear();
    _historialPromedio.clear();
    _puntoZona = null;
    _visualizadorZonas.limpiar();
    _comparadorPrecision.limpiarHistorial();

    _puntoAdafruit = null;
    _puntoNeo6m = null;
    _puntoC = null;

    print('🧹 Historial global limpiado: todos los datos eliminados');
  }

  /// Alterna la visualización de zonas
  bool toggleVisualizacionZonas() {
    final estaActivoAhora = _visualizadorZonas.toggle(_historialGlobal);
    return estaActivoAhora;
  }
  /// Configura el análisis de precisión
  void configurarAnalisisPrecision({
    required double toleranciaMetros,
    required dynamic lineaReferencia,
  }) {
    _comparadorPrecision.configurarAnalisis(
      toleranciaMetros: toleranciaMetros,
      lineaReferencia: lineaReferencia,
    );
  }

  /// Obtiene estadísticas rápidas de precisión
  Map<String, dynamic> obtenerEstadisticasPrecision() {
    return _comparadorPrecision.obtenerEstadisticasRapidas();
  }

  /// Genera y comparte reporte de precisión
  Future<void> generarReportePrecision({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    await _comparadorPrecision.generarYCompartirReporte(
      incluirDetallado: incluirDetallado,
      nombrePersonalizado: nombrePersonalizado,
    );
  }

  /// Obtiene la ruta del archivo GPS
  Future<String> obtenerRutaArchivo() async {
    return await _archivoGPS.obtenerRuta();
  }

  /// Filtra puntos por cercanía a una línea
  List<LatLng> filtrarPuntosCercanos({
    required List<LatLng> puntos,
    required LatLng puntoA,
    required LatLng puntoB,
    required double toleranciaMetros,
  }) {
    return puntos.where((punto) =>
        _estaCercaDeLinea(punto, puntoA, puntoB, toleranciaMetros)
    ).toList();
  }

  /// Determina si un punto está cerca de una línea
  bool _estaCercaDeLinea(LatLng punto, LatLng A, LatLng B, double toleranciaMetros) {
    if (A == B) return false;

    final double x0 = punto.longitude;
    final double y0 = punto.latitude;
    final double x1 = A.longitude;
    final double y1 = A.latitude;
    final double x2 = B.longitude;
    final double y2 = B.latitude;

    final double numerador = ((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1).abs();
    final double denominador = _distance.distance(A, B) / 111320; // Aproximación

    if (denominador == 0) return false;

    final double distanciaMetros = (numerador / denominador) * 111320;
    return distanciaMetros <= toleranciaMetros;
  }

  /// Obtiene listas de puntos filtradas y limitadas
  Map<String, List<LatLng>> obtenerPuntosFiltrados({
    int limite = 1000,
    LatLng? puntoA,
    LatLng? puntoB,
    double? toleranciaMetros,
  }) {
    // Convertir a LatLng y limitar
    List<LatLng> puntosAdafruit = _historialAdafruit.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosNeo6m = _historialNeo6m.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosPromedio = _historialPromedio.map((p) => p.toLatLng()).toList();

    // Aplicar límite
    List<LatLng> ultimosAdafruit = puntosAdafruit.length <= limite
        ? puntosAdafruit
        : puntosAdafruit.sublist(puntosAdafruit.length - limite);

    List<LatLng> ultimosNeo6m = puntosNeo6m.length <= limite
        ? puntosNeo6m
        : puntosNeo6m.sublist(puntosNeo6m.length - limite);

    List<LatLng> ultimosPromedio = puntosPromedio.length <= limite
        ? puntosPromedio
        : puntosPromedio.sublist(puntosPromedio.length - limite);

    // Filtrar por línea si se especifica
    if (puntoA != null && puntoB != null && toleranciaMetros != null) {
      ultimosAdafruit = filtrarPuntosCercanos(
        puntos: ultimosAdafruit,
        puntoA: puntoA,
        puntoB: puntoB,
        toleranciaMetros: toleranciaMetros,
      );
      ultimosNeo6m = filtrarPuntosCercanos(
        puntos: ultimosNeo6m,
        puntoA: puntoA,
        puntoB: puntoB,
        toleranciaMetros: toleranciaMetros,
      );
      ultimosPromedio = filtrarPuntosCercanos(
        puntos: ultimosPromedio,
        puntoA: puntoA,
        puntoB: puntoB,
        toleranciaMetros: toleranciaMetros,
      );
    }
    return {
      'adafruit': ultimosAdafruit,
      'neo6m': ultimosNeo6m,
      'promedio': ultimosPromedio,
    };
  }
// Generar reporte de precisión intra-tolerancia
  Future<void> generarReporteIntraTolerancia({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    await _comparadorPrecision.generarYCompartirReporteIntraTolerancia(
      incluirDetallado: incluirDetallado,
      nombrePersonalizado: nombrePersonalizado,
    );
  }
// Obtener estadísticas de precisión intra-tolerancia
  Map<String, dynamic> obtenerEstadisticasIntraTolerancia() {
    return _comparadorPrecision.obtenerEstadisticasIntraTolerancia();
  }
  /// Libera recursos
  void dispose() {
    _visualizadorZonas.limpiar();
  }
}