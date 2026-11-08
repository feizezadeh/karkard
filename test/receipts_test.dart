import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karkard/core/domain_exception.dart';
import 'package:karkard/core/platform_ports.dart';
import 'package:karkard/data/database.dart';
import 'package:karkard/main.dart';
import 'package:karkard/services/receipt_service.dart';
import 'package:karkard/ui/new_transaction_dialog.dart';
import 'package:karkard/ui/receipts/receipt_attachment_widget.dart';
import 'package:karkard/ui/receipts/receipt_list_dialog.dart';
import 'package:karkard/ui/receipts/receipt_missing_placeholder.dart';

/// 1x1 pixel transparent PNG for genuine Flutter image decoding in widget tests
final kValidPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeReceiptPicker implements ReceiptPicker {
  PickedFile? fileToReturn;
  FakeReceiptPicker([this.fileToReturn]);

  @override
  Future<PickedFile?> pick() async => fileToReturn;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Receipts Database Schema & Triggers', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      // Seed project, person, and transaction
      await db.into(db.projects).insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'پروژه تست رسیدها',
              status: const Value('open'),
            ),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p1'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(
              id: 'pers1',
              name: 'شخص ۱',
              kind: 'client',
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx1',
              projectId: 'p1',
              type: 'work_in',
              amount: 1500000,
              date: '2026-01-01',
              clientId: const Value('pers1'),
            ),
          );
    });

    tearDown(() => db.close());

    test('schemaVersion remains 3', () {
      expect(db.schemaVersion, equals(3));
    });

    test('insert and select receipt with all extended metadata', () async {
      final sha = sha256.convert([10, 20, 30]).toString();
      await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              id: 'rec_full',
              transactionId: 'tx1',
              filePath: 'receipts/test-uuid.png',
              mime: 'image/png',
              fileName: const Value('factor_01.png'),
              fileSize: const Value(3),
              hash: Value(sha),
            ),
          );

      final row = await (db.select(db.receipts)..where((r) => r.id.equals('rec_full'))).getSingle();
      expect(row.id, 'rec_full');
      expect(row.transactionId, 'tx1');
      expect(row.filePath, 'receipts/test-uuid.png');
      expect(row.fileName, 'factor_01.png');
      expect(row.fileSize, 3);
      expect(row.hash, sha);
      expect(row.mime, 'image/png');
    });

    test('insert receipt with minimal fields (backward compatibility)', () async {
      await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              id: 'rec_min',
              transactionId: 'tx1',
              filePath: 'receipts/min-uuid.jpg',
              mime: 'image/jpeg',
            ),
          );

      final row = await (db.select(db.receipts)..where((r) => r.id.equals('rec_min'))).getSingle();
      expect(row.id, 'rec_min');
      expect(row.fileName, isNull);
      expect(row.fileSize, isNull);
      expect(row.hash, isNull);
    });

    test('foreign key constraint prevents receipt for non-existent transaction', () async {
      expect(
        db.into(db.receipts).insert(
              ReceiptsCompanion.insert(
                id: 'rec_fk_fail',
                transactionId: 'non_existent_tx',
                filePath: 'receipts/fake.jpg',
                mime: 'image/jpeg',
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('trigger trg_receipts_no_insert_locked blocks insert when project is locked', () async {
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p1'");

      expect(
        db.into(db.receipts).insert(
              ReceiptsCompanion.insert(
                id: 'rec_locked_fail',
                transactionId: 'tx1',
                filePath: 'receipts/locked.png',
                mime: 'image/png',
              ),
            ),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.toString(),
            'message',
            contains('ERR_PROJECT_LOCKED_RECEIPTS'),
          ),
        ),
      );
    });

    test('trigger trg_receipts_no_delete_locked blocks delete when project is locked', () async {
      await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              id: 'rec_to_del',
              transactionId: 'tx1',
              filePath: 'receipts/del.png',
              mime: 'image/png',
            ),
          );

      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p1'");

      expect(
        (db.delete(db.receipts)..where((r) => r.id.equals('rec_to_del'))).go(),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.toString(),
            'message',
            contains('ERR_PROJECT_LOCKED_RECEIPTS'),
          ),
        ),
      );
    });
  });

  group('ReceiptService Unit & Physical Storage Tests', () {
    late AppDatabase db;
    late Directory tempDir;
    late ReceiptService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      tempDir = Directory.systemTemp.createTempSync('karkard_test_receipts_');
      service = ReceiptService(db, receiptsDirectory: tempDir);

      // Seed project, person, and transaction
      await db.into(db.projects).insert(
            ProjectsCompanion.insert(
              id: 'proj_srv',
              name: 'پروژه تست سرویس',
              status: const Value('open'),
            ),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'proj_srv'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(
              id: 'pers_srv',
              name: 'مشتری ۱',
              kind: 'client',
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_srv_1',
              projectId: 'proj_srv',
              type: 'work_in',
              amount: 2000000,
              date: '2026-01-02',
              clientId: const Value('pers_srv'),
            ),
          );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saveReceipt successfully writes physical file and inserts DB row', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final picked = PickedFile('my_invoice.png', 'image/png', sampleBytes);

      final stored = await service.saveReceipt(
        transactionId: 'tx_srv_1',
        file: picked,
      );

      expect(stored.id, isNotEmpty);
      expect(stored.transactionId, 'tx_srv_1');
      expect(stored.fileName, 'my_invoice.png');
      expect(stored.fileSize, 8);
      expect(stored.mime, 'image/png');
      expect(stored.hash, sha256.convert(sampleBytes).toString());
      expect(stored.relativePath, startsWith('receipts/'));
      expect(stored.relativePath, endsWith('.png'));

      // Check physical file
      final exists = await service.receiptExists(stored.relativePath);
      expect(exists, isTrue);

      final file = await service.getReceiptFile(stored.relativePath);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), sampleBytes);

      // Check query list
      final list = await service.getReceiptsForTransaction('tx_srv_1');
      expect(list.length, 1);
      expect(list.first.id, stored.id);
      expect(list.first.fileName, 'my_invoice.png');

      final single = await service.getReceiptById(stored.id);
      expect(single, isNotNull);
      expect(single!.id, stored.id);
    });

    test('saveReceipt with empty file throws ERR_RECEIPT_EMPTY_FILE', () async {
      final picked = PickedFile('empty.png', 'image/png', Uint8List(0));

      expect(
        service.saveReceipt(transactionId: 'tx_srv_1', file: picked),
        throwsA(
          isA<DomainException>().having((e) => e.code, 'code', 'ERR_RECEIPT_EMPTY_FILE'),
        ),
      );
    });

    test('saveReceipt with unwhitelisted extensions throws ERR_RECEIPT_INVALID_EXTENSION', () async {
      final invalidFiles = [
        PickedFile('script.exe', 'application/octet-stream', Uint8List.fromList([1])),
        PickedFile('hack.sh', 'text/x-shellscript', Uint8List.fromList([1])),
        PickedFile('server.php', 'text/php', Uint8List.fromList([1])),
        PickedFile('image.svg', 'image/svg+xml', Uint8List.fromList([1])),
        PickedFile('document.docx', 'application/docx', Uint8List.fromList([1])),
        PickedFile('noextension', '', Uint8List.fromList([1])),
      ];

      for (final f in invalidFiles) {
        expect(
          service.saveReceipt(transactionId: 'tx_srv_1', file: f),
          throwsA(
            isA<DomainException>().having((e) => e.code, 'code', 'ERR_RECEIPT_INVALID_EXTENSION'),
          ),
        );
      }
    });

    test('saveReceipt succeeds for all whitelisted extensions', () async {
      final validExtensions = ['factor.jpg', 'factor.jpeg', 'factor.png', 'factor.webp', 'factor.pdf'];

      for (var i = 0; i < validExtensions.length; i++) {
        final f = PickedFile(validExtensions[i], '', Uint8List.fromList([i + 1]));
        final stored = await service.saveReceipt(transactionId: 'tx_srv_1', file: f);
        expect(stored.fileName, validExtensions[i]);
        expect(await service.receiptExists(stored.relativePath), isTrue);
      }

      final all = await service.getReceiptsForTransaction('tx_srv_1');
      expect(all.length, validExtensions.length);
    });

    test('strict path traversal attacks are rejected by getReceiptFile and receiptExists', () async {
      final maliciousPaths = [
        '../../etc/passwd',
        'receipts/../../karkard.db',
        '/root/.bashrc',
        '..\\..\\windows\\system32',
        'receipts/subdir/../../../etc/shadow',
        '../outside.png',
      ];

      for (final p in maliciousPaths) {
        expect(
          service.getReceiptFile(p),
          throwsA(
            isA<DomainException>().having((e) => e.code, 'code', 'ERR_PATH_TRAVERSAL'),
          ),
        );

        expect(
          service.receiptExists(p),
          throwsA(
            isA<DomainException>().having((e) => e.code, 'code', 'ERR_PATH_TRAVERSAL'),
          ),
        );
      }

      // Empty path test
      expect(
        service.getReceiptFile('   '),
        throwsA(
          isA<DomainException>().having((e) => e.code, 'code', 'ERR_RECEIPT_INVALID_PATH'),
        ),
      );
    });

    test('saveReceipt blocks when project is locked and leaves no orphan files', () async {
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='proj_srv'");

      final picked = PickedFile('locked_test.png', 'image/png', Uint8List.fromList([1, 2, 3]));

      expect(
        service.saveReceipt(transactionId: 'tx_srv_1', file: picked),
        throwsA(
          isA<DomainException>().having((e) => e.code, 'code', 'ERR_PROJECT_LOCKED_RECEIPTS'),
        ),
      );

      // Verify no files were created in tempDir
      final files = tempDir.listSync();
      expect(files, isEmpty);
    });

    test('deleteReceipt deletes both DB record and physical file in open project', () async {
      final sample = Uint8List.fromList([9, 8, 7]);
      final stored = await service.saveReceipt(
        transactionId: 'tx_srv_1',
        file: PickedFile('to_del.png', 'image/png', sample),
      );

      expect(await service.receiptExists(stored.relativePath), isTrue);

      await service.deleteReceipt(stored.id);

      // Record removed from DB
      final dbCheck = await service.getReceiptById(stored.id);
      expect(dbCheck, isNull);

      // File removed from disk
      expect(await service.receiptExists(stored.relativePath), isFalse);
    });

    test('deleteReceipt rejects when project is locked and preserves physical file', () async {
      final sample = Uint8List.fromList([4, 5, 6]);
      final stored = await service.saveReceipt(
        transactionId: 'tx_srv_1',
        file: PickedFile('preserve.png', 'image/png', sample),
      );

      // Lock project
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='proj_srv'");

      expect(
        service.deleteReceipt(stored.id),
        throwsA(
          isA<DomainException>().having((e) => e.code, 'code', 'ERR_PROJECT_LOCKED_RECEIPTS'),
        ),
      );

      // File on disk must still exist
      expect(await service.receiptExists(stored.relativePath), isTrue);

      // DB record must still exist
      final dbCheck = await service.getReceiptById(stored.id);
      expect(dbCheck, isNotNull);
    });

    test('deleteReceipt handles non-existent receipt with ERR_RECEIPT_NOT_FOUND', () async {
      expect(
        service.deleteReceipt('non_existent_receipt_id'),
        throwsA(
          isA<DomainException>().having((e) => e.code, 'code', 'ERR_RECEIPT_NOT_FOUND'),
        ),
      );
    });

    test('deleteReceipt gracefully cleans up DB record if physical file was already missing', () async {
      final sample = Uint8List.fromList([1, 1, 1]);
      final stored = await service.saveReceipt(
        transactionId: 'tx_srv_1',
        file: PickedFile('ghost.png', 'image/png', sample),
      );

      // Delete physical file externally
      final physicalFile = await service.getReceiptFile(stored.relativePath);
      await physicalFile.delete();
      expect(await physicalFile.exists(), isFalse);

      // deleteReceipt should not crash
      await service.deleteReceipt(stored.id);

      final dbCheck = await service.getReceiptById(stored.id);
      expect(dbCheck, isNull);
    });
  });

  group('Receipts UI Widgets Tests', () {
    testWidgets('ReceiptMissingPlaceholder renders correctly in compact and full modes', (tester) async {
      // 1. Compact mode
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReceiptMissingPlaceholder(
              fileName: 'missing.jpg',
              relativePath: 'receipts/missing.jpg',
              fileSize: 1024,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('ناموجود'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      // 2. Full mode
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReceiptMissingPlaceholder(
              fileName: 'factor_lost.pdf',
              relativePath: 'receipts/lost.pdf',
              fileSize: 2048000,
              compact: false,
            ),
          ),
        ),
      );

      expect(find.text('فایل رسید روی دیسک یافت نشد'), findsOneWidget);
      expect(find.text('factor_lost.pdf'), findsOneWidget);
      expect(find.text('receipts/lost.pdf'), findsOneWidget);
    });

    testWidgets('ReceiptAttachmentWidget renders empty state and handles add/remove', (tester) async {
      List<PickedFile> pending = [];
      final fakePicker = FakeReceiptPicker(
        PickedFile('invoice.png', 'image/png', kValidPngBytes),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ReceiptAttachmentWidget(
                  pendingFiles: pending,
                  picker: fakePicker,
                  onChanged: (updated) {
                    setState(() {
                      pending = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Initial empty state
      expect(find.text('پیوست رسید و فاکتور (0)'), findsOneWidget);
      expect(find.text('می‌توانید تصویر یا فایل PDF فاکتور را پیوست کنید (اختیاری).'), findsOneWidget);

      // Click "انتخاب فایل"
      await tester.tap(find.text('انتخاب فایل'));
      await tester.pumpAndSettle();

      // Should now show 1 file chip
      expect(find.text('پیوست رسید و فاکتور (1)'), findsOneWidget);
      expect(find.text('invoice.png'), findsOneWidget);

      // Click remove button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Back to empty
      expect(find.text('پیوست رسید و فاکتور (0)'), findsOneWidget);
    });

    testWidgets('ReceiptAttachmentWidget rejects non-whitelisted extension with snackbar', (tester) async {
      List<PickedFile> pending = [];
      final fakePicker = FakeReceiptPicker(
        PickedFile('malicious.exe', 'application/octet-stream', Uint8List.fromList([1, 2, 3])),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptAttachmentWidget(
              pendingFiles: pending,
              picker: fakePicker,
              onChanged: (updated) => pending = updated,
            ),
          ),
        ),
      );

      await tester.tap(find.text('انتخاب فایل'));
      await tester.pumpAndSettle();

      expect(find.text('تنها فایل‌های تصویری (JPG, PNG, WEBP) و PDF مجاز هستند.'), findsOneWidget);
      expect(pending, isEmpty);
    });

    testWidgets('ReceiptListDialog displays receipts, add button for open projects, and delete confirmation', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      final tempDir = Directory.systemTemp.createTempSync('karkard_test_dialog_');
      final service = ReceiptService(db, receiptsDirectory: tempDir);

      await db.into(db.projects).insert(
            ProjectsCompanion.insert(id: 'p_dlg', name: 'پروژه دیالوگ'),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p_dlg'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(id: 'cli_dlg', name: 'مشتری دیالوگ', kind: 'client'),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_dlg',
              projectId: 'p_dlg',
              type: 'work_in',
              amount: 5000000,
              date: '2026-01-01',
              clientId: const Value('cli_dlg'),
            ),
          );

      // Pre-save a receipt
      await service.saveReceipt(
        transactionId: 'tx_dlg',
        file: PickedFile('dialog_factor.png', 'image/png', kValidPngBytes),
      );

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_dlg'))).getSingle();

      // Open dialog
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptListDialog(
              transaction: tx,
              isProjectLocked: false,
              receiptService: service,
              picker: FakeReceiptPicker(
                PickedFile('dialog_factor2.png', 'image/png', kValidPngBytes),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('اسناد و رسیدهای پیوست'), findsOneWidget);
      expect(find.text('dialog_factor.png'), findsOneWidget);

      // Tap delete button to trigger confirmation
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('تأیید حذف رسید'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Back to empty
      expect(find.text('هیچ رسیدی برای این تراکنش پیوست نشده است.'), findsOneWidget);

      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('ReceiptListDialog disables deletion and hides add button when project is locked', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      final tempDir = Directory.systemTemp.createTempSync('karkard_test_locked_dialog_');
      final service = ReceiptService(db, receiptsDirectory: tempDir);

      await db.into(db.projects).insert(
            ProjectsCompanion.insert(id: 'p_locked_dlg', name: 'پروژه قفل', status: const Value('open')),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p_locked_dlg'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(id: 'cli_locked', name: 'مشتری قفل', kind: 'client'),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_locked_dlg',
              projectId: 'p_locked_dlg',
              type: 'work_in',
              amount: 5000000,
              date: '2026-01-01',
              clientId: const Value('cli_locked'),
            ),
          );

      // Insert receipt directly into DB before locking
      await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              id: 'r_locked_existing',
              transactionId: 'tx_locked_dlg',
              filePath: 'receipts/locked_file.png',
              fileName: const Value('locked_file.png'),
              mime: 'image/png',
            ),
          );

      // Lock project after initial setup
      await db.customStatement("UPDATE projects SET status='locked' WHERE id='p_locked_dlg'");

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx_locked_dlg'))).getSingle();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptListDialog(
              transaction: tx,
              isProjectLocked: true,
              receiptService: service,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // "افزودن رسید جدید" should NOT be present
      expect(find.text('افزودن رسید جدید'), findsNothing);

      // Delete icon button should have onPressed == null
      final deleteBtn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(deleteBtn.onPressed, isNull);

      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('NewTransactionDialog persists attached receipts upon submission', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      final tempDir = Directory.systemTemp.createTempSync('karkard_test_newtx_');
      final service = ReceiptService(db, receiptsDirectory: tempDir);

      await db.into(db.projects).insert(
            ProjectsCompanion.insert(id: 'p_newtx', name: 'پروژه ثبت تراکنش'),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p_newtx'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(id: 'c_newtx', name: 'کارفرما علی', kind: 'client'),
          );

      final fakePicker = FakeReceiptPicker(
        PickedFile('factor_attached.png', 'image/png', kValidPngBytes),
      );

      var savedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewTransactionDialog(
              db: db,
              projectId: 'p_newtx',
              receiptService: service,
              picker: fakePicker,
              onSaved: () => savedCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter amount
      await tester.enterText(find.widgetWithText(TextField, 'مبلغ (تومان)'), '3000000');

      // Click "انتخاب فایل" to attach receipt
      await tester.ensureVisible(find.text('انتخاب فایل'));
      await tester.tap(find.text('انتخاب فایل'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('factor_attached.png'), findsOneWidget);

      // Submit
      await tester.ensureVisible(find.text('ذخیره و ثبت در دفتر'));
      await tester.tap(find.text('ذخیره و ثبت در دفتر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(savedCalled, isTrue);

      // Verify transaction was saved
      final txList = await (db.select(db.transactions)..where((t) => t.projectId.equals('p_newtx'))).get();
      expect(txList.length, 1);
      final createdTx = txList.first;
      expect(createdTx.amount, 3000000);

      // Verify receipt was saved for this transaction
      final receipts = await service.getReceiptsForTransaction(createdTx.id);
      expect(receipts.length, 1);
      expect(receipts.first.fileName, 'factor_attached.png');

      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('NewTransactionDialog persists receiptNotRequired flag', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      await db.into(db.projects).insert(
            ProjectsCompanion.insert(id: 'p_not_req', name: 'پروژه بدون رسید'),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p_not_req'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(id: 'c_not_req', name: 'کارفرما رضا', kind: 'client'),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NewTransactionDialog(
              db: db,
              projectId: 'p_not_req',
              onSaved: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter amount
      await tester.enterText(find.widgetWithText(TextField, 'مبلغ (تومان)'), '1200000');

      // Check "رسید لازم ندارد"
      await tester.ensureVisible(find.text('رسید لازم ندارد'));
      await tester.tap(find.text('رسید لازم ندارد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Submit
      await tester.ensureVisible(find.text('ذخیره و ثبت در دفتر'));
      await tester.tap(find.text('ذخیره و ثبت در دفتر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final txList = await (db.select(db.transactions)..where((t) => t.projectId.equals('p_not_req'))).get();
      expect(txList.length, 1);
      expect(txList.first.receiptNotRequired, isTrue);

      await db.close();
    });

    testWidgets('Home page DataTable and Cards show receipt count badge', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('select 1').get();

      final tempDir = Directory.systemTemp.createTempSync('karkard_test_home_');
      final service = ReceiptService(db, receiptsDirectory: tempDir);

      await db.into(db.projects).insert(
            ProjectsCompanion.insert(id: 'p_home', name: 'پروژه اصلی'),
          );
      await db.into(db.projectSettings).insert(
            ProjectSettingsCompanion.insert(projectId: 'p_home'),
          );
      await db.into(db.persons).insert(
            PersonsCompanion.insert(id: 'pers_home', name: 'کارفرما بهرام', kind: 'client'),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx_home_1',
              projectId: 'p_home',
              type: 'work_in',
              amount: 4000000,
              date: '2026-01-01',
              clientId: const Value('pers_home'),
            ),
          );

      // Attach 2 receipts
      await service.saveReceipt(
        transactionId: 'tx_home_1',
        file: PickedFile('f1.png', 'image/png', kValidPngBytes),
      );
      await service.saveReceipt(
        transactionId: 'tx_home_1',
        file: PickedFile('f2.png', 'image/png', kValidPngBytes),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbProvider.overrideWithValue(db),
            receiptServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      // Advance frames to resolve streams and future providers
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to transactions tab
      await tester.tap(find.text('تراکنش‌ها'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // DataTable should show 'رسید' column
      expect(find.text('رسید'), findsOneWidget);

      // Should show Persian count '۲'
      expect(find.text('۲'), findsOneWidget);

      // Tap on receipt button to open ReceiptListDialog
      await tester.tap(find.widgetWithText(OutlinedButton, '۲'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('اسناد و رسیدهای پیوست'), findsOneWidget);
      expect(find.text('f1.png'), findsOneWidget);
      expect(find.text('f2.png'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('بستن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
  });
}
