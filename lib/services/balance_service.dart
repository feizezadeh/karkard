import 'package:drift/drift.dart';

import '../core/domain_exception.dart';
import '../core/money.dart';
import '../data/database.dart';

/// Financial statement for a single person in a project.
class PersonBalance {
  final String personId;
  final int pay; // Pay(p): wage payable (positive) or advance prepayment (negative)
  final int share; // Share(p): claimable profit share
  final int custody; // Cust(p): project funds custody (positive=project owes person, negative=person holds money)
  final int due; // Due(p) = Pay + Share + Cust

  const PersonBalance({
    required this.personId,
    required this.pay,
    required this.share,
    required this.custody,
    required this.due,
  });
}

/// Detailed profit allocation breakdown for a partner.
class PartnerProfitAllocation {
  final String personId;
  final int directProfit; // work_in(performed) - work_out(attr) - exp(attr)
  final int poolShare; // share of shared pool
  final int totalProfit; // direct + poolShare
  final int distributionPayouts; // sum of payout(distribution)
  final int claimableShare; // totalProfit - distributionPayouts

  const PartnerProfitAllocation({
    required this.personId,
    required this.directProfit,
    required this.poolShare,
    required this.totalProfit,
    required this.distributionPayouts,
    required this.claimableShare,
  });
}

/// Comprehensive project financial balance report.
class ProjectBalanceReport {
  final String projectId;
  final String reportBasis; // accrual | cash | both
  final String shareBasis; // accrual | cash
  final String shareMethod; // fixed_percent | by_work

  final int win; // sum work_in
  final int wout; // sum work_out
  final int exp; // sum expense
  final int inc; // sum income
  final int ps; // sum payout(settle_payable)
  final int pd; // sum payout(distribution)

  final int profitAccrual; // Win - Wout - Exp
  final int profitCash; // Inc - Exp - Ps

  final Map<String, int> projectAccountBalances; // accountId -> balance
  final Map<String, int> personalAccountBalances; // accountId -> balance
  final int totalProjectAccountsBalance;

  final Map<String, int> receivables; // clientId -> Rec(c)
  final int totalReceivables;

  final Map<String, int> payables; // personId -> Pay(p)
  final int totalPayables;

  final Map<String, int> custodies; // personId -> Cust(p)
  final int totalCustody;

  final Map<String, PartnerProfitAllocation> partnerAllocations;
  final Map<String, PersonBalance> personBalances;
  final int totalDue;

  final bool isGoldenEquationBalanced; // bal(project) + Rec == Due
  final String? startDateIso;
  final String? endDateIso;

  const ProjectBalanceReport({
    required this.projectId,
    required this.reportBasis,
    required this.shareBasis,
    required this.shareMethod,
    required this.win,
    required this.wout,
    required this.exp,
    required this.inc,
    required this.ps,
    required this.pd,
    required this.profitAccrual,
    required this.profitCash,
    required this.projectAccountBalances,
    required this.personalAccountBalances,
    required this.totalProjectAccountsBalance,
    required this.receivables,
    required this.totalReceivables,
    required this.payables,
    required this.totalPayables,
    required this.custodies,
    required this.totalCustody,
    required this.partnerAllocations,
    required this.personBalances,
    required this.totalDue,
    required this.isGoldenEquationBalanced,
    this.startDateIso,
    this.endDateIso,
  });
}

class PartnerShareItem {
  final String personId;
  final int shareBp;
  final int shareOrder;

  const PartnerShareItem({
    required this.personId,
    required this.shareBp,
    required this.shareOrder,
  });
}

/// BalanceService: Financial calculation engine for «دفتر کارکرد» (Business Rules v3).
class BalanceService {
  final AppDatabase db;

  BalanceService(this.db);

