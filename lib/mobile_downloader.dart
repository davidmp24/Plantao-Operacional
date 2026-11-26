// lib/mobile_downloader.dart
import 'package:flutter/foundation.dart';

// Esta é uma implementação "stub" ou vazia para plataformas não-web.
// Ela fornece os mesmos métodos, mas eles não fazem nada relacionado a dart:html.
class WebDownloader {
  static void downloadFile(String fileName, List<int> bytes, String mimeType) {
    debugPrint("WebDownloader.downloadFile chamado em plataforma não-web. Isso não deveria acontecer se kIsWeb for usado corretamente.");
  }

  static void showJsonInDialogForWeb(dynamic context, String jsonBackup) {
    debugPrint("WebDownloader.showJsonInDialogForWeb chamado em plataforma não-web.");
  }
}