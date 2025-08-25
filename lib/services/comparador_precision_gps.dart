import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/geopoint.dart';
import '../services/linea.dart';

enum TipoModulo { adafruit, neo6m, promedio }

// Clase para el análisis tradicional (mantener compatibilidad)
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

// Nueva clase para análisis intra-tolerancia mejorado
class DatosPrecisionIntraTolerancia {
  final TipoModulo modulo;
  final String nombreModulo;
  final int puntosAnalizados;
  final int puntosOriginales;
  final int puntosExcluidosPorTolerancia;
  final double distanciaPromedio;
  final double distanciaMinima;
  final double distanciaMaxima;
  final double desviacionEstandar;
  final double mediana;
  final double porcentajePrecisionIntraTolerancia; // NUEVA: 0-100% basado en tolerancia
  final double factorCalidadGlobal; // NUEVA: considera puntos excluidos
  final List<double> distancias;
  final double toleranciaUtilizada;

  DatosPrecisionIntraTolerancia({
    required this.modulo,
    required this.nombreModulo,
    required this.puntosAnalizados,
    required this.puntosOriginales,
    required this.puntosExcluidosPorTolerancia,
    required this.distanciaPromedio,
    required this.distanciaMinima,
    required this.distanciaMaxima,
    required this.desviacionEstandar,
    required this.mediana,
    required this.porcentajePrecisionIntraTolerancia,
    required this.factorCalidadGlobal,
    required this.distancias,
    required this.toleranciaUtilizada,
  });

  // Getter para porcentaje de puntos válidos
  double get porcentajePuntosValidos => puntosOriginales > 0
      ? (puntosAnalizados / puntosOriginales * 100)
      : 0.0;

  // Getter para clasificación de calidad
  String get clasificacionCalidad {
    if (factorCalidadGlobal >= 90) return 'Excelente';
    if (factorCalidadGlobal >= 75) return 'Buena';
    if (factorCalidadGlobal >= 60) return 'Regular';
    if (factorCalidadGlobal >= 40) return 'Deficiente';
    return 'Muy Deficiente';
  }

  // Getter para clasificación de precisión intra-tolerancia
  String get clasificacionPrecision {
    if (porcentajePrecisionIntraTolerancia >= 95) return 'Muy Alta';
    if (porcentajePrecisionIntraTolerancia >= 85) return 'Alta';
    if (porcentajePrecisionIntraTolerancia >= 70) return 'Media';
    if (porcentajePrecisionIntraTolerancia >= 50) return 'Baja';
    return 'Muy Baja';
  }
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

