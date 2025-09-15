import 'dart:async';
import 'dart:convert';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/geopoint.dart';
import 'dart:typed_data'; // ← Para el metodo eviarComando (resetea)

class BluetoothManager {
  final BluetoothConnection _conexion;
  StreamSubscription? _listener;
  Timer? _timerConexion;

  // Callbacks que el mapa_page puede configurar
  Function(String)? onDataReceived;
  Function()? onConnectionLost;

  BluetoothManager(this._conexion);

  // Getter para verificar conexión
  bool get isConnected => _conexion.isConnected;
  BluetoothConnection get conexion => _conexion;

  void iniciarLectura() {
    _listener = _conexion.input!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((data) async {
      // Llamar al callback si está configurado
      if (onDataReceived != null) {
        // Si es un Future, await; si no, solo llamar
        final result = onDataReceived!(data);
        if (result is Future) {
          await result;
        }
      }
    });
  }

  void iniciarMonitoreo() {
    _timerConexion = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_conexion.isConnected) {
        timer.cancel();
        // Notificar pérdida de conexión
        if (onConnectionLost != null) {
          onConnectionLost!();
        }
      }
    });
  }

  Future<void> desconectar() async {
    await _listener?.cancel();
    _timerConexion?.cancel();
    if (_conexion.isConnected) {
      await _conexion.close();
    }
  }

  // Método estático para parsear posición
  static GeoPoint? parsearPosicion(String data) {
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

  Future<void> enviarComando(String comando) async {
    if (conexion.isConnected) {
      conexion.output.add(Uint8List.fromList(comando.codeUnits));
      await conexion.output.allSent;
    } else {
      throw Exception('No hay conexión Bluetooth activa');
    }
  }
}