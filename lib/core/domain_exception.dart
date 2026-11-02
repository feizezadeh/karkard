/// Domain exceptions and error codes per Section 1 & Section 6 of business_rules_v3.md.
class DomainException implements Exception {
  final String code;
  final String message;

  const DomainException(this.code, this.message);

  @override
  String toString() => 'DomainException($code): $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainException &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

class DomainErrors {
  static const String byWorkRequiresAccrual = 'ERR_BY_WORK_REQUIRES_ACCRUAL';
  static const String shareBpSumNot10000 = 'ERR_SHARE_BP_SUM_NOT_10000';
  static const String distributionForPayoutOnly = 'ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON';
  static const String distributionExceedsShare = 'ERR_DISTRIBUTION_EXCEEDS_SHARE';
  static const String settlePayableExceedsPay = 'ERR_SETTLE_PAYABLE_EXCEEDS_PAY';
  static const String partnerNotParticipating = 'ERR_PARTNER_NOT_PARTICIPATING';
  static const String projectSettingsLocked = 'ERR_PROJECT_SETTINGS_LOCKED';
  static const String projectPersonsLocked = 'ERR_PROJECT_PERSONS_LOCKED';
  static const String projectLockedTx = 'ERR_PROJECT_LOCKED_TX';
  static const String projectLockedReceipts = 'ERR_PROJECT_LOCKED_RECEIPTS';
  static const String transferSameAccount = 'ERR_TRANSFER_SAME_ACCOUNT';
  static const String missingCashAccount = 'ERR_MISSING_CASH_ACCOUNT';
  static const String workInMissingClient = 'ERR_WORK_IN_MISSING_CLIENT';
  static const String incomeMissingClient = 'ERR_INCOME_MISSING_CLIENT';
  static const String workOutMissingPerson = 'ERR_WORK_OUT_MISSING_PERSON';
  static const String workOutPersonNotInProject = 'ERR_WORK_OUT_PERSON_NOT_IN_PROJECT';
  static const String clientKindMismatch = 'ERR_CLIENT_KIND_MISMATCH';
  static const String personalAccountMissingHolder = 'ERR_PERSONAL_ACCOUNT_MISSING_HOLDER';
  static const String payoutPersonNotInProject = 'ERR_PAYOUT_PERSON_NOT_IN_PROJECT';
  static const String cannotDemotePartnerWithTransactions = 'ERR_CANNOT_DEMOTE_PARTNER_WITH_TRANSACTIONS';
  static const String cannotDemotePayoutPartnerWithTx = 'ERR_CANNOT_DEMOTE_PAYOUT_PARTNER_WITH_TX';
  static const String cannotDeletePersonWithTransactions = 'ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS';
  static const String cannotChangePersonKindWithTx = 'ERR_CANNOT_CHANGE_PERSON_KIND_WITH_TX';
  static const String cannotUpdateProjectPersonPkWithTx = 'ERR_CANNOT_UPDATE_PROJECT_PERSON_PK_WITH_TX';
  static const String txUndeleteForbidden = 'ERR_TX_UNDELETE_FORBIDDEN';
  static const String appSettingsKeyImmutable = 'ERR_APP_SETTINGS_KEY_IMMUTABLE';
  static const String unitImmutable = 'ERR_UNIT_IMMUTABLE';
  static const String projectAccountHasHolder = 'ERR_PROJECT_ACCOUNT_HAS_HOLDER';
  static const String workInForbiddenFields = 'ERR_WORK_IN_FORBIDDEN_FIELDS';
  static const String workOutForbiddenFields = 'ERR_WORK_OUT_FORBIDDEN_FIELDS';
  static const String incomeForbiddenFields = 'ERR_INCOME_FORBIDDEN_FIELDS';
  static const String expenseForbiddenFields = 'ERR_EXPENSE_FORBIDDEN_FIELDS';
  static const String payoutForbiddenFields = 'ERR_PAYOUT_FORBIDDEN_FIELDS';
  static const String payoutRequiredFields = 'ERR_PAYOUT_REQUIRED_FIELDS';
  static const String transferForbiddenFields = 'ERR_TRANSFER_FORBIDDEN_FIELDS';
}

/// Thrown when an incompatible pre-release database version is detected.
class LegacyDatabaseException implements Exception {
  final int fromVersion;
  final int toVersion;
  final String message;

  const LegacyDatabaseException({
    required this.fromVersion,
    required this.toVersion,
    this.message = 'دیتابیس متعلق به نسخه آزمایشی قدیمی‌تر است و قابل ارتقای خودکار نیست. لطفاً دیتابیس را بازسازی کنید.',
  });

  @override
  String toString() => 'LegacyDatabaseException(v$fromVersion -> v$toVersion): $message';
}
