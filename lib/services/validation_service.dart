import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/domain_exception.dart';
import '../data/database.dart';
import 'balance_service.dart';

/// ValidationService enforces domain constraints and provides atomic transaction operations
/// with synchronized audit_log recording per Section 4 & 9 of the system specification.
class ValidationService {
  final AppDatabase db;
  final BalanceService balanceService;
  static const _uuid = Uuid();

  ValidationService(this.db, {BalanceService? balanceService})
      : balanceService = balanceService ?? BalanceService(db);

  /// Validates domain rules before inserting or updating a transaction.
  Future<void> validateTransaction(TransactionsCompanion tx, {bool isUpdate = false}) async {
    // 1. Amount validation
    if (tx.amount.present) {
      if (tx.amount.value <= 0) {
        throw const DomainException('ERR_TX_AMOUNT_POSITIVE', 'مبلغ باید عددی مثبت و بزرگ‌تر از صفر باشد.');
      }
    }

    // 2. Project check (must exist and not be locked)
    if (tx.projectId.present) {
      final project = await (db.select(db.projects)..where((p) => p.id.equals(tx.projectId.value))).getSingleOrNull();
      if (project == null) {
        throw const DomainException('ERR_PROJECT_NOT_FOUND', 'پروژه مورد نظر یافت نشد.');
      }
      if (project.status == 'locked') {
        throw const DomainException(DomainErrors.projectLockedTx, 'پروژه در وضعیت قفل دوره است و ثبت یا ویرایش تراکنش در آن مجاز نیست.');
      }
    }

    // 3. Type check & required/forbidden fields
    if (tx.type.present) {
      final type = tx.type.value;
      const validTypes = {'work_in', 'work_out', 'income', 'expense', 'payout', 'transfer'};
      if (!validTypes.contains(type)) {
        throw const DomainException('ERR_INVALID_TX_TYPE', 'نوع تراکنش نامعتبر است.');
      }

      switch (type) {
        case 'work_in':
          if (!tx.clientId.present || tx.clientId.value == null) {
            throw const DomainException(DomainErrors.workInMissingClient, 'ثبت کارکرد طلب نیازمند مشخص بودن کارفرما است.');
          }
          if ((tx.cashAccountId.present && tx.cashAccountId.value != null) ||
              (tx.fromAccountId.present && tx.fromAccountId.value != null) ||
              (tx.toAccountId.present && tx.toAccountId.value != null) ||
              (tx.personId.present && tx.personId.value != null) ||
              (tx.purpose.present && tx.purpose.value != null)) {
            throw const DomainException(DomainErrors.workInForbiddenFields, 'فیلدهای نقدی، شخص یا هدف پرداخت برای نوع work_in غیرمجاز است.');
          }
          break;

        case 'work_out':
          if (!tx.personId.present || tx.personId.value == null) {
            throw const DomainException(DomainErrors.workOutMissingPerson, 'ثبت کارکرد بدهی نیازمند مشخص بودن شخص مربوطه است.');
          }
          if ((tx.clientId.present && tx.clientId.value != null) ||
              (tx.cashAccountId.present && tx.cashAccountId.value != null) ||
              (tx.fromAccountId.present && tx.fromAccountId.value != null) ||
              (tx.toAccountId.present && tx.toAccountId.value != null) ||
              (tx.performedBy.present && tx.performedBy.value != null) ||
              (tx.purpose.present && tx.purpose.value != null)) {
            throw const DomainException(DomainErrors.workOutForbiddenFields, 'فیلدهای کارفرما یا حساب نقدی برای نوع work_out غیرمجاز است.');
          }
          break;

        case 'income':
          if (!tx.cashAccountId.present || tx.cashAccountId.value == null) {
            throw const DomainException(DomainErrors.missingCashAccount, 'ثبت دریافتی نیازمند تعیین حساب نقدی است.');
          }
          if (!tx.clientId.present || tx.clientId.value == null) {
            throw const DomainException(DomainErrors.incomeMissingClient, 'ثبت دریافتی نیازمند تعیین کارفرما است.');
          }
          if ((tx.fromAccountId.present && tx.fromAccountId.value != null) ||
              (tx.toAccountId.present && tx.toAccountId.value != null) ||
              (tx.personId.present && tx.personId.value != null) ||
              (tx.performedBy.present && tx.performedBy.value != null) ||
              (tx.attributedTo.present && tx.attributedTo.value != null) ||
              (tx.purpose.present && tx.purpose.value != null)) {
            throw const DomainException(DomainErrors.incomeForbiddenFields, 'فیلدهای نامربوط برای نوع income وارد شده است.');
          }
          break;

        case 'expense':
          if (!tx.cashAccountId.present || tx.cashAccountId.value == null) {
            throw const DomainException(DomainErrors.missingCashAccount, 'ثبت هزینه نیازمند تعیین حساب نقدی است.');
          }
          if ((tx.clientId.present && tx.clientId.value != null) ||
              (tx.fromAccountId.present && tx.fromAccountId.value != null) ||
              (tx.toAccountId.present && tx.toAccountId.value != null) ||
              (tx.personId.present && tx.personId.value != null) ||
              (tx.performedBy.present && tx.performedBy.value != null) ||
              (tx.purpose.present && tx.purpose.value != null)) {
            throw const DomainException(DomainErrors.expenseForbiddenFields, 'فیلدهای نامربوط برای نوع expense وارد شده است.');
          }
          break;

        case 'payout':
          if (!tx.personId.present || tx.personId.value == null ||
              !tx.cashAccountId.present || tx.cashAccountId.value == null ||
              !tx.purpose.present || tx.purpose.value == null) {
            throw const DomainException(DomainErrors.payoutRequiredFields, 'ثبت پرداخت به شخص نیازمند شخص، حساب نقدی و هدف پرداخت است.');
          }
          if ((tx.clientId.present && tx.clientId.value != null) ||
              (tx.performedBy.present && tx.performedBy.value != null) ||
              (tx.attributedTo.present && tx.attributedTo.value != null) ||
              (tx.fromAccountId.present && tx.fromAccountId.value != null) ||
              (tx.toAccountId.present && tx.toAccountId.value != null)) {
            throw const DomainException(DomainErrors.payoutForbiddenFields, 'فیلدهای نامربوط برای نوع payout وارد شده است.');
          }
          break;

        case 'transfer':
          final fromAcc = tx.fromAccountId.value;
          final toAcc = tx.toAccountId.value;
          if (fromAcc == null || toAcc == null || fromAcc == toAcc) {
            throw const DomainException(DomainErrors.transferSameAccount, 'انتقال باید بین دو حساب مجزا و متمایز انجام شود.');
          }
          if ((tx.cashAccountId.present && tx.cashAccountId.value != null) ||
              (tx.clientId.present && tx.clientId.value != null) ||
              (tx.personId.present && tx.personId.value != null) ||
              (tx.performedBy.present && tx.performedBy.value != null) ||
              (tx.attributedTo.present && tx.attributedTo.value != null) ||
              (tx.purpose.present && tx.purpose.value != null) ||
              (tx.categoryId.present && tx.categoryId.value != null)) {
            throw const DomainException(DomainErrors.transferForbiddenFields, 'فیلدهای نامربوط برای نوع transfer وارد شده است.');
          }
          break;
      }
    }

    // 4. Category ID only valid for expense
    if (tx.categoryId.present && tx.categoryId.value != null) {
      if (tx.type.present && tx.type.value != 'expense') {
        throw const DomainException('ERR_CATEGORY_ONLY_FOR_EXPENSE', 'دسته‌بندی فقط برای نوع هزینه مجاز است.');
      }
    }

    // 5. Date format validation (YYYY-MM-DD)
    if (tx.date.present) {
      final dateStr = tx.date.value;
      final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr);
      if (!match) {
        throw const DomainException('ERR_INVALID_DATE_FORMAT', 'فرمت تاریخ باید به صورت YYYY-MM-DD میلادی باشد.');
      }
      try {
        DateTime.parse(dateStr);
      } catch (_) {
        throw const DomainException('ERR_INVALID_DATE', 'تاریخ وارد شده در تقویم معتبر نیست.');
      }
    }

