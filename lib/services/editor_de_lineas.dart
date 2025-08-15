import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'linea.dart';

/// Enum para definir el modo actual del editor
enum ModoEditorLinea {
  inactivo,
  agregar,
  seleccionar,
  mover,
}

class EditorDeLineas extends ChangeNotifier {
  final List<Linea> _lineas = [];
  final List<LatLng> _puntosTemporales = [];
  int _contador = 0;

  final List<LatLng> _vertices = [];
  List<LatLng> get vertices => _vertices;


  ModoEditorLinea _modoEditor = ModoEditorLinea.inactivo;
  Linea? _lineaSeleccionada;

  // ======= Getters ========
  ModoEditorLinea get modoEditor => _modoEditor;
  List<Linea> get lineas => _lineas;
  Linea? get lineaSeleccionada => _lineaSeleccionada;

  // ======= Cambiar modo de edición ========
  void cambiarModoEditor(ModoEditorLinea nuevoModo) {
    _modoEditor = nuevoModo;
    _puntosTemporales.clear();

    // Solo limpiar la selección si NO estamos yendo a mover o seleccionar
    if (nuevoModo != ModoEditorLinea.mover && nuevoModo != ModoEditorLinea.seleccionar) {
      _lineaSeleccionada = null;
    }

    notifyListeners();
  }


  // ======= Selección y edición de líneas ========
  void seleccionarLinea(Linea linea) {
    _lineaSeleccionada = linea;
    notifyListeners();
  }

  void limpiarSeleccion() {
    _lineaSeleccionada = null;
    notifyListeners();
  }

  void borrarLineaSeleccionada() {
    if (_lineaSeleccionada != null) {
      _lineas.remove(_lineaSeleccionada);
      _lineaSeleccionada = null;
      notifyListeners();
    }
  }

  void cambiarColorLineaSeleccionada(Color nuevoColor) {
    if (_lineaSeleccionada != null) {
      _lineaSeleccionada!.color = nuevoColor;
      notifyListeners();
    }
  }

  void renombrarLineaSeleccionada(String nuevoNombre) {
    if (_lineaSeleccionada != null) {
      _lineaSeleccionada!.nombre = nuevoNombre;
      notifyListeners();
    }
  }

  // ======= Agregar nueva línea entre puntos ========
  void agregarPunto(LatLng punto) {
    if (_modoEditor != ModoEditorLinea.agregar) return;

    _vertices.add(punto); // Guarda el punto en la lista de vértices

    if (_vertices.length >= 2) {
      final inicio = _vertices[_vertices.length - 2];
      final fin = _vertices[_vertices.length - 1];

      final puntoA = _contador + 1;
      final puntoB = _contador + 2;
      final nombre = "$puntoA-$puntoB";


      final linea = Linea(
        id: 'linea_$_contador',
        puntoInicio: inicio,
        puntoFin: fin,
        nombre: nombre,
      );

      _lineas.add(linea);
      _contador++;

      notifyListeners();
    }
  }


  // ======= Otras utilidades ========
  void borrarLinea(Linea linea) {
    _lineas.remove(linea);
    notifyListeners();
  }

  void limpiarLineas() {
    _lineas.clear();
    _vertices.clear();
    _contador = 0;
    _puntosTemporales.clear();
    _lineaSeleccionada = null;
    notifyListeners();
  }

  void moverVerticeDeLinea(String idLinea, bool moverInicio, LatLng nuevaPosicion) {
    try {
      final linea = _lineas.firstWhere((l) => l.id == idLinea);

      LatLng puntoObjetivo = moverInicio ? linea.puntoInicio : linea.puntoFin;

      // Encuentra el vértice compartido y reemplaza su valor
      final index = _vertices.indexWhere((v) => v == puntoObjetivo);
      if (index != -1) {
        _vertices[index] = nuevaPosicion;

        // Actualiza referencias en todas las líneas que usan ese vértice
        for (var l in _lineas) {
          if (l.puntoInicio == puntoObjetivo) l.puntoInicio = nuevaPosicion;
          if (l.puntoFin == puntoObjetivo) l.puntoFin = nuevaPosicion;
        }

        notifyListeners();
      }
    } catch (_) {}
  }

  void ajustarVerticeSeleccionado(double deltaLat, double deltaLng) {
    final punto = _vertices.firstWhere(
          (v) => v == _lineaSeleccionada?.puntoInicio || v == _lineaSeleccionada?.puntoFin,
      orElse: () => LatLng(0, 0),
    );

    if (punto.latitude == 0 && punto.longitude == 0) return;

    final nuevo = LatLng(punto.latitude + deltaLat, punto.longitude + deltaLng);

    final index = _vertices.indexWhere((v) => v == punto);
    if (index != -1) {
      _vertices[index] = nuevo;

      for (var l in _lineas) {
        if (l.puntoInicio == punto) l.puntoInicio = nuevo;
        if (l.puntoFin == punto) l.puntoFin = nuevo;
      }

      notifyListeners();
    }
  }





  bool puntoCercaDeUnaLinea(LatLng punto, double maxDistanciaMetros) {
    final d = const Distance();
    for (var linea in _lineas) {
      final segmentos = linea.dividirEnSegmentos(1.0);
      for (var p in segmentos) {
        if (d(p as LatLng, punto) <= maxDistanciaMetros) {  //AQuí se hizo un casteo
          return true;
        }
      }
    }
    return false;
  }

  // ======= Dibujar líneas ========
  List<Polyline> obtenerPolilineas() {
    return _lineas.map((linea) {
      return Polyline(
        points: [linea.puntoInicio, linea.puntoFin],
        strokeWidth: 4.0,
        color: linea.color,
      );
    }).toList();
  }
}
