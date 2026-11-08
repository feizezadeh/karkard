import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/jalali.dart';
import '../../data/database.dart';
import '../../services/receipt_service.dart';
import 'receipt_missing_placeholder.dart';
import 'receipt_ui_helpers.dart';

/// High-fidelity full dialog viewer for receipts.
/// Supports interactive pan/zoom on images and PdfPreview for multi-page documents.
class ReceiptViewerDialog extends StatelessWidget {
  final Receipt receipt;
  final ReceiptService receiptService;

  const ReceiptViewerDialog({
    super.key,
    required this.receipt,
    required this.receiptService,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = receipt.fileName ?? receipt.filePath;
    final isPdf = isPdfMime(receipt.mime, fileName);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${formatFileSize(receipt.fileSize)} • ثبت: ${isoToJalali(receipt.createdAt.split('T').first)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'بستن',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: FutureBuilder<bool>(
            future: receiptService.receiptExists(receipt.filePath),
            builder: (context, existsSnap) {
              if (existsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (existsSnap.data != true) {
                return ReceiptMissingPlaceholder(
                  fileName: receipt.fileName,
                  relativePath: receipt.filePath,
                  fileSize: receipt.fileSize,
                  compact: false,
                );
              }

              return FutureBuilder<File>(
                future: receiptService.getReceiptFile(receipt.filePath),
                builder: (context, fileSnap) {
                  if (!fileSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final file = fileSnap.data!;

                  if (isPdf) {
                    return PdfPreview(
                      build: (format) => file.readAsBytes(),
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      allowPrinting: true,
                      allowSharing: true,
                      maxPageWidth: 720,
                      pdfFileName: fileName,
                    );
                  }

                  return InteractiveViewer(
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(24),
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.file(
                        file,
                        errorBuilder: (_, _, _) => ReceiptMissingPlaceholder(
                          fileName: receipt.fileName,
                          relativePath: receipt.filePath,
                          fileSize: receipt.fileSize,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ),
    );
  }
}
