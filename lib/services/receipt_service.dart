import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/domain_exception.dart';
import '../core/error_mapper.dart';
import '../core/platform_ports.dart';
import '../data/database.dart';

/// Data class representing a stored receipt with metadata.
class StoredReceipt {
  final String id;
  final String transactionId;
  final String relativePath;
  final String? fileName;
  final int? fileSize;
  final String? hash;
  final String mime;
  final String createdAt;

  const StoredReceipt({
    required this.id,
    required this.transactionId,
    required this.relativePath,
    this.fileName,
    this.fileSize,
    this.hash,
    required this.mime,
    required this.createdAt,
  });

  factory StoredReceipt.fromData(Receipt r) => StoredReceipt(
        id: r.id,
        transactionId: r.transactionId,
        relativePath: r.filePath,
        fileName: r.fileName,
        fileSize: r.fileSize,
        hash: r.hash,
        mime: r.mime,
        createdAt: r.createdAt,
      );
}

/// Abstract contract for ReceiptService per PROJECT.md interface contract.
abstract class IReceiptService {
  Future<StoredReceipt> saveReceipt({
    required String transactionId,
    required PickedFile file,
  });

  Future<File> getReceiptFile(String relativePath);

  Future<bool> receiptExists(String relativePath);

  Future<void> deleteReceipt(String receiptId);

  Stream<List<Receipt>> watchReceiptsForTransaction(String transactionId);

  Future<List<Receipt>> getReceiptsForTransaction(String transactionId);

  Future<Receipt?> getReceiptById(String receiptId);
}

class ReceiptService implements IReceiptService {
  final AppDatabase db;
  final Directory? _injectedReceiptsDir;
  static const _uuid = Uuid();

  ReceiptService(this.db, {Directory? receiptsDirectory})
      : _injectedReceiptsDir = receiptsDirectory;

