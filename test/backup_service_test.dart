import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/core/platform_ports.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/main.dart';
import 'package:karkard/services/backup_service.dart';
import 'package:karkard/ui/settings/safe_restore_dialog.dart';
import 'package:karkard/ui/settings/settings_screen.dart';

class FakeDirectoryPicker implements DirectoryPicker {
  final String? path;
  FakeDirectoryPicker(this.path);

  @override
  Future<String?> pickDirectory() async => path;
}

Future<void> seedProject(
  AppDatabase database, {
  required String projectId,
  String clientId = 'client_1',
}) async {
  await database.into(database.projects).insert(
        ProjectsCompanion.insert(id: projectId, name: 'پروژه تست'),
      );
  await database.into(database.projectSettings).insert(
        ProjectSettingsCompanion.insert(projectId: projectId),
      );
  await database.into(database.persons).insert(
        PersonsCompanion.insert(id: clientId, name: 'کارفرما', kind: 'client'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory tempDir;
  late File dbFile;
  late Directory defaultBackupDir;
  late AppDatabase db;
  late BackupService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('karkard_backup_test_');
    dbFile = File(p.join(tempDir.path, 'karkard.db'));
    defaultBackupDir = Directory(p.join(tempDir.path, 'backups'));
    defaultBackupDir.createSync(recursive: true);

    db = AppDatabase.forFile(dbFile);
    await db.customSelect('SELECT 1').get();

    // Default project seed
    await seedProject(db, projectId: 'p1', clientId: 'client_1');

    service = BackupService(
      db,
      databaseFile: dbFile,
      defaultBackupDir: defaultBackupDir,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('T1: Backup Creation, Checkpoint & SHA-256 Validation', () {
    test('performBackup executes WAL checkpoint and produces valid SQLite backup', () async {
      // Add transactions to active database
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_1',
              projectId: 'p1',
              type: 'work_in',
              amount: 1500000,
              date: '2026-11-03',
              clientId: const Value('client_1'),
            ),
          );

      final metadata = await service.performBackup(isStartup: false);

      expect(metadata.fileName, startsWith('karkard_backup_'));
      expect(metadata.fileName, endsWith('.db'));
      expect(File(metadata.filePath).existsSync(), isTrue);

      final bytes = await File(metadata.filePath).readAsBytes();
      expect(bytes.length, greaterThan(0));
      expect(metadata.fileSize, equals(bytes.length));

      final expectedSha = sha256.convert(bytes).toString();
      expect(metadata.sha256, equals(expectedSha));

      // Header verification: SQLite format 3\x00
      final header = String.fromCharCodes(bytes.take(16));
      expect(header.startsWith('SQLite format 3'), isTrue);

      // Verify data in backup file
      final backupDb = AppDatabase.forFile(File(metadata.filePath));
      final txs = await backupDb.select(backupDb.transactions).get();
      expect(txs.length, equals(1));
      expect(txs.first.id, equals('tx_1'));
      expect(txs.first.amount, equals(1500000));
      await backupDb.close();
    });
  });

  group('T2: Daily Startup Throttling & 30-Backup Rotation Policy', () {
    test('isStartup = true creates today backup then skips duplicate on second run', () async {
      final first = await service.performBackup(isStartup: true);
      final second = await service.performBackup(isStartup: true);

      expect(first.filePath, equals(second.filePath));
      expect(first.sha256, equals(second.sha256));

      final backups = await service.listBackups();
      expect(backups.length, equals(1));
    });

    test('rotateBackups retains newest 30 and prunes older files', () async {
      // Seed 35 simulated backup files with chronological timestamps
      for (var i = 1; i <= 35; i++) {
        final dayStr = i.toString().padLeft(2, '0');
        final f = File(p.join(
          defaultBackupDir.path,
          'karkard_backup_2026-10-${dayStr}_120000.db',
        ));
        await f.writeAsString('SQLite format 3\x00fake_sqlite_backup_data_$i');
      }

      await service.rotateBackups(keepCount: 30);
      final remaining = await service.listBackups();
      expect(remaining.length, equals(30));

      // Verify that the oldest 5 files (days 01 to 05) were pruned
      for (var i = 1; i <= 5; i++) {
        final dayStr = i.toString().padLeft(2, '0');
        final f = File(p.join(
          defaultBackupDir.path,
          'karkard_backup_2026-10-${dayStr}_120000.db',
        ));
        expect(f.existsSync(), isFalse);
      }

      // Verify that newest 30 files remain
      for (var i = 6; i <= 35; i++) {
        final dayStr = i.toString().padLeft(2, '0');
        final f = File(p.join(
          defaultBackupDir.path,
          'karkard_backup_2026-10-${dayStr}_120000.db',
        ));
        expect(f.existsSync(), isTrue);
      }
    });

    test('rotateBackups strictly protects emergency_pre_restore snapshots', () async {
      final emFile = File(p.join(
        defaultBackupDir.path,
        'emergency_pre_restore_2026-10-01_000000.db',
      ));
      await emFile.writeAsString('SQLite format 3\x00emergency_snapshot_data');

      for (var i = 1; i <= 32; i++) {
        final f = File(p.join(
          defaultBackupDir.path,
          'karkard_backup_2026-10-${i.toString().padLeft(2, '0')}_120000.db',
        ));
        await f.writeAsString('SQLite format 3\x00backup_$i');
      }

      await service.rotateBackups(keepCount: 30);

      expect(emFile.existsSync(), isTrue);
      final backups = await service.listBackups();
      expect(backups.length, equals(30));
    });
  });

  group('T3: Custom Backup Path & Writable Warning', () {
    test('persists custom path in AppSettings and switches target folder', () async {
      final customDir = Directory(p.join(tempDir.path, 'custom_backups'))..createSync();
      await service.setCustomBackupDirectory(customDir.path);

      expect(await service.hasCustomBackupDirectory(), isTrue);

      final metadata = await service.performBackup();
      expect(p.dirname(metadata.filePath), equals(customDir.path));

      await service.resetToDefaultBackupDirectory();
      expect(await service.hasCustomBackupDirectory(), isFalse);

      final metadata2 = await service.performBackup();
      expect(p.dirname(metadata2.filePath), equals(defaultBackupDir.path));
    });

    test('detects unwritable directory and throws DomainException', () async {
      const invalidPath = '/proc/invalid_forbidden_dir';
      expect(await service.isPathWritable(invalidPath), isFalse);

      expect(
        () => service.setCustomBackupDirectory(invalidPath),
        throwsA(isA<DomainException>().having(
          (e) => e.code,
          'code',
          anyOf('ERR_BACKUP_PATH_UNAVAILABLE', 'ERR_BACKUP_PATH_UNWRITABLE'),
        )),
      );
    });
  });

  group('T4: Candidate Inspection & DbComparison', () {
    test('rejects non-existent, 0-byte or non-SQLite file', () async {
      final nonExistent = File(p.join(tempDir.path, 'does_not_exist.db'));
      expect(
        () => service.inspectCandidate(nonExistent.path),
        throwsA(isA<DomainException>().having(
          (e) => e.code,
          'code',
          'ERR_BACKUP_FILE_NOT_FOUND',
        )),
      );

      final corruptFile = File(p.join(tempDir.path, 'corrupt.db'))..writeAsStringSync('not sqlite file');
      expect(
        () => service.inspectCandidate(corruptFile.path),
        throwsA(isA<DomainException>().having(
          (e) => e.code,
          'code',
          'ERR_CANDIDATE_CORRUPT',
        )),
      );
    });

    test('rejects candidate with mismatched SHA-256', () async {
      final candidateFile = File(p.join(tempDir.path, 'candidate_sha.db'));
      final cDb = AppDatabase.forFile(candidateFile);
      await cDb.customSelect('SELECT 1').get();
      await cDb.close();

      expect(
        () => service.inspectCandidate(candidateFile.path, expectedSha256: 'wrong_sha_code_12345'),
        throwsA(isA<DomainException>().having(
          (e) => e.code,
          'code',
          'ERR_BACKUP_CHECKSUM_MISMATCH',
        )),
      );
    });

    test('computes accurate DbComparison ignoring soft-deleted transactions', () async {
      // 1. Seed active DB: 2 active txs, 1 soft-deleted
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_act_1',
              projectId: 'p1',
              type: 'work_in',
              amount: 100000,
              date: '2026-11-01',
              clientId: const Value('client_1'),
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_act_2',
              projectId: 'p1',
              type: 'work_in',
              amount: 200000,
              date: '2026-11-03',
              clientId: const Value('client_1'),
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_deleted',
              projectId: 'p1',
              type: 'work_in',
              amount: 300000,
              date: '2026-11-04',
              clientId: const Value('client_1'),
              deletedAt: const Value('2026-11-04T12:00:00Z'),
              deletedReason: const Value('test delete reason'),
            ),
          );

      // 2. Candidate DB: 1 active tx
      final candidateFile = File(p.join(tempDir.path, 'candidate_valid.db'));
      final candidateDb = AppDatabase.forFile(candidateFile);
      await candidateDb.customSelect('SELECT 1').get();
      await seedProject(candidateDb, projectId: 'p_cand', clientId: 'client_1');

      await candidateDb.into(candidateDb.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_c1',
              projectId: 'p_cand',
              type: 'work_in',
              amount: 500000,
              date: '2026-10-25',
              clientId: const Value('client_1'),
            ),
          );
      await candidateDb.close();

      final comp = await service.inspectCandidate(candidateFile.path);

      expect(comp.currentTxCount, equals(2));
      expect(comp.currentLatestTxDate, equals('2026-11-03'));
      expect(comp.candidateTxCount, equals(1));
      expect(comp.candidateLatestTxDate, equals('2026-10-25'));
    });
  });

  group('T5: Safe Restore Flow & Pre-Restore Snapshot', () {
    test('creates emergency snapshot and restores candidate transactions', () async {
      // 1. Candidate DB with 1 transaction
      final candidateFile = File(p.join(tempDir.path, 'candidate_restore.db'));
      final candidateDb = AppDatabase.forFile(candidateFile);
      await candidateDb.customSelect('SELECT 1').get();
      await seedProject(candidateDb, projectId: 'p_res', clientId: 'client_1');

      await candidateDb.into(candidateDb.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_restored_item',
              projectId: 'p_res',
              type: 'work_in',
              amount: 777000,
              date: '2026-11-01',
              clientId: const Value('client_1'),
            ),
          );
      await candidateDb.close();

      // 2. Perform restore
      await service.restoreBackup(candidateFile.path);

      // 3. Verify emergency snapshot exists in backup directory
      final emergencies = defaultBackupDir
          .listSync()
          .where((f) => p.basename(f.path).startsWith('emergency_pre_restore_'))
          .toList();
      expect(emergencies.isNotEmpty, isTrue);

      // 4. Verify active database was replaced with candidate content
      final reopenedDb = AppDatabase.forFile(dbFile);
      final txs = await reopenedDb.select(reopenedDb.transactions).get();
      expect(txs.length, equals(1));
      expect(txs.first.id, equals('tx_restored_item'));
      expect(txs.first.amount, equals(777000));
      await reopenedDb.close();
    });
  });

  group('T6: Widget Tests for SettingsScreen & SafeRestoreDialog', () {
    testWidgets('SettingsScreen displays backup directory, manual backup button, and backups',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dbProvider.overrideWithValue(db),
              backupServiceProvider.overrideWithValue(service),
              directoryPickerProvider.overrideWithValue(FakeDirectoryPicker(tempDir.path)),
            ],
            child: const MaterialApp(
              locale: Locale('fa', 'IR'),
              supportedLocales: [Locale('fa', 'IR')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: SettingsScreen(),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('تنظیمات و پشتیبان‌گیری'), findsOneWidget);
      expect(find.text('مسیر ذخیره فایل‌های پشتیبان'), findsOneWidget);
      expect(find.text('پشتیبان‌گیری اکنون'), findsOneWidget);

      // Trigger manual backup
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'پشتیبان‌گیری اکنون'));
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      final backups = await service.listBackups();
      expect(backups.length, equals(1));
      expect(find.text(backups.first.fileName), findsOneWidget);
    });

    testWidgets('SafeRestoreDialog displays side-by-side comparison, warning, and reassurance',
        (tester) async {
      // Candidate with 1 transaction (active has 0 tx)
      final candidateFile = File(p.join(tempDir.path, 'candidate_widget.db'));
      final candidateDb = AppDatabase.forFile(candidateFile);
      await candidateDb.customSelect('SELECT 1').get();
      await seedProject(candidateDb, projectId: 'p_w', clientId: 'client_1');

      await candidateDb.into(candidateDb.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_w',
              projectId: 'p_w',
              type: 'work_in',
              amount: 250000,
              date: '2026-11-02',
              clientId: const Value('client_1'),
            ),
          );
      await candidateDb.close();

      final bytes = candidateFile.readAsBytesSync();
      final hash = sha256.convert(bytes).toString();

      final fakeCandidate = BackupMetadata(
        filePath: candidateFile.path,
        fileName: 'karkard_backup_widget.db',
        fileSize: bytes.length,
        createdAt: DateTime.now(),
        sha256: hash,
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SafeRestoreDialog(
                candidate: fakeCandidate,
                backupService: service,
              ),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.text('بازیابی امن پایگاه داده'), findsOneWidget);
      expect(find.text('مقایسه وضعیت پایگاه داده'), findsOneWidget);
      expect(find.text('پیش از بازیابی، یک نسخه پشتیبان اضطراری به طور خودکار ذخیره می‌شود.'),
          findsOneWidget);
      expect(find.text('تأیید و بازیابی'), findsOneWidget);
      expect(find.text('انصراف'), findsOneWidget);
    });
  });
}