  // MÉTODO PRINCIPAL MEJORADO - Análisis intra-tolerancia con nueva lógica
  DatosPrecisionIntraTolerancia _analizarModuloIntraToleranciaV2(
      List<GeoPoint> historial,
      TipoModulo tipoModulo,
      String nombre
      ) {
    if (_lineaReferencia == null || historial.isEmpty) {
      return DatosPrecisionIntraTolerancia(
        modulo: tipoModulo,
        nombreModulo: nombre,
        puntosAnalizados: 0,
        puntosOriginales: 0,
        puntosExcluidosPorTolerancia: 0,
        distanciaPromedio: 0.0,
        distanciaMinima: 0.0,
        distanciaMaxima: 0.0,
        desviacionEstandar: 0.0,
        mediana: 0.0,
        porcentajePrecisionIntraTolerancia: 0.0,
        factorCalidadGlobal: 0.0,
        distancias: [],
        toleranciaUtilizada: _toleranciaMetros,
      );
    }

    final List<double> distanciasDentroTolerancia = [];
    int puntosExcluidos = 0;

    // Filtrar puntos dentro de tolerancia
    for (final punto in historial) {
      final distancia = _calcularDistanciaALinea(
          LatLng(punto.latitud, punto.longitud),
          _lineaReferencia!
      );

      if (distancia <= _toleranciaMetros) {
        distanciasDentroTolerancia.add(distancia);
      } else {
        puntosExcluidos++;
      }
    }

    if (distanciasDentroTolerancia.isEmpty) {
      return DatosPrecisionIntraTolerancia(
        modulo: tipoModulo,
        nombreModulo: nombre,
        puntosAnalizados: 0,
        puntosOriginales: historial.length,
        puntosExcluidosPorTolerancia: puntosExcluidos,
        distanciaPromedio: 0.0,
        distanciaMinima: 0.0,
        distanciaMaxima: 0.0,
        desviacionEstandar: 0.0,
        mediana: 0.0,
        porcentajePrecisionIntraTolerancia: 0.0,
        factorCalidadGlobal: 0.0,
        distancias: [],
        toleranciaUtilizada: _toleranciaMetros,
      );
    }

    // Calcular estadísticas básicas
    final distanciaPromedio = distanciasDentroTolerancia.reduce((a, b) => a + b) / distanciasDentroTolerancia.length;
    final distanciaMinima = distanciasDentroTolerancia.reduce((a, b) => a < b ? a : b);
    final distanciaMaxima = distanciasDentroTolerancia.reduce((a, b) => a > b ? a : b);

    // Calcular desviación estándar
    final varianza = distanciasDentroTolerancia
        .map((d) => pow(d - distanciaPromedio, 2))
        .reduce((a, b) => a + b) / distanciasDentroTolerancia.length;
    final desviacionEstandar = sqrt(varianza);

    // Calcular mediana
    final distanciasOrdenadas = List<double>.from(distanciasDentroTolerancia)..sort();
    final mediana = distanciasOrdenadas.length % 2 == 0
        ? (distanciasOrdenadas[distanciasOrdenadas.length ~/ 2 - 1] +
        distanciasOrdenadas[distanciasOrdenadas.length ~/ 2]) / 2
        : distanciasOrdenadas[distanciasOrdenadas.length ~/ 2];

    // NUEVA LÓGICA: Calcular precisión intra-tolerancia
    // 100% = distancia 0 (sobre la línea)
    // 0% = distancia = tolerancia máxima
    final porcentajePrecisionIntraTolerancia = _calcularPrecisionIntraTolerancia(distanciaPromedio);

    // NUEVA MÉTRICA: Factor de calidad global (considera puntos excluidos)
    final factorCalidadGlobal = _calcularFactorCalidadGlobal(
        distanciasDentroTolerancia.length,
        historial.length,
        porcentajePrecisionIntraTolerancia
    );

    return DatosPrecisionIntraTolerancia(
      modulo: tipoModulo,
      nombreModulo: nombre,
      puntosAnalizados: distanciasDentroTolerancia.length,
      puntosOriginales: historial.length,
      puntosExcluidosPorTolerancia: puntosExcluidos,
      distanciaPromedio: distanciaPromedio,
      distanciaMinima: distanciaMinima,
      distanciaMaxima: distanciaMaxima,
      desviacionEstandar: desviacionEstandar,
      mediana: mediana,
      porcentajePrecisionIntraTolerancia: porcentajePrecisionIntraTolerancia,
      factorCalidadGlobal: factorCalidadGlobal,
      distancias: distanciasDentroTolerancia,
      toleranciaUtilizada: _toleranciaMetros,
    );
  }

  // NUEVA FUNCIÓN: Calcula precisión intra-tolerancia
  double _calcularPrecisionIntraTolerancia(double distanciaPromedio) {
    if (_toleranciaMetros == 0) return 100.0;

    // Fórmula: 100% - (distancia_promedio / tolerancia_maxima * 100%)
    final porcentaje = 100.0 - ((distanciaPromedio / _toleranciaMetros) * 100.0);
    return porcentaje.clamp(0.0, 100.0);
  }

