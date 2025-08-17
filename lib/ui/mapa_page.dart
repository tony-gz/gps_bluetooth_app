import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geopoint.dart';
import '../services/puntos_guardados_service.dart';
import '../services/editor_de_lineas.dart';
import '../services/linea.dart';
import '../services/recorrido_service.dart';
import '../services/leyenda_zonas_widget.dart';
import '../ui/seleccionar_dispositivo_page.dart';
import '../services/bluetooth_manager.dart';
import '../widgets/dialogs_helper.dart';

// Widgets separados
import '../widgets/floating_action_buttons_widget.dart';
import '../widgets/map_controller_widget.dart';
import '../services/data_processing_service.dart';

class MapaPage extends StatefulWidget {
  final BluetoothConnection conexion;
  const MapaPage({Key? key, required this.conexion}) : super(key: key);

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  // Servicios principales
  late BluetoothManager _bluetoothManager;
  late DataProcessingService _dataProcessingService;
  final EditorDeLineas _editorDeLineas = EditorDeLineas();

  // Controladores
  final MapController _mapController = MapController();

  // Estado de UI
  final List<Marker> _manualMarkers = [];
  List<LatLng> _waypoints = [];
  List<LatLng> _lineaWaypoints = [];
  bool _modoAgregarLinea = false;
  double _toleranciaMetros = 5.0;
  bool _mostrarSlider = false;

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  void _inicializarServicios() {
    // Inicializar servicio de procesamiento de datos
    _dataProcessingService = DataProcessingService();
    _dataProcessingService.onPositionChanged = (posicion) {
      setState(() {});
    };
    _dataProcessingService.onDataUpdated = () {
      setState(() {});
    };

    // Inicializar Bluetooth Manager
    _bluetoothManager = BluetoothManager(widget.conexion);
    _bluetoothManager.onDataReceived = _procesarDatosBluetooth;
    _bluetoothManager.onConnectionLost = _onConnectionLost;
    _bluetoothManager.iniciarLectura();
    _bluetoothManager.iniciarMonitoreo();
  }

