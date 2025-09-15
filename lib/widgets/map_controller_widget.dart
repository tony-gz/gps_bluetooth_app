import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/geopoint.dart';
import '../services/editor_de_lineas.dart';
import '../services/linea.dart';
import '../services/recorrido_service.dart';
import '../services/visualizador_zonas.dart';
import '../widgets/dialogs_helper.dart';

class MapControllerWidget extends StatefulWidget {
  final LatLng posicion;
  final MapController mapController;
  final EditorDeLineas editorDeLineas;
  final VisualizadorZonas visualizadorZonas;
  final RecorridoService? recorridoService;
  final List<LatLng> lineaWaypoints;
  final List<LatLng> waypoints;
  final List<Marker> manualMarkers;
  final GeoPoint? puntoAdafruit;
  final GeoPoint? puntoNeo6m;
  final GeoPoint? puntoC;
  final List<LatLng> ultimosAdafruit;
  final List<LatLng> ultimosNeo6m;
  final List<LatLng> ultimosPromedio;
  final Function(BuildContext, LatLng) onTap;
  final Function(BuildContext, Linea) onMostrarDialogoLinea;
  final VoidCallback? onRegenerarSubWaypoints;

  const MapControllerWidget({
    Key? key,
    required this.posicion,
    required this.mapController,
    required this.editorDeLineas,
    required this.visualizadorZonas,
    this.recorridoService,
    required this.lineaWaypoints,
    required this.waypoints,
    required this.manualMarkers,
    this.puntoAdafruit,
    this.puntoNeo6m,
    this.puntoC,
    required this.ultimosAdafruit,
    required this.ultimosNeo6m,
    required this.ultimosPromedio,
    required this.onTap,
    required this.onMostrarDialogoLinea,
    this.onRegenerarSubWaypoints,
  }) : super(key: key);

  @override
  State<MapControllerWidget> createState() => _MapControllerWidgetState();
}

class _MapControllerWidgetState extends State<MapControllerWidget> {
  // Constantes para evitar magic numbers
  static const double _gpsPointSize = 5.0;
  static const double _gpsPointMarkerSize = 15.0;
  static const double _locationPinSize = 30.0;
  static const double _flagSize = 18.0;
  static const double _bigFlagSize = 30.0;
  static const double _vertexSize = 50.0;
  static const double _subWaypointSize = 8.0;
  static const double _subWaypointMarkerSize = 14.0;
  static const double _lineWidth = 2.0;
  static const double _defaultZoom = 14.0;

