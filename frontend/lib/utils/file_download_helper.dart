import 'file_download_helper_stub.dart'
    if (dart.library.html) 'file_download_helper_web.dart' as impl;

String? lastDownloadedFileName;
List<int>? lastDownloadedBytes;
String? lastDownloadedMimeType;

String? lastPreviewedFileName;
List<int>? lastPreviewedBytes;

String? downloadFileBytes(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) {
  lastDownloadedFileName = fileName;
  lastDownloadedBytes = bytes;
  lastDownloadedMimeType = mimeType;
  return impl.saveDownloadedFile(bytes, fileName, mimeType: mimeType);
}

String? previewPdfBytes(List<int> bytes, String fileName) {
  lastPreviewedFileName = fileName;
  lastPreviewedBytes = bytes;
  return impl.openPdfPreview(bytes, fileName);
}
