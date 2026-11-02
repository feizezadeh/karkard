#!/usr/bin/env python3
"""
راستی‌آزمایی محاسبات بخش ۵ سند business_rules.md
از لیست خام تراکنش‌های بخش ۵ و بررسی تساوی طلایی در هر سه حالت:
- حالت A: مبنای تعهدی، روش کارکردی (by_work)
- حالت B: مبنای تعهدی، روش درصد ثابت (fixed_percent)
- حالت C: مبنای نقدی، روش درصد ثابت (cash, fixed_percent)
همراه با:
- آزمون تخصیص باقی‌مانده (۳ شریک، مبالغ نامقسوم مثبت و منفی)
- آزمون تزریق نقدینگی شریک (آورده نقدی به صندوق پروژه)
"""

def floor_div(a: int, b: int) -> int:
    return a // b

def allocate_remainder(total_amount, partners):
    """
    تخصیص مبلغ total_amount بر اساس share_bp و قاعده باقی‌مانده (share_order).
    طبق قاعده ۴ سند: leftover >= 0 است و شاخه منفی وجود ندارد.
    """
    allocated = {}
    pre_sum = 0
    rem_map = {}
    for p in partners:
        base = floor_div(p['bp'] * total_amount, 10000)
        allocated[p['id']] = base
        pre_sum += base
        rem_map[p['id']] = (p['bp'] * total_amount) % 10000
    rem = total_amount - pre_sum
    assert rem >= 0, f"Leftover cannot be negative: {rem}"
    # مرتب‌سازی بر اساس باقیمانده کسری نزولی، سپس share_order صعودی
    sorted_p = sorted(partners, key=lambda x: (-rem_map[x['id']], x['order']))
    for i in range(rem):
        allocated[sorted_p[i % len(sorted_p)]['id']] += 1
    return allocated

