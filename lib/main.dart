import 'package:flutter/material.dart';
import 'package:gps_bluetooth_app/ui/seleccionar_dispositivo_page.dart';
//import 'ui/mapa_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SeleccionarDispositivoPage(),
    );
  }
}
