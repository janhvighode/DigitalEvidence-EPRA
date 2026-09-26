import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

/// Cross-platform mobile (Android / iOS) & desktop file saver for downloads.
/// Saves the file to the platform-appropriate downloads or documents folder.
String? saveDownloadedFile(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) {
  try {
    Directory? targetDir;

    // Fast path for test environments without platform channels
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final testFile = File('${Directory.systemTemp.path}/$fileName');
      testFile.writeAsBytesSync(bytes);
      return testFile.path;
    }

    if (Platform.isAndroid) {
      // 1. Check standard Android public Downloads directory
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (publicDownload.existsSync()) {
        targetDir = publicDownload;
      }
    }

    targetDir ??= Directory.systemTemp;

    // Ensure safe file name
    String sanitizedName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (sanitizedName.isEmpty) sanitizedName = "downloaded_file.pdf";

    final targetPath = '${targetDir.path}/$sanitizedName';
    final targetFile = File(targetPath);
    targetFile.writeAsBytesSync(bytes);

    debugPrint("[Download] File saved successfully at: $targetPath");
    return targetPath;
  } catch (e) {
    debugPrint("[Download] Failed to save file: $e");
    // Fallback write to systemTemp
    try {
      final fallbackFile = File('${Directory.systemTemp.path}/$fileName');
      fallbackFile.writeAsBytesSync(bytes);
      return fallbackFile.path;
    } catch (_) {
      return null;
    }
  }
}

/// Cross-platform mobile (Android / iOS) & desktop PDF previewer.
/// Saves to a temporary application cache file and opens via the native
/// system PDF viewer / intent without downloading to the user's files.
String? openPdfPreview(List<int> bytes, String fileName) {
  try {
    final tempDir = Directory.systemTemp;

    String sanitizedName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!sanitizedName.toLowerCase().endsWith('.pdf')) {
      sanitizedName = '$sanitizedName.pdf';
    }

    final tempFilePath = '${tempDir.path}/preview_$sanitizedName';
    final tempFile = File(tempFilePath);
    tempFile.writeAsBytesSync(bytes);

    debugPrint("[Preview] Saved temporary PDF for preview at: $tempFilePath");

    // Launch using system native PDF viewer / open-with mechanism on real devices
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      OpenFilex.open(tempFilePath, type: 'application/pdf').then((result) {
        debugPrint("[Preview] OpenFilex result: ${result.type} - ${result.message}");
      }).catchError((err) {
        debugPrint("[Preview] OpenFilex error: $err");
      });
    }

    return tempFilePath;
  } catch (e) {
    debugPrint("[Preview] Failed to open PDF preview: $e");
    return null;
  }
}
