// lib/downloader_service.dart

export 'mobile_downloader.dart' // Implementação padrão (para mobile/desktop)
if (dart.library.html) 'web_downloader.dart'; // Implementação para web