  // Getters para mejorar legibilidad
  bool get _isMapInteractive => widget.editorDeLineas.modoEditor != ModoEditorLinea.mover;
  bool get _shouldShowZoneVisualization => widget.visualizadorZonas.estaActivo;
  bool get _hasRecorrido => widget.recorridoService != null;
  bool get _hasTemporalLine => widget.lineaWaypoints.length == 2;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildFlutterMap(),
        if (!_isMapInteractive) _buildMoverVerticesOverlay(),
      ],
    );
  }

  Widget _buildFlutterMap() {
    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        center: widget.posicion,
        zoom: _defaultZoom,
        onTap: (tapPosition, point) => widget.onTap(context, point),
        interactiveFlags: _isMapInteractive ? InteractiveFlag.all : InteractiveFlag.none,
      ),
      children: [
        _buildTileLayer(),
        ..._buildZoneVisualizationLayers(),
        ..._buildLineLayers(),
        ..._buildSubWaypointsLayers(),
        ..._buildWaypointLayers(),
        _buildGpsPointsLayer(),
        _buildMainMarkersLayer(),
        _buildLineVerticesLayer(),
      ],
    );
  }

  // Layers organizados por función
  TileLayer _buildTileLayer() {
    return TileLayer(
      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      userAgentPackageName: 'com.example.gps_bluetooth_app',
    );
  }

  List<Widget> _buildZoneVisualizationLayers() {
    if (!_shouldShowZoneVisualization) return [];

    return [
      CircleLayer(circles: widget.visualizadorZonas.obtenerCirculos()),
      MarkerLayer(markers: widget.visualizadorZonas.obtenerMarkers()),
    ];
  }

  List<Widget> _buildLineLayers() {
    final layers = <Widget>[
      // Líneas del editor
      PolylineLayer(polylines: widget.editorDeLineas.obtenerPolilineas()),
    ];

    // Línea temporal si existe
    if (_hasTemporalLine) {
      layers.insert(0, PolylineLayer(
        polylines: [
          Polyline(
            points: widget.lineaWaypoints,
            color: Colors.blue,
            strokeWidth: _lineWidth,
          ),
        ],
      ));
    }

    return layers;
  }

  List<Widget> _buildSubWaypointsLayers() {
    if (!_hasRecorrido) return [];

    return [
      MarkerLayer(
        markers: widget.recorridoService!.obtenerSubWaypoints()
            .map((sw) => _buildSubWaypointMarker(sw))
            .toList(),
      ),
    ];
  }

  Marker _buildSubWaypointMarker(dynamic subWaypoint) {
    return Marker(
      point: subWaypoint.posicion,
      width: _subWaypointMarkerSize,
      height: _subWaypointMarkerSize,
      child: Icon(
        Icons.circle,
        size: _subWaypointSize,
        color: _getSubWaypointColor(subWaypoint),
      ),
    );
  }

  Color _getSubWaypointColor(dynamic subWaypoint) {
    if (subWaypoint.esInicio || subWaypoint.esFinal) return Colors.blue;
    return subWaypoint.visitado ? Colors.grey : Colors.purple;
  }

  List<Widget> _buildWaypointLayers() {
    return [
      // Waypoints de línea (morados)
      if (widget.lineaWaypoints.isNotEmpty)
        MarkerLayer(
          markers: widget.lineaWaypoints
              .map((p) => _buildWaypointMarker(p, Colors.purpleAccent, _bigFlagSize))
              .toList(),
        ),
      // Waypoints generales (naranjas)
      if (widget.waypoints.isNotEmpty)
        MarkerLayer(
          markers: widget.waypoints
              .map((p) => _buildWaypointMarker(p, Colors.orange, _flagSize))
              .toList(),
        ),
    ];
  }

  Marker _buildWaypointMarker(LatLng point, Color color, double size) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Icon(Icons.flag, color: color, size: size),
    );
  }

  MarkerLayer _buildGpsPointsLayer() {
    final allGpsMarkers = <Marker>[
      // Puntos Adafruit (verdes)
      ...widget.ultimosAdafruit.map((p) => _buildGpsPointMarker(p, Colors.green)),
      // Puntos Neo6m (rojos)
      ...widget.ultimosNeo6m.map((p) => _buildGpsPointMarker(p, Colors.red)),
      // Puntos promedio (negros)
      ...widget.ultimosPromedio.map((p) => _buildGpsPointMarker(p, Colors.black)),
    ];

    return MarkerLayer(markers: allGpsMarkers);
  }

  Marker _buildGpsPointMarker(LatLng point, Color color) {
    return Marker(
      point: point,
      width: _gpsPointMarkerSize,
      height: _gpsPointMarkerSize,
      child: Icon(Icons.circle, color: color, size: _gpsPointSize),
    );
  }

  MarkerLayer _buildMainMarkersLayer() {
    final mainMarkers = <Marker>[
      ...widget.manualMarkers,
    ];

    // Agregar marcadores GPS principales si existen
    final gpsMarkers = [
      (widget.puntoAdafruit, Colors.green),
      (widget.puntoNeo6m, Colors.red),
      (widget.puntoC, Colors.black54),
    ];

    for (final (punto, color) in gpsMarkers) {
      if (punto != null) {
        mainMarkers.add(_buildMainGpsMarker(punto.toLatLng(), color));
      }
    }

    return MarkerLayer(markers: mainMarkers);
  }

  Marker _buildMainGpsMarker(LatLng point, Color color) {
    return Marker(
      point: point,
      width: _locationPinSize,
      height: _locationPinSize,
      child: Icon(Icons.location_pin, color: color),
    );
  }

  MarkerLayer _buildLineVerticesLayer() {
    final vertexMarkers = widget.editorDeLineas.lineas
        .expand((linea) => _buildVerticesForLine(linea))
        .toList();

    return MarkerLayer(markers: vertexMarkers);
  }

  List<Marker> _buildVerticesForLine(Linea linea) {
    final letras = linea.nombre.split('-');
    return [
      _buildVertexMarker(linea, linea.puntoInicio, letras.first, true),
      _buildVertexMarker(linea, linea.puntoFin, letras.last, false),
    ];
  }

  Marker _buildVertexMarker(Linea linea, LatLng point, String letra, bool isStart) {
    return Marker(
      point: point,
      width: _vertexSize,
      height: _vertexSize,
      child: _VerticeInteractivo(
        letra: letra,
        linea: linea,
        moverInicio: isStart,
        editorDeLineas: widget.editorDeLineas,
        mapController: widget.mapController,
        onRegenerarSubWaypoints: widget.onRegenerarSubWaypoints,
        onVerticeMovido: _onVerticeMovido,
      ),
    );
  }

  Widget _buildMoverVerticesOverlay() {
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.95),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.open_with, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'MODO MOVER VÉRTICES - Mapa congelado. Arrastra los puntos morados.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(width: 8),
            _OverlayLockIcon(),
          ],
        ),
      ),
    );
  }

  // Callback para forzar actualización desde vértices
  void _onVerticeMovido() {
    if (mounted) {
      setState(() {
      });
    }
  }
}

// Widget separado para el icono de bloqueo
class _OverlayLockIcon extends StatelessWidget {
  const _OverlayLockIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.lock, color: Colors.white, size: 16),
    );
  }
}

// Widget optimizado para manejar vértices con mejor performance
class _VerticeInteractivo extends StatefulWidget {
  final String letra;
  final Linea linea;
  final bool moverInicio;
  final EditorDeLineas editorDeLineas;
  final MapController mapController;
  final VoidCallback? onRegenerarSubWaypoints;
  final VoidCallback? onVerticeMovido;