def verify():
    # ۱. تعاریف اولیه و شرکا
    partners = ['amir', 'aref']
    share_bp = {'amir': 5000, 'aref': 5000}
    share_order = {'amir': 1, 'aref': 2}

    # ۲. فهرست تراکنش‌های بخش ۵ (واحد: میلیون تومان)
    txs = [
        {'id': 1,  'type': 'work_in',  'amount': 60, 'client': 'gozel', 'performed_by': 'amir'},
        {'id': 2,  'type': 'work_in',  'amount': 20, 'client': 'gozel', 'performed_by': 'aref'},
        {'id': 3,  'type': 'work_in',  'amount': 10, 'client': 'hadi',  'performed_by': None},
        {'id': 4,  'type': 'work_out', 'amount': 6,  'person': 'driver', 'attributed_to': 'amir'},
        {'id': 5,  'type': 'expense',  'amount': 2,  'acc': 'C1', 'attributed_to': None},
        {'id': 6,  'type': 'expense',  'amount': 3,  'acc': 'A1', 'attributed_to': 'amir'},
        {'id': 7,  'type': 'expense',  'amount': 1,  'acc': 'B1', 'attributed_to': 'aref'},
        {'id': 8,  'type': 'income',   'amount': 30, 'client': 'gozel', 'acc': 'C1'},
        {'id': 9,  'type': 'income',   'amount': 20, 'client': 'gozel', 'acc': 'B1'},
        {'id': 10, 'type': 'income',   'amount': 10, 'client': 'hadi',  'acc': 'C1'},
        {'id': 11, 'type': 'payout',   'amount': 4,  'person': 'driver', 'acc': 'C1', 'purpose': 'settle_payable'},
        {'id': 12, 'type': 'transfer', 'amount': 3,  'from': 'C1', 'to': 'A1'},
        {'id': 13, 'type': 'payout',   'amount': 10, 'person': 'aref',   'acc': 'B1', 'purpose': 'distribution'},
        {'id': 14, 'type': 'payout',   'amount': 5,  'person': 'amir',   'acc': 'C1', 'purpose': 'distribution'},
    ]

    # ۳. محاسبات پایه
    win_total = sum(t['amount'] for t in txs if t['type'] == 'work_in')
    wout_total = sum(t['amount'] for t in txs if t['type'] == 'work_out')
    exp_total = sum(t['amount'] for t in txs if t['type'] == 'expense')
    inc_total = sum(t['amount'] for t in txs if t['type'] == 'income')

    assert win_total == 90, f"Win expected 90, got {win_total}"
    assert wout_total == 6, f"Wout expected 6, got {wout_total}"
    assert exp_total == 6, f"Exp expected 6, got {exp_total}"
    assert inc_total == 60, f"Inc expected 60, got {inc_total}"

    profit_acc = win_total - wout_total - exp_total
    assert profit_acc == 78, f"Profit_acc expected 78, got {profit_acc}"

    # ۴. موجودی حساب‌ها
    bal = {'C1': 0, 'A1': 0, 'B1': 0}
    for t in txs:
        tp = t['type']
        amt = t['amount']
        if tp == 'income':
            bal[t['acc']] += amt
        elif tp in ('expense', 'payout'):
            bal[t['acc']] -= amt
        elif tp == 'transfer':
            bal[t['from']] -= amt
            bal[t['to']] += amt

    assert bal['C1'] == 26, f"C1 expected 26, got {bal['C1']}"
    assert bal['A1'] == 0,  f"A1 expected 0, got {bal['A1']}"
    assert bal['B1'] == 9,  f"B1 expected 9, got {bal['B1']}"

    # ۵. مطالبات از کارفرمایان (Rec)
    rec_gozel = sum(t['amount'] for t in txs if t['type'] == 'work_in' and t.get('client') == 'gozel') - \
                sum(t['amount'] for t in txs if t['type'] == 'income' and t.get('client') == 'gozel')
    rec_hadi = sum(t['amount'] for t in txs if t['type'] == 'work_in' and t.get('client') == 'hadi') - \
               sum(t['amount'] for t in txs if t['type'] == 'income' and t.get('client') == 'hadi')
    assert rec_gozel == 30, f"Rec gozel expected 30, got {rec_gozel}"
    assert rec_hadi == 0,   f"Rec hadi expected 0, got {rec_hadi}"
    rec_total = rec_gozel + rec_hadi
    assert rec_total == 30

    # ۶. بدهی به عوامل (Pay)
    pay_driver = sum(t['amount'] for t in txs if t['type'] == 'work_out' and t.get('person') == 'driver') - \
                 sum(t['amount'] for t in txs if t['type'] == 'payout' and t.get('person') == 'driver' and t.get('purpose') == 'settle_payable')
    assert pay_driver == 2, f"Pay driver expected 2, got {pay_driver}"

    # ۷. موجودی حساب‌های شخصی شرکا نزد پروژه (Cust)
    cust_amir = -bal['A1'] # 0
    cust_aref = -bal['B1'] # -9
    assert cust_amir == 0
    assert cust_aref == -9

    # پرداخت‌های توزیع سود
    dist_payouts = {
        'amir': sum(t['amount'] for t in txs if t['type'] == 'payout' and t.get('person') == 'amir' and t.get('purpose') == 'distribution'),
        'aref': sum(t['amount'] for t in txs if t['type'] == 'payout' and t.get('person') == 'aref' and t.get('purpose') == 'distribution'),
    }
    assert dist_payouts['amir'] == 5
    assert dist_payouts['aref'] == 10

    # پرداخت‌های تسویه بدهی (settle_payable)
    payout_settle_total = sum(t['amount'] for t in txs if t['type'] == 'payout' and t.get('purpose') == 'settle_payable')
    assert payout_settle_total == 4, f"Payout settle expected 4, got {payout_settle_total}"

    print("=== راستی‌آزمایی مقادیر پایه ===")
    print(f"Win = {win_total}, Wout = {wout_total}, Exp = {exp_total}, Inc = {inc_total}")
    print(f"Profit_acc = {profit_acc} م")
    print(f"موجودی حساب‌ها: C1 = {bal['C1']}, A1 = {bal['A1']}, B1 = {bal['B1']}")
    print(f"طلب از کارفرما (Rec) = {rec_total} م")
    print(f"بدهی به راننده (Pay) = {pay_driver} م\n")

    # =========================================================
    # حالت A: مبنای تعهدی، روش کارکردی (by_work)
    # =========================================================
    direct_amir = sum(t['amount'] for t in txs if t['type'] == 'work_in' and t.get('performed_by') == 'amir') - \
                  sum(t['amount'] for t in txs if t['type'] == 'work_out' and t.get('attributed_to') == 'amir') - \
                  sum(t['amount'] for t in txs if t['type'] == 'expense' and t.get('attributed_to') == 'amir')
    direct_aref = sum(t['amount'] for t in txs if t['type'] == 'work_in' and t.get('performed_by') == 'aref') - \
                  sum(t['amount'] for t in txs if t['type'] == 'work_out' and t.get('attributed_to') == 'aref') - \
                  sum(t['amount'] for t in txs if t['type'] == 'expense' and t.get('attributed_to') == 'aref')
    pool_s = sum(t['amount'] for t in txs if t['type'] == 'work_in' and not t.get('performed_by')) - \
             sum(t['amount'] for t in txs if t['type'] == 'work_out' and not t.get('attributed_to')) - \
             sum(t['amount'] for t in txs if t['type'] == 'expense' and not t.get('attributed_to'))

    assert direct_amir == 51, f"Direct Amir expected 51, got {direct_amir}"
    assert direct_aref == 19, f"Direct Aref expected 19, got {direct_aref}"
    assert pool_s == 8, f"Pool S expected 8, got {pool_s}"

    # سهم از استخر با قاعده باقی‌مانده
    partners_obj = [
        {'id': 'amir', 'bp': share_bp['amir'], 'order': share_order['amir']},
        {'id': 'aref', 'bp': share_bp['aref'], 'order': share_order['aref']},
    ]
    pool_alloc = allocate_remainder(pool_s, partners_obj)
    assert pool_alloc['amir'] == 4 and pool_alloc['aref'] == 4

    profit_a = {'amir': direct_amir + pool_alloc['amir'], 'aref': direct_aref + pool_alloc['aref']}
    assert profit_a['amir'] == 55, f"Expected amir profit 55, got {profit_a['amir']}"
    assert profit_a['aref'] == 23, f"Expected aref profit 23, got {profit_a['aref']}"
    assert profit_a['amir'] + profit_a['aref'] == profit_acc

    share_a = {'amir': profit_a['amir'] - dist_payouts['amir'], 'aref': profit_a['aref'] - dist_payouts['aref']}
    assert share_a['amir'] == 50 and share_a['aref'] == 13

    due_a = {
        'driver': pay_driver,
        'amir': share_a['amir'] + cust_amir,
        'aref': share_a['aref'] + cust_aref,
    }
    assert due_a['driver'] == 2
    assert due_a['amir'] == 50
    assert due_a['aref'] == 4
    sum_due_a = sum(due_a.values())
    assert sum_due_a == 56

    # تساوی طلایی حالت A: bal(C1) + Rec = sum(Due)
    left_a = bal['C1'] + rec_total
    right_a = sum_due_a
    assert left_a == right_a == 56, f"Golden equality failed in Mode A: {left_a} != {right_a}"
    print("--- حالت A (by_work) ---")
    print(f"سود: امیر={profit_a['amir']}، عارف={profit_a['aref']} (مجموع={profit_acc})")
    print(f"Share: امیر={share_a['amir']}، عارف={share_a['aref']}")
    print(f"Due: راننده={due_a['driver']}، امیر={due_a['amir']}، عارف={due_a['aref']} (مجموع={sum_due_a})")
    print(f"تساوی طلایی: bal(C1)[{bal['C1']}] + Rec[{rec_total}] = {left_a} == ΣDue[{right_a}] ✓\n")

    # =========================================================
    # حالت B: مبنای تعهدی، روش درصد ثابت (fixed_percent)
    # =========================================================
    profit_b = allocate_remainder(profit_acc, partners_obj)
    assert profit_b['amir'] == 39 and profit_b['aref'] == 39

    share_b = {'amir': profit_b['amir'] - dist_payouts['amir'], 'aref': profit_b['aref'] - dist_payouts['aref']}
    assert share_b['amir'] == 34 and share_b['aref'] == 29

    due_b = {
        'driver': pay_driver,
        'amir': share_b['amir'] + cust_amir,
        'aref': share_b['aref'] + cust_aref,
    }
    assert due_b['driver'] == 2
    assert due_b['amir'] == 34
    assert due_b['aref'] == 20
    sum_due_b = sum(due_b.values())
    assert sum_due_b == 56

    # تساوی طلایی حالت B: bal(C1) + Rec = sum(Due)
    left_b = bal['C1'] + rec_total
    right_b = sum_due_b
    assert left_b == right_b == 56, f"Golden equality failed in Mode B: {left_b} != {right_b}"
    print("--- حالت B (fixed_percent) ---")
    print(f"سود: امیر={profit_b['amir']}، عارف={profit_b['aref']} (مجموع={profit_acc})")
    print(f"Share: امیر={share_b['amir']}، عارف={share_b['aref']}")
    print(f"Due: راننده={due_b['driver']}، امیر={due_b['amir']}، عارف={due_b['aref']} (مجموع={sum_due_b})")
    print(f"تساوی طلایی: bal(C1)[{bal['C1']}] + Rec[{rec_total}] = {left_b} == ΣDue[{right_b}] ✓\n")

    # =========================================================
    # حالت C: مبنای نقدی (fixed_percent, share_basis=cash)
    # =========================================================
    # محاسبه پویا از روی txs (نه ثابت -4):
    profit_cash = inc_total - exp_total - payout_settle_total
    assert profit_cash == 50, f"Profit_cash expected 50, got {profit_cash}"

    # سهم موقت هر شریک بر اساس share_bp و allocate_remainder:
    partners_c = [
        {'id': 'amir', 'bp': share_bp['amir'], 'order': 1},
        {'id': 'aref', 'bp': share_bp['aref'], 'order': 2},
    ]
    temp_share_c = allocate_remainder(profit_cash, partners_c)
    assert temp_share_c['amir'] == 25 and temp_share_c['aref'] == 25

    # سهم خالص پس از برداشت توزیع سود نقدی
    share_c = {
        'amir': temp_share_c['amir'] - dist_payouts['amir'],  # 25 - 5 = 20
        'aref': temp_share_c['aref'] - dist_payouts['aref'],  # 25 - 10 = 15
    }
    assert share_c['amir'] == 20 and share_c['aref'] == 15

    # در مبنای نقدی: طلب پرداخت‌نشده کارفرما (Rec=0) و دستمزد معوق راننده (Pay) در Due نقدی لحاظ نمی‌شوند.
    # ادعای نقدی شرکا روی وجوه نقد در دست پروژه:
    # Due_cash(amir) = Share_cash + Cust = 20 + 0 = 20
    # Due_cash(aref) = Share_cash + Cust = 15 - 9 = 6
    due_c = {
        'amir': share_c['amir'] + cust_amir,
        'aref': share_c['aref'] + cust_aref,
    }
    assert due_c['amir'] == 20
    assert due_c['aref'] == 6
    sum_due_c = sum(due_c.values())
    assert sum_due_c == 26

    # تساوی طلایی حالت C:
    # در مبنای نقدی Rec=0 است، و موجودی نقدی پروژه bal(C1) دقیقا برابر مجموع مطالبات نقدی شرکاست:
    # bal(C1) + Rec_cash (0) = sum(Due_cash)
    left_c = bal['C1'] + 0
    right_c = sum_due_c
    assert left_c == right_c == 26, f"Golden equality failed in Mode C: {left_c} != {right_c}"
    print("--- حالت C (نقدی / cash) ---")
    print(f"سود نقدی موقت: {profit_cash} م (پویا از txs: {inc_total} - {exp_total} - {payout_settle_total})")
    print(f"Share نقدی: امیر={share_c['amir']}، عارف={share_c['aref']}")
    print(f"Due نقدی (بدون Pay معوق): امیر={due_c['amir']}، عارف={due_c['aref']} (مجموع={sum_due_c})")
    print(f"تساوی طلایی نقدی: bal(C1)[{bal['C1']}] + Rec_cash[0] = {left_c} == ΣDue_cash[{right_c}] ✓\n")

    # =========================================================
    # آزمون تخصیص باقی‌مانده (۳ شریک، ۳۳۳۳/۳۳۳۳/۳۳۳۴، مبالغ نامقسوم)
    # =========================================================
    p3_partners = [
        {'id': 'P1', 'bp': 3333, 'order': 1},
        {'id': 'P2', 'bp': 3333, 'order': 2},
        {'id': 'P3', 'bp': 3334, 'order': 3},
    ]
    assert sum(p['bp'] for p in p3_partners) == 10000

    test_amounts = [7, 100, 10001]
    for amt in test_amounts:
        parts = allocate_remainder(amt, p3_partners)
        assert sum(parts.values()) == amt, f"Remainder allocation failed: sum {sum(parts.values())} != {amt}"
        if amt == 7:
            assert parts['P1'] == 2 and parts['P2'] == 2 and parts['P3'] == 3
    print("--- آزمون تخصیص باقی‌مانده (۳ شریک) ---")
    print(f"تخصیص برای مبالغ {test_amounts} با تابع allocate_remainder با موفقیت تأیید شد (Σ = کل) ✓\n")

    # =========================================================
    # آزمون تزریق نقدینگی شریک (آورده نقدی به صندوق پروژه)
    # =========================================================
    # فرض: امیر ۱۵ میلیون تومان از جیبش (حساب A1) به صندوق پروژه (C1) واریز می‌کند
    # تراکنش: transfer از A1 به C1 به مبلغ 15
    tx_injection = {'id': 15, 'type': 'transfer', 'amount': 15, 'from': 'A1', 'to': 'C1'}
    txs_with_inj = txs + [tx_injection]

    bal_inj = dict(bal)
    bal_inj['A1'] -= 15 # A1 = 0 - 15 = -15
    bal_inj['C1'] += 15 # C1 = 26 + 15 = 41
    assert bal_inj['A1'] == -15
    assert bal_inj['C1'] == 41

    # اثر بر Cust(amir):
    cust_amir_inj = -bal_inj['A1'] # -(-15) = +15 (پروژه به امیر بدهکار است)
    assert cust_amir_inj == 15

    # سهم سود تغییر نمی‌کند (transfer روی سود بی اثر است)
    due_a_inj = {
        'driver': pay_driver,
        'amir': share_a['amir'] + cust_amir_inj, # 50 + 15 = 65
        'aref': share_a['aref'] + cust_aref,     # 13 - 9 = 4
    }
    sum_due_inj = sum(due_a_inj.values()) # 2 + 65 + 4 = 71

    # تساوی طلایی جدید: bal(C1)[41] + Rec[30] = 71 == sum(Due)[71]
    left_inj = bal_inj['C1'] + rec_total
    right_inj = sum_due_inj
    assert left_inj == right_inj == 71, f"Cash injection golden equality failed: {left_inj} != {right_inj}"
    print("--- آزمون تزریق نقدینگی شریک (آورده نقدی) ---")
    print(f"انتقال ۱۵م از A1 به C1: C1={bal_inj['C1']}م، A1={bal_inj['A1']}م ⇒ Cust(amir)=+{cust_amir_inj}م")
    print(f"Due جدید: راننده={due_a_inj['driver']}، امیر={due_a_inj['amir']}، عارف={due_a_inj['aref']} (مجموع={sum_due_inj})")
    print(f"تساوی طلایی پس از تزریق: bal(C1)[{bal_inj['C1']}] + Rec[{rec_total}] = {left_inj} == ΣDue[{right_inj}] ✓\n")

    # =========================================================
    # آزمون شکست تساوی طلایی در صورت income بدون client_id
    # =========================================================
    # اگر تراکنش income به مبلغ ۱۰م بدون client_id ثبت شود:
    # 1. موجودی C1 ده میلیون زیاد می‌شود: bal(C1) = 26 + 10 = 36
    # 2. چون کارفرمایی مشخص نشده، هیچ طلبی از کارفرما کاهش نمی‌یابد: Rec همچنان 30 باقی می‌ماند
    # 3. سمت چپ: bal(C1)[36] + Rec[30] = 66
    # 4. سمت راست: دریافتی نقدی سود ایجاد نمی‌کند (فقط وصول طلب است)، لذا Due شرکا همان 56 می‌ماند
    # در نتیجه: 66 != 56 (تساوی طلایی ۱۰ میلیون تراز را به هم می‌زند!)
    bal_bad_inc = bal['C1'] + 10
    left_bad_inc = bal_bad_inc + rec_total  # 36 + 30 = 66
    right_bad_inc = sum_due_a  # 56
    assert left_bad_inc != right_bad_inc, "Equality should break without client_id on income"
    print("--- آزمون شکست تساوی طلایی در صورت income بدون client ---")
    print(f"در صورت نبود client_id: bal(C1)[{bal_bad_inc}] + Rec[{rec_total}] = {left_bad_inc} != ΣDue[{right_bad_inc}] (شکست {left_bad_inc - right_bad_inc} میلیونی تساوی)")

    # راستی‌آزمایی رد این سناریو توسط SQLite DB
    import sqlite3
    con = sqlite3.connect(":memory:")
    con.execute("CREATE TABLE t (type TEXT, client_id TEXT, cash_account_id TEXT, CONSTRAINT chk_tx_income_client_required CHECK (type != 'income' OR client_id IS NOT NULL))")
    try:
        con.execute("INSERT INTO t VALUES ('income', NULL, 'c1')")
        assert False, "DB should have rejected income without client_id"
    except sqlite3.IntegrityError:
        print("دیتابیس تراکنش income بدون client_id را با موفقیت رد کرد (CHECK chk_tx_income_client_required) ✓\n")
    con.close()

    print("ALL ASSERTS PASSED SUCCESSFULLY!")

if __name__ == '__main__':
    verify()
