import 'dart:async';
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
import '../services/bluetooth_manager.dart';
import '../widgets/dialogs_helper.dart';

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
  late BluetoothManager _bluetoothManager;
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

  final ValueNotifier<LatLng> posicionActual = ValueNotifier(const LatLng(0, 0));
  final ValueNotifier<LatLng?> posicionAdafruit = ValueNotifier(null);
  final ValueNotifier<LatLng?> posicionNeo6m = ValueNotifier(null);
  final ValueNotifier<LatLng?> posicionCombinada = ValueNotifier(null);

  final VisualizadorZonas _visualizadorZonas = VisualizadorZonas();
  final ComparadorPrecisionGPS _comparadorPrecision = ComparadorPrecisionGPS();

  List<LatLng> waypoints = [];
  List<LatLng> lineaWaypoints = [];
  bool modoAgregarLinea = false;

  List<LatLng> puntosFiltrados = [];
  double toleranciaMetros = 5.0;
  bool mostrarSlider = false;

  Future<void> _desconectarYRegresarABluetoothSelection() async {
    final confirmar = await DialogsHelper.mostrarConfirmacionDesconexion(context);
    if (confirmar) {
      await _ejecutarDesconexionYNavegacion();
    }
  }

  Future<void> _ejecutarDesconexionYNavegacion() async {
    try {
      DialogsHelper.mostrarProgreso(context, 'Desconectando dispositivo...');
      await _bluetoothManager.desconectar();

      _limpiarRecursosLocales();

      if (mounted) DialogsHelper.cerrarDialogo(context);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const SeleccionarDispositivoPage(),
          ),
        );
      }
    } catch (e) {
      if (mounted) DialogsHelper.cerrarDialogo(context);
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

      _comparadorPrecision.limpiarHistorial();

      _puntoAdafruit = null;
      _puntoNeo6m = null;
      _puntoC = null;
    });
    print('🧹 Historial global limpiado: todos los datos eliminados');
  }

  void _toggleVisualizacionZonas() {
    final estaActivoAhora = _visualizadorZonas.toggle(_historialGlobal);
    setState(() {});
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
      _puntoZona = punto;
      _historialZona.clear();
      _historialZona.add(punto);
      _historialGlobal.add(punto);

      print('🆕 Nueva zona iniciada. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
    } else {
      _historialGlobal.add(punto);
      if (_historialZona.length < _maxPuntosZona) {
        _historialZona.add(punto);
        print('➕ Agregado a zona. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length}');
      } else {
        _historialZona.removeAt(0); // Eliminar el primer elemento (más antiguo)
        _historialZona.add(punto);  // Agregar el nuevo al final
        print('🔄 Buffer circular. Global: ${_historialGlobal.length}, Zona: ${_historialZona.length} (máx: $_maxPuntosZona)');
      }
    }
    _limpiarHistorialAntiguo();
  }

  void _imprimirEstadoHistorial() {// Función auxiliar para verificar el estado
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

  void _procesarDatosBluetooth(String data) async {
    final punto = BluetoothManager.parsearPosicion(data);

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
  }

  void _onConnectionLost() {
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
  }

  @override
  void initState() {
    super.initState();
    _bluetoothManager = BluetoothManager(widget.conexion);
    _bluetoothManager.onDataReceived = _procesarDatosBluetooth;
    _bluetoothManager.onConnectionLost = _onConnectionLost;
    _bluetoothManager.iniciarLectura();
    _bluetoothManager.iniciarMonitoreo();
  }

  @override
  void dispose() {
    _bluetoothManager.desconectar();
    _visualizadorZonas.limpiar();
    super.dispose();
  }

  bool estaCercaDeLinea(LatLng punto, LatLng A, LatLng B, double toleranciaMetros) {
    final Distance distance = const Distance();
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

  void _configurarAnalisisPrecision() {
    final lineaSeleccionada = editorDeLineas.lineaSeleccionada;
    if (lineaSeleccionada != null) {
      _comparadorPrecision.configurarAnalisis(
        toleranciaMetros: toleranciaMetros,
        lineaReferencia: lineaSeleccionada,
      );
    }
  }

  void _mostrarEstadisticasPrecision() {
    final stats = _comparadorPrecision.obtenerEstadisticasRapidas();
    DialogsHelper.mostrarEstadisticasPrecision(
      context,
      stats,
      onGenerarReporte: _generarReportePrecision,
    );
  }

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

    _configurarAnalisisPrecision();
    try {
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
      await _comparadorPrecision.generarYCompartirReporte(// Generar el reporte
        incluirDetallado: true,
        nombrePersonalizado: 'precision_${lineaSeleccionada.nombre}_${DateTime.now().millisecondsSinceEpoch}',
      );

      DialogsHelper.cerrarDialogo(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Reporte de precisión generado y compartido'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al generar reporte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _limpiarHistorialAntiguo() {
    const int maxPuntosGlobales = 1000; // Límite total para evitar problemas de memoria
    if (_historialGlobal.length > maxPuntosGlobales) {
      final puntosAEliminar = _historialGlobal.length - maxPuntosGlobales;// Mantener solo los últimos puntos, eliminando los más antiguos
      _historialGlobal.removeRange(0, puntosAEliminar);
    }
  }
  @override
  Widget build(BuildContext context) {
    List<LatLng> puntosAdafruit = _historialAdafruit.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosNeo6m = _historialNeo6m.map((p) => p.toLatLng()).toList();
    List<LatLng> puntosPromedio = _historialPromedio.map((p) => p.toLatLng()).toList();

    List<LatLng> ultimosAdafruit = puntosAdafruit.length <= 1000
        ? puntosAdafruit
        : puntosAdafruit.sublist(puntosAdafruit.length - 1000);

    List<LatLng> ultimosNeo6m = puntosNeo6m.length <= 1000
        ? puntosNeo6m
        : puntosNeo6m.sublist(puntosNeo6m.length - 1000);

    List<LatLng> ultimosPromedio = puntosPromedio.length <= 1000
        ? puntosPromedio
        : puntosPromedio.sublist(puntosPromedio.length - 1000);

    final lineaSeleccionada = editorDeLineas.lineaSeleccionada;// Si hay línea, filtramos por cercanía
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _bluetoothManager.isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _bluetoothManager.isConnected
                    ? Colors.green
                    : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _bluetoothManager.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  size: 16,
                  color: _bluetoothManager.isConnected
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _bluetoothManager.isConnected ? 'Conectado' : 'Desconectado',
                  style: TextStyle(
                    fontSize: 12,
                    color: _bluetoothManager.isConnected
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
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
          LeyendaZonasWidget(
            visualizador: _visualizadorZonas,
            onZonaTap: () {
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
          FloatingActionButton(
            heroTag: 'iniciarRecorrido',
            tooltip: 'Iniciar recorrido',
            child: const Icon(Icons.play_arrow),
            onPressed: () {
              if (editorDeLineas.lineas.isNotEmpty) {
                setState(() {
                  _recorridoService = RecorridoService(
                    lineas: editorDeLineas.lineas,
                    conexion: _bluetoothManager.conexion, // ← Agregar esta línea
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

          if (_recorridoService != null) ...[
            const SizedBox(height: 12),
            Container(
              width: 56,
              height: 2,
              color: Colors.grey[400],
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
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
        conexion: _bluetoothManager.conexion, // ← Agregar esta línea
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
    final nombreController = TextEditingController(text: linea.nombre);

    DialogsHelper.mostrarDialogoLinea(
      context,
      linea.nombre,
      '${linea.puntoInicio.latitude}, ${linea.puntoInicio.longitude}',
      '${linea.puntoFin.latitude}, ${linea.puntoFin.longitude}',
      nombreController: nombreController,
      onGuardarNombre: () => editorDeLineas.renombrarLineaSeleccionada(nombreController.text),
      onCambiarColor: () => editorDeLineas.cambiarColorLineaSeleccionada(Colors.green),
      onBorrar: () => editorDeLineas.borrarLineaSeleccionada(),
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