  // NUEVA FUNCIÓN: Factor de calidad global (considera puntos válidos + precisión)
  double _calcularFactorCalidadGlobal(int puntosValidos, int puntosTotal, double precisionIntra) {
    if (puntosTotal == 0) return 0.0;

    final factorCobertura = (puntosValidos / puntosTotal) * 100.0; // % puntos válidos
    final factorPrecision = precisionIntra; // % precisión intra-tolerancia

    // Combinar ambos factores con pesos (70% precisión, 30% cobertura)
    final factorCombinado = (factorPrecision * 0.7) + (factorCobertura * 0.3);
    return factorCombinado.clamp(0.0, 100.0);
  }

  // Generar análisis completo intra-tolerancia V2
  Map<TipoModulo, DatosPrecisionIntraTolerancia> generarAnalisisIntraToleranciaV2() {
    final Map<TipoModulo, DatosPrecisionIntraTolerancia> resultados = {};

    resultados[TipoModulo.adafruit] = _analizarModuloIntraToleranciaV2(
        _historialAdafruit,
        TipoModulo.adafruit,
        'Adafruit GPS'
    );

    resultados[TipoModulo.neo6m] = _analizarModuloIntraToleranciaV2(
        _historialNeo6m,
        TipoModulo.neo6m,
        'NEO-6M GPS'
    );

    resultados[TipoModulo.promedio] = _analizarModuloIntraToleranciaV2(
        _historialPromedio,
        TipoModulo.promedio,
        'Promedio Combinado'
    );

    return resultados;
  }

  // NUEVO REPORTE CSV con métricas mejoradas
  String generarReporteIntraToleranciaV2CSV() {
    final analisis = generarAnalisisIntraToleranciaV2();
    final buffer = StringBuffer();

    // Encabezados mejorados
    buffer.writeln('ANÁLISIS DE PRECISIÓN INTRA-TOLERANCIA V2.0');
    buffer.writeln('Módulo,Puntos Originales,Puntos Válidos,Puntos Excluidos,% Cobertura,Distancia Prom (m),Dist Min (m),Dist Max (m),Desv Std (m),Mediana (m),% Precisión Intra,Factor Calidad,Clasificación,Tolerancia (m)');

    // Datos de cada módulo
    for (final datos in analisis.values) {
      buffer.writeln(
          '${datos.nombreModulo},'
              '${datos.puntosOriginales},'
              '${datos.puntosAnalizados},'
              '${datos.puntosExcluidosPorTolerancia},'
              '${datos.porcentajePuntosValidos.toStringAsFixed(2)}%,'
              '${datos.distanciaPromedio.toStringAsFixed(3)},'
              '${datos.distanciaMinima.toStringAsFixed(3)},'
              '${datos.distanciaMaxima.toStringAsFixed(3)},'
              '${datos.desviacionEstandar.toStringAsFixed(3)},'
              '${datos.mediana.toStringAsFixed(3)},'
              '${datos.porcentajePrecisionIntraTolerancia.toStringAsFixed(2)}%,'
              '${datos.factorCalidadGlobal.toStringAsFixed(2)},'
              '${datos.clasificacionCalidad},'
              '${datos.toleranciaUtilizada.toStringAsFixed(1)}'
      );
    }

    // Análisis comparativo mejorado
    buffer.writeln('\n--- RANKINGS INTRA-TOLERANCIA ---');
    final modulosConDatos = analisis.values.where((d) => d.puntosAnalizados > 0).toList();

    if (modulosConDatos.isNotEmpty) {
      // Ranking por factor de calidad global
      final mejorCalidad = modulosConDatos
          .reduce((a, b) => a.factorCalidadGlobal > b.factorCalidadGlobal ? a : b);

      // Ranking por precisión intra-tolerancia
      final mejorPrecisionIntra = modulosConDatos
          .reduce((a, b) => a.porcentajePrecisionIntraTolerancia > b.porcentajePrecisionIntraTolerancia ? a : b);

      // Ranking por cobertura
      final mejorCobertura = modulosConDatos
          .reduce((a, b) => a.porcentajePuntosValidos > b.porcentajePuntosValidos ? a : b);

      buffer.writeln('Mejor Factor de Calidad Global,${mejorCalidad.nombreModulo},${mejorCalidad.factorCalidadGlobal.toStringAsFixed(2)}% (${mejorCalidad.clasificacionCalidad})');
      buffer.writeln('Mejor Precisión Intra-Tolerancia,${mejorPrecisionIntra.nombreModulo},${mejorPrecisionIntra.porcentajePrecisionIntraTolerancia.toStringAsFixed(2)}% (${mejorPrecisionIntra.clasificacionPrecision})');
      buffer.writeln('Mejor Cobertura de Puntos,${mejorCobertura.nombreModulo},${mejorCobertura.porcentajePuntosValidos.toStringAsFixed(2)}%');
    }

    // Información adicional
    buffer.writeln('\n--- EXPLICACIÓN DE MÉTRICAS ---');
    buffer.writeln('Precisión Intra-Tolerancia,Precisión calculada solo sobre puntos válidos (0m=100% - tolerancia=0%)');
    buffer.writeln('Factor Calidad Global,Combina precisión intra-tolerancia (70%) + cobertura puntos válidos (30%)');
    buffer.writeln('Cobertura,Porcentaje de puntos que pasaron el filtro de tolerancia');

    if (_lineaReferencia != null) {
      buffer.writeln('Línea de referencia,${_lineaReferencia!.nombre}');
      buffer.writeln('Tolerancia aplicada,${_toleranciaMetros.toStringAsFixed(1)} metros');
    }

    buffer.writeln('Fecha del análisis,${DateTime.now().toIso8601String()}');

    return buffer.toString();
  }