    // 6. Balance ceilings (distribution & settle_payable)
    if (!isUpdate) {
      await balanceService.validateTransactionForInsert(tx);
    }
  }

  /// Atomically inserts a transaction and logs it to audit_log in the same DB transaction.
  /// Guarantees rollback if audit_log or transaction insertion fails.
  Future<Transaction> createTransactionAtomic(TransactionsCompanion tx) async {
    await validateTransaction(tx, isUpdate: false);

    final id = tx.id.present ? tx.id.value : _uuid.v4();
    final companionWithId = tx.copyWith(id: Value(id));

    return db.transaction(() async {
      await db.into(db.transactions).insert(companionWithId);
      final createdTx = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

      // Write audit log row in the same transaction
      await db.into(db.auditLog).insert(AuditLogCompanion.insert(
            id: _uuid.v4(),
            entityType: 'transaction',
            entityId: id,
            action: 'insert',
            afterJson: Value(jsonEncode(createdTx.toJson())),
          ));

      return createdTx;
    });
  }

  /// Atomically updates a transaction and logs before/after JSON diff to audit_log.
  Future<Transaction> updateTransactionAtomic(
    String txId,
    TransactionsCompanion updates, {
    String? reason,
  }) async {
    final existing = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingleOrNull();
    if (existing == null) {
      throw const DomainException('ERR_TX_NOT_FOUND', 'تراکنش یافت نشد.');
    }
    if (existing.deletedAt != null) {
      throw const DomainException(DomainErrors.txUndeleteForbidden, 'ویرایش تراکنش حذف‌شده مجاز نیست.');
    }

    await validateTransaction(updates, isUpdate: true);

    return db.transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      final updatedCompanion = updates.copyWith(
        id: Value(txId),
        updatedAt: Value(now),
      );
      await (db.update(db.transactions)..where((t) => t.id.equals(txId))).write(updatedCompanion);

      final updatedTx = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingle();

      await db.into(db.auditLog).insert(AuditLogCompanion.insert(
            id: _uuid.v4(),
            entityType: 'transaction',
            entityId: txId,
            action: 'update',
            beforeJson: Value(jsonEncode(existing.toJson())),
            afterJson: Value(jsonEncode(updatedTx.toJson())),
            reason: Value(reason),
          ));

      return updatedTx;
    });
  }

  /// Atomically soft-deletes a transaction with mandatory reason and logs to audit_log.
  Future<void> softDeleteTransactionAtomic(
    String txId, {
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const DomainException('ERR_DELETE_REASON_REQUIRED', 'ذکر دلیل برای حذف تراکنش الزامی است.');
    }

    final existing = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingleOrNull();
    if (existing == null) {
      throw const DomainException('ERR_TX_NOT_FOUND', 'تراکنش یافت نشد.');
    }
    if (existing.deletedAt != null) {
      throw const DomainException('ERR_ALREADY_DELETED', 'این تراکنش قبلاً حذف شده است.');
    }

    return db.transaction(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      await (db.update(db.transactions)..where((t) => t.id.equals(txId))).write(TransactionsCompanion(
        deletedAt: Value(now),
        deletedReason: Value(reason),
        updatedAt: Value(now),
      ));

      await db.into(db.auditLog).insert(AuditLogCompanion.insert(
            id: _uuid.v4(),
            entityType: 'transaction',
            entityId: txId,
            action: 'soft_delete',
            beforeJson: Value(jsonEncode(existing.toJson())),
            reason: Value(reason),
          ));
    });
  }
}