  /// Distributes an integer amount [amount] (positive, zero, or negative)
  /// among [partners] according to their [shareBp] using the Largest Remainder Method
  /// (Hamilton-Hare method) with [shareOrder] tie-breaking.
  ///
  /// Guarantees:
  /// 1. Exactly integer amounts (no floats).
  /// 2. Sum of allocated amounts == [amount] exactly.
  static Map<String, int> allocateRemainder(int amount, List<PartnerShareItem> partners) {
    if (partners.isEmpty) return {};
    if (amount == 0) {
      return {for (final p in partners) p.personId: 0};
    }

    final parts = <String, int>{};
    final remainders = <String, int>{};
    var sumParts = 0;

    for (final p in partners) {
      // part_i = floor(share_bp_i * amount / 10000) using integer floorDiv
      final product = p.shareBp * amount;
      final part = floorDiv(product, 10000);
      parts[p.personId] = part;
      sumParts += part;
      // rem_i = product - part * 10000 (always >= 0 and < 10000)
      remainders[p.personId] = product - part * 10000;
    }

    var leftover = amount - sumParts; // 0 <= leftover < partners.length

    // Sort partners descending by rem_i; tie-break ascending by shareOrder
    final sorted = List<PartnerShareItem>.from(partners)
      ..sort((a, b) {
        final cmpRem = (remainders[b.personId] ?? 0).compareTo(remainders[a.personId] ?? 0);
        if (cmpRem != 0) return cmpRem;
        return a.shareOrder.compareTo(b.shareOrder);
      });

    for (var i = 0; i < leftover && i < sorted.length; i++) {
      final pid = sorted[i].personId;
      parts[pid] = (parts[pid] ?? 0) + 1;
    }

    return parts;
  }

  /// Calculates the complete balance report for [projectId], optionally
  /// filtered to a specific date range ([startDateIso] and [endDateIso] in YYYY-MM-DD).
  Future<ProjectBalanceReport> calculateProjectBalance(
    String projectId, {
    String? startDateIso,
    String? endDateIso,
  }) async {
    // 1. Fetch project settings
    final settingsRow = await (db.select(db.projectSettings)
          ..where((s) => s.projectId.equals(projectId)))
        .getSingleOrNull();
    final reportBasis = settingsRow?.reportBasis ?? 'accrual';
    final shareBasis = settingsRow?.shareBasis ?? 'accrual';
    final shareMethod = settingsRow?.shareMethod ?? 'fixed_percent';

    // 2. Fetch project persons
    final ppRows = await (db.select(db.projectPersons)
          ..where((pp) => pp.projectId.equals(projectId)))
        .get();

    final participatingPartners = ppRows
        .where((pp) => pp.settlementMode == 'profit_share' || pp.settlementMode == 'both')
        .map((pp) => PartnerShareItem(
              personId: pp.personId,
              shareBp: pp.shareBp ?? 0,
              shareOrder: pp.shareOrder,
            ))
        .toList();

    // 3. Fetch active cash accounts
    final allCashAccounts = await db.select(db.cashAccounts).get();
    final cashAccountKindMap = {for (final a in allCashAccounts) a.id: a.kind};
    final personalAccountHolderMap = {
      for (final a in allCashAccounts)
        if (a.kind == 'personal' && a.holderPersonId != null) a.id: a.holderPersonId!
    };

    // 4. Fetch all active (non-deleted) transactions for this project, with optional date filtering
    final txQuery = db.select(db.transactions)
      ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull());
    if (startDateIso != null) {
      txQuery.where((t) => t.date.isBiggerOrEqualValue(startDateIso));
    }
    if (endDateIso != null) {
      txQuery.where((t) => t.date.isSmallerOrEqualValue(endDateIso));
    }
    final txRows = await txQuery.get();

    // 5. Compute base sums
    var win = 0;
    var wout = 0;
    var exp = 0;
    var inc = 0;
    var ps = 0;
    var pd = 0;

    final accountBalances = <String, int>{for (final a in allCashAccounts) a.id: 0};
    final receivables = <String, int>{};
    final payables = <String, int>{};
    final directProfits = <String, int>{for (final p in participatingPartners) p.personId: 0};
    final partnerDistributions = <String, int>{for (final p in participatingPartners) p.personId: 0};

    var winShared = 0;
    var woutShared = 0;
    var expShared = 0;

