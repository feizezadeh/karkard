import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../core/domain_exception.dart';
import '../data/database.dart';

const List<int> kSqliteHeaderBytes = [
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
];

/// Metadata representing an existing or newly created backup file.
@immutable
class BackupMetadata {
  final String filePath;
  final String fileName;
  final int fileSize;
  final DateTime createdAt;
  final String sha256;

  const BackupMetadata({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
    required this.sha256,
  });

  /// Short SHA-256 for compact UI display (first 10 chars).
  String get shortSha256 =>
      sha256.length >= 10 ? sha256.substring(0, 10) : sha256;

  /// Human-readable file size (KB / MB).
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupMetadata &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(filePath, sha256);

  @override
  String toString() =>
      'BackupMetadata(name: $fileName, size: $formattedSize, sha256: $shortSha256, date: $createdAt)';
}

/// Comparison metrics between current active DB and candidate backup DB.
@immutable
class DbComparison {
  final int currentTxCount;
  final String? currentLatestTxDate;
  final int candidateTxCount;
  final String? candidateLatestTxDate;

  const DbComparison({
    required this.currentTxCount,
    required this.currentLatestTxDate,
    required this.candidateTxCount,
    required this.candidateLatestTxDate,
  });

  @override
  String toString() =>
      'DbComparison(current: $currentTxCount @ $currentLatestTxDate, candidate: $candidateTxCount @ $candidateLatestTxDate)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbComparison &&
          runtimeType == other.runtimeType &&
          currentTxCount == other.currentTxCount &&
          currentLatestTxDate == other.currentLatestTxDate &&
          candidateTxCount == other.candidateTxCount &&
          candidateLatestTxDate == other.candidateLatestTxDate;

  @override
  int get hashCode => Object.hash(
        currentTxCount,
        currentLatestTxDate,
        candidateTxCount,
        candidateLatestTxDate,
      );
}

/// Validates that a file begins with the 16-byte SQLite format 3 magic string.
Future<bool> isValidSqliteHeader(File file) async {
  if (!await file.exists()) return false;
  final length = await file.length();
  if (length < 16) return false;

  final raf = await file.open(mode: FileMode.read);
  try {
    final bytes = await raf.read(16);
    if (bytes.length < 16) return false;
    for (var i = 0; i < 16; i++) {
      if (bytes[i] != kSqliteHeaderBytes[i]) return false;
    }
    return true;
  } catch (_) {
    return false;
  } finally {
    await raf.close();
  }
}

/// Computes SHA-256 hash using streaming to prevent reading large DB files into memory.
Future<String> calculateFileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Interface contract for BackupService per PROJECT.md
abstract class IBackupService {
  Future<BackupMetadata> performBackup({bool isStartup = false});
  Future<List<BackupMetadata>> listBackups();
  Future<void> rotateBackups({int keepCount = 30});
  Future<DbComparison> inspectCandidate(String candidatePath, {String? expectedSha256});
  Future<void> restoreBackup(String candidatePath, {String? expectedSha256});
  Future<Directory> getEffectiveBackupDirectory();
  Future<Directory> getBackupDirectory();
  Future<void> setCustomBackupPath(String? path);
  Future<void> setCustomBackupDirectory(String path);
  Future<void> resetToDefaultBackupDirectory();
  Future<bool> hasCustomBackupDirectory();
  Future<bool> isPathWritable(String path);
}

class BackupService implements IBackupService {
  final AppDatabase db;
  final File? _injectedDbFile;
  final Directory? _injectedDefaultBackupsDir;
  final Future<void> Function(AppDatabase newDb)? onDatabaseRestored;

  static const String customPathSettingKey = 'custom_backup_path';
  static final RegExp backupRegex = RegExp(
    r'^karkard_backup_(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})\.db$',
  );

  BackupService(
    this.db, {
    File? databaseFile,
    File? dbFile,
    Directory? defaultBackupDir,
    Directory? defaultBackupsDirectory,
    this.onDatabaseRestored,
  })  : _injectedDbFile = databaseFile ?? dbFile,
        _injectedDefaultBackupsDir = defaultBackupDir ?? defaultBackupsDirectory;

  /// Resolves the physical database file to back up.
  Future<File> getSourceDatabaseFile() async {
    final injected = _injectedDbFile;
    if (injected != null) return injected;
    return AppDatabase.getDatabaseFile();
  }

  /// Formats backup file name: karkard_backup_YYYY-MM-DD_HHmmss.db
  static String formatBackupFileName(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return 'karkard_backup_$y-$m-${d}_$h$min$s.db';
  }

