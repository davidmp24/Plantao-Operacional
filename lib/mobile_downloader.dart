// lib/mobile_downloader.dart

// Esta é uma implementação "stub" ou vazia para plataformas não-web.
// Ela fornece os mesmos métodos, mas eles não fazem nada relacionado a dart:html.
class WebDownloader {
  static void downloadFile(String fileName, List<int> bytes, String mimeType) {
    // Não faz nada em plataformas móveis/desktop, pois o FilePicker é usado lá.
    // Poderia lançar um UnimplementedError se chamado incorretamente, mas
    // a lógica no main.dart já usa kIsWeb para evitar chamá-lo.
    print("WebDownloader.downloadFile chamado em plataforma não-web. Isso não deveria acontecer se kIsWeb for usado corretamente.");
  }

  static void showJsonInDialogForWeb(dynamic context, String jsonBackup) {
    // Não faz nada.
    print("WebDownloader.showJsonInDialogForWeb chamado em plataforma não-web.");
  }
}