    for (final tx in txRows) {
      final amt = tx.amount;
      switch (tx.type) {
        case 'work_in':
          win += amt;
          if (tx.clientId != null) {
            receivables[tx.clientId!] = (receivables[tx.clientId!] ?? 0) + amt;
          }
          if (tx.performedBy != null) {
            directProfits[tx.performedBy!] = (directProfits[tx.performedBy!] ?? 0) + amt;
          } else {
            winShared += amt;
          }
          break;

        case 'work_out':
          wout += amt;
          if (tx.personId != null) {
            payables[tx.personId!] = (payables[tx.personId!] ?? 0) + amt;
          }
          if (tx.attributedTo != null) {
            directProfits[tx.attributedTo!] = (directProfits[tx.attributedTo!] ?? 0) - amt;
          } else {
            woutShared += amt;
          }
          break;

        case 'income':
          inc += amt;
          if (tx.cashAccountId != null) {
            accountBalances[tx.cashAccountId!] = (accountBalances[tx.cashAccountId!] ?? 0) + amt;
          }
          if (tx.clientId != null) {
            receivables[tx.clientId!] = (receivables[tx.clientId!] ?? 0) - amt;
          }
          break;

        case 'expense':
          exp += amt;
          if (tx.cashAccountId != null) {
            accountBalances[tx.cashAccountId!] = (accountBalances[tx.cashAccountId!] ?? 0) - amt;
          }
          if (tx.attributedTo != null) {
            directProfits[tx.attributedTo!] = (directProfits[tx.attributedTo!] ?? 0) - amt;
          } else {
            expShared += amt;
          }
          break;

        case 'payout':
          if (tx.cashAccountId != null) {
            accountBalances[tx.cashAccountId!] = (accountBalances[tx.cashAccountId!] ?? 0) - amt;
          }
          if (tx.purpose == 'settle_payable') {
            ps += amt;
            if (tx.personId != null) {
              payables[tx.personId!] = (payables[tx.personId!] ?? 0) - amt;
            }
          } else if (tx.purpose == 'distribution') {
            pd += amt;
            if (tx.personId != null) {
              partnerDistributions[tx.personId!] =
                  (partnerDistributions[tx.personId!] ?? 0) + amt;
            }
          }
          break;

        case 'transfer':
          if (tx.fromAccountId != null) {
            accountBalances[tx.fromAccountId!] =
                (accountBalances[tx.fromAccountId!] ?? 0) - amt;
          }
          if (tx.toAccountId != null) {
            accountBalances[tx.toAccountId!] =
                (accountBalances[tx.toAccountId!] ?? 0) + amt;
          }
          break;
      }
    }

    final profitAcc = win - wout - exp;
    final profitCash = inc - exp - ps;

    // 6. Profit distribution per partner
    final partnerAllocations = <String, PartnerProfitAllocation>{};
    if (shareBasis == 'cash') {
      // Cash basis (only fixed_percent permitted)
      final poolShares = allocateRemainder(profitCash, participatingPartners);
      for (final p in participatingPartners) {
        final totalProfit = poolShares[p.personId] ?? 0;
        final dist = partnerDistributions[p.personId] ?? 0;
        partnerAllocations[p.personId] = PartnerProfitAllocation(
          personId: p.personId,
          directProfit: 0,
          poolShare: totalProfit,
          totalProfit: totalProfit,
          distributionPayouts: dist,
          claimableShare: totalProfit - dist,
        );
      }
    } else {
      // Accrual basis
      if (shareMethod == 'by_work') {
        final poolAmount = winShared - woutShared - expShared;
        final poolShares = allocateRemainder(poolAmount, participatingPartners);
        for (final p in participatingPartners) {
          final direct = directProfits[p.personId] ?? 0;
          final pool = poolShares[p.personId] ?? 0;
          final total = direct + pool;
          final dist = partnerDistributions[p.personId] ?? 0;
          partnerAllocations[p.personId] = PartnerProfitAllocation(
            personId: p.personId,
            directProfit: direct,
            poolShare: pool,
            totalProfit: total,
            distributionPayouts: dist,
            claimableShare: total - dist,
          );
        }
      } else {
        // fixed_percent
        final shares = allocateRemainder(profitAcc, participatingPartners);
        for (final p in participatingPartners) {
          final total = shares[p.personId] ?? 0;
          final dist = partnerDistributions[p.personId] ?? 0;
          partnerAllocations[p.personId] = PartnerProfitAllocation(
            personId: p.personId,
            directProfit: 0,
            poolShare: total,
            totalProfit: total,
            distributionPayouts: dist,
            claimableShare: total - dist,
          );
        }
      }
    }

    // 7. Custody calculation: Cust(p) = - bal(personal_account_held_by_p)
    final custodies = <String, int>{};
    for (final entry in personalAccountHolderMap.entries) {
      final accId = entry.key;
      final holderId = entry.value;
      final bal = accountBalances[accId] ?? 0;
      custodies[holderId] = (custodies[holderId] ?? 0) - bal;
    }

