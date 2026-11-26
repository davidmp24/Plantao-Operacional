// lib/backup_helper_web.dart

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use, uri_does_not_exist
import 'dart:html' as html;

// Esta é a implementação real para a plataforma Web.
Future<void> performWebBackup(String fileName, String jsonContent) async {
  final bytes = utf8.encode(jsonContent);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute("download", fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}