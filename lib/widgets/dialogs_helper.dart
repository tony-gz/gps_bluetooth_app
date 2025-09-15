import 'package:flutter/material.dart';

class DialogsHelper {
  // Diálogo de confirmación para desconectar Bluetooth
  static Future<bool> mostrarConfirmacionDesconexion(BuildContext context) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.blue),
            SizedBox(width: 8),
            Text('Cambiar conexión'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Deseas desconectarte del dispositivo actual y seleccionar otro?'),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se perderá la conexión actual',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cambiar dispositivo'),
          ),
        ],
      ),
    );

    return resultado ?? false;
  }

  // Diálogo de progreso genérico
  static void mostrarProgreso(BuildContext context, String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(mensaje),
          ],
        ),
      ),
    );
  }

  // Cerrar cualquier diálogo abierto
  static void cerrarDialogo(BuildContext context) {
    Navigator.of(context).pop();
  }

  // Mostrar estadísticas de precisión
  static void mostrarEstadisticasPrecision(
      BuildContext context,
      Map<String, dynamic> stats,
      {VoidCallback? onGenerarReporte}
      ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('Estadísticas de Precisión'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total de puntos analizados: ${stats['total_puntos']}'),
            const SizedBox(height: 8),
            Text('Mejor módulo: ${stats['mejor_modulo']}'),
            Text('Precisión: ${stats['mejor_precision'].toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            Text('Promedio general: ${stats['promedio_general'].toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            Text('Tolerancia actual: ${stats['tolerancia_actual'].toStringAsFixed(1)}m'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  stats['tiene_linea_referencia'] ? Icons.check_circle : Icons.warning,
                  color: stats['tiene_linea_referencia'] ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  stats['tiene_linea_referencia']
                      ? 'Línea de referencia configurada'
                      : 'Sin línea de referencia',
                  style: TextStyle(
                    color: stats['tiene_linea_referencia'] ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          if (onGenerarReporte != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onGenerarReporte();
              },
              child: const Text('Generar Reporte'),
            ),
        ],
      ),
    );
  }

  // Diálogo para opciones de línea
  static void mostrarDialogoLinea(
      BuildContext context,
      String nombreLinea,
      String puntoInicio,
      String puntoFin,
      {
        VoidCallback? onGuardarNombre,
        VoidCallback? onCambiarColor,
        VoidCallback? onBorrar,
        TextEditingController? nombreController,
      }
      ) {
    final controller = nombreController ?? TextEditingController(text: nombreLinea);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Opciones para $nombreLinea'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Inicio: $puntoInicio'),
            Text('Fin: $puntoFin'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Renombrar línea'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onGuardarNombre?.call();
            },
            child: const Text('Guardar nombre'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onCambiarColor?.call();
            },
            child: const Text('Cambiar color'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onBorrar?.call();
            },
            child: const Text('Borrar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // SnackBar helper para mensajes rápidos
  static void mostrarMensaje(
      BuildContext context,
      String mensaje, {
        Color? backgroundColor,
        Duration? duracion,
        SnackBarAction? accion,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: backgroundColor,
        duration: duracion ?? const Duration(seconds: 3),
        action: accion,
      ),
    );
  }

  // SnackBar con icono
  static void mostrarMensajeConIcono(
      BuildContext context,
      String mensaje,
      IconData icono, {
        Color? backgroundColor,
        Color? iconColor,
        Duration? duracion,
        SnackBarAction? accion,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icono, color: iconColor ?? Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duracion ?? const Duration(seconds: 3),
        action: accion,
      ),
    );
  }
  // Agregar este método a la clase DialogsHelper

  static void mostrarEstadisticasIntraTolerancia(
      BuildContext context,
      Map<String, dynamic> stats, {
        VoidCallback? onGenerarReporte,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.precision_manufacturing, color: Colors.teal),
            SizedBox(width: 8),
            Text('Estadísticas Intra-Tolerancia'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stats['mensaje'] != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(stats['mensaje'])),
                    ],
                  ),
                )
              else ...[
                _buildStatCard(
                  'Total de Puntos Analizados',
                  '${stats['total_puntos_analizados']}',
                  Icons.analytics,
                  Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildStatCard(
                  'Mejor Módulo (Distancia Promedio)',
                  '${stats['mejor_modulo_promedio']}\n${stats['mejor_distancia_promedio']?.toStringAsFixed(3)} m',
                  Icons.emoji_events,
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildStatCard(
                  'Mejor Módulo (Desviación Estándar)',
                  '${stats['mejor_modulo_desviacion']}\n${stats['mejor_desviacion']?.toStringAsFixed(3)} m',
                  Icons.show_chart,
                  Colors.purple,
                ),
                const SizedBox(height: 12),
                _buildStatCard(
                  'Tolerancia Utilizada',
                  '${stats['tolerancia_actual']?.toStringAsFixed(1)} metros',
                  Icons.tune,
                  Colors.orange,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.teal, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Análisis Intra-Tolerancia',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Este análisis solo considera puntos que están dentro de la tolerancia especificada, descartando todos los puntos que excedan la distancia límite.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          if (onGenerarReporte != null && stats['total_puntos_analizados'] > 0)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onGenerarReporte();
              },
              icon: const Icon(Icons.file_download),
              label: const Text('Generar Reporte'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  static Widget _buildStatCard(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}