  /// Whitelist of permitted file extensions (lowercase with leading dot).
  static const Set<String> allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.pdf',
  };

  /// Canonical MIME mapping for permitted extensions.
  static const Map<String, String> extensionToMime = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.pdf': 'application/pdf',
  };

  /// Resolves physical `<dbDir>/receipts/` directory.
  Future<Directory> getReceiptsDirectory() async {
    if (_injectedReceiptsDir != null) {
      if (!_injectedReceiptsDir.existsSync()) {
        _injectedReceiptsDir.createSync(recursive: true);
      }
      return _injectedReceiptsDir;
    }

    final dbFile = await AppDatabase.getDatabaseFile();
    final receiptsDir = Directory(p.join(dbFile.parent.path, 'receipts'));
    if (!receiptsDir.existsSync()) {
      receiptsDir.createSync(recursive: true);
    }
    return receiptsDir;
  }

  @override
  Future<StoredReceipt> saveReceipt({
    required String transactionId,
    required PickedFile file,
  }) async {
    // 1. Validate file content
    if (file.bytes.isEmpty) {
      throw const DomainException(
        'ERR_RECEIPT_EMPTY_FILE',
        'فایل انتخاب شده خالی است.',
      );
    }

    // 2. Validate and normalize extension
    final ext = p.extension(file.name).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw const DomainException(
        'ERR_RECEIPT_INVALID_EXTENSION',
        'نوع فایل نامعتبر است. پسوندهای مجاز: jpg, jpeg, png, webp, pdf',
      );
    }

    // 3. Resolve MIME type
    final mime = (file.mime.isNotEmpty && file.mime != 'application/octet-stream')
        ? file.mime
        : extensionToMime[ext]!;

    // 4. Verify transaction exists and project is not locked
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (tx == null) {
      throw const DomainException('ERR_TX_NOT_FOUND', 'تراکنش یافت نشد.');
    }

    final project = await (db.select(db.projects)..where((p) => p.id.equals(tx.projectId))).getSingleOrNull();
    if (project == null) {
      throw const DomainException('ERR_PROJECT_NOT_FOUND', 'پروژه یافت نشد.');
    }
    if (project.status == 'locked') {
      throw const DomainException(
        DomainErrors.projectLockedReceipts,
        'پروژه در وضعیت قفل دوره است و افزودن رسید به آن مجاز نیست.',
      );
    }

    // 5. Generate unique IDs and relative path
    final receiptId = _uuid.v4();
    final fileId = _uuid.v4();
    final diskFileName = '$fileId$ext';
    final relativePath = 'receipts/$diskFileName';

    // 6. Compute SHA-256 hash and metadata
    final sha256Hash = sha256.convert(file.bytes).toString();
    final fileSize = file.bytes.length;
    final sanitizedOriginalName = p.basename(file.name);

    // 7. Write to physical disk
    final receiptsDir = await getReceiptsDirectory();
    final physicalFile = File(p.join(receiptsDir.path, diskFileName));
    physicalFile.writeAsBytesSync(file.bytes, flush: true);

    // 8. Insert record in DB with rollback on failure
    try {
      await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              id: receiptId,
              transactionId: transactionId,
              filePath: relativePath,
              mime: mime,
              fileName: Value(sanitizedOriginalName),
              fileSize: Value(fileSize),
              hash: Value(sha256Hash),
            ),
          );

      final row = await (db.select(db.receipts)..where((r) => r.id.equals(receiptId))).getSingle();
      return StoredReceipt.fromData(row);
    } catch (e) {
      // Rollback physical file if DB insert fails
      if (physicalFile.existsSync()) {
        try {
          physicalFile.deleteSync();
        } catch (_) {}
      }
      throw mapSqliteException(e);
    }
  }

  @override
  Future<File> getReceiptFile(String relativePath) async {
    if (relativePath.trim().isEmpty) {
      throw const DomainException(
        'ERR_RECEIPT_INVALID_PATH',
        'مسیر رسید نمی‌تواند خالی باشد.',
      );
    }

    final receiptsDir = await getReceiptsDirectory();
    final canonicalBase = p.canonicalize(receiptsDir.path);

    // Normalize slashes and strip optional leading 'receipts/'
    var cleanRel = p.normalize(relativePath.replaceAll('\\', '/'));
    if (cleanRel.startsWith('receipts/')) {
      cleanRel = cleanRel.substring('receipts/'.length);
    }

    // Resolve full path and canonicalize
    final fullPath = p.canonicalize(p.join(canonicalBase, cleanRel));

    // Strict path traversal check: fullPath MUST be strictly inside canonicalBase
    if (!p.isWithin(canonicalBase, fullPath)) {
      throw const DomainException(
        'ERR_PATH_TRAVERSAL',
        'دسترسی غیرمجاز به مسیر خارج از پوشه رسیدها (Path Traversal Detected).',
      );
    }

    return File(fullPath);
  }

  @override
  Future<bool> receiptExists(String relativePath) async {
    try {
      final file = await getReceiptFile(relativePath);
      return file.existsSync();
    } on DomainException catch (e) {
      if (e.code == 'ERR_PATH_TRAVERSAL') {
        rethrow;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteReceipt(String receiptId) async {
    // 1. Look up receipt
    final receipt = await (db.select(db.receipts)..where((r) => r.id.equals(receiptId))).getSingleOrNull();
    if (receipt == null) {
      throw const DomainException('ERR_RECEIPT_NOT_FOUND', 'رسید مورد نظر یافت نشد.');
    }

    // 2. Proactive check for locked project
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(receipt.transactionId))).getSingleOrNull();
    if (tx != null) {
      final project = await (db.select(db.projects)..where((p) => p.id.equals(tx.projectId))).getSingleOrNull();
      if (project?.status == 'locked') {
        throw const DomainException(
          DomainErrors.projectLockedReceipts,
          'پروژه در وضعیت قفل دوره است و حذف رسید از آن مجاز نیست.',
        );
      }
    }

    // 3. Delete from DB first (triggers enforce locking)
    try {
      await (db.delete(db.receipts)..where((r) => r.id.equals(receiptId))).go();
    } catch (e) {
      throw mapSqliteException(e);
    }

    // 4. Delete physical file only after DB delete succeeds
    try {
      final file = await getReceiptFile(receipt.filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Gracefully handle if file was already missing
    }
  }

  @override
  Stream<List<Receipt>> watchReceiptsForTransaction(String transactionId) {
    return (db.select(db.receipts)
          ..where((r) => r.transactionId.equals(transactionId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  @override
  Future<List<Receipt>> getReceiptsForTransaction(String transactionId) {
    return (db.select(db.receipts)
          ..where((r) => r.transactionId.equals(transactionId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .get();
  }

  @override
  Future<Receipt?> getReceiptById(String receiptId) {
    return (db.select(db.receipts)..where((r) => r.id.equals(receiptId))).getSingleOrNull();
  }
}
