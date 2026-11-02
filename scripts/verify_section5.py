#!/usr/bin/env python3
"""
راستی‌آزمایی محاسبات بخش ۵ سند business_rules.md
از لیست خام تراکنش‌های بخش ۵ و بررسی تساوی طلایی در هر سه حالت:
- حالت A: مبنای تعهدی، روش کارکردی (by_work)
- حالت B: مبنای تعهدی، روش درصد ثابت (fixed_percent)
- حالت C: مبنای نقدی، روش درصد ثابت (cash, fixed_percent)
"""

def floor_div(a: int, b: int) -> int:
    return a // b

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
    pool_amir = floor_div(share_bp['amir'] * pool_s, 10000)
    pool_aref = floor_div(share_bp['aref'] * pool_s, 10000)
    rem_s = pool_s - (pool_amir + pool_aref)
    if rem_s > 0:
        pool_amir += 1
    assert pool_amir == 4 and pool_aref == 4

    profit_a = {'amir': direct_amir + pool_amir, 'aref': direct_aref + pool_aref}
    assert profit_a['amir'] == 55 and profit_a['aref'] == 23
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
    profit_b = {
        'amir': floor_div(share_bp['amir'] * profit_acc, 10000),
        'aref': floor_div(share_bp['aref'] * profit_acc, 10000),
    }
    rem_b = profit_acc - (profit_b['amir'] + profit_b['aref'])
    if rem_b > 0:
        profit_b['amir'] += 1
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
    # در مبنای نقدی: فقط درآمدها و هزینه‌های نقدی واقع‌شده لحاظ می‌شوند
    # Profit_cash = Inc - Exp - Payout(settle_payable) = 60 - 6 - 4 = 50 م
    profit_cash = inc_total - exp_total - 4
    assert profit_cash == 50, f"Profit_cash expected 50, got {profit_cash}"

    # سهم موقت هر شریک: 25 م
    temp_share_c = {
        'amir': floor_div(share_bp['amir'] * profit_cash, 10000),
        'aref': floor_div(share_bp['aref'] * profit_cash, 10000),
    }
    assert temp_share_c['amir'] == 25 and temp_share_c['aref'] == 25

    # سهم خالص پس از برداشت توزیع سود نقدی
    share_c = {
        'amir': temp_share_c['amir'] - dist_payouts['amir'],  # 25 - 5 = 20
        'aref': temp_share_c['aref'] - dist_payouts['aref'],  # 25 - 10 = 15
    }
    assert share_c['amir'] == 20 and share_c['aref'] == 15

    # در مبنای نقدی، طلب تحقق‌نیافته از کارفرما (Rec=0) و بدهی پرداخت‌نشده دستمزد (Pay=0) در سود نقدی نیست.
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
    print(f"سود نقدی موقت: {profit_cash} م (امیر={temp_share_c['amir']}، عارف={temp_share_c['aref']})")
    print(f"Share نقدی: امیر={share_c['amir']}، عارف={share_c['aref']}")
    print(f"Due نقدی: امیر={due_c['amir']}، عارف={due_c['aref']} (مجموع={sum_due_c})")
    print(f"تساوی طلایی نقدی: bal(C1)[{bal['C1']}] + Rec_cash[0] = {left_c} == ΣDue_cash[{right_c}] ✓\n")

    print("ALL ASSERTS PASSED SUCCESSFULLY!")

if __name__ == '__main__':
    verify()
