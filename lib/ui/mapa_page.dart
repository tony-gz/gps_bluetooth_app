import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geopoint.dart';
import '../services/archivo_gps.dart';
import '../services/puntos_guardados_service.dart';
import '../services/editor_de_lineas.dart';
import '../services/linea.dart';
import '../services/recorrido_service.dart';
import '../services/visualizador_zonas.dart';
import '../services/leyenda_zonas_widget.dart';
import '../ui/seleccionar_dispositivo_page.dart';
import '../services/comparador_precision_gps.dart';

class MapaPage extends StatefulWidget {
  final BluetoothConnection conexion;
  const MapaPage({Key? key, required this.conexion}) : super(key: key);
  @override
  State<MapaPage> createState() => _MapaPageState();
}
extension TakeLastExtension<T> on List<T> {
  List<T> takeLast(int count) => length <= count ? this : sublist(length - count);
}
class _MapaPageState extends State<MapaPage> {
  LatLng _posicion = const LatLng(17.5515346, -99.5006322);
  late StreamSubscription _listener;

  RecorridoService? _recorridoService;

  GeoPoint? _puntoAdafruit;
  GeoPoint? _puntoNeo6m;
  GeoPoint? _puntoC;
  final List<GeoPoint> _historial = [];
  final List<Marker> _manualMarkers = [];

  final List<GeoPoint> _historialAdafruit = [];
  final List<GeoPoint> _historialNeo6m = [];
  final List<GeoPoint> _historialPromedio = [];

  final ArchivoGPS _archivoGPS = ArchivoGPS();
  final MapController _mapController = MapController();
  final Distance _distance = Distance();

  final EditorDeLineas editorDeLineas = EditorDeLineas();


  static const double minDistanceMeters = 0.2;

  //Psiciones de los pines
  final ValueNotifier<LatLng> posicionActual = ValueNotifier(const LatLng(0, 0));
  final ValueNotifier<LatLng?> posicionAdafruit = ValueNotifier(null);
  final ValueNotifier<LatLng?> posicionNeo6m = ValueNotifier(null);
  final ValueNotifier<LatLng?> posicionCombinada = ValueNotifier(null);

  // ✅ NUEVA INSTANCIA DEL SERVICIO
  final VisualizadorZonas _visualizadorZonas = VisualizadorZonas();

  //Instancia del comparardor de precisión
  final ComparadorPrecisionGPS _comparadorPrecision = ComparadorPrecisionGPS();


  // Waypoints normales
  List<LatLng> waypoints = [];
  // Nuevo: puntos para la línea
  List<LatLng> lineaWaypoints = [];
  // Modo: ¿estás colocando la línea?
  bool modoAgregarLinea = false;

  List<LatLng> puntosFiltrados = [];
  double toleranciaMetros = 5.0;
  bool mostrarSlider = false;

  Future<void> _desconectarYRegresarABluetoothSelection() async {
    // Mostrar diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.blue),
            SizedBox(width: 8),
            Text('Cambiar conexión'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Deseas desconectarte del dispositivo actual y seleccionar otro?'),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se perderá la conexión actual',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cambiar dispositivo'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _ejecutarDesconexionYNavegacion();
    }
  }

  Future<void> _ejecutarDesconexionYNavegacion() async {
    try {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Desconectando dispositivo...'),
            ],
          ),
        ),
      );

      // 1. Cancelar el listener de Bluetooth
      await _listener.cancel();

      // 2. Cerrar la conexión Bluetooth
      if (widget.conexion.isConnected) {
        await widget.conexion.close();
      }

      // 3. Limpiar recursos locales (opcional)
      _limpiarRecursosLocales();

      // Cerrar diálogo de carga
      if (mounted) Navigator.of(context).pop();

      // 4. Navegar a la selección de dispositivos
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const SeleccionarDispositivoPage(),
          ),
        );
      }

    } catch (e) {
      // Cerrar diálogo de carga si está abierto
      if (mounted) Navigator.of(context).pop();

      // Mostrar error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desconectar: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: _ejecutarDesconexionYNavegacion,
            ),
          ),
        );
      }
    }
  }

  void _limpiarRecursosLocales() {
    // Limpiar historiales si es necesario
    setState(() {
      // Opcional: limpiar datos para empezar fresh
      // _historialGlobal.clear();
      // _historial.clear();
      // _visualizadorZonas.limpiar();
    });
  }

  GeoPoint? _puntoZona;
  final double _radioZona = 10.0; // metros
  final int _maxPuntosZona = 200;

  List<GeoPoint> _historialZona = [];
  List<GeoPoint> _historialGlobal = [];


  bool _estaEnMismaZona(GeoPoint nuevoPunto) {
    if (_puntoZona == null) return false;
    final d = const Distance();
    final p1 = LatLng(_puntoZona!.latitud, _puntoZona!.longitud);
    final p2 = LatLng(nuevoPunto.latitud, nuevoPunto.longitud);
    return d(p1, p2) <= _radioZona;
  }
