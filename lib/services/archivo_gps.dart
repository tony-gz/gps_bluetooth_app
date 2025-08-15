import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ArchivoGPS {
  late final Future<File> _archivo;

  ArchivoGPS() {
    _archivo = _inicializarArchivo();
  }

  Future<File> _inicializarArchivo() async {
    final dir = await getApplicationDocumentsDirectory();
    final nombreArchivo = 'coordenadas_gps.txt';
    final path = '${dir.path}/$nombreArchivo';
    final archivo = File(path);

    if (!(await archivo.exists())) {
      await archivo.create(recursive: true);
      await archivo.writeAsString('Registro de coordenadas GPS\n\n');
    }

    return archivo;
  }

  Future<void> guardar(String linea) async {
    final archivo = await _archivo;
    final fecha = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    await archivo.writeAsString('[$fecha] $linea\n', mode: FileMode.append);
  }

  Future<String> leerContenido() async {
    final archivo = await _archivo;
    return archivo.readAsString();
  }

  Future<void> borrarArchivo() async {
    final archivo = await _archivo;
    if (await archivo.exists()) {
      await archivo.delete();
    }
  }

  Future<String> obtenerRuta() async {
    final archivo = await _archivo;
    return archivo.path;
  }
}