  Future<void> _procesarDatosBluetooth(String data) async {
    final punto = BluetoothManager.parsearPosicion(data);
    if (punto != null) {
      await _dataProcessingService.procesarDatosBluetooth(punto, data);
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

  // ========== CALLBACKS PARA FLOATING ACTION BUTTONS ==========

  void _onMostrarEstadisticasPrecision() {
    final stats = _dataProcessingService.obtenerEstadisticasPrecision();
    DialogsHelper.mostrarEstadisticasPrecision(
      context,
      stats,
      onGenerarReporte: _onGenerarReportePrecision,
    );
  }

  Future<void> _onGenerarReportePrecision() async {
    final lineaSeleccionada = _editorDeLineas.lineaSeleccionada;

    if (lineaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Selecciona una línea de referencia primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _dataProcessingService.configurarAnalisisPrecision(
      toleranciaMetros: _toleranciaMetros,
      lineaReferencia: lineaSeleccionada,
    );

    try {
      DialogsHelper.mostrarProgreso(context, 'Generando reporte de precisión...');

      await _dataProcessingService.generarReportePrecision(
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
      DialogsHelper.cerrarDialogo(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al generar reporte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onToggleVisualizacionZonas() {
    final estaActivoAhora = _dataProcessingService.toggleVisualizacionZonas();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(estaActivoAhora
            ? 'Mostrando ${_dataProcessingService.visualizadorZonas.numeroDeZonas} zonas con colores'
            : 'Visualización por zonas desactivada'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onToggleMostrarSlider() {
    setState(() {
      _mostrarSlider = !_mostrarSlider;
    });
  }

  void _onToggleModoAgregarLinea() {
    setState(() {
      _modoAgregarLinea = !_modoAgregarLinea;
      if (_modoAgregarLinea) {
        _lineaWaypoints.clear();
      }
    });
  }

  void _onGuardarPuntosCercanos() {
    final lineaSeleccionada = _editorDeLineas.lineaSeleccionada;
    if (lineaSeleccionada == null) return;

    final puntosFiltrados = _dataProcessingService.obtenerPuntosFiltrados(
      limite: 1000,
      puntoA: lineaSeleccionada.puntoInicio,
      puntoB: lineaSeleccionada.puntoFin,
      toleranciaMetros: _toleranciaMetros,
    );

    bool seGuardoAlMenosUno = false;

    for (final lista in puntosFiltrados.values) {
      for (final punto in lista) {
        PuntosGuardadosService.agregarPunto(punto);
        seGuardoAlMenosUno = true;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(seGuardoAlMenosUno
          ? 'Puntos cercanos guardados'
          : 'No se encontraron puntos cercanos a la línea')),
    );
    setState(() {});
  }

  void _onIniciarRecorrido() {
    if (_editorDeLineas.lineas.isEmpty) return;

    final recorrido = RecorridoService(
      lineas: _editorDeLineas.lineas,
      conexion: _bluetoothManager.conexion,
      distanciaSubWaypoint: 5.0,
      toleranciaRuta: _toleranciaMetros,
      toleranciaLlegada: 0.8,
    );

    _dataProcessingService.configurarRecorrido(recorrido);
    setState(() {});
  }



  // Solo necesitas reemplazar este método en tu mapa_page.dart

  void _onAjustarVerticeSeleccionado(double deltaLat, double deltaLng) {
    setState(() {
      _editorDeLineas.ajustarVerticeSeleccionado(deltaLat, deltaLng);
    });
    _regenerarSubWaypoints();
  }

// Y también asegurar que el método _regenerarSubWaypoints tenga setState:
  void _regenerarSubWaypoints() {
    if (_dataProcessingService.recorridoService != null) {
      final nuevoRecorrido = RecorridoService(
        lineas: _editorDeLineas.lineas,
        conexion: _bluetoothManager.conexion,
        distanciaSubWaypoint: 5.0,
        toleranciaRuta: _toleranciaMetros,
        toleranciaLlegada: 0.8,
      );
      _dataProcessingService.configurarRecorrido(nuevoRecorrido);

      // Forzar actualización del estado
      if (mounted) {
        setState(() {});

        // Feedback opcional para el usuario
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔄 Sub-waypoints regenerados'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ========== CALLBACKS DEL MAPA ==========

  void _onMapTap(BuildContext context, LatLng point) {
    final modo = _editorDeLineas.modoEditor;

    if (modo == ModoEditorLinea.agregar) {
      setState(() {
        _editorDeLineas.agregarPunto(point);
      });
    } else if (modo == ModoEditorLinea.seleccionar) {
      try {
        final lineaTocada = _editorDeLineas.lineas.firstWhere((linea) {
          const dist = Distance();
          final segmentos = linea.dividirEnSegmentos(1.0);
          return segmentos.any((p) => dist(p.posicion, point) < 10);
        });

        _editorDeLineas.seleccionarLinea(lineaTocada);
        _mostrarDialogoLinea(context, lineaTocada);
      } catch (_) {}
    }
  }

  void _mostrarDialogoLinea(BuildContext context, Linea linea) {
    final nombreController = TextEditingController(text: linea.nombre);

    DialogsHelper.mostrarDialogoLinea(
      context,
      linea.nombre,
      '${linea.puntoInicio.latitude}, ${linea.puntoInicio.longitude}',
      '${linea.puntoFin.latitude}, ${linea.puntoFin.longitude}',
      nombreController: nombreController,
      onGuardarNombre: () {
        _editorDeLineas.renombrarLineaSeleccionada(nombreController.text);
        setState(() {});
      },
      onCambiarColor: () {
        _editorDeLineas.cambiarColorLineaSeleccionada(Colors.green);
        setState(() {});
      },
      onBorrar: () {
        _editorDeLineas.borrarLineaSeleccionada();
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final puntosFiltrados = _dataProcessingService.obtenerPuntosFiltrados(
      limite: 1000,
      puntoA: _editorDeLineas.lineaSeleccionada?.puntoInicio,
      puntoB: _editorDeLineas.lineaSeleccionada?.puntoFin,
      toleranciaMetros: _toleranciaMetros,
    );

    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(puntosFiltrados),
      floatingActionButton: _buildFloatingActionButtons(),
      drawer: _buildDrawer(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
              color: _bluetoothManager.isConnected ? Colors.green : Colors.red,
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
                color: _bluetoothManager.isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                _bluetoothManager.isConnected ? 'Conectado' : 'Desconectado',
                style: TextStyle(
                  fontSize: 12,
                  color: _bluetoothManager.isConnected ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Y modificar el _buildBody para pasar el callback:

  Widget _buildBody(Map<String, List<LatLng>> puntosFiltrados) {
    return Stack(
      children: [
        const SizedBox.expand(),
        Column(
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  MapControllerWidget(
                    posicion: _dataProcessingService.posicion,
                    mapController: _mapController,
                    editorDeLineas: _editorDeLineas,
                    visualizadorZonas: _dataProcessingService.visualizadorZonas,
                    recorridoService: _dataProcessingService.recorridoService,
                    lineaWaypoints: _lineaWaypoints,
                    waypoints: _waypoints,
                    manualMarkers: _manualMarkers,
                    puntoAdafruit: _dataProcessingService.puntoAdafruit,
                    puntoNeo6m: _dataProcessingService.puntoNeo6m,
                    puntoC: _dataProcessingService.puntoC,
                    ultimosAdafruit: puntosFiltrados['adafruit']!,
                    ultimosNeo6m: puntosFiltrados['neo6m']!,
                    ultimosPromedio: puntosFiltrados['promedio']!,
                    onTap: _onMapTap,
                    onMostrarDialogoLinea: _mostrarDialogoLinea,
                    onRegenerarSubWaypoints: _regenerarSubWaypoints, // ← NUEVO
                  ),
                ],
              ),
            ),

            // Resto del código del slider y panel de información permanece igual...
            if (_mostrarSlider)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tolerancia: ${_toleranciaMetros.toStringAsFixed(1)} m',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      min: 1.0,
                      max: 20.0,
                      divisions: 19,
                      value: _toleranciaMetros,
                      label: '${_toleranciaMetros.toStringAsFixed(1)} m',
                      onChanged: (value) {
                        setState(() {
                          _toleranciaMetros = value;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Panel de información del recorrido e historial
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  // Mensaje del recorrido
                  if (_dataProcessingService.recorridoService != null)
                    ValueListenableBuilder<String>(
                      valueListenable: _dataProcessingService.recorridoService!.ultimoMensaje,
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

                  // Lista del historial
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: ListView.builder(
                        itemCount: _dataProcessingService.historial.length,
                        itemBuilder: (_, index) {
                          final p = _dataProcessingService.historial[index];
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

        // Leyenda de zonas
        LeyendaZonasWidget(
          visualizador: _dataProcessingService.visualizadorZonas,
          onZonaTap: () {
            print('Zona tocada en la leyenda');
          },
          onLimpiarPuntosGlobales: () {
            _dataProcessingService.limpiarHistorialGlobal();
            setState(() {});
          },
          mostrarEstadisticas: true,
        ),
      ],
    );
  }

  Widget _buildFloatingActionButtons() {
    return FloatingActionButtonsWidget(
      onMostrarEstadisticasPrecision: _onMostrarEstadisticasPrecision,
      onGenerarReportePrecision: _onGenerarReportePrecision,
      onToggleVisualizacionZonas: _onToggleVisualizacionZonas,
      onToggleMostrarSlider: _onToggleMostrarSlider,
      onToggleModoAgregarLinea: _onToggleModoAgregarLinea,
      onGuardarPuntosCercanos: _onGuardarPuntosCercanos,
      onIniciarRecorrido: _onIniciarRecorrido,
      onResetearThrottling: _dataProcessingService.recorridoService?.resetearThrottling,
      onEnviarTest: _dataProcessingService.recorridoService?.enviarTest,
      onEnviarAvanzar: _dataProcessingService.recorridoService?.enviarAvanzar,
      onEnviarAlto: _dataProcessingService.recorridoService?.enviarAlto,
      onEnviarIzquierda: _dataProcessingService.recorridoService?.enviarIzquierda,
      onEnviarDerecha: _dataProcessingService.recorridoService?.enviarDerecha,
      editorDeLineas: _editorDeLineas,
      visualizadorZonas: _dataProcessingService.visualizadorZonas,
      recorridoService: _dataProcessingService.recorridoService,
      modoAgregarLinea: _modoAgregarLinea,
      mostrarSlider: _mostrarSlider,
      onAjustarVerticeSeleccionado: _onAjustarVerticeSeleccionado,
      // Callbacks adicionales para operaciones del editor
      onCambiarModoEditor: (modo) {
        setState(() {
          _editorDeLineas.cambiarModoEditor(modo);
        });
      },
      onLimpiarSeleccion: () {
        setState(() {
          _editorDeLineas.limpiarSeleccion();
        });
      },
      onLimpiarLineas: () {
        setState(() {
          _editorDeLineas.limpiarLineas();
          _dataProcessingService.configurarRecorrido(null);
        });
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
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
              Navigator.pop(context);
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
    );
  }

  @override
  void dispose() {
    _bluetoothManager.desconectar();
    _dataProcessingService.dispose();
    super.dispose();
  }
}