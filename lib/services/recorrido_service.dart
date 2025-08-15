import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'linea.dart';

class RecorridoService {
  final List<Linea> lineas;
  final BluetoothConnection conexion;
  final double distanciaSubWaypoint; // metros
  double toleranciaRuta;     // margen lateral
  double toleranciaLlegada;  // margen para marcar alcanzado

  int lineaActualIndex = 0;
  int subWaypointActualIndex = 0;

  late List<SubWaypoint> _subWaypoints;

  // Promedio móvil para filtrar ruido GPS
  final List<LatLng> _ventanaPosiciones = [];
  final int _tamVentana = 5; // número de lecturas para promediar

  /// Notificador para mostrar el último mensaje en la UI
  final ValueNotifier<String> ultimoMensaje = ValueNotifier<String>("");

  // ✅ CONTROL DE THROTTLING PARA COMANDOS AUTOMÁTICOS
  DateTime _ultimoComandoEnviado = DateTime.now().subtract(const Duration(seconds: 10));
  String _ultimoComandoTexto = "";
  static const Duration _intervaloMinimoComandos = Duration(milliseconds: 800); // 800ms entre comandos automáticos

  // ✅ CONTROL DE REPETICIÓN DE COMANDOS
  int _contadorComandoRepetido = 0;
  static const int _maxRepeticionesSinCambio = 3; // Máximo 3 veces el mismo comando seguido

  RecorridoService({
    required this.lineas,
    required this.conexion,
    this.distanciaSubWaypoint = 5.0,
    this.toleranciaRuta = 2.0,
    this.toleranciaLlegada = 0.8,
  }) {
    if (lineas.isEmpty) throw Exception("No hay líneas para recorrer");
    _subWaypoints = lineas[0].dividirEnSegmentos(distanciaSubWaypoint);
  }

  // ✅ MÉTODO CORREGIDO para enviar comando por Bluetooth CON THROTTLING
  void _enviarComandoBluetooth(String comando) {
    if (!conexion.isConnected) {
      print("❌ Conexión Bluetooth no disponible");
      return;
    }

    // ⏱️ VERIFICAR THROTTLING SOLO PARA COMANDOS AUTOMÁTICOS
    final ahora = DateTime.now();
    final tiempoTranscurrido = ahora.difference(_ultimoComandoEnviado);

    if (tiempoTranscurrido < _intervaloMinimoComandos) {
      print("🚫 Comando bloqueado por throttling: ${_intervaloMinimoComandos.inMilliseconds - tiempoTranscurrido.inMilliseconds}ms restantes");
      return;
    }

    // 🔄 VERIFICAR SI ES EL MISMO COMANDO REPETIDO
    if (comando == _ultimoComandoTexto) {
      _contadorComandoRepetido++;
      if (_contadorComandoRepetido > _maxRepeticionesSinCambio) {
        print("🚫 Comando repetido demasiadas veces: '$comando' (${_contadorComandoRepetido} veces)");
        return;
      }
    } else {
      _contadorComandoRepetido = 1;
      _ultimoComandoTexto = comando;
    }

    try {
      String letra;

      // 🔄 MAPEO DIRECTO A COMANDOS QUE ESPERA EL ROBOT
      if (comando.contains("AVANZAR")) {
        letra = "F"; // Forward - directamente lo que espera el robot
      } else if (comando.contains("ALTO")) {
        letra = "S"; // Stop - directamente lo que espera el robot
      } else if (comando.contains("IZQUIERDA")) {
        letra = "L"; // Left - directamente lo que espera el robot
      } else if (comando.contains("DERECHA")) {
        letra = "R"; // Right - directamente lo que espera el robot
      } else {
        letra = "S"; // Por defecto, stop
      }

      // 📤 ENVIAR COMANDO
      conexion.output.add(Uint8List.fromList(utf8.encode(letra)));
      _ultimoComandoEnviado = ahora; // Actualizar timestamp

      print("📡 Comando automático enviado: '$letra' (desde: $comando) [${_contadorComandoRepetido}/${_maxRepeticionesSinCambio}]");

    } catch (e) {
      print("❌ Error enviando comando Bluetooth: $e");
    }
  }

  // ✅ MÉTODO DIRECTO SIN THROTTLING (para comandos manuales)
  void _enviarComandoDirecto(String letra) {
    if (!conexion.isConnected) {
      print("❌ Conexión Bluetooth no disponible");
      return;
    }

    try {
      conexion.output.add(Uint8List.fromList(utf8.encode(letra)));
      print("📡 Comando manual enviado: '$letra' (sin throttling)");
    } catch (e) {
      print("❌ Error enviando comando directo: $e");
    }
  }

  void procesarPosicion(LatLng gps) {
    // Suavizar la posición con un promedio móvil
    final posicionSuavizada = _agregarYPromediar(gps);

    if (lineaActualIndex >= lineas.length) {
      _emitirMensaje("ALTO (Fin del recorrido)");
      return;
    }

    final actual = _subWaypoints[subWaypointActualIndex];

    // Distancia lateral a la línea (para tolerancia de ruta)
    final distanciaLateral = const Distance().as(
      LengthUnit.Meter,
      posicionSuavizada,
      actual.posicion,
    );

    if (distanciaLateral > toleranciaRuta) {
      _emitirMensaje("ALTO (Fuera de la ruta)");

      final lado = _calcularLado(posicionSuavizada, actual);
      if (lado > 0) {
        _emitirMensaje("ALTO. Regresar a la IZQUIERDA");
      } else if (lado < 0) {
        _emitirMensaje("ALTO. Regresar a la DERECHA");
      }
      return;
    }

    // Mensaje de avance si aún no lo visitaste
    if (!actual.visitado) {
      _emitirMensaje("AVANZAR hacia sub-waypoint ${actual.index}");
    }

    // Llegada real al sub-waypoint
    if (_haCruzadoPerpendicular(posicionSuavizada, actual)) {
      actual.visitado = true;
      subWaypointActualIndex++;

      if (subWaypointActualIndex >= _subWaypoints.length) {
        lineaActualIndex++;
        if (lineaActualIndex < lineas.length) {
          _subWaypoints = lineas[lineaActualIndex]
              .dividirEnSegmentos(distanciaSubWaypoint);
          subWaypointActualIndex = 0;
        } else {
          _emitirMensaje("ALTO (Fin del recorrido)");
        }
      }
    }
  }

