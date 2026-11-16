import 'web_link_launcher_stub.dart'
    if (dart.library.html) 'web_link_launcher_web.dart';

/// Mở liên kết trong tab mới của trình duyệt
void openInNewTab(String url) => openInNewTabImpl(url);

/// Tải tệp xuống máy người dùng qua trình duyệt
void triggerDownload(String url, String fileName) =>
    triggerDownloadImpl(url, fileName);
