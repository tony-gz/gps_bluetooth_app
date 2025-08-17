import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/editor_de_lineas.dart';
import '../services/recorrido_service.dart';
import '../services/visualizador_zonas.dart';
import '../services/comparador_precision_gps.dart';
import '../services/puntos_guardados_service.dart';

class FloatingActionButtonsWidget extends StatelessWidget {
  // Callbacks necesarios
  final VoidCallback onMostrarEstadisticasPrecision;
  final VoidCallback onGenerarReportePrecision;
  final VoidCallback onToggleVisualizacionZonas;
  final VoidCallback onToggleMostrarSlider;
  final VoidCallback onToggleModoAgregarLinea;
  final VoidCallback onGuardarPuntosCercanos;
  final VoidCallback onIniciarRecorrido;
  final VoidCallback? onResetearThrottling;
  final VoidCallback? onEnviarTest;
  final VoidCallback? onEnviarAvanzar;
  final VoidCallback? onEnviarAlto;
  final VoidCallback? onEnviarIzquierda;
  final VoidCallback? onEnviarDerecha;

  // Estados necesarios
  final EditorDeLineas editorDeLineas;
  final VisualizadorZonas visualizadorZonas;
  final RecorridoService? recorridoService;
  final bool modoAgregarLinea;
  final bool mostrarSlider;

  // Para controles de movimiento
  final Function(double, double) onAjustarVerticeSeleccionado;

  // Callbacks adicionales para el editor
  final Function(ModoEditorLinea) onCambiarModoEditor;
  final VoidCallback onLimpiarSeleccion;
  final VoidCallback onLimpiarLineas;

  const FloatingActionButtonsWidget({
    Key? key,
    required this.onMostrarEstadisticasPrecision,
    required this.onGenerarReportePrecision,
    required this.onToggleVisualizacionZonas,
    required this.onToggleMostrarSlider,
    required this.onToggleModoAgregarLinea,
    required this.onGuardarPuntosCercanos,
    required this.onIniciarRecorrido,
    required this.editorDeLineas,
    required this.visualizadorZonas,
    required this.recorridoService,
    required this.modoAgregarLinea,
    required this.mostrarSlider,
    required this.onAjustarVerticeSeleccionado,
    required this.onCambiarModoEditor,
    required this.onLimpiarSeleccion,
    required this.onLimpiarLineas,
    this.onResetearThrottling,
    this.onEnviarTest,
    this.onEnviarAvanzar,
    this.onEnviarAlto,
    this.onEnviarIzquierda,
    this.onEnviarDerecha,
  }) : super(key: key);

  // Constantes para evitar magic numbers
  static const double _buttonSpacing = 12.0;
  static const double _sectionSpacing = 16.0;
  static const double _miniButtonSpacing = 8.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Grupo: Análisis y Reportes
          _buildAnalysisButtons(context),

          // Grupo: Visualización
          _buildVisualizationButtons(context),

          // Grupo: Editor de Líneas
          if (_isEditorActive) _buildEditorButtons(context),

          // Grupo: Controles de Movimiento
          if (_shouldShowMovementControls) _buildMovementControls(context),

          // Botón principal del editor
          _buildMainEditorButton(context),

          // Botón de recorrido
          _buildRouteButton(context),