  bool _haCruzadoPerpendicular(LatLng posicion, SubWaypoint actual) {
    // Si es el último punto de la línea, usamos radio normal
    if (actual.esFinal) {
      final distancia = const Distance().as(
        LengthUnit.Meter,
        posicion,
        actual.posicion,
      );
      return distancia <= toleranciaLlegada;
    }

    // Punto siguiente en la trayectoria
    final siguiente = _subWaypoints[actual.index + 1].posicion;

    // Vector de la trayectoria actual -> siguiente
    final dx = siguiente.longitude - actual.posicion.longitude;
    final dy = siguiente.latitude - actual.posicion.latitude;

    // Ecuación de la recta perpendicular en actual.posicion
    // La perpendicular a (dx, dy) es (-dy, dx)
    final normalX = -dy;
    final normalY = dx;

    // Producto punto entre (posicion - actual) y la normal
    final vx = posicion.longitude - actual.posicion.longitude;
    final vy = posicion.latitude - actual.posicion.latitude;
    final dot = vx * normalX + vy * normalY;

    // Si dot > 0 → estamos del otro lado de la perpendicular
    return dot > 0;
  }

  LatLng _agregarYPromediar(LatLng nueva) {
    _ventanaPosiciones.add(nueva);
    if (_ventanaPosiciones.length > _tamVentana) {
      _ventanaPosiciones.removeAt(0);
    }

    double latProm = 0;
    double lngProm = 0;
    for (final p in _ventanaPosiciones) {
      latProm += p.latitude;
      lngProm += p.longitude;
    }
    latProm /= _ventanaPosiciones.length;
    lngProm /= _ventanaPosiciones.length;

    return LatLng(latProm, lngProm);
  }

  void _emitirMensaje(String mensaje) {
    ultimoMensaje.value = mensaje;
    print(mensaje); // sigue imprimiendo en consola
    _enviarComandoBluetooth(mensaje); // ← Enviar por Bluetooth
  }

  double _calcularLado(LatLng posicion, SubWaypoint actual) {
    if (actual.esFinal) return 0; // último punto, no se calcula

    final siguiente = _subWaypoints[actual.index + 1].posicion;

    // Vector trayectoria
    final dx = siguiente.longitude - actual.posicion.longitude;
    final dy = siguiente.latitude - actual.posicion.latitude;

    // Vector posición
    final px = posicion.longitude - actual.posicion.longitude;
    final py = posicion.latitude - actual.posicion.latitude;

    // Producto cruzado en 2D
    return (dx * py) - (dy * px);
  }

  // ✅ MÉTODOS DE PRUEBA MANUAL (sin throttling)
  void enviarAvanzar() {
    _enviarComandoDirecto("F");
    ultimoMensaje.value = "AVANZAR (manual)";
  }

  void enviarAlto() {
    _enviarComandoDirecto("S");
    ultimoMensaje.value = "ALTO (manual)";
  }

  void enviarIzquierda() {
    _enviarComandoDirecto("L");
    ultimoMensaje.value = "IZQUIERDA (manual)";
  }

  void enviarDerecha() {
    _enviarComandoDirecto("R");
    ultimoMensaje.value = "DERECHA (manual)";
  }

  void enviarTest() {
    _enviarComandoDirecto("T");
    ultimoMensaje.value = "TEST (manual)";
  }

  // ✅ MÉTODO PARA RESETEAR THROTTLING (útil para debugging)
  void resetearThrottling() {
    _ultimoComandoEnviado = DateTime.now().subtract(const Duration(seconds: 10));
    _contadorComandoRepetido = 0;
    _ultimoComandoTexto = "";
    print("🔄 Throttling reseteado");
  }

  // ✅ MÉTODO PARA AJUSTAR CONFIGURACIÓN DE THROTTLING
  void configurarThrottling({
    Duration? intervaloMinimo,
    int? maxRepeticiones,
  }) {
    // Estos valores serían constantes, pero podrías hacerlos variables si necesitas ajustarlos
    print("⚙️ Configuración actual:");
    print("   - Intervalo mínimo: ${_intervaloMinimoComandos.inMilliseconds}ms");
    print("   - Máx repeticiones: $_maxRepeticionesSinCambio");
  }

  // ✅ MÉTODO PARA VER ESTADO DEL THROTTLING
  Map<String, dynamic> obtenerEstadoThrottling() {
    final ahora = DateTime.now();
    final tiempoRestante = _intervaloMinimoComandos - ahora.difference(_ultimoComandoEnviado);

    return {
      'puede_enviar': tiempoRestante.isNegative,
      'tiempo_restante_ms': tiempoRestante.isNegative ? 0 : tiempoRestante.inMilliseconds,
      'ultimo_comando': _ultimoComandoTexto,
      'repeticiones_actuales': _contadorComandoRepetido,
      'max_repeticiones': _maxRepeticionesSinCambio,
    };
  }

  List<SubWaypoint> obtenerSubWaypoints() => _subWaypoints;

  // Limpiar recursos al destruir la clase
  void dispose() {
    ultimoMensaje.dispose();
  }
}