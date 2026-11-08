import 'dart:typed_data';

/// Platform-dependent inputs live behind these interfaces so domain/feature
/// logic never touches a platform API. Implementations come with the feature
/// that needs them (phase 2); none is faked here.

/// Picked receipt: bytes, never a path (Android may hand out content:// URIs).
class PickedFile {
  final String name;
  final String mime;
  final Uint8List bytes;
  const PickedFile(this.name, this.mime, this.bytes);
}

/// Desktop: drag-drop + file_picker. Android: image_picker.
abstract interface class ReceiptPicker {
  /// Returns null if the user cancelled. Throws on read failure.
  Future<PickedFile?> pick();
}

/// Source of an .xlsx import. Returns bytes, not a path.
abstract interface class FileImportSource {
  Future<PickedFile?> pickExcel();
}

/// Desktop: user-chosen folder. Android: app storage + export via picker/share.
abstract interface class BackupLocationService {
  /// Throws if the location is unavailable (never silently skips a backup).
  Future<void> writeBackup(String fileName, Uint8List bytes);

  /// User-facing export/transfer (desktop: copy to folder; Android: share).
  Future<void> exportBackup(String fileName, Uint8List bytes);
}

/// Directory picker interface for selecting custom backup folders.
abstract interface class DirectoryPicker {
  Future<String?> pickDirectory();
}

