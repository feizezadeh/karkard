#!/usr/bin/env python3
"""
راستی‌آزمایی حساب نقدی مشترک بین دو پروژه (Shared Cash Account)
آزمون جامع با الزامات تکمیلی:
۱. دو شریک در پروژه: امیر (۶۰٪ = 6000 بیپی) و عارف (۴۰٪ = 4000 بیپی)
۲. وجود حساب نقدی شخصی (Amir_Pocket با kind='personal' و holder_person_id='amir')
۳. سناریوی موجودی منفی پروژه‌ای در حساب مشترک:
   - در پروژه P2 هزینه‌ها/پرداخت‌ها بیش از درآمد است (bal(Bank, P2) < 0)
   - موجودی فیزیکی کل بانک به دلیل مازاد P1 مثبت باقی می‌ماند
۴. آزمون برقراری تساوی طلایی در تک‌تک پروژه‌ها:
   Σ bal(حساب‌های پروژه) + Σ Rec == Σ Due(تمام اشخاص: شرکا + کارگران + امانت شریک)
۵. تراز فیزیکی کل حساب‌های سیستم
"""

def floor_div(a: int, b: int) -> int:
    return a // b

def allocate_remainder(total_amount: int, partners: list) -> dict:
    """تخصیص سهم با روش بزرگ‌ترین باقیمانده و شکستن تساوی با share_order"""
    assert sum(p['share_bp'] for p in partners) == 10000, "Sum of share_bp must be 10000"
    sorted_partners = sorted(partners, key=lambda p: p['share_order'])
    allocations = {}
    remainders = []
    allocated_sum = 0
    for p in sorted_partners:
        prod = total_amount * p['share_bp']
        exact_share = floor_div(prod, 10000)
        rem = prod % 10000
        allocations[p['id']] = exact_share
        remainders.append((rem, p['share_order'], p['id']))
        allocated_sum += exact_share

    leftover = total_amount - allocated_sum
    if leftover > 0:
        remainders.sort(key=lambda x: (-x[0], x[1]))
        for i in range(leftover):
            p_id = remainders[i % len(remainders)][2]
            allocations[p_id] += 1
    elif leftover < 0:
        remainders.sort(key=lambda x: (x[0], -x[1]))
        for i in range(-leftover):
            p_id = remainders[i % len(remainders)][2]
            allocations[p_id] -= 1

    return allocations

