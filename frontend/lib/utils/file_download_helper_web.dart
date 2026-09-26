// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String? saveDownloadedFile(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) {
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  html.document.body?.children.remove(anchor);

  // Delay revoking URL to ensure browser has started the download stream
  Future.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });

  return fileName;
}

String? openPdfPreview(List<int> bytes, String fileName) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future.delayed(const Duration(minutes: 5), () {
    html.Url.revokeObjectUrl(url);
  });
  return url;
}
