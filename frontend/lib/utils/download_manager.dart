import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/session_manager.dart';
import 'file_download_helper.dart';

class DownloadManager {
  /// Resolves the final file name from the Content-Disposition header,
  /// falling back to [defaultFileName] if the header is missing or invalid.
  static String resolveFileName(
    Map<String, String> headers,
    String defaultFileName,
  ) {
    final cd = headers['content-disposition'] ?? headers['Content-Disposition'];
    if (cd != null && cd.isNotEmpty) {
      // 1. Try filename*=UTF-8''... (RFC 5987 / 6266)
      final starMatch = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
          .firstMatch(cd);
      if (starMatch != null && starMatch.group(1) != null) {
        try {
          final decoded = Uri.decodeComponent(starMatch.group(1)!.trim());
          if (decoded.isNotEmpty) return decoded;
        } catch (_) {}
      }

      // 2. Try standard filename="..." or filename=...
      final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
          .firstMatch(cd);
      if (match != null &&
          match.group(1) != null &&
          match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim();
      }
    }

    return defaultFileName.trim().isNotEmpty
        ? defaultFileName.trim()
        : "downloaded_file";
  }

  /// Formats byte count to human-readable string (KB/MB).
  static String formatByteCount(int bytes) {
    if (bytes < 1024) return "$bytes bytes";
    final kb = bytes / 1024;
    if (kb < 1024) return "${kb.toStringAsFixed(1)} KB";
    final mb = kb / 1024;
    return "${mb.toStringAsFixed(2)} MB";
  }

  /// Executes an authenticated download request, processes binary bytes,
  /// parses headers, handles errors, and triggers a real browser/device download.
  static Future<bool> executeDownload({
    required BuildContext context,
    required Future<http.Response> Function() request,
    required String defaultFileName,
    String? defaultMimeType,
    void Function(bool isDownloading)? onLoadingChanged,
    VoidCallback? onSuccess,
    void Function(String errorMessage)? onError,
  }) async {
    onLoadingChanged?.call(true);

    try {
      final response = await request();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;

        if (bytes.isEmpty) {
          throw Exception("Downloaded file is empty");
        }

        final contentType = response.headers['content-type'] ??
            response.headers['Content-Type'] ??
            defaultMimeType ??
            'application/octet-stream';

        // Check if the 200 OK response is actually an error/placeholder JSON
        if (contentType.toLowerCase().contains('application/json') &&
            !defaultFileName.toLowerCase().endsWith('.json')) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              if (decoded.containsKey('detail') ||
                  decoded.containsKey('error')) {
                final err = (decoded['detail'] ?? decoded['error']).toString();
                throw Exception(err);
              }
              if (decoded.containsKey('message')) {
                final msg = decoded['message'].toString();
                if (context.mounted) _showErrorSnackBar(context, msg);
                onError?.call(msg);
                return false;
              }
            }
          } catch (e) {
            if (e is Exception && !e.toString().contains("FormatException")) {
              rethrow;
            }
          }
        }

        final finalFileName = resolveFileName(
          response.headers,
          defaultFileName,
        );

        // Trigger real file download via web blob/anchor or platform mechanism
        downloadFileBytes(bytes, finalFileName, mimeType: contentType);

        if (context.mounted) {
          _showSuccessSnackBar(
            context,
            finalFileName,
            bytes.length,
          );
        }

        onSuccess?.call();
        return true;
      } else if (response.statusCode == 401) {
        if (context.mounted) {
          await SessionManager.instance.logoutAndRedirectToLogin(
            reason: "Session expired. Please log in again.",
          );
        }
        onError?.call("Session expired");
        return false;
      } else if (response.statusCode == 403) {
        final msg = "Access denied. You do not have permission to download this file.";
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      } else if (response.statusCode == 404) {
        debugPrint("[DownloadManager] HTTP 404: ${response.request?.url ?? 'unknown URL'} - Response: ${response.body}");
        final msg = "File or report not found (HTTP 404).";
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      } else if (response.statusCode >= 500) {
        final msg = "Server error (${response.statusCode}). Please retry in a moment.";
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      } else {
        String errorMsg = "Download failed (HTTP ${response.statusCode})";
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded["detail"] != null) {
            errorMsg = decoded["detail"].toString();
          }
        } catch (_) {}

        if (context.mounted) _showErrorSnackBar(context, errorMsg);
        onError?.call(errorMsg);
        return false;
      }
    } catch (e) {
      final msg = e.toString().replaceFirst("Exception: ", "");
      if (context.mounted) {
        _showErrorSnackBar(context, "Error downloading file: $msg");
      }
      onError?.call(msg);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  static void _showSuccessSnackBar(
    BuildContext context,
    String fileName,
    int byteCount,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF059669),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Successfully downloaded $fileName (${formatByteCount(byteCount)})",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Executes an authenticated PDF preview request, processes binary bytes,
  /// and triggers an inline browser preview without regenerating.
  static Future<bool> executePdfPreview({
    required BuildContext context,
    required Future<http.Response> Function() request,
    required String defaultFileName,
    void Function(bool isLoading)? onLoadingChanged,
    VoidCallback? onSuccess,
    void Function(String errorMessage)? onError,
  }) async {
    onLoadingChanged?.call(true);

    try {
      final response = await request();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;

        if (bytes.isEmpty) {
          throw Exception("Report file is empty");
        }

        final contentType = response.headers['content-type'] ??
            response.headers['Content-Type'] ??
            'application/pdf';

        if (contentType.toLowerCase().contains('application/json')) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map) {
              if (decoded.containsKey('detail') || decoded.containsKey('error')) {
                final err = (decoded['detail'] ?? decoded['error']).toString();
                throw Exception(err);
              }
              if (decoded.containsKey('message')) {
                final msg = decoded['message'].toString();
                if (context.mounted) _showErrorSnackBar(context, msg);
                onError?.call(msg);
                return false;
              }
            }
          } catch (e) {
            if (e is Exception && !e.toString().contains("FormatException")) {
              rethrow;
            }
          }
        }

        final finalFileName = resolveFileName(
          response.headers,
          defaultFileName,
        );

        previewPdfBytes(bytes, finalFileName);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Opening preview for $finalFileName",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E40AF),
              duration: const Duration(seconds: 3),
            ),
          );
        }

        onSuccess?.call();
      } else if (response.statusCode == 401) {
        if (context.mounted) {
          await SessionManager.instance.logoutAndRedirectToLogin(
            reason: "Session expired. Please log in again.",
          );
        }
        onError?.call("Session expired");
        return false;
      } else if (response.statusCode == 403) {
        const msg = "Access Denied: You are not authorized to preview this report.";
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      } else if (response.statusCode == 404) {
        const msg = "Report not found: Persisted report file is unavailable.";
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      } else {
        String msg = "Preview failed (HTTP ${response.statusCode})";
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['detail'] != null) {
            msg = decoded['detail'].toString();
          }
        } catch (_) {}
        if (context.mounted) _showErrorSnackBar(context, msg);
        onError?.call(msg);
        return false;
      }
    } catch (e) {
      final msg = "Preview error: ${e.toString().replaceAll("Exception: ", "")}";
      if (context.mounted) _showErrorSnackBar(context, msg);
      onError?.call(msg);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
    return false;
  }
}