    // 8. PersonBalance calculation: Due(p) = Pay(p) + Share(p) + Cust(p)
    final allInvolvedPersons = <String>{
      ...ppRows.map((pp) => pp.personId),
      ...payables.keys,
      ...custodies.keys,
    };

    final personBalances = <String, PersonBalance>{};
    var totalDue = 0;

    for (final pid in allInvolvedPersons) {
      final pay = payables[pid] ?? 0;
      final share = partnerAllocations[pid]?.claimableShare ?? 0;
      final custody = custodies[pid] ?? 0;
      final due = (shareBasis == 'cash') ? (share + custody) : (pay + share + custody);
      personBalances[pid] = PersonBalance(
        personId: pid,
        pay: pay,
        share: share,
        custody: custody,
        due: due,
      );
      totalDue += due;
    }

    // 9. Accounts categorized
    final projectAccountBalances = <String, int>{};
    final personalAccountBalances = <String, int>{};
    var totalProjectAccountsBal = 0;

    for (final entry in accountBalances.entries) {
      final aid = entry.key;
      final bal = entry.value;
      if (cashAccountKindMap[aid] == 'project') {
        projectAccountBalances[aid] = bal;
        totalProjectAccountsBal += bal;
      } else {
        personalAccountBalances[aid] = bal;
      }
    }

    final totalRec = receivables.values.fold(0, (a, b) => a + b);
    final totalPay = payables.values.fold(0, (a, b) => a + b);
    final totalCust = custodies.values.fold(0, (a, b) => a + b);

    // 10. Golden equation verification: bal(project) + Rec == Due
    final isBalanced = (totalProjectAccountsBal + totalRec) == totalDue;

    return ProjectBalanceReport(
      projectId: projectId,
      reportBasis: reportBasis,
      shareBasis: shareBasis,
      shareMethod: shareMethod,
      win: win,
      wout: wout,
      exp: exp,
      inc: inc,
      ps: ps,
      pd: pd,
      profitAccrual: profitAcc,
      profitCash: profitCash,
      projectAccountBalances: projectAccountBalances,
      personalAccountBalances: personalAccountBalances,
      totalProjectAccountsBalance: totalProjectAccountsBal,
      receivables: receivables,
      totalReceivables: totalRec,
      payables: payables,
      totalPayables: totalPay,
      custodies: custodies,
      totalCustody: totalCust,
      partnerAllocations: partnerAllocations,
      personBalances: personBalances,
      totalDue: totalDue,
      isGoldenEquationBalanced: isBalanced,
      startDateIso: startDateIso,
      endDateIso: endDateIso,
    );
  }

  /// Validates business-level payout ceilings before inserting a transaction into the DB.
  /// Throws [DomainException] if limits are exceeded without [overrideReason].
  Future<void> validateTransactionForInsert(TransactionsCompanion tx) async {
    final type = tx.type.value;
    if (type != 'payout') return;

    final purpose = tx.purpose.value;
    final personId = tx.personId.value;
    final projectId = tx.projectId.value;
    final amount = tx.amount.value;
    final override = tx.overrideReason.value;

    final hasOverride = override != null && override.trim().isNotEmpty;
    if (hasOverride) return;

    if (personId == null) return;

    final report = await calculateProjectBalance(projectId);

    if (purpose == 'distribution') {
      final claimable = report.partnerAllocations[personId]?.claimableShare ?? 0;
      if (amount > claimable) {
        throw DomainException(
          DomainErrors.distributionExceedsShare,
          'مبلغ برداشت از سود ($amount تومان) بیش از سهم قابل‌مطالبه ($claimable تومان) است. ثبت این تراکنش نیازمند ذکر دلیل در override_reason است.',
        );
      }
    } else if (purpose == 'settle_payable') {
      final payable = report.payables[personId] ?? 0;
      if (amount > payable) {
        throw DomainException(
          DomainErrors.settlePayableExceedsPay,
          'مبلغ تسویه دستمزد ($amount تومان) بیش از مانده بدهی دستمزد ($payable تومان) است. ثبت این تراکنش نیازمند ذکر دلیل در override_reason است.',
        );
      }
    }
  }

  /// Inserts a transaction after performing domain-level balance limit validations.
  Future<int> insertTransaction(TransactionsCompanion tx) async {
    await validateTransactionForInsert(tx);
    return db.into(db.transactions).insert(tx);
  }
}
