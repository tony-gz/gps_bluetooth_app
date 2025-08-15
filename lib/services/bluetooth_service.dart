import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothService {
  /// Solicita permisos y retorna la lista de dispositivos emparejados
  Future<List<BluetoothDevice>> obtenerDispositivosEmparejados() async {
    final bluetooth = FlutterBluetoothSerial.instance;

    // Asegura que Bluetooth esté activado
    final estado = await bluetooth.requestEnable();
    if (estado != true) {
      throw Exception('Bluetooth no habilitado');
    }

    return await bluetooth.getBondedDevices();
  }

  /// Intenta conectarse a un dispositivo Bluetooth específico
  Future<BluetoothConnection> conectarDispositivo(BluetoothDevice dispositivo) async {
    try {
      final conexion = await BluetoothConnection.toAddress(dispositivo.address);
      print('Conectado a ${dispositivo.name}');
      return conexion;
    } catch (e) {
      print('Error de conexión: $e');
      throw Exception('No se pudo conectar al dispositivo');
    }
  }
}