/*
  void _limpiarHistorialGlobal() {
    setState(() {
      // Limpiar todos los historiales
      _historialGlobal.clear();
      _historial.clear();
      _historialZona.clear();
      _historialAdafruit.clear();
      _historialNeo6m.clear();
      _historialPromedio.clear();

      // Reiniciar puntos de zona
      _puntoZona = null;
      // Limpiar el visualizador de zonas
      _visualizadorZonas.limpiar();
      // Opcional: También podrías limpiar los puntos GPS actuales
      _puntoAdafruit = null;
      _puntoNeo6m = null;
      _puntoC = null;
    });
    print('🧹 Historial global limpiado: todos los datos eliminados');
  }

 */
  // Modificar el método _limpiarHistorialGlobal para incluir el comparador:
  void _limpiarHistorialGlobal() {
    setState(() {
      _historialGlobal.clear();
      _historial.clear();
      _historialZona.clear();
      _historialAdafruit.clear();
      _historialNeo6m.clear();
      _historialPromedio.clear();
      _puntoZona = null;
      _visualizadorZonas.limpiar();

      // ✅ LIMPIAR COMPARADOR
      _comparadorPrecision.limpiarHistorial();

      _puntoAdafruit = null;
      _puntoNeo6m = null;
      _puntoC = null;
    });
    print('🧹 Historial global limpiado: todos los datos eliminados');
  }

  void _toggleVisualizacionZonas() {
    final estaActivoAhora = _visualizadorZonas.toggle(_historialGlobal);
    setState(() {}); // Actualizar UI
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(estaActivoAhora
            ? 'Mostrando ${_visualizadorZonas.numeroDeZonas} zonas con colores'
            : 'Visualización por zonas desactivada'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _procesarPunto(GeoPoint punto) {
    if (_puntoZona == null || !_estaEnMismaZona(punto)) {
      // Nueva zona: cambiar punto de referencia
      _puntoZona = punto;
      _historialZona.clear(); // Limpiar zona actual
      _historialZona.add(punto);

      // ✅ SIEMPRE agregar al historial global
      _historialGlobal.add(punto);

      print('🆕 Nueva zona iniciada. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
    } else {
      // Misma zona: SIEMPRE agregar al historial global
      _historialGlobal.add(punto);

      if (_historialZona.length < _maxPuntosZona) {
        // Aún hay espacio en la zona, agregar normalmente
        _historialZona.add(punto);
        print('➕ Agregado a zona. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
      } else {
        // ✅ BUFFER CIRCULAR: La zona está llena, eliminar el más antiguo y agregar el nuevo
        _historialZona.removeAt(0); // Eliminar el primer elemento (más antiguo)
        _historialZona.add(punto);  // Agregar el nuevo al final
        print('🔄 Buffer circular. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length} (máx: $_maxPuntosZona)');
      }
    }
    _limpiarHistorialAntiguo();
  }

  // Función auxiliar para verificar el estado (puedes llamarla ocasionalmente para debug)
  void _imprimirEstadoHistorial() {
    print('=' * 50);
    print('📊 ESTADO DEL HISTORIAL:');
    print('🌍 Historial Global: ${_historialGlobal.length} puntos');
    print('📍 Historial Zona: ${_historialZona.length} puntos (máx: $_maxPuntosZona)');
    if (_puntoZona != null) {
      print('🎯 Zona actual centrada en: ${_puntoZona!.latitud}, ${_puntoZona!.longitud}');
      print('📐 Radio de zona: $_radioZona metros');
    }
    print('=' * 50);
  }

  // FUNCIÓN PARA VERIFICAR ESTADO DE CONEXIÓN PERIODICAMENTE
  Timer? _timerConexion;
  void _iniciarMonitoreoConexion() {
    _timerConexion = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!widget.conexion.isConnected) {
        // Conexión perdida, mostrar mensaje
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.white),
                SizedBox(width: 8),
                Text('Conexión Bluetooth perdida'),
              ],
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Reconectar',
              onPressed: _desconectarYRegresarABluetoothSelection,
            ),
            duration: const Duration(seconds: 10),
          ),
        );
        timer.cancel();
      }
    });
  }

// Llamar en initState si quieres monitoreo automático
  @override
  void initState() {
    super.initState();
    _iniciarLecturaBluetooth();
    _iniciarMonitoreoConexion(); // Opcional
  }

