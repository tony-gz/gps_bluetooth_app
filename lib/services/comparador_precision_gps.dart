import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/geopoint.dart';
import '../services/linea.dart';

enum TipoModulo { adafruit, neo6m, promedio }

class DatosPrecision {
  final TipoModulo modulo;
  final String nombreModulo;
  final int puntosCercanos;
  final int puntosTotal;
  final double distanciaPromedio;
  final double distanciaMinima;
  final double distanciaMaxima;
  final double porcentajePrecision;
  final List<double> distancias;

  DatosPrecision({
    required this.modulo,
    required this.nombreModulo,
    required this.puntosCercanos,
    required this.puntosTotal,
    required this.distanciaPromedio,
    required this.distanciaMinima,
    required this.distanciaMaxima,
    required this.porcentajePrecision,
    required this.distancias,
  });
}

class ComparadorPrecisionGPS {
  final Distance _distance = Distance();

  // Almacena los datos históricos para análisis
  final List<GeoPoint> _historialAdafruit = [];
  final List<GeoPoint> _historialNeo6m = [];
  final List<GeoPoint> _historialPromedio = [];

  // Configuración
  double _toleranciaMetros = 5.0;
  Linea? _lineaReferencia;

  void configurarAnalisis({
    required double toleranciaMetros,
    required Linea lineaReferencia,
  }) {
    _toleranciaMetros = toleranciaMetros;
    _lineaReferencia = lineaReferencia;
  }

  void agregarPuntoAdafruit(GeoPoint punto) {
    _historialAdafruit.add(punto);
  }

  void agregarPuntoNeo6m(GeoPoint punto) {
    _historialNeo6m.add(punto);
  }

  void agregarPuntoPromedio(GeoPoint punto) {
    _historialPromedio.add(punto);
  }

  void limpiarHistorial() {
    _historialAdafruit.clear();
    _historialNeo6m.clear();
    _historialPromedio.clear();
  }