  // NUEVO REPORTE DETALLADO
  String generarReporteIntraToleranciaV2Detallado() {
    final analisis = generarAnalisisIntraToleranciaV2();
    final buffer = StringBuffer();

    buffer.writeln('REPORTE DETALLADO DE PRECISIÓN INTRA-TOLERANCIA V2.0');
    buffer.writeln('=' * 70);
    buffer.writeln('Fecha: ${DateTime.now().toLocal()}');
    buffer.writeln('Tolerancia: ${_toleranciaMetros.toStringAsFixed(1)} metros');
    buffer.writeln('UNIVERSO DE ESTUDIO: Solo puntos dentro de tolerancia');
    buffer.writeln('LÓGICA DE PRECISIÓN: 100% = sobre línea (0m), 0% = límite tolerancia');

    if (_lineaReferencia != null) {
      buffer.writeln('Línea de referencia: ${_lineaReferencia!.nombre}');
      buffer.writeln('Desde: ${_lineaReferencia!.puntoInicio}');
      buffer.writeln('Hasta: ${_lineaReferencia!.puntoFin}');
    }

    buffer.writeln('');

    // Resumen detallado por módulo
    for (final datos in analisis.values) {
      buffer.writeln('━' * 60);
      buffer.writeln('${datos.nombreModulo.toUpperCase()}');
      buffer.writeln('━' * 60);

      // Estadísticas de cobertura
      buffer.writeln('📊 COBERTURA DE DATOS:');
      buffer.writeln('  • Total puntos originales: ${datos.puntosOriginales}');
      buffer.writeln('  • Puntos válidos (dentro tolerancia): ${datos.puntosAnalizados}');
      buffer.writeln('  • Puntos excluidos (fuera tolerancia): ${datos.puntosExcluidosPorTolerancia}');
      buffer.writeln('  • Porcentaje de cobertura: ${datos.porcentajePuntosValidos.toStringAsFixed(2)}%');

      if (datos.puntosAnalizados > 0) {
        // Estadísticas de precisión intra-tolerancia
        buffer.writeln('\n🎯 ANÁLISIS DE PRECISIÓN INTRA-TOLERANCIA:');
        buffer.writeln('  • Distancia promedio: ${datos.distanciaPromedio.toStringAsFixed(3)} m');
        buffer.writeln('  • Distancia mínima: ${datos.distanciaMinima.toStringAsFixed(3)} m');
        buffer.writeln('  • Distancia máxima: ${datos.distanciaMaxima.toStringAsFixed(3)} m');
        buffer.writeln('  • Desviación estándar: ${datos.desviacionEstandar.toStringAsFixed(3)} m');
        buffer.writeln('  • Mediana: ${datos.mediana.toStringAsFixed(3)} m');

        // Métricas principales
        buffer.writeln('\n⭐ MÉTRICAS PRINCIPALES:');
        buffer.writeln('  • Precisión Intra-Tolerancia: ${datos.porcentajePrecisionIntraTolerancia.toStringAsFixed(2)}% (${datos.clasificacionPrecision})');
        buffer.writeln('  • Factor de Calidad Global: ${datos.factorCalidadGlobal.toStringAsFixed(2)}% (${datos.clasificacionCalidad})');

        // Interpretación
        buffer.writeln('\n💡 INTERPRETACIÓN:');
        if (datos.porcentajePrecisionIntraTolerancia >= 90) {
          buffer.writeln('  • Excelente precisión dentro del área de tolerancia');
        } else if (datos.porcentajePrecisionIntraTolerancia >= 70) {
          buffer.writeln('  • Buena precisión, con margen de mejora');
        } else {
          buffer.writeln('  • Precisión mejorable, considerar ajustes en configuración');
        }

        if (datos.porcentajePuntosValidos < 50) {
          buffer.writeln('  • ⚠️  Baja cobertura de puntos válidos, considerar aumentar tolerancia');
        }
      } else {
        buffer.writeln('\n❌ Sin datos válidos dentro de la tolerancia especificada');
      }
      buffer.writeln('');
    }

    // Comparación entre módulos
    buffer.writeln('━' * 70);
    buffer.writeln('COMPARACIÓN ENTRE MÓDULOS');
    buffer.writeln('━' * 70);

    final modulosValidos = analisis.values.where((d) => d.puntosAnalizados > 0).toList();

    if (modulosValidos.isEmpty) {
      buffer.writeln('❌ No hay datos suficientes para comparar entre módulos.');
      return buffer.toString();
    }

    // Ranking por factor de calidad global
    buffer.writeln('🏆 RANKING POR FACTOR DE CALIDAD GLOBAL:');
    final sortedByCalidad = modulosValidos.toList()
      ..sort((a, b) => b.factorCalidadGlobal.compareTo(a.factorCalidadGlobal));

    for (int i = 0; i < sortedByCalidad.length; i++) {
      final datos = sortedByCalidad[i];
      final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '  ';
      buffer.writeln('  $medal ${i + 1}. ${datos.nombreModulo}: ${datos.factorCalidadGlobal.toStringAsFixed(2)}% (${datos.clasificacionCalidad})');
    }

    // Ranking por precisión intra-tolerancia
    buffer.writeln('\n🎯 RANKING POR PRECISIÓN INTRA-TOLERANCIA:');
    final sortedByPrecision = modulosValidos.toList()
      ..sort((a, b) => b.porcentajePrecisionIntraTolerancia.compareTo(a.porcentajePrecisionIntraTolerancia));

    for (int i = 0; i < sortedByPrecision.length; i++) {
      final datos = sortedByPrecision[i];
      final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '  ';
      buffer.writeln('  $medal ${i + 1}. ${datos.nombreModulo}: ${datos.porcentajePrecisionIntraTolerancia.toStringAsFixed(2)}% (${datos.clasificacionPrecision})');
    }

    // Ranking por cobertura
    buffer.writeln('\n📊 RANKING POR COBERTURA DE PUNTOS:');
    final sortedByCobertura = modulosValidos.toList()
      ..sort((a, b) => b.porcentajePuntosValidos.compareTo(a.porcentajePuntosValidos));

    for (int i = 0; i < sortedByCobertura.length; i++) {
      final datos = sortedByCobertura[i];
      final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '  ';
      buffer.writeln('  $medal ${i + 1}. ${datos.nombreModulo}: ${datos.porcentajePuntosValidos.toStringAsFixed(2)}%');
    }

    return buffer.toString();
  }

