// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void openInNewTabImpl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return;
  html.window.open(clean, '_blank');
}

void triggerDownloadImpl(String url, String fileName) {
  final clean = url.trim();
  if (clean.isEmpty) return;
  final anchor = html.AnchorElement(href: clean)
    ..target = '_blank'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
}
