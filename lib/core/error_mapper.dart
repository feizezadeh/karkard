import 'domain_exception.dart';

/// Maps raw SqliteException / DB constraint violations to DomainException
/// code-by-code according to Section 6 & 7 of business_rules_v3.md.
/// Unknown errors are rethrown.
DomainException mapSqliteException(Object error) {
  final msg = error.toString();

  if (msg.contains('ERR_BY_WORK_REQUIRES_ACCRUAL') ||
      msg.contains('chk_ps_by_work_requires_accrual') ||
      msg.contains("share_method != 'by_work' OR share_basis = 'accrual'")) {
    return const DomainException(
      DomainErrors.byWorkRequiresAccrual,
      'by_work is only permitted with share_basis=accrual',
    );
  }

  if (msg.contains('ERR_SHARE_BP_SUM_NOT_10000') ||
      msg.contains('trg_tx_check_distribution_share_bp')) {
    return const DomainException(
      DomainErrors.shareBpSumNot10000,
      'sum of share_bp for participating partners must be 10000',
    );
  }

  if (msg.contains('ERR_DISTRIBUTION_FOR_PAYOUT_ONLY_PERSON') ||
      msg.contains('trg_tx_check_distribution_mode')) {
    return const DomainException(
      DomainErrors.distributionForPayoutOnly,
      'distribution is forbidden for payout_only person or person not in project_persons',
    );
  }

  if (msg.contains('ERR_PAYOUT_PERSON_NOT_IN_PROJECT') ||
      msg.contains('trg_tx_check_payout_person_in_project_persons')) {
    return const DomainException(
      DomainErrors.payoutPersonNotInProject,
      'payout is forbidden: person is not registered in project_persons',
    );
  }

  if (msg.contains('ERR_WORK_OUT_PERSON_NOT_IN_PROJECT') ||
      msg.contains('trg_tx_check_work_out_person')) {
    return const DomainException(
      DomainErrors.workOutPersonNotInProject,
      'work_out person must be registered in project_persons with payout_only or both',
    );
  }

  if (msg.contains('ERR_PARTNER_NOT_PARTICIPATING') ||
      msg.contains('trg_tx_check_partner_participating')) {
    return const DomainException(
      DomainErrors.partnerNotParticipating,
      'performed_by and attributed_to must be a participating partner in project_persons',
    );
  }

  if (msg.contains('ERR_PROJECT_LOCKED_TX') ||
      msg.contains('trg_tx_no_insert_locked') ||
      msg.contains('trg_tx_no_update_locked') ||
      msg.contains('project is locked: cannot insert transaction') ||
      msg.contains('project is locked: cannot update transaction')) {
    return const DomainException(
      DomainErrors.projectLockedTx,
      'project is locked: transaction mutations forbidden',
    );
  }

  if (msg.contains('ERR_PROJECT_LOCKED_RECEIPTS') ||
      msg.contains('trg_receipts_no_insert_locked') ||
      msg.contains('trg_receipts_no_delete_locked') ||
      msg.contains('locked project') && msg.contains('receipt')) {
    return const DomainException(
      DomainErrors.projectLockedReceipts,
      'project is locked: receipt mutations forbidden',
    );
  }

  if (msg.contains('ERR_PROJECT_SETTINGS_LOCKED') ||
      msg.contains('trg_project_settings_lock')) {
    return const DomainException(
      DomainErrors.projectSettingsLocked,
      'project settings are locked after first distribution or project lock',
    );
  }

  if (msg.contains('ERR_PROJECT_PERSONS_LOCKED') ||
      msg.contains('trg_project_persons_lock')) {
    return const DomainException(
      DomainErrors.projectPersonsLocked,
      'project persons are locked after first distribution or project lock',
    );
  }

  if (msg.contains('ERR_CANNOT_DEMOTE_PARTNER_WITH_TRANSACTIONS') ||
      msg.contains('trg_project_persons_no_demote_with_tx')) {
    return const DomainException(
      DomainErrors.cannotDemotePartnerWithTransactions,
      'cannot change settlement_mode to payout_only when transactions reference this partner',
    );
  }

  if (msg.contains('ERR_CANNOT_DEMOTE_PAYOUT_PARTNER_WITH_TX') ||
      msg.contains('trg_project_persons_no_demote_payout_with_tx')) {
    return const DomainException(
      DomainErrors.cannotDemotePayoutPartnerWithTx,
      'cannot change settlement_mode to profit_share when active work_out or settle_payable payout transactions reference this person',
    );
  }

  if (msg.contains('ERR_CANNOT_UPDATE_PROJECT_PERSON_PK_WITH_TX') ||
      msg.contains('trg_project_persons_no_update_pk_with_tx')) {
    return const DomainException(
      DomainErrors.cannotUpdateProjectPersonPkWithTx,
      'cannot change project_id or person_id of project_person when active transactions reference this person',
    );
  }

  if (msg.contains('ERR_CANNOT_DELETE_PERSON_WITH_TRANSACTIONS') ||
      msg.contains('trg_project_persons_no_delete_with_tx')) {
    return const DomainException(
      DomainErrors.cannotDeletePersonWithTransactions,
      'cannot delete person from project_persons while active transactions reference this person',
    );
  }

  if (msg.contains('ERR_TX_UNDELETE_FORBIDDEN') ||
      msg.contains('trg_tx_no_undelete')) {
    return const DomainException(
      DomainErrors.txUndeleteForbidden,
      'undeleting a soft-deleted transaction is forbidden',
    );
  }

  if (msg.contains('ERR_APP_SETTINGS_KEY_IMMUTABLE') ||
      msg.contains('trg_app_settings_no_update_key')) {
    return const DomainException(
      DomainErrors.appSettingsKeyImmutable,
      'app_settings key cannot be updated',
    );
  }

  if (msg.contains('ERR_UNIT_IMMUTABLE') ||
      msg.contains('trg_app_settings_unit') ||
      msg.contains('chk_app_settings_unit')) {
    return const DomainException(
      DomainErrors.unitImmutable,
      'app_settings.unit is immutable and must be toman',
    );
  }

  if (msg.contains('chk_tx_transfer_accounts_required') ||
      msg.contains('ERR_TRANSFER_SAME_ACCOUNT') ||
      msg.contains('from_account_id != to_account_id')) {
    return const DomainException(
      DomainErrors.transferSameAccount,
      'transfer from and to accounts must be distinct and non-null',
    );
  }

  if (msg.contains('chk_tx_income_forbidden_fields')) {
    return const DomainException(
      DomainErrors.incomeForbiddenFields,
      'income has forbidden fields (person_id, accounts, purpose, etc.)',
    );
  }

  if (msg.contains('chk_tx_expense_forbidden_fields')) {
    return const DomainException(
      DomainErrors.expenseForbiddenFields,
      'expense has forbidden fields (client_id, person_id, purpose, etc.)',
    );
  }

  if (msg.contains('chk_tx_payout_forbidden_fields')) {
    return const DomainException(
      DomainErrors.payoutForbiddenFields,
      'payout has forbidden fields (client_id, performed_by, attributed_to, accounts)',
    );
  }

  if (msg.contains('chk_tx_payout_required_fields')) {
    return const DomainException(
      DomainErrors.payoutRequiredFields,
      'payout requires person_id, cash_account_id, and purpose',
    );
  }

  if (msg.contains('chk_tx_work_in_forbidden_fields')) {
    return const DomainException(
      DomainErrors.workInForbiddenFields,
      'work_in has forbidden fields',
    );
  }

  if (msg.contains('chk_tx_work_out_forbidden_fields')) {
    return const DomainException(
      DomainErrors.workOutForbiddenFields,
      'work_out has forbidden fields',
    );
  }

  if (msg.contains('chk_tx_transfer_forbidden_fields')) {
    return const DomainException(
      DomainErrors.transferForbiddenFields,
      'transfer has forbidden fields',
    );
  }

  if (msg.contains('chk_tx_income_account_required') ||
      msg.contains('chk_tx_expense_account_required') ||
      msg.contains('ERR_MISSING_CASH_ACCOUNT') ||
      msg.contains('cash_account_id IS NOT NULL')) {
    return const DomainException(
      DomainErrors.missingCashAccount,
      'transaction requires cash_account_id',
    );
  }

  if (msg.contains('chk_tx_income_client_required') ||
      msg.contains('ERR_INCOME_MISSING_CLIENT')) {
    return const DomainException(
      DomainErrors.incomeMissingClient,
      'income requires client_id',
    );
  }

  if (msg.contains('chk_tx_work_in_client_required') ||
      msg.contains('ERR_WORK_IN_MISSING_CLIENT') ||
      msg.contains('client_id IS NOT NULL')) {
    return const DomainException(
      DomainErrors.workInMissingClient,
      'work_in requires client_id',
    );
  }

  if (msg.contains('chk_tx_work_out_person_required') ||
      msg.contains('ERR_WORK_OUT_MISSING_PERSON')) {
    return const DomainException(
      DomainErrors.workOutMissingPerson,
      'work_out requires person_id',
    );
  }

  if (msg.contains('ERR_CLIENT_KIND_MISMATCH') ||
      msg.contains('trg_tx_check_client_kind') ||
      msg.contains('client_id must have kind=client')) {
    return const DomainException(
      DomainErrors.clientKindMismatch,
      'client_id must have kind=client',
    );
  }

  if (msg.contains('chk_cash_account_holder_required') ||
      msg.contains('ERR_PERSONAL_ACCOUNT_MISSING_HOLDER') ||
      msg.contains('holder_person_id IS NOT NULL')) {
    return const DomainException(
      DomainErrors.personalAccountMissingHolder,
      'personal cash account requires holder_person_id',
    );
  }

  if (msg.contains('chk_cash_account_project_holder_null') ||
      msg.contains('ERR_PROJECT_ACCOUNT_HAS_HOLDER')) {
    return const DomainException(
      DomainErrors.projectAccountHasHolder,
      'project cash account cannot have a holder_person_id',
    );
  }

  if (msg.contains('ERR_CANNOT_CHANGE_PERSON_KIND_WITH_TX') ||
      msg.contains('trg_persons_no_update_kind_with_tx')) {
    return const DomainException(
      DomainErrors.cannotChangePersonKindWithTx,
      'cannot change kind of person referenced by active transactions',
    );
  }

  // Unknown errors are rethrown
  throw error;
}
