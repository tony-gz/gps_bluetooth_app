import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/bluetooth_service.dart';
import 'mapa_page.dart';

class SeleccionarDispositivoPage extends StatefulWidget {
  const SeleccionarDispositivoPage({super.key});

  @override
  State<SeleccionarDispositivoPage> createState() => _SeleccionarDispositivoPageState();
}

class _SeleccionarDispositivoPageState extends State<SeleccionarDispositivoPage> {
  final BluetoothService _bluetoothService = BluetoothService();
  List<BluetoothDevice> _dispositivos = [];
  bool _cargando = true;
  String? _error;
  String? _dispositivoConectando; // Para mostrar estado de conexión

  @override
  void initState() {
    super.initState();
    _cargarDispositivos();
  }

  void _cargarDispositivos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final dispositivos = await _bluetoothService.obtenerDispositivosEmparejados();
      setState(() {
        _dispositivos = dispositivos;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar dispositivos: $e';
        _cargando = false;
      });
    }
  }

  void _conectar(BluetoothDevice dispositivo) async {
    setState(() {
      _dispositivoConectando = dispositivo.address;
    });

    try {
      // Mostrar progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Conectando a ${dispositivo.name ?? 'Dispositivo'}...'),
              const SizedBox(height: 8),
              Text(
                dispositivo.address,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );

      final conexion = await _bluetoothService.conectarDispositivo(dispositivo);

      // Cerrar diálogo de progreso
      if (mounted) Navigator.of(context).pop();

      if (conexion.isConnected) {
        // Conexión exitosa
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MapaPage(conexion: conexion),
            ),
          );
        }
      } else {
        throw Exception('No se pudo establecer la conexión');
      }
    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      if (mounted) Navigator.of(context).pop();

      setState(() {
        _dispositivoConectando = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text("Error al conectar: $e")),
              ],
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => _conectar(dispositivo),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDispositivos,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cargando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Buscando dispositivos...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargarDispositivos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_dispositivos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay dispositivos emparejados',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Empareja un dispositivo desde la configuración de Bluetooth',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargarDispositivos,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _dispositivos.length,
      itemBuilder: (context, index) {
        final dispositivo = _dispositivos[index];
        final conectando = _dispositivoConectando == dispositivo.address;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.bluetooth,
                color: Colors.blue,
              ),
            ),
            title: Text(
              dispositivo.name ?? 'Sin nombre',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dispositivo.address),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Emparejado',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: conectando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.arrow_forward_ios),
            onTap: conectando ? null : () => _conectar(dispositivo),
          ),
        );
      },
    );
  }
}