  // Mantener métodos originales para compatibilidad
  Map<TipoModulo, DatosPrecisionIntraTolerancia> generarAnalisisIntraTolerancia() {
    return generarAnalisisIntraToleranciaV2();
  }

  // Wrapper para mantener compatibilidad con métodos antiguos
  String generarReporteIntraToleranciaCSV() {
    return generarReporteIntraToleranciaV2CSV();
  }

  String generarReporteIntraToleranciaDetallado() {
    return generarReporteIntraToleranciaV2Detallado();
  }

  // Estadísticas rápidas mejoradas
  Map<String, dynamic> obtenerEstadisticasIntraToleranciaV2() {
    final analisis = generarAnalisisIntraToleranciaV2();
    final modulosValidos = analisis.values.where((d) => d.puntosAnalizados > 0).toList();

    if (modulosValidos.isEmpty) {
      return {
        'total_puntos_analizados': 0,
        'mejor_modulo_calidad': 'N/A',
        'mejor_factor_calidad': 0.0,
        'mejor_modulo_precision': 'N/A',
        'mejor_precision_intra': 0.0,
        'tiene_linea_referencia': _lineaReferencia != null,
        'tolerancia_actual': _toleranciaMetros,
        'mensaje': 'No hay puntos dentro de la tolerancia especificada',
      };
    }

    final totalPuntosAnalizados = modulosValidos.map((d) => d.puntosAnalizados).reduce((a, b) => a + b);
    final mejorCalidad = modulosValidos.reduce((a, b) => a.factorCalidadGlobal > b.factorCalidadGlobal ? a : b);
    final mejorPrecision = modulosValidos.reduce((a, b) => a.porcentajePrecisionIntraTolerancia > b.porcentajePrecisionIntraTolerancia ? a : b);

    return {
      'total_puntos_analizados': totalPuntosAnalizados,
      'mejor_modulo_calidad': mejorCalidad.nombreModulo,
      'mejor_factor_calidad': mejorCalidad.factorCalidadGlobal,
      'mejor_modulo_precision': mejorPrecision.nombreModulo,
      'mejor_precision_intra': mejorPrecision.porcentajePrecisionIntraTolerancia,
      'clasificacion_mejor': mejorCalidad.clasificacionCalidad,
      'tiene_linea_referencia': _lineaReferencia != null,
      'tolerancia_actual': _toleranciaMetros,
    };
  }