  const _VerticeInteractivo({
    required this.letra,
    required this.linea,
    required this.moverInicio,
    required this.editorDeLineas,
    required this.mapController,
    this.onRegenerarSubWaypoints,
    this.onVerticeMovido,
  });

  @override
  State<_VerticeInteractivo> createState() => _VerticeInteractivoState();
}

class _VerticeInteractivoState extends State<_VerticeInteractivo> {
  bool _estaArrastrando = false;
  Offset? _ultimaPosicion;

  // Constantes para el comportamiento de arrastre
  static const double _conversionFactor = 0.00001;
  static const int _baseZoomLevel = 15;

  // Getters para mejorar legibilidad
  bool get _canMove => widget.editorDeLineas.modoEditor == ModoEditorLinea.mover;
  bool get _isDragging => _estaArrastrando && _ultimaPosicion != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _canMove ? _onPanStart : null,
      onPanUpdate: _isDragging ? _onPanUpdate : null,
      onPanEnd: _estaArrastrando ? _onPanEnd : null,
      child: _buildMarkerCircle(),
    );
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _estaArrastrando = true;
      _ultimaPosicion = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _moverVerticeOptimizado(details.localPosition);
    _ultimaPosicion = details.localPosition;

    // Notificar cambio en tiempo real
    widget.onVerticeMovido?.call();
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _estaArrastrando = false;
      _ultimaPosicion = null;
    });

    // Regenerar sub-waypoints y notificar cambio final
    widget.onRegenerarSubWaypoints?.call();
    widget.onVerticeMovido?.call();
  }

  void _moverVerticeOptimizado(Offset currentPosition) {
    if (_ultimaPosicion == null) return;

    try {
      final delta = currentPosition - _ultimaPosicion!;
      final (deltaLat, deltaLng) = _calculateMovementDelta(delta);
      final newPosition = _calculateNewPosition(deltaLat, deltaLng);

      _updateVertexPosition(newPosition);
    } catch (e) {
      debugPrint('Error al mover vértice: $e');
    }
  }

  (double, double) _calculateMovementDelta(Offset delta) {
    final zoom = widget.mapController.zoom;
    final factor = pow(2, _baseZoomLevel - zoom) * _conversionFactor;

    return (-delta.dy * factor, delta.dx * factor); // Y invertido
  }

  LatLng _calculateNewPosition(double deltaLat, double deltaLng) {
    final currentPos = widget.moverInicio
        ? widget.linea.puntoInicio
        : widget.linea.puntoFin;

    return LatLng(
      currentPos.latitude + deltaLat,
      currentPos.longitude + deltaLng,
    );
  }

  void _updateVertexPosition(LatLng newPosition) {
    widget.editorDeLineas.moverVerticeDeLinea(
      widget.linea.id,
      widget.moverInicio,
      newPosition,
    );
  }

  Widget _buildMarkerCircle() {
    final style = _getMarkerStyle();

    return Container(
      width: 50,
      height: 50,
      decoration: style.decoration,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.letra,
            style: style.textStyle,
          ),
          if (style.showMoveIcon)
            const Icon(
              Icons.open_with,
              color: Colors.white70,
              size: 12,
            ),
        ],
      ),
    );
  }

  _MarkerStyle _getMarkerStyle() {
    final isActive = _canMove;
    final isDragging = _estaArrastrando;

    return _MarkerStyle(
      color: isDragging ? Colors.orange : Colors.purple,
      opacity: isActive ? 0.95 : 0.8,
      borderColor: isActive ? Colors.white : Colors.grey[300]!,
      borderWidth: isDragging ? 4.0 : (isActive ? 3.0 : 2.0),
      shadowBlur: isDragging ? 12.0 : (isActive ? 8.0 : 4.0),
      shadowOffset: isDragging ? 6.0 : (isActive ? 4.0 : 2.0),
      textSize: isDragging ? 16.0 : 14.0,
      showMoveIcon: isActive && !isDragging,
    );
  }
}

// Clase helper para estilos del marcador
class _MarkerStyle {
  final Color color;
  final double opacity;
  final Color borderColor;
  final double borderWidth;
  final double shadowBlur;
  final double shadowOffset;
  final double textSize;
  final bool showMoveIcon;

  const _MarkerStyle({
    required this.color,
    required this.opacity,
    required this.borderColor,
    required this.borderWidth,
    required this.shadowBlur,
    required this.shadowOffset,
    required this.textSize,
    required this.showMoveIcon,
  });

  BoxDecoration get decoration => BoxDecoration(
    shape: BoxShape.circle,
    color: color.withOpacity(opacity),
    border: Border.all(color: borderColor, width: borderWidth),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(shadowOffset > 4 ? 0.45 : 0.26),
        blurRadius: shadowBlur,
        offset: Offset(0, shadowOffset),
      ),
    ],
  );

  TextStyle get textStyle => TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    fontSize: textSize,
  );
}