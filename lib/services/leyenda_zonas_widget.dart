import 'package:flutter/material.dart';
import '../services/visualizador_zonas.dart';

class LeyendaZonasWidget extends StatelessWidget {
  final VisualizadorZonas visualizador;
  final VoidCallback? onZonaTap;
  final VoidCallback? onLimpiarPuntosGlobales; // ✅ NUEVO CALLBACK
  final bool mostrarEstadisticas;

  const LeyendaZonasWidget({
    Key? key,
    required this.visualizador,
    this.onZonaTap,
    this.onLimpiarPuntosGlobales, // ✅ NUEVO PARÁMETRO
    this.mostrarEstadisticas = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!visualizador.estaActivo || visualizador.zonasColoreadas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 60,
      left: 10,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: const BoxConstraints(
          maxHeight: 300,
          maxWidth: 180,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título
            Row(
              children: [
                const Icon(Icons.palette, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Zonas (${visualizador.numeroDeZonas})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),

            // Estadísticas generales
            if (mostrarEstadisticas) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total puntos: ${visualizador.totalPuntos}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      'Promedio: ${(visualizador.totalPuntos / visualizador.numeroDeZonas).round()}/zona',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Lista de zonas
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visualizador.zonasColoreadas.length,
                itemBuilder: (context, index) {
                  final zona = visualizador.zonasColoreadas[index];
                  return _buildZonaItem(zona, context);
                },
              ),
            ),

            // Botón de acciones
            const SizedBox(height: 8),
            _buildBotonesAccion(context),
          ],
        ),
      ),
    );
  }

  Widget _buildZonaItem(ZonaColoreada zona, BuildContext context) {
    return InkWell(
      onTap: onZonaTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de color
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: zona.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: zona.color.withOpacity(0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${zona.numeroZona}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Información de la zona
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zona ${zona.numeroZona}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${zona.puntos.length} puntos',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Barra de proporción visual
            _buildBarraPorcentaje(zona),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraPorcentaje(ZonaColoreada zona) {
    final maxPuntos = visualizador.zonasColoreadas
        .map((z) => z.puntos.length)
        .reduce((a, b) => a > b ? a : b);

    final proporcion = zona.puntos.length / maxPuntos;

    return Container(
      width: 24,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: Colors.grey.shade200,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: proporcion,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: zona.color.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildBotonesAccion(BuildContext context) {
    return Column(
      children: [
        // Primera fila: Info y Export
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _mostrarEstadisticasDetalladas(context),
                icon: const Icon(Icons.info_outline, size: 14),
                label: const Text('Info', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _exportarDatos(context),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Export', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Segunda fila: Botón de limpiar
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => _confirmarLimpiarPuntosGlobales(context),
            icon: const Icon(Icons.clear_all, size: 14, color: Colors.red),
            label: const Text(
              'Limpiar puntos globales',
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              side: BorderSide(color: Colors.red.withOpacity(0.3), width: 1),
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarEstadisticasDetalladas(BuildContext context) {
    final stats = visualizador.obtenerEstadisticas();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('Estadísticas de Zonas'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatItem('Total de zonas', '${stats['zonas']}'),
              _buildStatItem('Puntos totales', '${stats['puntos_totales']}'),
              _buildStatItem('Zona más grande', '${stats['zona_mas_grande']} puntos'),
              _buildStatItem('Zona más pequeña', '${stats['zona_mas_pequeña']} puntos'),
              _buildStatItem('Promedio por zona', '${stats['promedio_puntos_por_zona']} puntos'),
              const Divider(),
              const Text('Detalle por zona:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...visualizador.zonasColoreadas.map((zona) =>
                  _buildZonaDetalle(zona)
              ).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildZonaDetalle(ZonaColoreada zona) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: zona.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('Zona ${zona.numeroZona}: ${zona.puntos.length} puntos',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _confirmarLimpiarPuntosGlobales(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirmar limpieza'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Estás seguro de que quieres eliminar todos los puntos del historial global?'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Esta acción eliminará:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('• ${visualizador.totalPuntos} puntos del historial global'),
                  Text('• ${visualizador.numeroDeZonas} zonas analizadas'),
                  const Text('• Todo el recorrido registrado'),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta acción NO se puede deshacer.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _ejecutarLimpiezaGlobal(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, eliminar todo'),
          ),
        ],
      ),
    );
  }

  void _ejecutarLimpiezaGlobal(BuildContext context) {
    if (onLimpiarPuntosGlobales != null) {
      onLimpiarPuntosGlobales!();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Historial global limpiado correctamente'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _exportarDatos(BuildContext context) {
    final datos = visualizador.exportarDatos();

    // Aquí podrías implementar la lógica de exportación
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Datos de ${datos['total_zonas']} zonas listos para exportar'),
        action: SnackBarAction(
          label: 'Ver JSON',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Datos JSON'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    datos.toString(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}