  // RESTO DE MÉTODOS ORIGINALES (mantenidos para compatibilidad)

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

    if (A == B) return double.infinity;

    final double x0 = punto.longitude;
    final double y0 = punto.latitude;
    final double x1 = A.longitude;
    final double y1 = A.latitude;
    final double x2 = B.longitude;
    final double y2 = B.latitude;

    final double numerador = ((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1).abs();
    final double denominador = sqrt(pow(y2 - y1, 2) + pow(x2 - x1, 2));

    final double distanciaGrados = numerador / denominador;
    return distanciaGrados * 111320;
  }

  // Método original de análisis (para compatibilidad)
  DatosPrecision _analizarModulo(List<GeoPoint> historial, TipoModulo tipoModulo, String nombre) {
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

  // Genera el análisis completo original
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

  // Genera reporte en formato CSV original
  String generarReporteCSV() {
    final analisis = generarAnalisisCompleto();
    final buffer = StringBuffer();

    buffer.writeln('Módulo,Puntos Totales,Puntos Cercanos,Porcentaje Precisión,Distancia Promedio (m),Distancia Mínima (m),Distancia Máxima (m),Tolerancia (m),Línea Referencia');

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

    buffer.writeln('\n--- ANÁLISIS COMPARATIVO ---');

    final mejorPorcentaje = analisis.values
        .reduce((a, b) => a.porcentajePrecision > b.porcentajePrecision ? a : b);

    final mejorDistanciaPromedio = analisis.values
        .reduce((a, b) => a.distanciaPromedio < b.distanciaPromedio ? a : b);

    buffer.writeln('Mejor Porcentaje de Precisión,${mejorPorcentaje.nombreModulo},${mejorPorcentaje.porcentajePrecision.toStringAsFixed(2)}%');
    buffer.writeln('Mejor Distancia Promedio,${mejorDistanciaPromedio.nombreModulo},${mejorDistanciaPromedio.distanciaPromedio.toStringAsFixed(3)} m');

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

  // Genera reporte detallado original
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

  // Guarda y comparte el reporte V2
  Future<void> generarYCompartirReporteIntraToleranciaV2({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final nombreBase = nombrePersonalizado ?? 'reporte_precision_intra_v2_$timestamp';

      // Generar archivo CSV
      final csvContent = generarReporteIntraToleranciaV2CSV();
      final csvFile = File('${directory.path}/${nombreBase}.csv');
      await csvFile.writeAsString(csvContent, encoding: utf8);

      List<String> archivosACompartir = [csvFile.path];

      // Generar archivo detallado si se solicita
      if (incluirDetallado) {
        final detalladoContent = generarReporteIntraToleranciaV2Detallado();
        final detalladoFile = File('${directory.path}/${nombreBase}_detallado.txt');
        await detalladoFile.writeAsString(detalladoContent, encoding: utf8);
        archivosACompartir.add(detalladoFile.path);
      }

      // Compartir archivos
      await Share.shareXFiles(
        archivosACompartir.map((path) => XFile(path)).toList(),
        text: 'Reporte de precisión GPS Intra-Tolerancia V2 - ${DateTime.now().toLocal()}',
        subject: 'Análisis de Precisión GPS Intra-Tolerancia V2.0',
      );

    } catch (e) {
      throw Exception('Error al generar reporte intra-tolerancia V2: $e');
    }
  }

  // Método original para compatibilidad
  Future<void> generarYCompartirReporteIntraTolerancia({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    return generarYCompartirReporteIntraToleranciaV2(
      incluirDetallado: incluirDetallado,
      nombrePersonalizado: nombrePersonalizado,
    );
  }

  // Guarda y comparte el reporte original
  Future<void> generarYCompartirReporte({
    bool incluirDetallado = true,
    String? nombrePersonalizado,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final nombreBase = nombrePersonalizado ?? 'reporte_precision_gps_$timestamp';

      final csvContent = generarReporteCSV();
      final csvFile = File('${directory.path}/${nombreBase}.csv');
      await csvFile.writeAsString(csvContent, encoding: utf8);

      List<String> archivosACompartir = [csvFile.path];

      if (incluirDetallado) {
        final detalladoContent = generarReporteDetallado();
        final detalladoFile = File('${directory.path}/${nombreBase}_detallado.txt');
        await detalladoFile.writeAsString(detalladoContent, encoding: utf8);
        archivosACompartir.add(detalladoFile.path);
      }

      await Share.shareXFiles(
        archivosACompartir.map((path) => XFile(path)).toList(),
        text: 'Reporte de precisión GPS - ${DateTime.now().toLocal()}',
        subject: 'Análisis de Precisión GPS',
      );

    } catch (e) {
      throw Exception('Error al generar reporte: $e');
    }
  }

  // Obtiene estadísticas rápidas originales
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

  // Wrapper para estadísticas intra-tolerancia (mantener compatibilidad)
  Map<String, dynamic> obtenerEstadisticasIntraTolerancia() {
    return obtenerEstadisticasIntraToleranciaV2();
  }

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