  /// Parses creation DateTime from backup filename.
  static DateTime? parseBackupFileNameDate(String fileName) {
    final match = backupRegex.firstMatch(fileName);
    if (match == null) return null;
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final h = int.parse(match.group(4)!);
    final min = int.parse(match.group(5)!);
    final s = int.parse(match.group(6)!);
    return DateTime(y, m, d, h, min, s);
  }

  @override
  Future<bool> isPathWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {
          return false;
        }
      }
      final probe = File(
        p.join(dir.path, '.probe_${DateTime.now().microsecondsSinceEpoch}.tmp'),
      );
      probe.writeAsStringSync('probe');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getCustomBackupPath() async {
    final setting = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(customPathSettingKey)))
        .getSingleOrNull();
    final val = setting?.value.trim();
    return (val != null && val.isNotEmpty) ? val : null;
  }

  @override
  Future<bool> hasCustomBackupDirectory() async {
    final path = await getCustomBackupPath();
    return path != null;
  }

  @override
  Future<void> setCustomBackupPath(String? path) async {
    final cleanPath = path?.trim();
    if (cleanPath == null || cleanPath.isEmpty) {
      await (db.delete(db.appSettings)
            ..where((s) => s.key.equals(customPathSettingKey)))
          .go();
      return;
    }

    // Verify validity before saving
    final dir = Directory(cleanPath);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        throw DomainException(
          'ERR_BACKUP_PATH_UNAVAILABLE',
          'امکان دسترسی یا ایجاد مسیر پشتیبان‌گیری انتخابی وجود ندارد: $e',
        );
      }
    }
    final writable = await isPathWritable(dir.path);
    if (!writable) {
      throw const DomainException(
        'ERR_BACKUP_PATH_UNWRITABLE',
        'مسیر پشتیبان‌گیری انتخابی مجوز نوشتن ندارد.',
      );
    }

    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(
            key: customPathSettingKey,
            value: cleanPath,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> setCustomBackupDirectory(String path) => setCustomBackupPath(path);

  @override
  Future<void> resetToDefaultBackupDirectory() => setCustomBackupPath(null);

  @override
  Future<Directory> getEffectiveBackupDirectory() => getBackupDirectory();

  @override
  Future<Directory> getBackupDirectory() async {
    // 1. Check custom path
    final customPath = await getCustomBackupPath();
    if (customPath != null) {
      final dir = Directory(customPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (e) {
          throw DomainException(
            'ERR_BACKUP_PATH_UNAVAILABLE',
            'پوشه سفارشی پشتیبان‌گیری در دسترس نیست: $customPath',
          );
        }
      }
      final writable = await isPathWritable(dir.path);
      if (!writable) {
        throw DomainException(
          'ERR_BACKUP_PATH_UNWRITABLE',
          'پوشه سفارشی پشتیبان‌گیری قابل نوشتن نیست: $customPath',
        );
      }
      return dir;
    }

    // 2. Default directory: <dbDir>/backups/
    final injectedDir = _injectedDefaultBackupsDir;
    if (injectedDir != null) {
      if (!injectedDir.existsSync()) {
        injectedDir.createSync(recursive: true);
      }
      return injectedDir;
    }

    final dbFile = await getSourceDatabaseFile();
    final defaultDir = Directory(p.join(dbFile.parent.path, 'backups'));
    if (!defaultDir.existsSync()) {
      defaultDir.createSync(recursive: true);
    }
    return defaultDir;
  }

  /// Checkpoints the SQLite WAL journal and truncates it to 0 bytes.
  Future<void> checkpointWal() async {
    try {
      final row = await db.customSelect('PRAGMA wal_checkpoint(TRUNCATE);').getSingle();
      final busy = row.data['busy'] as int? ?? 0;
      if (busy != 0) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final retryRow = await db.customSelect('PRAGMA wal_checkpoint(TRUNCATE);').getSingle();
        if ((retryRow.data['busy'] as int? ?? 0) != 0) {
          throw const DomainException(
            'ERR_WAL_CHECKPOINT_BUSY',
            'پایگاه داده در حال حاضر مشغول است و عملیات فلاش کردن ژورنال با خطا مواجه شد.',
          );
        }
      }
    } catch (e) {
      if (e is DomainException) rethrow;
      throw DomainException(
        'ERR_WAL_CHECKPOINT_FAILED',
        'خطا در اجرای چک‌پوینت پایگاه داده: $e',
      );
    }
  }

  @override
  Future<BackupMetadata> performBackup({bool isStartup = false}) async {
    final now = DateTime.now();

    // 1. Startup daily throttling: skip if a backup was already created today
    if (isStartup) {
      final existingBackups = await listBackups();
      final todayPrefix =
          'karkard_backup_${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_';
      final alreadyDoneToday =
          existingBackups.where((b) => b.fileName.startsWith(todayPrefix)).firstOrNull;
      if (alreadyDoneToday != null) {
        return alreadyDoneToday;
      }
    }

    // 2. Execute WAL checkpoint to transfer all pages into base db file
    await checkpointWal();

    // 3. Resolve source database file
    final sourceFile = await getSourceDatabaseFile();
    if (!sourceFile.existsSync()) {
      throw const DomainException(
        'ERR_DB_FILE_NOT_FOUND',
        'فایل پایگاه داده جهت تهیه نسخه پشتیبان یافت نشد.',
      );
    }

    // 4. Resolve destination backup directory
    final targetDir = await getBackupDirectory();

    // 5. Generate filename
    final fileName = formatBackupFileName(now);
    final targetPath = p.join(targetDir.path, fileName);
    final tmpPath = '$targetPath.tmp';
    final tmpFile = File(tmpPath);

    try {
      // 6. Atomic copy: write to .tmp file first
      await sourceFile.copy(tmpPath);

      // 7. Calculate SHA-256 hash and size
      final bytes = await tmpFile.readAsBytes();
      final hashString = sha256.convert(bytes).toString();
      final fileSize = bytes.length;

      // 8. Atomically rename .tmp to final .db filename
      File finalFile;
      try {
        finalFile = await tmpFile.rename(targetPath);
      } catch (_) {
        finalFile = await tmpFile.copy(targetPath);
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      }

      final metadata = BackupMetadata(
        filePath: finalFile.path,
        fileName: fileName,
        fileSize: fileSize,
        createdAt: now,
        sha256: hashString,
      );

      // 9. Execute 30-backup rotation policy
      await rotateBackups(keepCount: 30);

      return metadata;
    } catch (e) {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
      if (e is DomainException) rethrow;
      throw DomainException(
        'ERR_BACKUP_CREATION_FAILED',
        'خطا در ایجاد فایل پشتیبان: $e',
      );
    }
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final dir = await getBackupDirectory();
    if (!dir.existsSync()) return [];

    final entities = dir.listSync();
    final backups = <BackupMetadata>[];

    for (final entity in entities) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final dt = parseBackupFileNameDate(name);
      if (dt == null) continue; // Skip non-matching or emergency files

      try {
        final bytes = entity.readAsBytesSync();
        final hash = sha256.convert(bytes).toString();
        backups.add(BackupMetadata(
          filePath: entity.path,
          fileName: name,
          fileSize: bytes.length,
          createdAt: dt,
          sha256: hash,
        ));
      } catch (_) {
        // Skip inaccessible files during scan
      }
    }

    // Sort descending by creation date (newest first)
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  @override
  Future<void> rotateBackups({int keepCount = 30}) async {
    if (keepCount <= 0) return;

    final dir = await getBackupDirectory();
    if (!dir.existsSync()) return;

    final entities = dir.listSync();
    final backupItems = <({File file, DateTime dt})>[];

    for (final entity in entities) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final dt = parseBackupFileNameDate(name);
      if (dt == null) continue; // Emergency snapshots and temp files protected

      backupItems.add((file: entity, dt: dt));
    }

    backupItems.sort((a, b) => b.dt.compareTo(a.dt));

    if (backupItems.length > keepCount) {
      final toDelete = backupItems.sublist(keepCount);
      for (final item in toDelete) {
        try {
          if (item.file.existsSync()) {
            item.file.deleteSync();
          }
        } catch (_) {}
      }
    }
  }

  @override
  Future<DbComparison> inspectCandidate(
    String candidatePath, {
    String? expectedSha256,
  }) async {
    final candidateFile = File(candidatePath);

    // 1. Existence and size verification
    if (!await candidateFile.exists()) {
      throw const DomainException(
        'ERR_BACKUP_FILE_NOT_FOUND',
        'فایل پشتیبان در مسیر مشخص‌شده یافت نشد.',
      );
    }
    final fileSize = await candidateFile.length();
    if (fileSize < 100) {
      throw const DomainException(
        'ERR_CANDIDATE_CORRUPT',
        'فایل پشتیبان خالی یا فاقد اندازه معتبر است.',
      );
    }

    // 2. Validate SQLite 16-byte magic header
    final validHeader = await isValidSqliteHeader(candidateFile);
    if (!validHeader) {
      throw const DomainException(
        'ERR_CANDIDATE_CORRUPT',
        'فایل انتخاب شده یک پایگاه داده معتبر SQLite نیست (سربرگ نامعتبر).',
      );
    }

    // 3. Verify SHA-256 checksum if provided
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final actualSha256 = await calculateFileSha256(candidateFile);
      if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
        throw const DomainException(
          'ERR_BACKUP_CHECKSUM_MISMATCH',
          'کد هش SHA-256 فایل پشتیبان با مقدار مورد انتظار مغایرت دارد.',
        );
      }
    }

    // 4. Open candidate DB in strict read-only mode
    sqlite.Database candidateDb;
    try {
      candidateDb = sqlite.sqlite3.open(
        candidatePath,
        mode: sqlite.OpenMode.readOnly,
      );
    } catch (e) {
      throw DomainException(
        'ERR_CANDIDATE_CORRUPT',
        'امکان باز کردن فایل پشتیبان در حالت فقط-خواندنی وجود ندارد: $e',
      );
    }

    int candidateTxCount = 0;
    String? candidateLatestTxDate;

    try {
      // 5. Quick integrity check
      final checkResult = candidateDb.select('PRAGMA quick_check;');
      if (checkResult.isEmpty || checkResult.first.values.first != 'ok') {
        throw const DomainException(
          'ERR_CANDIDATE_CORRUPT',
          'ساختار فایل پشتیبان دچار خرابی یا آسیب است و تأیید نشد.',
        );
      }

      // 6. Schema check: transactions table must exist
      final tables = candidateDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
      );
      if (tables.isEmpty) {
        throw const DomainException(
          'ERR_BACKUP_INCOMPATIBLE_SCHEMA',
          'جدول ضروری transactions در فایل پشتیبان یافت نشد.',
        );
      }

      // 7. Schema version check (must be >= 3)
      final settingsTable = candidateDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'",
      );
      if (settingsTable.isNotEmpty) {
        final versionRows = candidateDb.select(
          "SELECT value FROM app_settings WHERE key = 'schema_version'",
        );
        if (versionRows.isNotEmpty) {
          final ver = int.tryParse(versionRows.first['value'] as String? ?? '');
          if (ver != null && ver < 3) {
            throw LegacyDatabaseException(
              fromVersion: ver,
              toVersion: 3,
              message:
                  'فایل پشتیبان متعلق به نسخه قدیمی دیتابیس (نسخه $ver) است و قابل بازیابی مستقیم نیست.',
            );
          }
        }
      }

      // 8. Extract candidate metrics (ignoring soft-deleted transactions)
      final countResult = candidateDb.select(
        'SELECT COUNT(*) AS cnt FROM transactions WHERE deleted_at IS NULL;',
      );
      candidateTxCount = countResult.first['cnt'] as int;

      final dateResult = candidateDb.select(
        'SELECT MAX(date) AS max_date FROM transactions WHERE deleted_at IS NULL;',
      );
      candidateLatestTxDate = dateResult.first['max_date'] as String?;
    } finally {
      candidateDb.close();
    }

    // 9. Extract current active database metrics
    final currentCountRow = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM transactions WHERE deleted_at IS NULL;',
    ).getSingle();
    final currentTxCount = currentCountRow.data['cnt'] as int;

    final currentDateRow = await db.customSelect(
      'SELECT MAX(date) AS max_date FROM transactions WHERE deleted_at IS NULL;',
    ).getSingle();
    final currentLatestTxDate = currentDateRow.data['max_date'] as String?;

    return DbComparison(
      currentTxCount: currentTxCount,
      currentLatestTxDate: currentLatestTxDate,
      candidateTxCount: candidateTxCount,
      candidateLatestTxDate: candidateLatestTxDate,
    );
  }

  Future<File> _createEmergencySnapshot() async {
    final dbFile = await getSourceDatabaseFile();
    if (!await dbFile.exists()) {
      throw const DomainException(
        'ERR_ACTIVE_DATABASE_NOT_FOUND',
        'فایل فعال پایگاه داده یافت نشد.',
      );
    }

    final backupDir = await getBackupDirectory();
    final now = DateTime.now();
    final timestamp = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final emergencyFile = File(
      p.join(backupDir.path, 'emergency_pre_restore_$timestamp.db'),
    );

    // Checkpoint active database first to flush WAL into dbFile
    try {
      await checkpointWal();
    } catch (_) {
      // Proceed with copy attempt
    }

    await dbFile.copy(emergencyFile.path);

    if (!await isValidSqliteHeader(emergencyFile)) {
      throw const DomainException(
        'ERR_EMERGENCY_BACKUP_FAILED',
        'ایجاد نسخه پشتیبان اضطراری با خطا مواجه شد: سربرگ فایل نامعتبر است.',
      );
    }

    return emergencyFile;
  }

  @override
  Future<void> restoreBackup(
    String candidatePath, {
    String? expectedSha256,
  }) async {
    // Step 1: Pre-inspect candidate before touching current DB
    await inspectCandidate(candidatePath, expectedSha256: expectedSha256);

    final candidateFile = File(candidatePath);
    final dbFile = await getSourceDatabaseFile();
    final walFile = File('${dbFile.path}-wal');
    final shmFile = File('${dbFile.path}-shm');
    final stagingFile = File('${dbFile.path}.restore_staging');

    // Step 2: Create pre-restore emergency snapshot
    final emergencyFile = await _createEmergencySnapshot();

    // Step 3: Close active DB connection
    await db.close();

    // Step 4: Perform file swap within try/catch rollback guard
    try {
      // Delete stale WAL and SHM files
      if (walFile.existsSync()) walFile.deleteSync();
      if (shmFile.existsSync()) shmFile.deleteSync();

      // Copy candidate to staging file
      if (stagingFile.existsSync()) stagingFile.deleteSync();
      await candidateFile.copy(stagingFile.path);

      // Verify staging file header
      if (!await isValidSqliteHeader(stagingFile)) {
        throw StateError('Staging file header invalid after copy');
      }

      // Atomic rename (or copy-overwrite fallback)
      try {
        stagingFile.renameSync(dbFile.path);
      } catch (_) {
        stagingFile.copySync(dbFile.path);
        if (stagingFile.existsSync()) stagingFile.deleteSync();
      }

      // Clean any WAL/SHM again
      if (walFile.existsSync()) walFile.deleteSync();
      if (shmFile.existsSync()) shmFile.deleteSync();

      // Step 5: Post-restore verification
      final verifyDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final check = verifyDb.select('PRAGMA quick_check;');
        if (check.isEmpty || check.first.values.first != 'ok') {
          throw StateError(
              'Restored database failed quick_check: ${check.first.values.first}');
        }
        verifyDb.select('SELECT COUNT(*) FROM transactions;');
      } finally {
        verifyDb.close();
      }

      // Clean any wal/shm left by verifyDb
      if (walFile.existsSync()) walFile.deleteSync();
      if (shmFile.existsSync()) shmFile.deleteSync();

      // Step 6: Notify callback / Riverpod if registered
      if (onDatabaseRestored != null) {
        final newDb = AppDatabase.forFile(dbFile);
        await newDb.customSelect('SELECT 1').get();
        await onDatabaseRestored!(newDb);
      }
    } catch (restoreError) {
      // ROLLBACK MECHANISM
      try {
        if (stagingFile.existsSync()) stagingFile.deleteSync();
        if (walFile.existsSync()) walFile.deleteSync();
        if (shmFile.existsSync()) shmFile.deleteSync();

        // Copy emergency backup back to active dbFile
        if (emergencyFile.existsSync()) {
          emergencyFile.copySync(dbFile.path);
        }
        if (walFile.existsSync()) walFile.deleteSync();
        if (shmFile.existsSync()) shmFile.deleteSync();

        // Reconnect original DB
        if (onDatabaseRestored != null) {
          final originalDb = AppDatabase.forFile(dbFile);
          await originalDb.customSelect('SELECT 1').get();
          await onDatabaseRestored!(originalDb);
        }
      } catch (rollbackError) {
        throw DomainException(
          'ERR_RESTORE_ROLLBACK_FAILED',
          'خطای بحرانی در بازیابی و بازگردانی خودکار: $rollbackError. '
          'فایل نسخه اضطراری در مسیر زیر محفوظ است: ${emergencyFile.path}',
        );
      }

      throw DomainException(
        'ERR_RESTORE_FAILED',
        'عملیات بازیابی با خطا مواجه شد و وضعیت پایگاه داده به نسخه اضطراری بازگردانی گردید: $restoreError',
      );
    }
  }
}
