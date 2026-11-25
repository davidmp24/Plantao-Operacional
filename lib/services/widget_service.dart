import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Serviço para atualizar o Home Screen Widget Android
/// com dados do dia atual do banco Hive local
class WidgetService {
  static const String _appGroupId = 'com.davidmp.plantao.widget';
  static const String _iOSWidgetName = 'PlantaoWidget';

  /// Inicializa o home_widget com o grupo do app
  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (e) {
      debugPrint('WidgetService: setAppGroupId error (ignorado): $e');
    }
    try {
      await HomeWidget.registerInteractivityCallback(_backgroundCallback);
    } catch (e) {
      // No MIUI/Redmi, registerInteractivityCallback pode falhar com
      // PlatformException por restrições de permissão de background.
      // O widget ainda funciona sem este callback.
      debugPrint('WidgetService: registerInteractivityCallback error (ignorado): $e');
    }
  }

  /// Callback para interações no widget (em background)
  @pragma('vm:entry-point')
  static Future<void> _backgroundCallback(Uri? uri) async {
    // Lida com toques no widget quando o app está em background
    debugPrint('Widget tapped: $uri');
  }

  /// Atualiza o widget com o status do dia atual
  static Future<void> updateTodayWidget() async {
    try {
      final now = DateTime.now();
      final todayKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Lê do Hive local
      final box = Hive.isBoxOpen('commitments') ? Hive.box('commitments') : null;
      if (box == null) return;

      final dayCommitments = box.get(todayKey);
      final List<dynamic> commitments = dayCommitments is List ? List.from(dayCommitments) : [];

      String statusTitle;
      String statusColor;
      String nextItem = '';

      if (commitments.isEmpty) {
        statusTitle = 'Dia livre';
        statusColor = '#666666';
      } else {
        final hasFolga = commitments.any((c) => c is Map && c['title'] == 'Folga');
        final nonFolga = commitments.where((c) => c is Map && c['title'] != 'Folga').toList();

        if (hasFolga && nonFolga.isEmpty) {
          statusTitle = 'Folga';
          statusColor = '#43A047';
        } else if (nonFolga.isNotEmpty) {
          // Primeiro compromisso como status principal
          final first = nonFolga.first as Map;
          final title = first['title'] as String? ?? 'Compromisso';
          final hour = first['hour'] as String? ?? '';
          statusTitle = hour.isNotEmpty ? '$title ($hour)' : title;
          final colorVal = first['color'] as int?;
          statusColor = colorVal != null
              ? '#${colorVal.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'
              : '#10A37F';

          // Todos os itens restantes como linhas da agenda
          if (nonFolga.length > 1) {
            final lines = nonFolga.skip(1).map((c) {
              if (c is Map) {
                final t = c['title'] as String? ?? '';
                final h = c['hour'] as String? ?? '';
                return h.isNotEmpty ? '• $t ($h)' : '• $t';
              }
              return '';
            }).where((s) => s.isNotEmpty).take(5).toList();
            if (hasFolga) lines.add('• Folga');
            nextItem = lines.join('\n');
          } else if (hasFolga) {
            nextItem = '• Folga';
          }
        } else {
          statusTitle = '${commitments.length} compromisso(s)';
          statusColor = '#10A37F';
        }
      }

      // Salva dados para o widget nativo
      await HomeWidget.saveWidgetData<String>('widget_status_title', statusTitle);
      await HomeWidget.saveWidgetData<String>('widget_status_color', statusColor);
      await HomeWidget.saveWidgetData<String>('widget_next_item', nextItem);

      // Solicita atualização do widget nativo
      await HomeWidget.updateWidget(
        androidName: 'PlantaoWidgetProvider',
        iOSName: _iOSWidgetName,
      );
    } catch (e) {
      debugPrint('WidgetService update error: $e');
    }
  }
}
