import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import '../core/platform_ports.dart';

class NativeReceiptPicker implements ReceiptPicker {
  const NativeReceiptPicker();

  @override
  Future<PickedFile?> pick() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );

      if (files.isEmpty) return null;
      final file = files.first;

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final name = file.name;
      final ext = file.extension?.toLowerCase() ?? '';
      final mime = ext == 'pdf'
          ? 'application/pdf'
          : ext == 'png'
              ? 'image/png'
              : ext == 'webp'
                  ? 'image/webp'
                  : 'image/jpeg';

      return PickedFile(name, mime, bytes);
    } catch (_) {
      return null;
    }
  }
}

class NativeFileImportSource implements FileImportSource {
  const NativeFileImportSource();

  @override
  Future<PickedFile?> pickExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (files.isEmpty) return null;
      final file = files.first;

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      return PickedFile(
        file.name,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes,
      );
    } catch (_) {
      return null;
    }
  }
}

class NativeDirectoryPicker implements DirectoryPicker {
  const NativeDirectoryPicker();

  @override
  Future<String?> pickDirectory() async {
    try {
      return await FilePicker.getDirectoryPath();
    } catch (_) {
      return null;
    }
  }
}

