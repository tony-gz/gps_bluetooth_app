import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:latlong2/latlong.dart';

class PuntosGuardadosService {
  static final List<LatLng> _puntosCercanos = [];

  /// Añadir un nuevo punto cercano a la línea
  static void agregarPunto(LatLng punto) {
    _puntosCercanos.add(punto);
  }

  /// Obtener todos los puntos guardados
  static Future<List<LatLng>> obtenerPuntos() async {
    return List.unmodifiable(_puntosCercanos);
  }

  /// Borrar todos los puntos
  static void limpiar() {
    _puntosCercanos.clear();
  }

  /// Guardar los puntos en almacenamiento interno como .txt
  static Future<String> guardarEnArchivo() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/puntos_guardados.txt';
    final file = File(path);

    final contenido = _puntosCercanos
        .map((p) => '${p.latitude},${p.longitude}')
        .join('\n');

    await file.writeAsString(contenido);

    return path;
  }

  /// Compartir el archivo .txt
  static Future<void> compartirArchivo() async {
    final path = await guardarEnArchivo();
    await Share.shareXFiles([XFile(path)], text: 'Puntos GPS cercanos a la línea');
  }
}
