// lib/web_downloader.dart
import 'dart:convert';
import 'dart:html' as html; // Importação direta, pois este arquivo só será usado na web

class WebDownloader {
  static void downloadFile(String fileName, List<int> bytes, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void showJsonInDialogForWeb(dynamic context, String jsonBackup) async {
    // Esta função pode ser chamada como fallback se o download direto não for preferido
    // ou se houver algum problema com a implementação de download.
    // Para usar 'showDialog' e 'AlertDialog' aqui, você precisaria de um BuildContext.
    // No entanto, a forma como está no main.dart (chamando showDialog de lá) é mais simples.
    // Por enquanto, vamos manter o foco no download. Se precisar do diálogo aqui,
    // precisaríamos de uma forma de passar o context ou usar um pacote de overlay.
    // Para simplificar, a lógica do diálogo de fallback permanece no main.dart.
    print("Fallback: Mostrar JSON para cópia (implementação de diálogo está no main.dart)");
    print(jsonBackup); // Apenas para debug se esta função for chamada inesperadamente.
  }
}