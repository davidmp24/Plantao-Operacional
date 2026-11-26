// lib/web_downloader.dart
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html; // Importação direta, pois este arquivo só será usado na web

class WebDownloader {
  static void downloadFile(String fileName, List<int> bytes, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void showJsonInDialogForWeb(dynamic context, String jsonBackup) async {
    debugPrint("Fallback: Mostrar JSON para cópia (implementação de diálogo está no main.dart)");
    debugPrint(jsonBackup);
  }
}