// Y cancelar en dispose
  @override
  void dispose() {
    _listener.cancel();
    _timerConexion?.cancel(); // Cancelar timer
    _visualizadorZonas.limpiar();
    super.dispose();
  }

  bool estaCercaDeLinea(LatLng punto, LatLng A, LatLng B, double toleranciaMetros) {
    final Distance distance = const Distance();
    // Si los puntos A y B son iguales, no hay línea real
    if (A == B) return false;
    final double x0 = punto.longitude;
    final double y0 = punto.latitude;
    final double x1 = A.longitude;
    final double y1 = A.latitude;
    final double x2 = B.longitude;
    final double y2 = B.latitude;

    final double numerador = ((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1).abs();
    final double denominador = sqrt(pow((y2 - y1), 2) + pow((x2 - x1), 2));
    final double distanciaGrados = numerador / denominador;
    final double distanciaMetros = distanciaGrados * 111320;
    return distanciaMetros <= toleranciaMetros;
  }
/*
  void _iniciarLecturaBluetooth() {
    _listener = widget.conexion.input!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((data) async {
      final punto = _parsearPosicion(data); // Debe devolver GeoPoint

      if (punto != null) {
        posicionActual.value = LatLng(punto.latitud, punto.longitud);

        setState(() {
          _posicion = LatLng(punto.latitud, punto.longitud);

          // Filtramos y guardamos puntos
          _procesarPunto(punto);

          // Actualizar historial de visualización con el historial global completo
          _historial
            ..clear()
            ..addAll(_historialGlobal);

          // Debug cada 10 puntos para ver el progreso
          if (_historialGlobal.length % 10 == 0) {
            _imprimirEstadoHistorial();
          }

          const int maxHistorial = 20;




          if (data.startsWith("A")) {
            if (_puntoAdafruit == null || _distance(_puntoAdafruit!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoAdafruit = punto;
              _historialAdafruit.add(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialAdafruit.length > maxHistorial) {
                _historialAdafruit.removeAt(0);
              }
            }
          } else if (data.startsWith("N")) {
            if (_puntoNeo6m == null || _distance(_puntoNeo6m!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoNeo6m = punto;
              _historialNeo6m.add(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialNeo6m.length > maxHistorial) {
                _historialNeo6m.removeAt(0);
              }
            }
          } else if (data.startsWith("C")) {
            if (_puntoC == null || _distance(_puntoC!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoC = punto;
              _historialPromedio.add(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialPromedio.length > maxHistorial) {
                _historialPromedio.removeAt(0);
              }
            }
          }
        });

        final linea = '${punto.tiempo.toIso8601String()},${punto.latitud},${punto.longitud}';
        await _archivoGPS.guardar(linea);
      }
    });
  }

 */
  void _iniciarLecturaBluetooth() {
    _listener = widget.conexion.input!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((data) async {
      final punto = _parsearPosicion(data);

      if (punto != null) {
        posicionActual.value = LatLng(punto.latitud, punto.longitud);

        setState(() {
          _posicion = LatLng(punto.latitud, punto.longitud);
          _procesarPunto(punto);
          _historial..clear()..addAll(_historialGlobal);

          if (_historialGlobal.length % 10 == 0) {
            _imprimirEstadoHistorial();
          }

          const int maxHistorial = 1000;

          if (data.startsWith("A")) {
            if (_puntoAdafruit == null || _distance(_puntoAdafruit!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoAdafruit = punto;
              _historialAdafruit.add(punto);

              // ✅ AGREGAR AL COMPARADOR
              _comparadorPrecision.agregarPuntoAdafruit(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialAdafruit.length > maxHistorial) {
                _historialAdafruit.removeAt(0);
              }
            }
          } else if (data.startsWith("N")) {
            if (_puntoNeo6m == null || _distance(_puntoNeo6m!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoNeo6m = punto;
              _historialNeo6m.add(punto);

              // ✅ AGREGAR AL COMPARADOR
              _comparadorPrecision.agregarPuntoNeo6m(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialNeo6m.length > maxHistorial) {
                _historialNeo6m.removeAt(0);
              }
            }
          } else if (data.startsWith("C")) {
            if (_puntoC == null || _distance(_puntoC!.toLatLng(), LatLng(punto.latitud, punto.longitud)) >= minDistanceMeters) {
              _puntoC = punto;
              _historialPromedio.add(punto);

              // ✅ AGREGAR AL COMPARADOR
              _comparadorPrecision.agregarPuntoPromedio(punto);

              _recorridoService?.procesarPosicion(_posicion);
              _recorridoService?.procesarPosicion(LatLng(punto.latitud, punto.longitud));

              if (_historialPromedio.length > maxHistorial) {
                _historialPromedio.removeAt(0);
              }
            }
          }
        });

        final linea = '${punto.tiempo.toIso8601String()},${punto.latitud},${punto.longitud}';
        await _archivoGPS.guardar(linea);
      }
    });
  }

  // Agregar método para configurar el análisis cuando se selecciona una línea:
  void _configurarAnalisisPrecision() {
    final lineaSeleccionada = editorDeLineas.lineaSeleccionada;
    if (lineaSeleccionada != null) {
      _comparadorPrecision.configurarAnalisis(
        toleranciaMetros: toleranciaMetros,
        lineaReferencia: lineaSeleccionada,
      );
    }
  }


  // Agregar método para mostrar estadísticas rápidas:
  void _mostrarEstadisticasPrecision() {
    final stats = _comparadorPrecision.obtenerEstadisticasRapidas();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('Estadísticas de Precisión'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total de puntos analizados: ${stats['total_puntos']}'),
            const SizedBox(height: 8),
            Text('Mejor módulo: ${stats['mejor_modulo']}'),
            Text('Precisión: ${stats['mejor_precision'].toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            Text('Promedio general: ${stats['promedio_general'].toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            Text('Tolerancia actual: ${stats['tolerancia_actual'].toStringAsFixed(1)}m'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  stats['tiene_linea_referencia'] ? Icons.check_circle : Icons.warning,
                  color: stats['tiene_linea_referencia'] ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  stats['tiene_linea_referencia']
                      ? 'Línea de referencia configurada'
                      : 'Sin línea de referencia',
                  style: TextStyle(
                    color: stats['tiene_linea_referencia'] ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _generarReportePrecision();
            },
            child: const Text('Generar Reporte'),
          ),
        ],
      ),
    );
  }

  // Agregar método para generar reporte:
  Future<void> _generarReportePrecision() async {
    final lineaSeleccionada = editorDeLineas.lineaSeleccionada;

    if (lineaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selecciona una línea de referencia primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Configurar análisis con la línea actual
    _configurarAnalisisPrecision();

    try {
      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generando reporte de precisión...'),
            ],
          ),
        ),
      );

      // Generar el reporte
      await _comparadorPrecision.generarYCompartirReporte(
        incluirDetallado: true,
        nombrePersonalizado: 'precision_${lineaSeleccionada.nombre}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Cerrar diálogo de progreso
      Navigator.pop(context);

      // Mostrar mensaje de éxito
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Reporte de precisión generado y compartido'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      // Cerrar diálogo de progreso
      Navigator.pop(context);

      // Mostrar error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al generar reporte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


// Función para limpiar historial antiguo si se vuelve muy grande
  void _limpiarHistorialAntiguo() {
    const int maxPuntosGlobales = 1000; // Límite total para evitar problemas de memoria

    if (_historialGlobal.length > maxPuntosGlobales) {
      // Mantener solo los últimos puntos, eliminando los más antiguos
      final puntosAEliminar = _historialGlobal.length - maxPuntosGlobales;
      _historialGlobal.removeRange(0, puntosAEliminar);
    }
  }

  GeoPoint? _parsearPosicion(String data) {
    try {
      final partes = data.trim().split(',');
      if (partes.length != 3) return null;
      final lat = double.parse(partes[1]);
      final lng = double.parse(partes[2]);
      final tiempo = DateTime.now();
      return GeoPoint(latitud: lat, longitud: lng, tiempo: tiempo);
    } catch (_) {
      return null;
    }
  }
  void _toggleManualMarker(LatLng tappedLatLng) {
    const double threshold = 0.00001; // Aprox ~5m según zoom

    final existing = _manualMarkers.indexWhere((m) {
      return (m.point.latitude - tappedLatLng.latitude).abs() < threshold &&
          (m.point.longitude - tappedLatLng.longitude).abs() < threshold;
    });
    setState(() {
      if (existing != -1) {
        _manualMarkers.removeAt(existing); // Borrar si ya existía cerca
      } else {
        _manualMarkers.add(
          Marker(
            point: tappedLatLng,
            width: 40,
            height: 40,
            child: const Icon(Icons.flag, color: Colors.blue, size: 30),
          ),
        );
      }
    });
  }
  @override
  Widget build(BuildContext context) {

    // Convertimos a LatLng las listas ya existentes
    List<LatLng> puntosAdafruit = _historialAdafruit.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosNeo6m = _historialNeo6m.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosPromedio = _historialPromedio.map((p) => p.toLatLng()).toList();

    List<LatLng> ultimosAdafruit = puntosAdafruit.length <= 1000
        ? puntosAdafruit
        : puntosAdafruit.sublist(puntosAdafruit.length - 1000);

    List<LatLng> ultimosNeo6m = puntosNeo6m.length <= 10
        ? puntosNeo6m
        : puntosNeo6m.sublist(puntosNeo6m.length - 10);

    List<LatLng> ultimosPromedio = puntosPromedio.length <= 10
        ? puntosPromedio
        : puntosPromedio.sublist(puntosPromedio.length - 10);


// Si hay línea, filtramos por cercanía
    final lineaSeleccionada = editorDeLineas.lineaSeleccionada;
    if (lineaSeleccionada != null) {
      final A = lineaSeleccionada.puntoInicio;
      final B = lineaSeleccionada.puntoFin;

      ultimosAdafruit = ultimosAdafruit.where((p) => estaCercaDeLinea(p, A, B, toleranciaMetros)).toList();
      ultimosNeo6m = ultimosNeo6m.where((p) => estaCercaDeLinea(p, A, B, toleranciaMetros)).toList();
      ultimosPromedio = ultimosPromedio.where((p) => estaCercaDeLinea(p, A, B, toleranciaMetros)).toList();
    }


    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa en tiempo real'),
        leading: IconButton(
          icon: const Icon(Icons.bluetooth),
          onPressed: _desconectarYRegresarABluetoothSelection,
          tooltip: 'Cambiar dispositivo Bluetooth',
        ),
        actions: [
          // Estado de conexión (opcional)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: widget.conexion.isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.conexion.isConnected
                    ? Colors.green
                    : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.conexion.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  size: 16,
                  color: widget.conexion.isConnected
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.conexion.isConnected ? 'Conectado' : 'Desconectado',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.conexion.isConnected
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          /*
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                waypoints.clear();
                //_manualMarkers.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                lineaWaypoints.clear(); // borra los puntos
                modoAgregarLinea = false;
              });
            },
            tooltip: 'Borrar línea A-B',
          )

           */

        ],
      ),
      body: Stack(
        children: [
          const SizedBox.expand(),
        Column(
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: _posicion,
                    zoom: 14,
                    onTap: (tapPosition, point) {
                      final modo = editorDeLineas.modoEditor;

                      if (modo == ModoEditorLinea.agregar) {
                        setState(() {
                          editorDeLineas.agregarPunto(point);
                        });
                      } else if (modo == ModoEditorLinea.seleccionar) {
                        try {
                          final lineaTocada = editorDeLineas.lineas.firstWhere((linea) {
                            final dist = Distance();
                            final segmentos = linea.dividirEnSegmentos(1.0);
                            return segmentos.any((p) => dist(p.posicion, point) < 10);
                          });

                          editorDeLineas.seleccionarLinea(lineaTocada);
                          _mostrarDialogoLinea(context, lineaTocada);
                        } catch (_) {}
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: 'com.example.gps_bluetooth_app',
                    ),

                    // ✅ LAYERS PARA VISUALIZACIÓN POR ZONAS
                    if (_visualizadorZonas.estaActivo)
                      CircleLayer(circles: _visualizadorZonas.obtenerCirculos()),

                    if (_visualizadorZonas.estaActivo)
                      MarkerLayer(markers: _visualizadorZonas.obtenerMarkers()),




                    if (lineaWaypoints.length == 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: lineaWaypoints,
                            color: Colors.blue,
                            strokeWidth: 2.0,
                          ),
                        ],
                      ),
                    PolylineLayer(
                      polylines: editorDeLineas.obtenerPolilineas(),
                    ),

                    /*
                    // En el build(), después de las polilíneas existentes, agregar:
                    PolylineLayer(
                      polylines: [
                        if (_historialGlobal.length > 1)
                          Polyline(
                            points: _historialGlobal.map((p) => LatLng(p.latitud, p.longitud)).toList(),
                            color: Colors.blue.withOpacity(0.7),
                            strokeWidth: 3.0,
                          ),
                      ],
                    ),

                     */


                    if (_recorridoService != null)
                      MarkerLayer(
                        markers: _recorridoService!.obtenerSubWaypoints().map((sw) {
                          return Marker(
                            point: sw.posicion,
                            width: 14,
                            height: 14,
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: sw.esInicio || sw.esFinal
                                  ? Colors.blue
                                  : sw.visitado
                                  ? Colors.grey
                                  : Colors.purple,
                            ),
                          );
                        }).toList(),
                      ),

                    MarkerLayer(
                      markers: lineaWaypoints.map((p) => Marker(
                        point: p,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.flag, color: Colors.purpleAccent, size: 30),
                      )).toList(),
                    ),
                    MarkerLayer(
                      markers: waypoints.map((p) => Marker(
                        point: p,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.flag, color: Colors.orange, size: 18),
                      )).toList(),
                    ),
                    MarkerLayer(
                      markers: [
                        ...ultimosAdafruit.map((p) => Marker(
                          point: p,
                          width: 15,
                          height: 15,
                          child: const Icon(Icons.circle, color: Colors.green, size: 5),
                        )),
                        ...ultimosNeo6m.map((p) => Marker(
                          point: p,
                          width: 15,
                          height: 15,
                          child: const Icon(Icons.circle, color: Colors.red, size: 5),
                        )),
                        ...ultimosPromedio.map((p) => Marker(
                          point: p,
                          width: 15,
                          height: 15,
                          child: const Icon(Icons.circle, color: Colors.black, size: 5),
                        )),



                        if (_puntoAdafruit != null)
                          Marker(
                            point: _puntoAdafruit!.toLatLng(),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.location_pin, color: Colors.green),
                          ),
                        if (_puntoNeo6m != null)
                          Marker(
                            point: _puntoNeo6m!.toLatLng(),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.location_pin, color: Colors.red),
                          ),
                        if (_puntoC != null)
                          Marker(
                            point: _puntoC!.toLatLng(),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.location_pin, color: Colors.black54),
                          ),


                        ..._manualMarkers,
                      ],
                    ),
                    MarkerLayer(
                      markers: editorDeLineas.lineas.expand((linea) {
                        final letras = linea.nombre.split('-');
                        return [
                          Marker(
                            point: linea.puntoInicio,
                            width: 40,
                            height: 40,
                            child: _buildVerticeDraggable(
                              letra: letras.first,
                              idLinea: linea.id,
                              moverInicio: true,
                              posicion: linea.puntoInicio,
                              mapController: _mapController,
                              context: context,
                            ),
                          ),
                          Marker(
                            point: linea.puntoFin,
                            width: 40,
                            height: 40,
                            child: _buildVerticeDraggable(
                              letra: letras.last,
                              idLinea: linea.id,
                              moverInicio: false,
                              posicion: linea.puntoFin,
                              mapController: _mapController,
                              context: context,
                            ),
                          ),
                        ];
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (mostrarSlider)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tolerancia: ${toleranciaMetros.toStringAsFixed(1)} m',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    min: 1.0,
                    max: 20.0,
                    divisions: 19,
                    value: toleranciaMetros,
                    label: '${toleranciaMetros.toStringAsFixed(1)} m',
                    onChanged: (value) {
                      setState(() {
                        toleranciaMetros = value;
                      });
                    },
                  ),
                ],
              ),
            ),

          Expanded(
            flex: 4,
            child: Column(
              children: [

                if (_recorridoService != null)
                  ValueListenableBuilder<String>(
                    valueListenable: _recorridoService!.ultimoMensaje,
                    builder: (context, mensaje, _) {
                      if (mensaje.isEmpty) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        color: Colors.blue[200],
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          mensaje,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  ),


                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: ListView.builder(
                      itemCount: _historial.length,
                      itemBuilder: (_, index) {
                        final p = _historial[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            '${p.tiempo.toLocal()} - Lat: ${p.latitud}, Lng: ${p.longitud}',
                            style: const TextStyle(color: Colors.black),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          // ✅ LEYENDA DE ZONAS
          LeyendaZonasWidget(
            visualizador: _visualizadorZonas,
            onZonaTap: () {
              // Opcional: acción cuando se toca una zona en la leyenda
              print('Zona tocada en la leyenda');
            },
            onLimpiarPuntosGlobales: _limpiarHistorialGlobal,
            mostrarEstadisticas: true,
          ),


        ],
      ),

      floatingActionButton: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Agregar estos FloatingActionButtons al final de la columna de botones en el build():

// En el método build(), dentro de la Column de FloatingActionButtons, agregar estos botones:
          FloatingActionButton(
            heroTag: 'btnEstadisticas',
            tooltip: 'Ver estadísticas de precisión',
            onPressed: _mostrarEstadisticasPrecision,
            backgroundColor: Colors.deepPurple,
            child: const Icon(Icons.analytics),
          ),
          const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: 'btnReporte',
            tooltip: 'Generar reporte de precisión',
            onPressed: () {
              final lineaSeleccionada = editorDeLineas.lineaSeleccionada;
              if (lineaSeleccionada != null) {
                _generarReportePrecision();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Selecciona una línea primero')),
                );
              }
            },
            backgroundColor: Colors.indigo,
            child: const Icon(Icons.assessment),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'btnVisualizarZonas',
            onPressed: _toggleVisualizacionZonas,
            backgroundColor: _visualizadorZonas.estaActivo ? Colors.green : Colors.grey,
            tooltip: _visualizadorZonas.estaActivo
                ? 'Ocultar visualización por zonas'
                : 'Mostrar puntos por zonas con colores',
            child: Icon(
              _visualizadorZonas.estaActivo ? Icons.visibility_off : Icons.palette,
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'btn1', // Necesario si hay múltiples FABs
            onPressed: () {
              setState(() {
                mostrarSlider = !mostrarSlider;
              });
            },
            child: const Icon(Icons.tune),
            tooltip: 'Ajustar tolerancia',
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'btn2', // Diferente heroTag
            child: Icon(modoAgregarLinea ? Icons.close : Icons.timeline),
            tooltip: modoAgregarLinea
                ? 'Salir del modo línea'
                : 'Entrar al modo para agregar línea A–B',
            onPressed: () {
              setState(() {
                modoAgregarLinea = !modoAgregarLinea;
                if (modoAgregarLinea) {
                  lineaWaypoints.clear();
                }
              });
            },
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'btn3',
            tooltip: 'Guardar puntos cercanos a la línea',
            child: const Icon(Icons.save),
            onPressed: () {
              final lineaSeleccionada = editorDeLineas.lineaSeleccionada;
              if (lineaSeleccionada != null) {
                final A = lineaSeleccionada.puntoInicio;
                final B = lineaSeleccionada.puntoFin;

                bool seGuardoAlMenosUno = false;

                for (final punto in ultimosPromedio) {
                  if (estaCercaDeLinea(punto, A, B, toleranciaMetros)) {
                    PuntosGuardadosService.agregarPunto(punto);
                    seGuardoAlMenosUno = true;
                  }
                }
                for (final punto in ultimosAdafruit) {
                  if (estaCercaDeLinea(punto, A, B, toleranciaMetros)) {
                    PuntosGuardadosService.agregarPunto(punto);
                    seGuardoAlMenosUno = true;
                  }
                }
                for (final punto in ultimosNeo6m) {
                  if (estaCercaDeLinea(punto, A, B, toleranciaMetros)) {
                    PuntosGuardadosService.agregarPunto(punto);
                    seGuardoAlMenosUno = true;
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(seGuardoAlMenosUno
                      ? 'Puntos cercanos guardados'
                      : 'No se encontraron puntos cercanos a la línea')),
                );
                setState(() {}); // <-- Esto es clave para que el Drawer se actualice
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('❗ Selecciona una línea para guardar puntos cercanos')),
                );
              }
            },
          ),
          const SizedBox(height: 12),

          // Mostrar solo los siguientes botones si el editor está activo
          if (editorDeLineas.modoEditor != ModoEditorLinea.inactivo) ...[
            FloatingActionButton(
              heroTag: 'modoAgregar',
              tooltip: 'Agregar línea manual',
              onPressed: () {
                setState(() {
                  editorDeLineas.cambiarModoEditor(ModoEditorLinea.agregar);
                });
              },
              backgroundColor: editorDeLineas.modoEditor == ModoEditorLinea.agregar
                  ? Colors.green
                  : Colors.blue,
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 12),

            FloatingActionButton(
              heroTag: 'modoSeleccionar',
              tooltip: 'Seleccionar línea',
              onPressed: () {
                setState(() {
                  editorDeLineas.cambiarModoEditor(ModoEditorLinea.seleccionar);
                });
              },
              backgroundColor: editorDeLineas.modoEditor == ModoEditorLinea.seleccionar
                  ? Colors.green
                  : Colors.orange,
              child: const Icon(Icons.select_all),
            ),
            const SizedBox(height: 12),

            FloatingActionButton(
              heroTag: 'limpiarSeleccion',
              tooltip: 'Cancelar selección',
              onPressed: () {
                setState(() {
                  editorDeLineas.limpiarSeleccion();
                });
              },
              backgroundColor: editorDeLineas.lineaSeleccionada != null
                  ? Colors.red
                  : Colors.grey,
              child: const Icon(Icons.close),
            ),
            const SizedBox(height: 12),

            FloatingActionButton(
              heroTag: 'borrarTodo',
              tooltip: 'Borrar todas las líneas',
              onPressed: () {
                setState(() {
                  editorDeLineas.limpiarLineas();
                  _recorridoService = null;
                  setState(() {});
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Todas las líneas fueron eliminadas')),
                );
              },
              backgroundColor: Colors.black,
              child: const Icon(Icons.delete_forever),
            ),
            const SizedBox(height: 12),
            // Botón: Activar modo mover
            FloatingActionButton(
              heroTag: 'btnMover',
              backgroundColor: editorDeLineas.modoEditor == ModoEditorLinea.mover
                  ? Colors.orange
                  : Colors.grey,
              onPressed: () {
                setState(() {
                  editorDeLineas.cambiarModoEditor(ModoEditorLinea.mover);
                });
              },
              tooltip: 'Mover vértices',
              child: const Icon(Icons.open_with),
            ),

            const SizedBox(height: 16),
            // Si está en modo mover, mostrar flechas
            if (editorDeLineas.modoEditor == ModoEditorLinea.mover &&
                editorDeLineas.lineaSeleccionada != null) ...[
              FloatingActionButton(
                heroTag: 'btnUp',
                mini: true,
                onPressed: () {
                  setState(() {
                    editorDeLineas.ajustarVerticeSeleccionado(0.00001, 0);
                  });
                },
                tooltip: 'Mover arriba',
                child: const Icon(Icons.keyboard_arrow_up),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'btnLeft',
                    mini: true,
                    onPressed: () {
                      setState(() {
                        editorDeLineas.ajustarVerticeSeleccionado(0, -0.00001);
                      });
                    },
                    tooltip: 'Mover izquierda',
                    child: const Icon(Icons.keyboard_arrow_left),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'btnRight',
                    mini: true,
                    onPressed: () {
                      setState(() {
                        editorDeLineas.ajustarVerticeSeleccionado(0, 0.00001);
                      });
                    },
                    tooltip: 'Mover derecha',
                    child: const Icon(Icons.keyboard_arrow_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'btnDown',
                mini: true,
                onPressed: () {
                  setState(() {
                    editorDeLineas.ajustarVerticeSeleccionado(-0.00001, 0);
                  });
                },
                tooltip: 'Mover abajo',
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
            const SizedBox(height: 12),

          ],

          // Botón principal: activar/desactivar editor

          FloatingActionButton(
            heroTag: 'editorToggle',
            tooltip: editorDeLineas.modoEditor != ModoEditorLinea.inactivo
                ? 'Desactivar editor'
                : 'Activar editor',
            onPressed: () {
              setState(() {
                if (editorDeLineas.modoEditor != ModoEditorLinea.inactivo) {
                  editorDeLineas.cambiarModoEditor(ModoEditorLinea.inactivo);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Editor desactivado')),
                  );
                } else {
                  editorDeLineas.cambiarModoEditor(ModoEditorLinea.seleccionar);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Editor activado en modo selección')),
                  );
                }
              });
            },
            backgroundColor: editorDeLineas.modoEditor != ModoEditorLinea.inactivo
                ? Colors.green
                : Colors.blueGrey,
            child: const Icon(Icons.edit),
          ),
          const SizedBox(height: 12),

          /*
          FloatingActionButton(
            heroTag: 'btnIniciarRecorrido', // Necesario si hay múltiples FABs
            onPressed: () {
              setState(() {
                _recorridoService = RecorridoService(
                  lineas: editorDeLineas.lineas,
                  distanciaSubWaypoint: 10.0,
                  toleranciaMetros: toleranciaMetros,
                );
              });
            },
            child: const Icon(Icons.tune),
            tooltip: 'Ajustar tolerancia',
          ),

           */
          FloatingActionButton(
            heroTag: 'iniciarRecorrido',
            tooltip: 'Iniciar recorrido',
            child: const Icon(Icons.play_arrow),
            onPressed: () {
              if (editorDeLineas.lineas.isNotEmpty) {
                setState(() {
                  _recorridoService = RecorridoService(
                    lineas: editorDeLineas.lineas,
                    conexion: widget.conexion, // ← Agregar esta línea
                    distanciaSubWaypoint: 5.0,
                    toleranciaRuta: toleranciaMetros,
                    toleranciaLlegada: 0.8,
                  );
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recorrido iniciado')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No hay líneas para recorrer')),
                );
              }
            },
          ),
          // Agregar esto en tu mapa_page.dart dentro del build method

// Después de tus botones existentes, agrega estos botones de prueba:
          if (_recorridoService != null) ...[
            const SizedBox(height: 12),

            // Separador visual
            Container(
              width: 56,
              height: 2,
              color: Colors.grey[400],
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),

            // Texto informativo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PRUEBAS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),

            const SizedBox(height: 8),
            // ✅ BOTÓN PARA RESETEAR THROTTLING
            FloatingActionButton(
              heroTag: 'btnResetThrottle',
              mini: true,
              tooltip: 'Resetear throttling',
              backgroundColor: Colors.amber,
              onPressed: () {
                _recorridoService?.resetearThrottling();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔄 Throttling reseteado')),
                );
              },
              child: const Icon(Icons.refresh, size: 16),
            ),

            const SizedBox(height: 8),

            // Botón TEST
            FloatingActionButton(
              heroTag: 'btnTest',
              mini: true,
              tooltip: 'Enviar TEST',
              backgroundColor: Colors.purple,
              onPressed: () {
                _recorridoService?.enviarTest();
              },
              child: const Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 8),

            // Botón AVANZAR
            FloatingActionButton(
              heroTag: 'btnAvanzarManual',
              mini: true,
              tooltip: 'AVANZAR manual',
              backgroundColor: Colors.green,
              onPressed: () {
                _recorridoService?.enviarAvanzar();
              },
              child: const Text('F', style: TextStyle(fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 8),

            // Botón ALTO
            FloatingActionButton(
              heroTag: 'btnAltoManual',
              mini: true,
              tooltip: 'ALTO manual',
              backgroundColor: Colors.red,
              onPressed: () {
                _recorridoService?.enviarAlto();
              },
              child: const Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 8),

            // Botones direccionales en fila
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'btnIzquierdaManual',
                  mini: true,
                  tooltip: 'IZQUIERDA manual',
                  backgroundColor: Colors.orange,
                  onPressed: () {
                    _recorridoService?.enviarIzquierda();
                  },
                  child: const Text('L', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  heroTag: 'btnDerechaManual',
                  mini: true,
                  tooltip: 'DERECHA manual',
                  backgroundColor: Colors.orange,
                  onPressed: () {
                    _recorridoService?.enviarDerecha();
                  },
                  child: const Text('R', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],



        ],
      ),
      ),

      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              child: Text('Puntos guardados'),
            ),
            Expanded(
              child: FutureBuilder<List<LatLng>>(
                future: PuntosGuardadosService.obtenerPuntos(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No hay puntos guardados'));
                  } else {
                    final puntos = snapshot.data!;
                    return ListView.builder(
                      itemCount: puntos.length,
                      itemBuilder: (context, index) {
                        final punto = puntos[index];
                        return ListTile(
                          title: Text('Lat: ${punto.latitude}, Lng: ${punto.longitude}'),
                        );
                      },
                    );
                  }
                },
              ),
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Borrar todos los puntos'),
              onTap: () {
                PuntosGuardadosService.limpiar();
                Navigator.pop(context); // cerrar el drawer
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Puntos eliminados')),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Compartir como .txt'),
                onPressed: () async {
                  await PuntosGuardadosService.compartirArchivo();
                },
              ),
            ),

          ],
        ),
      ),
    );
  }

  void regenerarSubWaypoints() {
    if (_recorridoService != null) {
      _recorridoService = RecorridoService(
        lineas: editorDeLineas.lineas,
        conexion: widget.conexion, // ← Agregar esta línea
        distanciaSubWaypoint: 5.0,
        toleranciaRuta: toleranciaMetros,
        toleranciaLlegada: 0.8,
      );
      setState(() {});
    }
  }

  void _descargarArchivo() async {
    final ruta = await _archivoGPS.obtenerRuta();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Archivo guardado en:\n$ruta')),
    );
  }

  void _mostrarDialogoLinea(BuildContext context, Linea linea) {
    showDialog(
      context: context,
      builder: (context) {
        final nombreController = TextEditingController(text: linea.nombre);
        return AlertDialog(
          title: Text('Opciones para ${linea.nombre}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Inicio: ${linea.puntoInicio.latitude}, ${linea.puntoInicio.longitude}'),
              Text('Fin: ${linea.puntoFin.latitude}, ${linea.puntoFin.longitude}'),
              const SizedBox(height: 12),
              TextField(
                controller: nombreController,
                decoration: const InputDecoration(labelText: 'Renombrar línea'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                editorDeLineas.renombrarLineaSeleccionada(nombreController.text);
                Navigator.pop(context);
              },
              child: const Text('Guardar nombre'),
            ),
            TextButton(
              onPressed: () {
                editorDeLineas.cambiarColorLineaSeleccionada(Colors.green);
                Navigator.pop(context);
              },
              child: const Text('Cambiar color'),
            ),
            TextButton(
              onPressed: () {
                editorDeLineas.borrarLineaSeleccionada();
                Navigator.pop(context);
              },
              child: const Text('Borrar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
  Widget _buildVerticeDraggable({
    required String letra,
    required String idLinea,
    required bool moverInicio,
    required LatLng posicion,
    required MapController mapController,
    required BuildContext context,
  }) {
    return Listener(
      onPointerDown: (_) {
      },
      child: Draggable<String>(
        data: letra,
        feedback: _buildFeedback(letra),
        childWhenDragging: const SizedBox.shrink(),

        onDragUpdate: (details) {
          if (editorDeLineas.modoEditor != ModoEditorLinea.mover) return;

          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox == null) return;

          final localPos = renderBox.globalToLocal(details.globalPosition);

          // Compensar el centro del marcador
          final marcadorOffset = const Offset(20, 20); // mitad del ancho/alto del marcador
          final ajustado = localPos + marcadorOffset;

          final latlng = mapController.pointToLatLng(CustomPoint(ajustado.dx, ajustado.dy));

          if (latlng != null) {
            editorDeLineas.moverVerticeDeLinea(idLinea, moverInicio, latlng);
            regenerarSubWaypoints();
          }
        },



        child: _buildMarkerCircle(letra),
      ),
    );
  }

  Widget _buildMarkerCircle(String letra) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.purple,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        letra,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  Widget _buildFeedback(String letra) {
    return Material(
      color: Colors.transparent,
      child: _buildMarkerCircle(letra),
    );
  }
}