def verify_shared_account():
    # ۱. شرکای پروژه
    partners = [
        {'id': 'amir', 'share_bp': 6000, 'share_order': 1},
        {'id': 'aref', 'share_bp': 4000, 'share_order': 2},
    ]

    # ۲. تراکنش‌های دو پروژه روی حساب مشترک Bank_Mellat و حساب شخصی Amir_Pocket
    txs = [
        # ===== پروژه ۱ (P1) =====
        # کارکرد کارفرما: 100 میلیون
        {'id': 1, 'project': 'P1', 'type': 'work_in', 'amount': 100, 'client': 'C_A', 'performed_by': 'amir'},
        # دریافت نقدی از کارفرما به بانک مشترک: 80 میلیون
        {'id': 2, 'project': 'P1', 'type': 'income', 'amount': 80, 'client': 'C_A', 'acc': 'Bank_Mellat'},
        # کارکرد راننده ۱: 20 میلیون
        {'id': 3, 'project': 'P1', 'type': 'work_out', 'amount': 20, 'person': 'W_1'},
        # تسویه علی‌الحساب راننده ۱ از بانک مشترک: 15 میلیون
        {'id': 4, 'project': 'P1', 'type': 'payout', 'amount': 15, 'person': 'W_1', 'acc': 'Bank_Mellat', 'purpose': 'settle_payable'},
        # هزینه کارگاه از جیب امیر (حساب شخصی): 5 میلیون -> ایجاد تعهد Custody به امیر در P1
        {'id': 5, 'project': 'P1', 'type': 'expense', 'amount': 5, 'acc': 'Amir_Pocket'},

        # ===== پروژه ۲ (P2) - با موجودی منفی پروژه‌ای و واریز به حساب شخصی شریک =====
        # کارکرد کارفرما: 50 میلیون
        {'id': 6, 'project': 'P2', 'type': 'work_in', 'amount': 50, 'client': 'C_B', 'performed_by': 'aref'},
        # دریافت نقدی از کارفرما به بانک مشترک: 20 میلیون
        {'id': 7, 'project': 'P2', 'type': 'income', 'amount': 20, 'client': 'C_B', 'acc': 'Bank_Mellat'},
        # دریافت نقدی از کارفرما مستقیم به حساب شخصی عارف (Aref_Pocket): 12 میلیون
        # در نتیجه مانده حساب شخصی عارف مثبت می‌شود (+12) و Cust = -12 < 0 خواهد شد.
        {'id': 8, 'project': 'P2', 'type': 'income', 'amount': 12, 'client': 'C_B', 'acc': 'Aref_Pocket'},
        # کارکرد راننده ۲: 30 میلیون
        {'id': 9, 'project': 'P2', 'type': 'work_out', 'amount': 30, 'person': 'W_2'},
        # پرداخت به راننده ۲ از بانک مشترک: 25 میلیون
        {'id': 10, 'project': 'P2', 'type': 'payout', 'amount': 25, 'person': 'W_2', 'acc': 'Bank_Mellat', 'purpose': 'settle_payable'},
        # هزینه جاری از بانک مشترک: 10 میلیون
        {'id': 11, 'project': 'P2', 'type': 'expense', 'amount': 10, 'acc': 'Bank_Mellat'},
    ]

    for p_id in ['P1', 'P2']:
        p_txs = [t for t in txs if t['project'] == p_id]

        # موجودی Bank_Mellat در این پروژه (kind='project')
        bal_bank = sum(t['amount'] for t in p_txs if t['type'] == 'income' and t.get('acc') == 'Bank_Mellat') - \
                   sum(t['amount'] for t in p_txs if t['type'] in ('expense', 'payout') and t.get('acc') == 'Bank_Mellat')

        # موجودی حساب‌های شخصی در این پروژه (kind='personal')
        bal_amir_pocket = sum(t['amount'] for t in p_txs if t['type'] == 'income' and t.get('acc') == 'Amir_Pocket') - \
                          sum(t['amount'] for t in p_txs if t['type'] in ('expense', 'payout') and t.get('acc') == 'Amir_Pocket')

        bal_aref_pocket = sum(t['amount'] for t in p_txs if t['type'] == 'income' and t.get('acc') == 'Aref_Pocket') - \
                          sum(t['amount'] for t in p_txs if t['type'] in ('expense', 'payout') and t.get('acc') == 'Aref_Pocket')

        # موجودی حساب‌های با kind='project' در این پروژه:
        bal_project_cash = bal_bank

        # مطالبات از کارفرما (Rec)
        rec = sum(t['amount'] for t in p_txs if t['type'] == 'work_in') - \
              sum(t['amount'] for t in p_txs if t['type'] == 'income')

        # بدهی به کارگران (Pay)
        worker_id = 'W_1' if p_id == 'P1' else 'W_2'
        pay_worker = sum(t['amount'] for t in p_txs if t['type'] == 'work_out' and t.get('person') == worker_id) - \
                     sum(t['amount'] for t in p_txs if t['type'] == 'payout' and t.get('person') == worker_id and t.get('purpose') == 'settle_payable')

        # تعهد امانت شخصی شرکا (Custody):
        # طبق قاعده صریح: Cust = -bal(personal) به صورت نامشروط (بدون شرط علامت if bal < 0)
        # اگر شخص از جیب هزینه کند: bal < 0 => Cust > 0 (پروژه بدهکار شریک است)
        # اگر پول پروژه به حساب شخصی واریز شود: bal > 0 => Cust < 0 (شریک بدهکار پروژه است و طلبش کم می‌شود)
        cust_amir = -bal_amir_pocket
        cust_aref = -bal_aref_pocket

        # سود تعهدی پروژه
        win = sum(t['amount'] for t in p_txs if t['type'] == 'work_in')
        wout = sum(t['amount'] for t in p_txs if t['type'] == 'work_out')
        exp = sum(t['amount'] for t in p_txs if t['type'] == 'expense')
        profit = win - wout - exp

        # تسهیم سود تعهدی بین دو شریک بر اساس share_bp
        shares = allocate_remainder(profit, partners)
        share_amir = shares['amir']
        share_aref = shares['aref']

        # مطالبات شرکا (Due)
        due_amir = share_amir + cust_amir
        due_aref = share_aref + cust_aref

        # مجموع مطالبات اشخاص (Due)
        total_due = pay_worker + due_amir + due_aref

        # تساوی طلایی: Σ bal(حساب‌های kind='project') + Rec == Σ Due
        assert bal_project_cash + rec == total_due, f"Golden equality failed for {p_id}: {bal_project_cash} + {rec} != {total_due}"

        print(f"=== پروژه {p_id} ===")
        print(f"موجودی Bank_Mellat در این پروژه = {bal_bank} میلیون")
        if p_id == 'P2':
            assert bal_bank < 0, "P2 bank balance must be negative!"
            assert bal_aref_pocket > 0, "P2 Aref pocket must be positive!"
            assert cust_aref < 0, "P2 Aref custody must be negative!"
            print(f"  * توجه: موجودی پروژه در حساب مشترک منفی است ({bal_bank} میلیون).")
            print(f"  * حساب شخصی Aref_Pocket دارای مانده مثبت ({bal_aref_pocket}م) و Custody منفی ({cust_aref}م) است.")
        print(f"موجودی حساب‌های شخصی: Amir_Pocket={bal_amir_pocket}م (Cust={cust_amir}), Aref_Pocket={bal_aref_pocket}م (Cust={cust_aref})")
        print(f"طلب از کارفرما (Rec) = {rec} میلیون")
        print(f"بدهی کارگر (Pay) = {pay_worker} میلیون")
        print(f"سود پروژه = {profit} م (سهم امیر={share_amir}، سهم عارف={share_aref})")
        print(f"Due اشخاص: کارگر={pay_worker}، امیر={due_amir}، عارف={due_aref} | مجموع Due={total_due}")
        print(f"تساوی طلایی: bal({bal_project_cash}) + Rec({rec}) = {bal_project_cash + rec} == ΣDue({total_due}) ✓\n")

    # تراز فیزیکی بانک مشترک در کل شرکت
    total_bank_inc = sum(t['amount'] for t in txs if t['type'] == 'income' and t.get('acc') == 'Bank_Mellat')
    total_bank_out = sum(t['amount'] for t in txs if t['type'] in ('expense', 'payout') and t.get('acc') == 'Bank_Mellat')
    physical_bank = total_bank_inc - total_bank_out

    bal_p1_bank = (80 - 15)      # +65
    bal_p2_bank = (20 - 25 - 10) # -15 (منفی!)
    assert physical_bank == bal_p1_bank + bal_p2_bank == 50, "Physical bank balance mismatch"

    print("=== تراز فیزیکی حساب بانکی مشترک ===")
    print(f"کل واریز به بانک: {total_bank_inc} | کل برداشت از بانک: {total_bank_out}")
    print(f"موجودی فیزیکی کل بانک = {physical_bank} میلیون == bal(P1)[{bal_p1_bank}] + bal(P2)[{bal_p2_bank}] ✓")
    print("تست حساب مشترک با موفقیت همه الزامات را اثبات کرد.\n")

if __name__ == '__main__':
    verify_shared_account()