          // Controles de prueba (solo si hay recorrido activo)
          if (recorridoService != null) _buildTestControls(context),
        ],
      ),
    );
  }

  // Getters para mejorar legibilidad
  bool get _isEditorActive => editorDeLineas.modoEditor != ModoEditorLinea.inactivo;
  bool get _shouldShowMovementControls =>
      editorDeLineas.modoEditor == ModoEditorLinea.mover &&
          editorDeLineas.lineaSeleccionada != null;
  bool get _hasSelectedLine => editorDeLineas.lineaSeleccionada != null;
  bool get _hasLines => editorDeLineas.lineas.isNotEmpty;
  bool get _isMoveMode => editorDeLineas.modoEditor == ModoEditorLinea.mover;

  Widget _buildAnalysisButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingButton(
          heroTag: 'btnEstadisticas',
          tooltip: 'Ver estadísticas de precisión',
          onPressed: onMostrarEstadisticasPrecision,
          backgroundColor: Colors.deepPurple,
          icon: Icons.analytics,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'btnReporte',
          tooltip: 'Generar reporte de precisión',
          onPressed: () => _handleReportGeneration(context),
          backgroundColor: Colors.indigo,
          icon: Icons.assessment,
        ),
        const SizedBox(height: _buttonSpacing),
      ],
    );
  }

  Widget _buildVisualizationButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingButton(
          heroTag: 'btnVisualizarZonas',
          onPressed: onToggleVisualizacionZonas,
          backgroundColor: visualizadorZonas.estaActivo ? Colors.green : Colors.grey,
          tooltip: visualizadorZonas.estaActivo
              ? 'Ocultar visualización por zonas'
              : 'Mostrar puntos por zonas con colores',
          icon: visualizadorZonas.estaActivo ? Icons.visibility_off : Icons.palette,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'btnTolerancia',
          onPressed: onToggleMostrarSlider,
          icon: Icons.tune,
          tooltip: 'Ajustar tolerancia',
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'btnModoLinea',
          icon: modoAgregarLinea ? Icons.close : Icons.timeline,
          tooltip: modoAgregarLinea
              ? 'Salir del modo línea'
              : 'Entrar al modo para agregar línea A–B',
          onPressed: onToggleModoAgregarLinea,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'btnGuardar',
          tooltip: 'Guardar puntos cercanos a la línea',
          icon: Icons.save,
          onPressed: () => _handleSavePoints(context),
        ),
        const SizedBox(height: _buttonSpacing),
      ],
    );
  }

  Widget _buildEditorButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingButton(
          heroTag: 'modoAgregar',
          tooltip: 'Agregar línea manual',
          onPressed: () => onCambiarModoEditor(ModoEditorLinea.agregar),
          backgroundColor: editorDeLineas.modoEditor == ModoEditorLinea.agregar
              ? Colors.green
              : Colors.blue,
          icon: Icons.add,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'modoSeleccionar',
          tooltip: 'Seleccionar línea',
          onPressed: () => onCambiarModoEditor(ModoEditorLinea.seleccionar),
          backgroundColor: editorDeLineas.modoEditor == ModoEditorLinea.seleccionar
              ? Colors.green
              : Colors.orange,
          icon: Icons.select_all,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'limpiarSeleccion',
          tooltip: 'Cancelar selección',
          onPressed: onLimpiarSeleccion,
          backgroundColor: _hasSelectedLine ? Colors.red : Colors.grey,
          icon: Icons.close,
        ),
        const SizedBox(height: _buttonSpacing),
        _buildFloatingButton(
          heroTag: 'borrarTodo',
          tooltip: 'Borrar todas las líneas',
          onPressed: () => _handleDeleteAllLines(context),
          backgroundColor: Colors.black,
          icon: Icons.delete_forever,
        ),
        const SizedBox(height: _buttonSpacing),
        // Botón de mover vértices optimizado
        _buildFloatingButton(
          heroTag: 'btnMover',
          backgroundColor: _isMoveMode ? Colors.orange : Colors.grey,
          onPressed: () => _handleToggleMoveMode(context),
          tooltip: _isMoveMode ? 'Desactivar modo mover' : 'Activar modo mover vértices',
          icon: Icons.open_with,
        ),
        const SizedBox(height: _sectionSpacing),
      ],
    );
  }

  Widget _buildMovementControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniFloatingButton(
          heroTag: 'btnUp',
          onPressed: () => onAjustarVerticeSeleccionado(0.00001, 0),
          tooltip: 'Mover arriba',
          icon: Icons.keyboard_arrow_up,
        ),
        const SizedBox(height: _miniButtonSpacing),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMiniFloatingButton(
              heroTag: 'btnLeft',
              onPressed: () => onAjustarVerticeSeleccionado(0, -0.00001),
              tooltip: 'Mover izquierda',
              icon: Icons.keyboard_arrow_left,
            ),
            const SizedBox(width: _miniButtonSpacing),
            _buildMiniFloatingButton(
              heroTag: 'btnRight',
              onPressed: () => onAjustarVerticeSeleccionado(0, 0.00001),
              tooltip: 'Mover derecha',
              icon: Icons.keyboard_arrow_right,
            ),
          ],
        ),
        const SizedBox(height: _miniButtonSpacing),
        _buildMiniFloatingButton(
          heroTag: 'btnDown',
          onPressed: () => onAjustarVerticeSeleccionado(-0.00001, 0),
          tooltip: 'Mover abajo',
          icon: Icons.keyboard_arrow_down,
        ),
        const SizedBox(height: _buttonSpacing),
      ],
    );
  }

  Widget _buildMainEditorButton(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingButton(
          heroTag: 'editorToggle',
          tooltip: _isEditorActive ? 'Desactivar editor' : 'Activar editor',
          onPressed: () => _handleToggleEditor(context),
          backgroundColor: _isEditorActive ? Colors.green : Colors.blueGrey,
          icon: Icons.edit,
        ),
        const SizedBox(height: _buttonSpacing),
      ],
    );
  }

  Widget _buildRouteButton(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingButton(
          heroTag: 'iniciarRecorrido',
          tooltip: 'Iniciar recorrido',
          icon: Icons.play_arrow,
          onPressed: () => _handleStartRoute(context),
        ),
        const SizedBox(height: _buttonSpacing),
      ],
    );
  }

  Widget _buildTestControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTestSeparator(),
        _buildMiniFloatingButton(
          heroTag: 'btnResetThrottle',
          tooltip: 'Resetear throttling',
          backgroundColor: Colors.amber,
          onPressed: () => _handleResetThrottling(context),
          icon: Icons.refresh,
          iconSize: 16,
        ),
        const SizedBox(height: _miniButtonSpacing),
        _buildTestCommandButton('btnTest', 'TEST', 'T', Colors.purple, onEnviarTest),
        const SizedBox(height: _miniButtonSpacing),
        _buildTestCommandButton('btnAvanzarManual', 'AVANZAR', 'F', Colors.green, onEnviarAvanzar),
        const SizedBox(height: _miniButtonSpacing),
        _buildTestCommandButton('btnAltoManual', 'ALTO', 'S', Colors.red, onEnviarAlto),
        const SizedBox(height: _miniButtonSpacing),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTestCommandButton('btnIzquierdaManual', 'IZQUIERDA', 'L', Colors.orange, onEnviarIzquierda),
            const SizedBox(width: _miniButtonSpacing),
            _buildTestCommandButton('btnDerechaManual', 'DERECHA', 'R', Colors.orange, onEnviarDerecha),
          ],
        ),
      ],
    );
  }

  // Métodos helpers para reducir duplicación de código
  Widget _buildFloatingButton({
    required String heroTag,
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
    Color? backgroundColor,
  }) {
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      child: Icon(icon),
    );
  }

  Widget _buildMiniFloatingButton({
    required String heroTag,
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
    Color? backgroundColor,
    double? iconSize,
  }) {
    return FloatingActionButton(
      heroTag: heroTag,
      mini: true,
      tooltip: tooltip,
      backgroundColor: backgroundColor,
      onPressed: onPressed,
      child: Icon(icon, size: iconSize),
    );
  }

  Widget _buildTestCommandButton(
      String heroTag,
      String fullCommand,
      String shortCommand,
      Color color,
      VoidCallback? onPressed,
      ) {
    return FloatingActionButton(
      heroTag: heroTag,
      mini: true,
      tooltip: '$fullCommand manual',
      backgroundColor: color,
      onPressed: onPressed,
      child: Text(shortCommand, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTestSeparator() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 2,
          color: Colors.grey[400],
          margin: const EdgeInsets.symmetric(vertical: _miniButtonSpacing),
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
        const SizedBox(height: _miniButtonSpacing),
      ],
    );
  }

  // Métodos de manejo de eventos centralizados
  void _handleReportGeneration(BuildContext context) {
    if (_hasSelectedLine) {
      onGenerarReportePrecision();
    } else {
      _showSnackBar(context, '⚠️ Selecciona una línea primero');
    }
  }

  void _handleSavePoints(BuildContext context) {
    if (_hasSelectedLine) {
      onGuardarPuntosCercanos();
    } else {
      _showSnackBar(context, '● Selecciona una línea para guardar puntos cercanos');
    }
  }

  void _handleDeleteAllLines(BuildContext context) {
    onLimpiarLineas();
    _showSnackBar(context, 'Todas las líneas fueron eliminadas');
  }

  void _handleToggleMoveMode(BuildContext context) {
    if (_isMoveMode) {
      onCambiarModoEditor(ModoEditorLinea.seleccionar);
      _showSnackBar(context, 'Modo mover vértices desactivado');
    } else {
      onCambiarModoEditor(ModoEditorLinea.mover);
      _showSnackBar(context, 'Modo mover vértices activado');
    }
  }

  void _handleToggleEditor(BuildContext context) {
    if (_isEditorActive) {
      onCambiarModoEditor(ModoEditorLinea.inactivo);
      _showSnackBar(context, 'Editor desactivado');
    } else {
      onCambiarModoEditor(ModoEditorLinea.seleccionar);
      _showSnackBar(context, 'Editor activado en modo selección');
    }
  }

  void _handleStartRoute(BuildContext context) {
    if (_hasLines) {
      onIniciarRecorrido();
      _showSnackBar(context, 'Recorrido iniciado');
    } else {
      _showSnackBar(context, 'No hay líneas para recorrer');
    }
  }

  void _handleResetThrottling(BuildContext context) {
    onResetearThrottling?.call();
    _showSnackBar(context, '🔄 Throttling reseteado');
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}