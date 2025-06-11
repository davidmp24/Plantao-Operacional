// lib/update_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String versionName;
  final String apkUrl;
  final String releaseNotes;
  final String releaseDate;

  UpdateInfo({
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.releaseDate,
  });
}

class UpdateService {
  final String _versionCheckUrl = "https://gist.githubusercontent.com/davidmp24/3bfcf2fd1b620b6a4b8b4994dcc4ee1c/raw/b75de313b5fc08e48503b44bb1a5e70a1be28378/gistfile1.txt";

  final ValueNotifier<bool> isDownloading = ValueNotifier(false);
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http.get(Uri.parse(_versionCheckUrl)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> versionData = jsonDecode(response.body);
        int latestVersionCode = versionData['latestVersionCode'] as int? ?? 0;

        if (latestVersionCode > currentVersionCode) {
          return UpdateInfo(
            versionName: versionData['latestVersionName'] as String? ?? 'Nova Versão',
            apkUrl: versionData['apkUrl'] as String? ?? '',
            releaseNotes: versionData['releaseNotes'] as String? ?? 'Melhorias e correções.',
            releaseDate: versionData['releaseDate'] as String? ?? '',
          );
        }
      }
      return null;
    } catch (e) {
      print("Erro ao verificar atualização: $e");
      rethrow;
    }
  }

  void showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Nova Atualização Disponível! (${info.versionName})'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Uma nova versão do Plantão Operacional está disponível.'),
                if (info.releaseDate.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Lançada em: ${info.releaseDate}',
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 15),
                const Text('Notas da versão:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(info.releaseNotes),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Mais Tarde'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Atualizar Agora'),
              onPressed: () {
                Navigator.of(context).pop();
                startUpdate(context, info);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> startUpdate(BuildContext context, UpdateInfo updateInfo) async {
    if (kIsWeb) {
      await launchUrl(Uri.parse(updateInfo.apkUrl));
      return;
    }

    if (Platform.isAndroid) {
      var status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        status = await Permission.requestInstallPackages.request();
      }

      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão para instalar apps é necessária.')),
          );
          await openAppSettings();
        }
        return;
      }

      isDownloading.value = true;
      downloadProgress.value = 0.0;

      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(updateInfo.apkUrl));
        final http.StreamedResponse response = await client.send(request);

        if (response.statusCode != 200) throw Exception('Falha no download: ${response.statusCode}');

        final Directory? dir = await getExternalStorageDirectory();
        if (dir == null) throw Exception("Diretório de downloads não encontrado.");

        final String filePath = '${dir.path}/plantao_update.apk';
        final File file = File(filePath);
        final totalBytes = response.contentLength ?? -1;
        var receivedBytes = 0;

        List<int> allBytes = [];
        final stream = response.stream.listen((chunk) {
          allBytes.addAll(chunk);
          receivedBytes += chunk.length;
          if (totalBytes != -1) {
            downloadProgress.value = receivedBytes / totalBytes;
          }
        });

        await stream.asFuture();
        await file.writeAsBytes(allBytes, flush: true);

        isDownloading.value = false;

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download concluído!')));
        }
        await OpenFilex.open(filePath, type: "application/vnd.android.package-archive");
      } catch (e) {
        isDownloading.value = false;
        print("Erro no download/instalação: $e");
        if(context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no download: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }
}