  // Calcula la distancia de un punto a la línea de referencia
  double _calcularDistanciaALinea(LatLng punto, Linea linea) {
    final A = linea.puntoInicio;
    final B = linea.puntoFin;

    // Si los puntos A y B son iguales, no hay línea real
    if (A == B) return double.infinity;

    // Fórmula de distancia punto a línea
    final double x0 = punto.longitude;
    final double y0 = punto.latitude;
    final double x1 = A.longitude;
    final double y1 = A.latitude;
    final double x2 = B.longitude;
    final double y2 = B.latitude;

    final double numerador = ((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1).abs();
    final double denominador = sqrt(pow(y2 - y1, 2) + pow(x2 - x1, 2));

    // Convertir de grados a metros (aproximación)
    final double distanciaGrados = numerador / denominador;
    return distanciaGrados * 111320; // Factor de conversión aproximado
  }

  // Analiza la precisión de un módulo específico
  DatosPrecision _analizarModulo(
      List<GeoPoint> historial,
      TipoModulo tipoModulo,
      String nombre
      ) {
    if (_lineaReferencia == null || historial.isEmpty) {
      return DatosPrecision(
        modulo: tipoModulo,
        nombreModulo: nombre,
        puntosCercanos: 0,
        puntosTotal: 0,
        distanciaPromedio: 0.0,
        distanciaMinima: 0.0,
        distanciaMaxima: 0.0,
        porcentajePrecision: 0.0,
        distancias: [],
      );
    }

    final List<double> distancias = [];
    int puntosCercanos = 0;

    for (final punto in historial) {
      final distancia = _calcularDistanciaALinea(
          LatLng(punto.latitud, punto.longitud),
          _lineaReferencia!
      );

      distancias.add(distancia);

      if (distancia <= _toleranciaMetros) {
        puntosCercanos++;
      }
    }

    final distanciaPromedio = distancias.isNotEmpty
        ? distancias.reduce((a, b) => a + b) / distancias.length
        : 0.0;

    final distanciaMinima = distancias.isNotEmpty
        ? distancias.reduce((a, b) => a < b ? a : b)
        : 0.0;

    final distanciaMaxima = distancias.isNotEmpty
        ? distancias.reduce((a, b) => a > b ? a : b)
        : 0.0;

    final porcentajePrecision = historial.isNotEmpty
        ? (puntosCercanos / historial.length) * 100
        : 0.0;

    return DatosPrecision(
      modulo: tipoModulo,
      nombreModulo: nombre,
      puntosCercanos: puntosCercanos,
      puntosTotal: historial.length,
      distanciaPromedio: distanciaPromedio,
      distanciaMinima: distanciaMinima,
      distanciaMaxima: distanciaMaxima,
      porcentajePrecision: porcentajePrecision,
      distancias: distancias,
    );
  }

  // Genera el análisis completo
  Map<TipoModulo, DatosPrecision> generarAnalisisCompleto() {
    final Map<TipoModulo, DatosPrecision> resultados = {};

    resultados[TipoModulo.adafruit] = _analizarModulo(
        _historialAdafruit,
        TipoModulo.adafruit,
        'Adafruit GPS'
    );

    resultados[TipoModulo.neo6m] = _analizarModulo(
        _historialNeo6m,
        TipoModulo.neo6m,
        'NEO-6M GPS'
    );

    resultados[TipoModulo.promedio] = _analizarModulo(
        _historialPromedio,
        TipoModulo.promedio,
        'Promedio Combinado'
    );

    return resultados;
  }

  // Genera reporte en formato CSV
  String generarReporteCSV() {
    final analisis = generarAnalisisCompleto();
    final buffer = StringBuffer();

    // Encabezados
    buffer.writeln('Módulo,Puntos Totales,Puntos Cercanos,Porcentaje Precisión,Distancia Promedio (m),Distancia Mínima (m),Distancia Máxima (m),Tolerancia (m),Línea Referencia');

    // Datos de cada módulo
    for (final datos in analisis.values) {
      final lineaInfo = _lineaReferencia != null
          ? '${_lineaReferencia!.nombre}'
          : 'No definida';

      buffer.writeln(
          '${datos.nombreModulo},'
              '${datos.puntosTotal},'
              '${datos.puntosCercanos},'
              '${datos.porcentajePrecision.toStringAsFixed(2)}%,'
              '${datos.distanciaPromedio.toStringAsFixed(3)},'
              '${datos.distanciaMinima.toStringAsFixed(3)},'
              '${datos.distanciaMaxima.toStringAsFixed(3)},'
              '${_toleranciaMetros.toStringAsFixed(1)},'
              '$lineaInfo'
      );
    }

    // Sección de análisis comparativo
    buffer.writeln('\n--- ANÁLISIS COMPARATIVO ---');

    final mejorPorcentaje = analisis.values
        .reduce((a, b) => a.porcentajePrecision > b.porcentajePrecision ? a : b);

    final mejorDistanciaPromedio = analisis.values
        .reduce((a, b) => a.distanciaPromedio < b.distanciaPromedio ? a : b);

    buffer.writeln('Mejor Porcentaje de Precisión,${mejorPorcentaje.nombreModulo},${mejorPorcentaje.porcentajePrecision.toStringAsFixed(2)}%');
    buffer.writeln('Mejor Distancia Promedio,${mejorDistanciaPromedio.nombreModulo},${mejorDistanciaPromedio.distanciaPromedio.toStringAsFixed(3)} m');

    // Información de configuración
    buffer.writeln('\n--- CONFIGURACIÓN DEL ANÁLISIS ---');
    buffer.writeln('Tolerancia utilizada,${_toleranciaMetros.toStringAsFixed(1)} metros');
    buffer.writeln('Fecha del análisis,${DateTime.now().toIso8601String()}');

    if (_lineaReferencia != null) {
      buffer.writeln('Línea de referencia,${_lineaReferencia!.nombre}');
      buffer.writeln('Punto inicio,"${_lineaReferencia!.puntoInicio.latitude}, ${_lineaReferencia!.puntoInicio.longitude}"');
      buffer.writeln('Punto fin,"${_lineaReferencia!.puntoFin.latitude}, ${_lineaReferencia!.puntoFin.longitude}"');
    }

    return buffer.toString();
  }

  // Genera reporte detallado con todos los puntos
  String generarReporteDetallado() {
    final analisis = generarAnalisisCompleto();
    final buffer = StringBuffer();

    buffer.writeln('REPORTE DETALLADO DE PRECISIÓN GPS');
    buffer.writeln('=' * 50);
    buffer.writeln('Fecha: ${DateTime.now().toLocal()}');
    buffer.writeln('Tolerancia: ${_toleranciaMetros.toStringAsFixed(1)} metros');

    if (_lineaReferencia != null) {
      buffer.writeln('Línea de referencia: ${_lineaReferencia!.nombre}');
      buffer.writeln('Desde: ${_lineaReferencia!.puntoInicio}');
      buffer.writeln('Hasta: ${_lineaReferencia!.puntoFin}');
    }

    buffer.writeln('');

    // Resumen por módulo
    for (final datos in analisis.values) {
      buffer.writeln('--- ${datos.nombreModulo.toUpperCase()} ---');
      buffer.writeln('Total de puntos: ${datos.puntosTotal}');
      buffer.writeln('Puntos dentro de tolerancia: ${datos.puntosCercanos}');
      buffer.writeln('Porcentaje de precisión: ${datos.porcentajePrecision.toStringAsFixed(2)}%');
      buffer.writeln('Distancia promedio: ${datos.distanciaPromedio.toStringAsFixed(3)} m');
      buffer.writeln('Distancia mínima: ${datos.distanciaMinima.toStringAsFixed(3)} m');
      buffer.writeln('Distancia máxima: ${datos.distanciaMaxima.toStringAsFixed(3)} m');
      buffer.writeln('');
    }

    // Análisis comparativo
    buffer.writeln('--- COMPARACIÓN ENTRE MÓDULOS ---');
    final sortedByPrecision = analisis.values.toList()
      ..sort((a, b) => b.porcentajePrecision.compareTo(a.porcentajePrecision));

    buffer.writeln('Ranking por precisión:');
    for (int i = 0; i < sortedByPrecision.length; i++) {
      final datos = sortedByPrecision[i];
      buffer.writeln('${i + 1}. ${datos.nombreModulo}: ${datos.porcentajePrecision.toStringAsFixed(2)}%');
    }

    return buffer.toString();
  }

  // Guarda y comparte el reporte
  Future<void> generarYCompartirReporte({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final nombreBase = nombrePersonalizado ?? 'reporte_precision_gps_$timestamp';

      // Generar archivo CSV
      final csvContent = generarReporteCSV();
      final csvFile = File('${directory.path}/${nombreBase}.csv');
      await csvFile.writeAsString(csvContent, encoding: utf8);

      List<String> archivosACompartir = [csvFile.path];

      // Generar archivo detallado si se solicita
      if (incluirDetallado) {
        final detalladoContent = generarReporteDetallado();
        final detalladoFile = File('${directory.path}/${nombreBase}_detallado.txt');
        await detalladoFile.writeAsString(detalladoContent, encoding: utf8);
        archivosACompartir.add(detalladoFile.path);
      }

      // Compartir archivos
      await Share.shareXFiles(
        archivosACompartir.map((path) => XFile(path)).toList(),
        text: 'Reporte de precisión GPS - ${DateTime.now().toLocal()}',
        subject: 'Análisis de Precisión GPS',
      );

    } catch (e) {
      throw Exception('Error al generar reporte: $e');
    }
  }

  // Obtiene estadísticas rápidas para mostrar en UI
  Map<String, dynamic> obtenerEstadisticasRapidas() {
    final analisis = generarAnalisisCompleto();

    if (analisis.isEmpty) {
      return {
        'total_puntos': 0,
        'mejor_modulo': 'N/A',
        'mejor_precision': 0.0,
        'promedio_general': 0.0,
      };
    }

    final totalPuntos = analisis.values
        .map((d) => d.puntosTotal)
        .reduce((a, b) => a + b);

    final mejorModulo = analisis.values
        .reduce((a, b) => a.porcentajePrecision > b.porcentajePrecision ? a : b);

    final promedioGeneral = analisis.values
        .map((d) => d.porcentajePrecision)
        .reduce((a, b) => a + b) / analisis.length;

    return {
      'total_puntos': totalPuntos,
      'mejor_modulo': mejorModulo.nombreModulo,
      'mejor_precision': mejorModulo.porcentajePrecision,
      'promedio_general': promedioGeneral,
      'tiene_linea_referencia': _lineaReferencia != null,
      'tolerancia_actual': _toleranciaMetros,
    };
  }

  // Resetea el análisis manteniendo configuración
  void reiniciarAnalisis() {
    limpiarHistorial();
  }

  // Getters para información actual
  int get totalPuntosAdafruit => _historialAdafruit.length;
  int get totalPuntosNeo6m => _historialNeo6m.length;
  int get totalPuntosPromedio => _historialPromedio.length;
  double get toleranciaActual => _toleranciaMetros;
  Linea? get lineaReferencia => _lineaReferencia;
}