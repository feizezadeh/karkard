// ============================================================================
// Karkard Frontend Application (Tauri v2 + Standalone Mock Fallback)
// Matches 100% of Flutter features, screens, Iranian accounting rules & YAGNI
// ============================================================================

// ----------------------------------------------------------------------------
// Dynamic IPC Invocation (Tauri v2 / v1 with Mock Fallback)
// Automatically maps snake_case to camelCase for Tauri command arguments
// ----------------------------------------------------------------------------
function toTauriArgs(args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) return args;
  const res = {};
  for (const [k, v] of Object.entries(args)) {
    const camel = k.replace(/_([a-z0-9])/g, (_, ch) => ch.toUpperCase());
    res[camel] = v;
    if (camel !== k) {
      res[k] = v;
    }
  }
  return res;
}

async function invoke(cmd, args = {}) {
  let tauriInvoke = null;
  if (typeof window !== 'undefined') {
    if (window.__TAURI_INTERNALS__ && typeof window.__TAURI_INTERNALS__.invoke === 'function') {
      tauriInvoke = window.__TAURI_INTERNALS__.invoke;
    } else if (window.__TAURI__ && window.__TAURI__.core && typeof window.__TAURI__.core.invoke === 'function') {
      tauriInvoke = window.__TAURI__.core.invoke;
    } else if (window.__TAURI__ && typeof window.__TAURI__.invoke === 'function') {
      tauriInvoke = window.__TAURI__.invoke;
    }
  }

  if (tauriInvoke) {
    try {
      const preparedArgs = toTauriArgs(args);
      return await tauriInvoke(cmd, preparedArgs);
    } catch (err) {
      console.error(`[Tauri IPC Error] ${cmd}:`, err);
      throw err;
    }
  }

  // Native Android Bridge via libkarkard.so
  if (typeof window !== 'undefined' && window.AndroidBridge && typeof window.AndroidBridge.invoke === 'function') {
    try {
      const preparedArgs = toTauriArgs(args);
      if (typeof window.AndroidBridge.getInternalFilesDir === 'function') {
        preparedArgs.dbPath = window.AndroidBridge.getInternalFilesDir() + '/karkard.db';
      }
      const resRaw = window.AndroidBridge.invoke(cmd, JSON.stringify(preparedArgs));
      if (resRaw) {
        const parsed = JSON.parse(resRaw);
        if (parsed && parsed.error) {
          console.error(`[Android Native Error] ${cmd}:`, parsed.error);
          throw new Error(parsed.error);
        }
        return parsed;
      }
    } catch (err) {
      console.warn(`[Android Bridge call] ${cmd}:`, err);
      // fallback to mock if unhandled
    }
  }

  console.log(`[Dev Mock Invoke] ${cmd}`, args);
  return mockInvoke(cmd, args);
}

// ----------------------------------------------------------------------------
// Mock Store (for standalone browser preview)
// ----------------------------------------------------------------------------
const mockState = {
  activeProjectId: 'proj-1',
  projects: [
    { id: 'proj-1', name: 'پروژه کارکرد جرثقیل آذرمی (مهر ۱۴۰۵)', start_date: '2026-09-23', end_date: '2026-10-22', status: 'open' },
    { id: 'proj-0', name: 'پروژه جرثقیل شهریور ۱۴۰۵', start_date: '2026-08-23', end_date: '2026-09-22', status: 'locked' },
  ],
  persons: [
    { id: 'p1', name: 'امیر', kind: 'partner', code: 'PRT-01', note: 'شریک سرمایه‌گذار', is_active: true },
    { id: 'p2', name: 'عارف', kind: 'partner', code: 'PRT-02', note: 'شریک اجرایی', is_active: true },
    { id: 'p3', name: 'راننده جرثقیل', kind: 'driver', code: 'DRV-01', note: 'راننده دکل بلند', is_active: true },
    { id: 'p4', name: 'کارفرما گوزل', kind: 'client', code: 'CLT-01', note: 'پروژه پل روگذر', is_active: true },
    { id: 'p5', name: 'کارگاه مکانیکی بهرام', kind: 'worker', code: 'WRK-01', note: 'سرویس‌کار هیدرولیک', is_active: true },
  ],
  cashAccounts: [
    { id: 'c1', name: 'صندوق کارگاه', kind: 'project', holder_person_id: null },
    { id: 'a1', name: 'جیب امیر', kind: 'personal', holder_person_id: 'p1' },
    { id: 'b1', name: 'حساب بانکی عارف', kind: 'personal', holder_person_id: 'p2' },
  ],
  transactions: [
    {
      id: 'tx-1',
      project_id: 'proj-1',
      tx_type: 'work_in',
      amount: 90000000,
      date: '1405/07/01',
      description: 'کارکرد چرثقیل در پروژه گوزل',
      client_id: 'p4',
      person_id: null,
      cash_account_id: null,
      from_account_id: null,
      to_account_id: null,
      purpose: null,
      override_reason: null,
    },
    {
      id: 'tx-2',
      project_id: 'proj-1',
      tx_type: 'income',
      amount: 60000000,
      date: '1405/07/04',
      description: 'دریافت پیش‌پرداخت نقدی از گوزل',
      client_id: 'p4',
      person_id: null,
      cash_account_id: 'c1',
      from_account_id: null,
      to_account_id: null,
      purpose: null,
      override_reason: null,
    },
    {
      id: 'tx-3',
      project_id: 'proj-1',
      tx_type: 'work_out',
      amount: 6000000,
      date: '1405/07/05',
      description: 'کارکرد و انعام راننده',
      client_id: null,
      person_id: 'p3',
      cash_account_id: null,
      from_account_id: null,
      to_account_id: null,
      purpose: null,
      override_reason: null,
    },
    {
      id: 'tx-4',
      project_id: 'proj-1',
      tx_type: 'payout',
      amount: 4000000,
      date: '1405/07/08',
      description: 'تسویه دستمزد راننده',
      client_id: null,
      person_id: 'p3',
      cash_account_id: 'c1',
      from_account_id: null,
      to_account_id: null,
      purpose: 'settle_payable',
      override_reason: null,
    },
    {
      id: 'tx-5',
      project_id: 'proj-1',
      tx_type: 'expense',
      amount: 6000000,
      date: '1405/07/10',
      description: 'گازوئیل و تعویض روغن جرثقیل',
      client_id: null,
      person_id: null,
      cash_account_id: 'c1',
      from_account_id: null,
      to_account_id: null,
      purpose: null,
      override_reason: null,
    },
  ],
  backups: [
    {
      file_path: './backups/karkard_backup_20261107_140000.db',
      file_name: 'karkard_backup_20261107_140000.db',
      file_size: 49152,
      created_at: '2026-11-07T14:00:00Z',
      sha256: '4a6b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b',
    },
  ],
};

async function mockInvoke(cmd, args) {
  switch (cmd) {
    case 'list_projects':
      return [...mockState.projects];
    case 'create_project': {
      const p = {
        id: 'proj-' + Date.now(),
        name: args.name,
        start_date: args.start_date || null,
        end_date: args.end_date || null,
        status: 'open',
      };
      mockState.projects.push(p);
      return p;
    }
    case 'lock_project': {
      const p = mockState.projects.find(x => x.id === args.project_id);
      if (p) p.status = 'locked';
      return null;
    }
    case 'rollover_project_cmd': {
      const newP = {
        id: 'proj-' + Date.now(),
        name: args.target_name,
        start_date: args.start_date || null,
        end_date: null,
        status: 'open',
      };
      mockState.projects.push(newP);
      if (args.lock_source) {
        const src = mockState.projects.find(x => x.id === args.source_project_id);
        if (src) src.status = 'locked';
      }
      return newP;
    }
    case 'list_persons':
      return args.active_only ? mockState.persons.filter(p => p.is_active) : [...mockState.persons];
    case 'create_person': {
      const per = {
        id: 'person-' + Date.now(),
        name: args.name,
        kind: args.kind,
        code: args.code || null,
        note: args.note || null,
        is_active: true,
      };
      mockState.persons.push(per);
      return per;
    }
    case 'list_cash_accounts':
      return [...mockState.cashAccounts];
    case 'create_cash_account': {
      const acc = {
        id: 'acc-' + Date.now(),
        name: args.name,
        kind: args.kind,
        code: args.code || null,
        holder_person_id: args.holder_person_id || null,
      };
      mockState.cashAccounts.push(acc);
      return acc;
    }
    case 'list_transactions':
      return [...mockState.transactions];
    case 'create_transaction': {
      const tx = { id: 'tx-' + Date.now(), ...args.tx };
      mockState.transactions.unshift(tx);
      return tx;
    }
    case 'soft_delete_transaction':
      mockState.transactions = mockState.transactions.filter(t => t.id !== (args.tx_id || args.txId));
      return null;
    case 'get_project_balance':
      return {
        project_id: args.project_id,
        win: 90000000,
        wout: 6000000,
        exp: 6000000,
        inc: 60000000,
        ps: 4000000,
        pd: 15000000,
        profit_accrual: 78000000,
        profit_cash: 50000000,
        total_project_accounts_balance: 26000000,
        total_receivables: 30000000,
        total_due: 56000000,
        is_golden_equation_balanced: true,
        partner_allocations: {
          p1: { person_id: 'p1', total_profit: 55000000, claimable_share: 50000000, distribution_payouts: 5000000 },
          p2: { person_id: 'p2', total_profit: 23000000, claimable_share: 13000000, distribution_payouts: 10000000 },
        },
        person_balances: {
          p1: { person_id: 'p1', pay: 0, share: 50000000, custody: 0, due: 50000000 },
          p2: { person_id: 'p2', pay: 0, share: 13000000, custody: -9000000, due: 4000000 },
          p3: { person_id: 'p3', pay: 2000000, share: 0, custody: 0, due: 2000000 },
        },
        receivables: { p4: 30000000 },
      };
    case 'create_backup_cmd': {
      const b = {
        file_path: `./backups/karkard_backup_${Date.now()}.db`,
        file_name: `karkard_backup_${Date.now()}.db`,
        created_at: new Date().toISOString(),
        sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        file_size: 51200,
      };
      mockState.backups.unshift(b);
      return b;
    }
    case 'list_backups_cmd':
      return [...mockState.backups];
    case 'inspect_excel_cmd':
      return [
        { name: 'کارکرد مهرماه', row_count: 32, col_count: 8 },
        { name: 'هزینه‌ها', row_count: 14, col_count: 5 },
      ];
    case 'preview_excel_import_cmd':
      return {
        headers: ['ردیف', 'تاریخ', 'شرح کارکرد و محل', 'ساعت کار', 'مبلغ کارکرد', 'نام کارفرما'],
        sample_rows: [
          ['۱', '۱۴۰۵/۰۷/۰۱', 'کارکرد جرثقیل در پروژه پل روگذر', '۸', '۹۰٬۰۰۰٬۰۰۰', 'کارفرما گوزل'],
          ['۲', '۱۴۰۵/۰۷/۰۴', 'تخلیه بار اسکلت فلزی کارگاه', '۶', '۶۰٬۰۰۰٬۰۰۰', 'کارفرما گوزل'],
          ['۳', '۱۴۰۵/۰۷/۰۵', 'بارگیری تیرچه و قطعات سنگین', '۱۰', '۴۵٬۰۰۰٬۰۰۰', 'کارفرما گوزل'],
        ],
        detected_mapping: {
          date_col: 1,
          desc_col: 2,
          amount_col: 4,
          party_col: 5,
          type_col: null,
          account_col: null,
          partner_col: null,
          has_header: true,
        },
        total_rows: 32,
        valid_rows: 32,
        invalid_rows: 0,
        duplicate_rows: 0,
        warnings: [],
      };
    case 'commit_excel_import_cmd': {
      const newTx = {
        id: 'tx-import-' + Date.now(),
        project_id: args.projectId || 'proj-1',
        tx_type: 'work_in',
        amount: 90000000,
        date: '1405/07/01',
        description: 'کارکرد چرثقیل در پروژه گوزل (وارد شده از اکسل)',
        client_id: 'p4',
        person_id: null,
        cash_account_id: null,
        from_account_id: null,
        to_account_id: null,
        purpose: null,
        override_reason: null,
      };
      mockState.transactions.unshift(newTx);
      return {
        total_rows_processed: 32,
        rows_imported: 32,
        duplicates_skipped: 0,
        invalid_skipped: 0,
        total_imported_amount: 195000000,
        new_parties_created: 1,
        new_accounts_created: 0,
      };
    }
    case 'jalali_to_iso_val':
      return `${args.y}-${String(args.m).padStart(2, '0')}-${String(args.d).padStart(2, '0')}`;
    case 'iso_to_jalali_val':
      return '۱۴۰۵/۰۸/۱۷';
    default:
      return null;
  }
}

// ----------------------------------------------------------------------------
// Persian Digits & Money Helpers
// ----------------------------------------------------------------------------
const FA_DIGITS = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
const AR_DIGITS = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

function toFaDigits(str) {
  if (str == null) return '';
  return String(str).replace(/\d/g, d => FA_DIGITS[parseInt(d, 10)]);
}

function normalizeDigits(str) {
  if (!str) return '';
  let res = String(str);
  for (let i = 0; i < 10; i++) {
    res = res.replaceAll(FA_DIGITS[i], i).replaceAll(AR_DIGITS[i], i);
  }
  return res;
}

function formatToman(amount, persianDigits = true) {
  if (amount == null) return '۰ تومان';
  const neg = amount < 0;
  const absStr = Math.abs(amount).toString();
  let parts = '';
  const len = absStr.length;
  for (let i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 === 0) parts += '٬';
    parts += absStr[i];
  }
  const out = (neg ? '-' : '') + parts + ' تومان';
  return persianDigits ? toFaDigits(out) : out;
}

function parseTomanInput(val) {
  const norm = normalizeDigits(val);
  const clean = norm.replace(/[,٬،\s]/g, '');
  const n = parseInt(clean, 10);
  return isNaN(n) ? 0 : n;
}

function formatDisplayDate(dateStr) {
  if (!dateStr) return '-';
  const clean = String(dateStr).trim();
  if (clean.includes('/')) return toFaDigits(clean);
  try {
    const d = new Date(clean + 'T12:00:00Z');
    if (isNaN(d.getTime())) return toFaDigits(clean);
    return new Intl.DateTimeFormat('fa-IR', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
  } catch {
    return toFaDigits(clean);
  }
}

// ----------------------------------------------------------------------------
// State Variables
// ----------------------------------------------------------------------------
let currentProjectId = null;
let currentProject = null;
let currentBalance = null;
let allProjects = [];
let personsCache = [];
let cashAccountsCache = [];
let allTransactions = [];
let currentPersonFilter = 'all';
let currentReportDateFilter = { preset: 'all', startIso: null, endIso: null, label: 'کل دوره مالی' };

// ----------------------------------------------------------------------------
// Tab Switching
// ----------------------------------------------------------------------------
window.switchTab = function(tabName) {
  // Desktop header tabs
  document.querySelectorAll('.nav-tab').forEach(t => {
    if (t.dataset.tab === tabName) {
      t.classList.add('border-blue-600', 'text-blue-600');
      t.classList.remove('border-transparent', 'text-gray-500');
    } else {
      t.classList.remove('border-blue-600', 'text-blue-600');
      t.classList.add('border-transparent', 'text-gray-500');
    }
  });

  // Mobile bottom navigation buttons
  document.querySelectorAll('.mobile-nav-btn').forEach(b => {
    if (b.dataset.tab === tabName) {
      b.classList.add('text-blue-600');
      b.classList.remove('text-gray-500');
    } else {
      b.classList.remove('text-blue-600');
      b.classList.add('text-gray-500');
    }
  });

  document.querySelectorAll('.tab-pane').forEach(p => p.classList.add('hidden'));
  const activePane = document.getElementById(`tab-${tabName}`);
  if (activePane) activePane.classList.remove('hidden');

  // Toggle Mobile FAB
  const fab = document.getElementById('mobileFabNewTx');
  if (fab) {
    if (tabName === 'dashboard' || tabName === 'transactions') {
      fab.classList.remove('hidden');
    } else {
      fab.classList.add('hidden');
    }
  }

  // Scroll to top smoothly
  window.scrollTo({ top: 0, behavior: 'smooth' });

  if (tabName === 'fiscal') {
    window.renderFiscalYearsTab();
  } else if (tabName === 'accounts') {
    window.renderAccountsTab();
  } else if (tabName === 'settings') {
    loadBackupsList();
    window.loadProjectSettingsAndShares();
  } else if (tabName === 'persons') {
    renderPersonsTable();
  }
};

function setupTabs() {
  const tabs = document.querySelectorAll('.nav-tab');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      window.switchTab(tab.dataset.tab);
    });
  });
}

// ----------------------------------------------------------------------------
// Modal Controllers
// ----------------------------------------------------------------------------
window.openModal = function(id) {
  const el = document.getElementById(id);
  if (el) el.classList.remove('hidden');
};

window.closeModal = function(id) {
  const el = document.getElementById(id);
  if (el) el.classList.add('hidden');
};

window.openAboutModal = function() {
  window.openModal('modalAbout');
};

window.openNewTxModal = function() {
  if (!currentProjectId) {
    alert('لطفاً ابتدا یک پروژه انتخاب کنید.');
    return;
  }
  if (currentProject && currentProject.status === 'locked') {
    alert('پروژه جاری قفل است؛ امکان ثبت تراکنش جدید در دوره بسته شده وجود ندارد.');
    return;
  }

  populateSelect('txInputClient', personsCache.filter(p => p.kind === 'client'));
  populateSelect('txInputPerson', personsCache.filter(p => p.kind !== 'client'));
  populateSelect('txInputCashAccount', cashAccountsCache);
  populateSelect('txInputFromAccount', cashAccountsCache);
  populateSelect('txInputToAccount', cashAccountsCache);

  document.getElementById('txInputDate').value = '۱۴۰۵/۰۸/۱۷';
  document.getElementById('txInputAmount').value = '';
  document.getElementById('txInputDesc').value = '';
  document.getElementById('txInputType').value = 'work_in';

  window.updateDynamicFields();
  window.openModal('modalNewTx');
};

window.openNewProjectModal = function() {
  document.getElementById('projInputName').value = '';
  document.getElementById('projInputStartDate').value = '';
  document.getElementById('projInputEndDate').value = '';
  window.openModal('modalNewProject');
};

window.openManageProjectsModal = function() {
  renderManageProjectsList();
  window.openModal('modalManageProjects');
};

window.openNewPersonModal = function() {
  document.getElementById('personInputName').value = '';
  document.getElementById('personInputKind').value = 'client';
  document.getElementById('personInputCode').value = '';
  document.getElementById('personInputNote').value = '';
  window.openModal('modalNewPerson');
};

window.openAccountsModal = function() {
  window.switchTab('accounts');
};

window.openExcelModal = function() {
  const pathInput = document.getElementById('excelFilePath');
  if (!pathInput.value) {
    pathInput.value = '/home/mehdi/karkard/دفتر_کارکرد_جرثقیل_آذرمی_آماده_ورود.xlsx';
  }
  const displayEl = document.getElementById('excelSelectedFileDisplay');
  if (displayEl) displayEl.textContent = pathInput.value;
  setExcelWizardStep(1);
  window.openModal('modalExcel');
  if (pathInput.value.trim()) {
    window.handleInspectExcel();
  }
};

window.handleBrowseExcelFile = function() {
  // 1. Android Native Bridge: open Android system file chooser
  if (typeof window !== 'undefined' && window.AndroidBridge && typeof window.AndroidBridge.pickExcelFile === 'function') {
    window.AndroidBridge.pickExcelFile();
    return;
  }

  // 2. Desktop Tauri: open native rfd file dialog
  if (window.__TAURI__ || window.__TAURI_INTERNALS__) {
    invoke('pick_excel_file_cmd').then(selected => {
      if (selected) {
        document.getElementById('excelFilePath').value = selected;
        const displayEl = document.getElementById('excelSelectedFileDisplay');
        if (displayEl) displayEl.textContent = selected;
        window.handleInspectExcel();
      }
    }).catch(err => {
      console.warn('Tauri picker error, falling back to input:', err);
      triggerFileInput();
    });
    return;
  }

  // 3. Fallback: trigger hidden HTML file input
  triggerFileInput();
};

function triggerFileInput() {
  const fileInput = document.getElementById('excelFileInput');
  if (fileInput) {
    fileInput.value = '';
    fileInput.click();
  }
}

// Callback invoked by Android MainActivity when file is picked
window.onAndroidFileSelected = async function(safePath, displayName) {
  console.log('File selected from Android system:', safePath, displayName);
  const pathInput = document.getElementById('excelFilePath');
  if (pathInput) pathInput.value = safePath;
  const displayEl = document.getElementById('excelSelectedFileDisplay');
  if (displayEl) displayEl.textContent = displayName || safePath;
  await window.handleInspectExcel();
};

window.handleExcelFileInputChange = async function(input) {
  if (input.files && input.files.length > 0) {
    const file = input.files[0];
    const path = file.path || file.name;
    document.getElementById('excelFilePath').value = path;
    const displayEl = document.getElementById('excelSelectedFileDisplay');
    if (displayEl) displayEl.textContent = file.name;
    await window.handleInspectExcel();
  }
};

window.openFiscalYearsModal = function() {
  window.switchTab('fiscal');
};

window.openCustomDateModal = function() {
  document.getElementById('custDateStart').value = '۱۴۰۵/۰۱/۰۱';
  document.getElementById('custDateEnd').value = '۱۴۰۵/۰۸/۱۷';
  window.openModal('modalCustomDate');
};

window.openDeleteTxModal = function(txId) {
  document.getElementById('deleteTxId').value = txId;
  document.getElementById('deleteTxReason').value = '';
  window.openModal('modalDeleteTx');
};

window.toggleAccountHolder = function() {
  const kind = document.getElementById('accInputKind').value;
  const holderDiv = document.getElementById('fieldAccHolder');
  if (kind === 'personal') {
    holderDiv.classList.remove('hidden');
  } else {
    holderDiv.classList.add('hidden');
  }
};

window.updateDynamicFields = function() {
  const type = document.getElementById('txInputType').value;
  const fClient = document.getElementById('fieldClient');
  const fPerson = document.getElementById('fieldPerson');
  const fCash = document.getElementById('fieldCashAccount');
  const fTransfer = document.getElementById('fieldTransfer');
  const fPurpose = document.getElementById('fieldPurpose');
  const fOverride = document.getElementById('fieldOverride');

  if (!fClient) return;

  fClient.classList.add('hidden');
  fPerson.classList.add('hidden');
  fCash.classList.add('hidden');
  fTransfer.classList.add('hidden');
  fPurpose.classList.add('hidden');
  fOverride.classList.add('hidden');

  switch (type) {
    case 'work_in':
      fClient.classList.remove('hidden');
      break;
    case 'work_out':
      fPerson.classList.remove('hidden');
      break;
    case 'income':
      fClient.classList.remove('hidden');
      fCash.classList.remove('hidden');
      break;
    case 'expense':
      fCash.classList.remove('hidden');
      break;
    case 'payout':
      fPerson.classList.remove('hidden');
      fCash.classList.remove('hidden');
      fPurpose.classList.remove('hidden');
      fOverride.classList.remove('hidden');
      break;
    case 'transfer':
      fTransfer.classList.remove('hidden');
      break;
  }
};

function populateSelect(elemId, items) {
  const sel = document.getElementById(elemId);
  if (!sel) return;
  sel.innerHTML = '';
  if (!items || items.length === 0) {
    const opt = document.createElement('option');
    opt.value = '';
    opt.textContent = '(موردی تعریف نشده)';
    sel.appendChild(opt);
    return;
  }
  items.forEach(it => {
    const opt = document.createElement('option');
    opt.value = it.id;
    opt.textContent = it.name;
    sel.appendChild(opt);
  });
}

// ----------------------------------------------------------------------------
// Projects & Manage Projects Modal
// ----------------------------------------------------------------------------
async function loadProjects() {
  try {
    let projects = await invoke('list_projects');
    const select = document.getElementById('projectSelect');
    select.innerHTML = '';

    if (!projects || projects.length === 0) {
      const defaultProj = await invoke('create_project', {
        name: 'پروژه اصلی دفتر کارکرد',
        start_date: null,
        end_date: null,
      });
      projects = [defaultProj];
    }

    allProjects = projects;

    projects.forEach(p => {
      const opt = document.createElement('option');
      opt.value = p.id;
      opt.textContent = p.name + (p.status === 'locked' ? ' (قفل)' : '');
      select.appendChild(opt);
    });

    if (!currentProjectId || !projects.some(p => p.id === currentProjectId)) {
      currentProjectId = projects[0].id;
    }

    select.value = currentProjectId;
    currentProject = projects.find(p => p.id === currentProjectId);

    updateProjectHeader();

    select.onchange = async (e) => {
      currentProjectId = e.target.value;
      currentProject = projects.find(p => p.id === currentProjectId);
      updateProjectHeader();
      await loadProjectBalance();
      await loadTransactions();
    };
  } catch (err) {
    console.error('Error loading projects:', err);
  }
}

function updateProjectHeader() {
  const isLocked = currentProject && currentProject.status === 'locked';
  const lockBadge = document.getElementById('projectLockBadge');
  const dashLockTag = document.getElementById('dashLockTag');
  const dashTitle = document.getElementById('dashProjectTitle');

  if (lockBadge) lockBadge.classList.toggle('hidden', !isLocked);
  if (dashLockTag) dashLockTag.classList.toggle('hidden', !isLocked);
  if (dashTitle && currentProject) dashTitle.textContent = currentProject.name;
}

function renderManageProjectsList() {
  const container = document.getElementById('manageProjectsList');
  if (!container) return;
  container.innerHTML = '';

  allProjects.forEach(p => {
    const isActive = p.id === currentProjectId;
    const isLocked = p.status === 'locked';

    const div = document.createElement('div');
    div.className = `p-3 rounded-xl border flex items-center justify-between transition ${isActive ? 'bg-blue-50 border-blue-300' : 'bg-gray-50 border-gray-200'}`;
    div.innerHTML = `
      <div>
        <div class="font-bold text-gray-900 flex items-center gap-2">
          <span>${p.name}</span>
          ${isLocked ? '<span class="text-[10px] bg-amber-100 text-amber-800 font-bold px-1.5 py-0.5 rounded border border-amber-300">قفل</span>' : ''}
          ${isActive ? '<span class="text-[10px] bg-blue-600 text-white font-bold px-1.5 py-0.5 rounded">پروژه فعال</span>' : ''}
        </div>
        <div class="text-[11px] text-gray-400 mt-0.5">شناسه: ${p.id.substring(0, 8)}...</div>
      </div>
      <div class="flex items-center gap-2">
        ${!isActive ? `<button onclick="selectActiveProject('${p.id}')" class="px-3 py-1 bg-white border border-gray-300 hover:bg-gray-100 text-gray-700 font-bold rounded-lg cursor-pointer">انتخاب</button>` : ''}
        ${!isLocked ? `<button onclick="handleLockProject('${p.id}')" class="px-2.5 py-1 text-amber-700 hover:bg-amber-50 border border-amber-300 rounded-lg font-bold cursor-pointer" title="بستن دوره و قفل">🔒 بستن</button>` : ''}
      </div>
    `;
    container.appendChild(div);
  });
}

window.selectActiveProject = async function(id) {
  currentProjectId = id;
  const sel = document.getElementById('projectSelect');
  if (sel) sel.value = id;
  currentProject = allProjects.find(p => p.id === id);
  updateProjectHeader();
  window.closeModal('modalManageProjects');
  await loadProjectBalance();
  await loadTransactions();
};

window.handleLockProject = async function(id) {
  if (!confirm('آیا از قفل کردن این پروژه اطمینان دارید؟ با قفل شدن پروژه، امکان ثبت یا ویرایش تراکنش جدید در این دوره وجود نخواهد داشت.')) {
    return;
  }
  try {
    await invoke('lock_project', { projectId: id });
    await loadProjects();
    renderManageProjectsList();
  } catch (err) {
    alert('خطا در قفل کردن پروژه: ' + err);
  }
};

// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// Fiscal Years & Rollover
// ----------------------------------------------------------------------------
window.renderFiscalYearsTab = async function() {
  const container = document.getElementById('fiscalYearsCardsList');
  const countLabel = document.getElementById('fiscalCountLabel');
  if (!container) return;

  container.innerHTML = '<div class="p-8 text-center text-gray-400 bg-white rounded-2xl border border-gray-200 text-xs">در حال دریافت و تحلیل دوره‌های مالی...</div>';

  try {
    const projects = await invoke('list_projects');
    if (projects) allProjects = projects;
    if (countLabel) countLabel.textContent = `${toFaDigits(allProjects.length)} دوره`;

    const list = [];
    for (const p of allProjects) {
      let bal = { total_project_accounts_balance: 0, total_receivables: 0, total_due: 0, profit_accrual: 0 };
      let txCount = 0;
      try {
        bal = await invoke('get_project_balance', { projectId: p.id, fromDate: null, toDate: null, startDateIso: null, endDateIso: null });
        const txs = await invoke('list_transactions', { projectId: p.id, includeDeleted: false });
        txCount = txs ? txs.length : 0;
      } catch (e) {
        console.warn('Error fetching balance for project', p.id, e);
      }
      list.push({ project: p, balance: bal, txCount });
    }

    container.innerHTML = '';
    list.forEach(item => {
      const p = item.project;
      const b = item.balance;
      const isActive = p.id === currentProjectId;
      const isLocked = p.status === 'locked';

      const card = document.createElement('div');
      card.className = `p-4 sm:p-5 rounded-2xl border transition ${
        isActive
          ? 'bg-gradient-to-r from-teal-50/60 to-white border-teal-400 shadow-sm'
          : 'bg-white border-gray-200 hover:border-gray-300'
      } space-y-4`;

      const safeName = (p.name || '').replace(/'/g, "\\'");

      card.innerHTML = `
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div class="flex items-center gap-3">
            <div class="w-11 h-11 rounded-2xl flex items-center justify-center font-bold text-lg shrink-0 ${
              isActive ? 'bg-teal-600 text-white shadow-xs' : 'bg-gray-100 text-gray-600'
            }">
              ${isLocked ? '🔒' : '🗓️'}
            </div>
            <div>
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm sm:text-base font-bold text-gray-900">${p.name}</span>
                ${isActive ? '<span class="text-[11px] bg-green-100 text-green-800 font-bold px-2 py-0.5 rounded-md border border-green-300">سال مالی فعال ✓</span>' : ''}
                ${isLocked ? '<span class="text-[11px] bg-amber-100 text-amber-800 font-bold px-2 py-0.5 rounded-md border border-amber-300">بسته و قفل‌شده 🔒</span>' : ''}
              </div>
              <div class="text-xs text-gray-400 mt-0.5">
                <span>${toFaDigits(item.txCount)} تراکنش ثبت‌شده</span>
                ${p.start_date ? `<span class="mx-1">•</span><span>تاریخ شروع: ${toFaDigits(p.start_date)}</span>` : ''}
              </div>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            ${!isActive ? `
              <button onclick="selectActiveProject('${p.id}')" class="px-3.5 py-1.5 bg-gray-100 hover:bg-gray-200 active:scale-95 text-gray-800 text-xs font-bold rounded-xl transition cursor-pointer flex items-center gap-1">
                <span>✓</span><span>انتخاب به عنوان دوره فعال</span>
              </button>
            ` : ''}
            <button onclick="startRolloverForProject('${p.id}', '${safeName}')" class="px-3.5 py-1.5 ${isLocked ? 'bg-gray-700 hover:bg-gray-800 text-white' : 'bg-teal-600 hover:bg-teal-700 text-white'} active:scale-95 text-xs font-bold rounded-xl transition shadow-xs cursor-pointer flex items-center gap-1">
              <span>🔄</span><span>${isLocked ? 'انتقال مجدد به سال جدید' : 'بستن سال مالی و انتقال دوره'}</span>
            </button>
            ${!isLocked ? `
              <button onclick="handleLockProject('${p.id}')" class="px-2.5 py-1.5 text-amber-700 hover:bg-amber-50 active:scale-95 border border-amber-300 rounded-xl text-xs font-bold cursor-pointer" title="بستن و قفل این دوره">
                🔒 قفل
              </button>
            ` : ''}
          </div>
        </div>

        <!-- 3 Financial Metrics matching Flutter FiscalYearsScreen -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2.5 pt-3 border-t border-gray-100 text-xs">
          <div class="p-2.5 bg-teal-50/60 rounded-xl border border-teal-100">
            <span class="text-gray-500 block text-[11px] mb-0.5">موجودی نقد و بانک:</span>
            <strong class="text-sm font-bold font-mono text-teal-800">${formatToman(b.total_project_accounts_balance)}</strong>
          </div>
          <div class="p-2.5 bg-indigo-50/60 rounded-xl border border-indigo-100">
            <span class="text-gray-500 block text-[11px] mb-0.5">طلب از کارفرمایان:</span>
            <strong class="text-sm font-bold font-mono text-indigo-800">${formatToman(b.total_receivables)}</strong>
          </div>
          <div class="p-2.5 bg-purple-50/60 rounded-xl border border-purple-100">
            <span class="text-gray-500 block text-[11px] mb-0.5">تعهدات و بدهی‌ها (Due):</span>
            <strong class="text-sm font-bold font-mono text-purple-800">${formatToman(b.total_due)}</strong>
          </div>
        </div>
      `;
      container.appendChild(card);
    });
  } catch (err) {
    container.innerHTML = `<div class="p-6 text-center text-red-600 bg-red-50 rounded-2xl text-xs">خطا در دریافت سال‌های مالی: ${err}</div>`;
  }
};

window.openRolloverModalForActive = function() {
  if (!currentProject) {
    alert('ابتدا یک دوره مالی انتخاب کنید.');
    return;
  }
  startRolloverForProject(currentProject.id, currentProject.name);
};

window.startRolloverForProject = function(pid, pname) {
  const targetInput = document.getElementById('rolloverTargetName');
  const dateInput = document.getElementById('rolloverStartDate');
  if (targetInput) {
    const nextYearMatch = (pname || '').match(/۱۴۰(\d)/);
    if (nextYearMatch) {
      const nextNum = parseInt(nextYearMatch[1], 10) + 1;
      targetInput.value = pname.replace(/۱۴۰\d/, `۱۴۰${nextNum}`);
    } else {
      targetInput.value = (pname || 'پروژه') + ' - سال مالی جدید';
    }
  }
  if (dateInput) {
    dateInput.value = '۱۴۰۶/۰۱/۰۱';
  }
  window._rolloverSourceProjectId = pid;
  renderFiscalYearsModal();
  window.openModal('modalFiscalYears');
};

// ----------------------------------------------------------------------------
// Cash Accounts Tab (Matching Flutter ManageAccountsDialog)
// ----------------------------------------------------------------------------
window.renderAccountsTab = async function() {
  const tableBody = document.getElementById('accountsDetailedTableBody');
  const cardsMobile = document.getElementById('accountsCardsMobile');
  if (!tableBody && !cardsMobile) return;

  try {
    const accounts = await invoke('list_cash_accounts');
    const persons = await invoke('list_persons', { activeOnly: false });
    const txs = await invoke('list_transactions', { projectId: currentProjectId, includeDeleted: false });

    // Calculate balances for each account within current project
    const accountBalances = {};
    (accounts || []).forEach(a => { accountBalances[a.id] = 0; });

    (txs || []).forEach(tx => {
      const amt = tx.amount || 0;
      if (tx.type === 'income') {
        if (tx.cash_account_id && accountBalances[tx.cash_account_id] !== undefined) {
          accountBalances[tx.cash_account_id] += amt;
        }
      } else if (tx.type === 'expense' || tx.type === 'payout') {
        if (tx.cash_account_id && accountBalances[tx.cash_account_id] !== undefined) {
          accountBalances[tx.cash_account_id] -= amt;
        }
      } else if (tx.type === 'transfer') {
        if (tx.cash_account_id && accountBalances[tx.cash_account_id] !== undefined) {
          accountBalances[tx.cash_account_id] -= amt;
        }
        if (tx.to_account_id && accountBalances[tx.to_account_id] !== undefined) {
          accountBalances[tx.to_account_id] += amt;
        }
      }
    });

    // Render desktop table
    if (tableBody) {
      tableBody.innerHTML = '';
      if (!accounts || accounts.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="5" class="p-6 text-center text-gray-400">هیچ حسابی تعریف نشده است.</td></tr>';
      } else {
        accounts.forEach(acc => {
          const isProj = acc.kind === 'project';
          const holder = !isProj && acc.holder_person_id
            ? (persons || []).find(p => p.id === acc.holder_person_id)?.name || 'شخص نامشخص'
            : 'پروژه (حساب سازمانی)';
          const bal = accountBalances[acc.id] || 0;

          const tr = document.createElement('tr');
          tr.className = 'hover:bg-gray-50/80 transition';
          tr.innerHTML = `
            <td class="p-3 font-bold text-gray-900 flex items-center gap-2">
              <span class="text-base">${isProj ? '🏦' : '👛'}</span>
              <span>${acc.name}</span>
            </td>
            <td class="p-3">
              <span class="px-2.5 py-1 rounded-full text-[11px] font-bold ${
                isProj ? 'bg-blue-100 text-blue-800' : 'bg-purple-100 text-purple-800'
              }">
                ${isProj ? 'حساب متعلق به پروژه' : 'کیف‌پول / جیب شریک'}
              </span>
            </td>
            <td class="p-3 text-gray-600">${holder}</td>
            <td class="p-3 font-mono font-bold ${bal >= 0 ? 'text-teal-800' : 'text-rose-700'}">
              ${formatToman(bal)}
            </td>
            <td class="p-3 text-left">
              <button onclick="openNewTxWithAccount('${acc.id}')" class="px-2.5 py-1 text-xs bg-blue-50 text-blue-700 hover:bg-blue-100 font-bold rounded-lg cursor-pointer">
                + ثبت تراکنش
              </button>
            </td>
          `;
          tableBody.appendChild(tr);
        });
      }
    }

    // Render mobile cards
    if (cardsMobile) {
      cardsMobile.innerHTML = '';
      if (!accounts || accounts.length === 0) {
        cardsMobile.innerHTML = '<div class="p-6 text-center text-gray-400 bg-white rounded-2xl border border-gray-200">هیچ حسابی تعریف نشده است.</div>';
      } else {
        accounts.forEach(acc => {
          const isProj = acc.kind === 'project';
          const holder = !isProj && acc.holder_person_id
            ? (persons || []).find(p => p.id === acc.holder_person_id)?.name || 'شخص نامشخص'
            : 'پروژه (حساب سازمانی)';
          const bal = accountBalances[acc.id] || 0;

          const card = document.createElement('div');
          card.className = 'p-4 bg-white rounded-2xl border border-gray-200 shadow-xs space-y-2';
          card.innerHTML = `
            <div class="flex items-center justify-between">
              <div class="font-bold text-sm text-gray-900 flex items-center gap-2">
                <span class="text-base">${isProj ? '🏦' : '👛'}</span>
                <span>${acc.name}</span>
              </div>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-bold ${
                isProj ? 'bg-blue-100 text-blue-800' : 'bg-purple-100 text-purple-800'
              }">
                ${isProj ? 'پروژه' : 'جیب شریک'}
              </span>
            </div>
            <div class="flex justify-between items-center text-xs pt-1 border-t border-gray-100">
              <span class="text-gray-500">${holder}</span>
              <strong class="font-mono ${bal >= 0 ? 'text-teal-800' : 'text-rose-700'}">${formatToman(bal)}</strong>
            </div>
          `;
          cardsMobile.appendChild(card);
        });
      }
    }
  } catch (err) {
    console.error('Error rendering accounts tab:', err);
  }
};

window.openNewAccountInlineForm = function() {
  const card = document.getElementById('newAccountInlineCard');
  if (card) {
    card.classList.remove('hidden');
    document.getElementById('accInlineName').value = '';
    document.getElementById('accInlineKind').value = 'project';
    toggleInlineAccountHolder();
  }
};

window.closeNewAccountInlineForm = function() {
  const card = document.getElementById('newAccountInlineCard');
  if (card) card.classList.add('hidden');
};

window.toggleInlineAccountHolder = function() {
  const kind = document.getElementById('accInlineKind')?.value;
  const holderDiv = document.getElementById('fieldInlineAccHolder');
  if (holderDiv) {
    if (kind === 'personal') {
      holderDiv.classList.remove('hidden');
      invoke('list_persons', { activeOnly: false }).then(persons => {
        const sel = document.getElementById('accInlineHolder');
        if (sel) {
          sel.innerHTML = '';
          const partners = (persons || []).filter(p => p.kind === 'partner');
          partners.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p.id;
            opt.textContent = p.name;
            sel.appendChild(opt);
          });
        }
      });
    } else {
      holderDiv.classList.add('hidden');
    }
  }
};

window.openNewTxWithAccount = function(accId) {
  openNewTxModal();
  setTimeout(() => {
    const sel = document.getElementById('txInputCashAccount');
    if (sel) sel.value = accId;
  }, 100);
};

// ----------------------------------------------------------------------------
// Project Settings & Partner Shares (Accounter logic)
// ----------------------------------------------------------------------------
window.loadProjectSettingsAndShares = async function() {
  if (!currentProjectId) return;
  try {
    const settings = await invoke('get_project_settings', { projectId: currentProjectId });
    if (settings) {
      const repEl = document.getElementById('setReportBasis');
      const sbEl = document.getElementById('setShareBasis');
      const smEl = document.getElementById('setShareMethod');
      if (repEl) repEl.value = settings.report_basis || 'both';
      if (sbEl) sbEl.value = settings.share_basis || 'accrual';
      if (smEl) smEl.value = settings.share_method || 'fixed_percent';
    }

    const persons = await invoke('list_persons', { activeOnly: false });
    const partners = (persons || []).filter(p => p.kind === 'partner');
    const projPersons = await invoke('list_project_persons', { projectId: currentProjectId });

    const tbody = document.getElementById('partnerSharesTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';

    if (partners.length === 0) {
      tbody.innerHTML = '<tr><td colspan="3" class="p-4 text-center text-gray-400">هیچ شخصی با نقش «شریک» تعریف نشده است. می‌توانید از بخش طرف‌حساب‌ها شریک جدید تعریف کنید.</td></tr>';
      updatePartnerSharesTotal();
      return;
    }

    partners.forEach((partner, idx) => {
      const pp = (projPersons || []).find(x => x.person_id === partner.id);
      const sharePercent = pp && pp.share_bp !== null && pp.share_bp !== undefined
        ? Math.round(pp.share_bp / 100)
        : (idx === 0 ? 100 : 0);
      const mode = pp ? pp.settlement_mode : 'profit_share';

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="p-2.5 font-bold text-gray-900">${partner.name}</td>
        <td class="p-2.5">
          <select class="partner-settle-mode border border-gray-300 rounded-lg p-1.5 text-xs bg-white" data-person-id="${partner.id}">
            <option value="profit_share" ${mode === 'profit_share' ? 'selected' : ''}>سهم سود</option>
            <option value="both" ${mode === 'both' ? 'selected' : ''}>هر دو (سود و دستمزد)</option>
            <option value="payout_only" ${mode === 'payout_only' ? 'selected' : ''}>فقط دستمزد (بدون سهم)</option>
          </select>
        </td>
        <td class="p-2.5">
          <div class="flex items-center gap-1">
            <input type="number" min="0" max="100" value="${sharePercent}" 
                   class="partner-share-input w-20 border border-gray-300 rounded-lg p-1.5 text-xs text-center font-bold"
                   data-person-id="${partner.id}"
                   oninput="updatePartnerSharesTotal()">
            <span class="text-xs font-bold text-gray-500">٪</span>
          </div>
        </td>
      `;
      tbody.appendChild(tr);
    });

    updatePartnerSharesTotal();
  } catch (err) {
    console.error('Error loading project settings and shares:', err);
  }
};

window.updatePartnerSharesTotal = function() {
  const inputs = document.querySelectorAll('.partner-share-input');
  let sum = 0;
  inputs.forEach(inp => {
    sum += parseFloat(inp.value) || 0;
  });
  const badge = document.getElementById('partnerSharesTotalBadge');
  if (badge) {
    if (Math.round(sum) === 100) {
      badge.className = 'font-bold px-2 py-0.5 rounded-md text-xs bg-green-100 text-green-800';
      badge.textContent = 'مجموع: ۱۰۰٪ ✓';
    } else {
      badge.className = 'font-bold px-2 py-0.5 rounded-md text-xs bg-rose-100 text-rose-800';
      badge.textContent = `مجموع: ${toFaDigits(sum)}٪ (باید ۱۰۰٪ باشد)`;
    }
  }
};

window.handleSaveProjectSettingsAndShares = async function(e) {
  if (e) e.preventDefault();
  if (!currentProjectId) {
    alert('پروژه‌ای انتخاب نشده است.');
    return;
  }

  const reportBasis = document.getElementById('setReportBasis')?.value || 'both';
  const shareBasis = document.getElementById('setShareBasis')?.value || 'accrual';
  const shareMethod = document.getElementById('setShareMethod')?.value || 'fixed_percent';

  const inputs = document.querySelectorAll('.partner-share-input');
  let sum = 0;
  inputs.forEach(inp => {
    sum += parseFloat(inp.value) || 0;
  });

  if (shareMethod === 'fixed_percent' && inputs.length > 0 && Math.round(sum) !== 100) {
    if (!confirm(`مجموع درصد سهم شرکا ${sum}٪ است (باید ۱۰۰٪ باشد). آیا مایل به ذخیره با همین مقادیر هستید؟`)) {
      return;
    }
  }

  try {
    await invoke('set_project_settings', {
      projectId: currentProjectId,
      reportBasis,
      shareBasis,
      shareMethod,
    });

    const modeSelects = document.querySelectorAll('.partner-settle-mode');
    let order = 1;
    for (const inp of inputs) {
      const personId = inp.dataset.personId;
      const percent = parseFloat(inp.value) || 0;
      const bp = Math.round(percent * 100);
      const modeSel = Array.from(modeSelects).find(s => s.dataset.personId === personId);
      const mode = modeSel ? modeSel.value : 'profit_share';

      await invoke('set_project_person', {
        projectId: currentProjectId,
        personId,
        settlementMode: mode,
        shareBp: bp,
        shareOrder: order++,
      });
    }

    const badge = document.getElementById('projSettingsSavedBadge');
    if (badge) {
      badge.classList.remove('hidden');
      setTimeout(() => badge.classList.add('hidden'), 3500);
    }

    await loadProjectBalance();
    alert('تنظیمات پروژه و درصد سهام شرکا با موفقیت ذخیره گردید.');
  } catch (err) {
    alert('خطا در ذخیره تنظیمات: ' + err);
  }
};

async function renderFiscalYearsModal() {
  const container = document.getElementById('fiscalYearsList');
  if (!container) return;
  container.innerHTML = '<div class="text-center p-3 text-gray-400">در حال دریافت وضعیت دوره‌های مالی...</div>';

  try {
    const list = [];
    for (const p of allProjects) {
      const bal = await invoke('get_project_balance', { projectId: p.id, fromDate: null, toDate: null, startDateIso: null, endDateIso: null });
      const txs = await invoke('list_transactions', { projectId: p.id, includeDeleted: false });
      list.push({ project: p, balance: bal, txCount: txs ? txs.length : 0 });
    }

    container.innerHTML = '';
    list.forEach(item => {
      const p = item.project;
      const b = item.balance;
      const isActive = p.id === currentProjectId;
      const isLocked = p.status === 'locked';

      const card = document.createElement('div');
      card.className = `p-4 rounded-xl border ${isActive ? 'bg-teal-50 border-teal-300' : 'bg-gray-50 border-gray-200'} space-y-2`;
      card.innerHTML = `
        <div class="flex justify-between items-center">
          <div class="font-bold text-sm text-gray-900 flex items-center gap-2">
            <span>${p.name}</span>
            <span class="text-xs px-2 py-0.5 rounded-full font-bold ${isLocked ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-800'}">
              ${isLocked ? 'بسته / قفل‌شده' : 'دوره فعال جاری'}
            </span>
          </div>
          <span class="text-xs text-gray-500 font-mono">${toFaDigits(item.txCount)} تراکنش</span>
        </div>
        <div class="grid grid-cols-3 gap-2 text-xs pt-1 border-t border-gray-200">
          <div><span class="text-gray-400 block">نقد و بانک:</span><strong class="text-teal-800">${formatToman(b.total_project_accounts_balance)}</strong></div>
          <div><span class="text-gray-400 block">طلب کارفرما:</span><strong class="text-indigo-800">${formatToman(b.total_receivables)}</strong></div>
          <div><span class="text-gray-400 block">سود تعهدی:</span><strong class="text-green-800">${formatToman(b.profit_accrual)}</strong></div>
        </div>
      `;
      container.appendChild(card);
    });
  } catch (err) {
    container.innerHTML = `<div class="text-red-600 text-xs">خطا در بارگذاری دوره‌ها: ${err}</div>`;
  }
}

// ----------------------------------------------------------------------------
// Balance & KPI Dashboard
// ----------------------------------------------------------------------------
async function loadProjectBalance() {
  if (!currentProjectId) return;
  try {
    const bal = await invoke('get_project_balance', {
      projectId: currentProjectId,
      fromDate: currentReportDateFilter.startIso,
      toDate: currentReportDateFilter.endIso,
      startDateIso: currentReportDateFilter.startIso,
      endDateIso: currentReportDateFilter.endIso,
    });
    currentBalance = bal;

    // 1. Dashboard 4 KPI Cards
    const elCash = document.getElementById('dashKpiCash');
    const elRec = document.getElementById('dashKpiReceivables');
    const elDue = document.getElementById('dashKpiDue');
    const elProf = document.getElementById('dashKpiProfit');
    if (elCash) elCash.textContent = formatToman(bal.total_project_accounts_balance);
    if (elRec) elRec.textContent = formatToman(bal.total_receivables);
    if (elDue) elDue.textContent = formatToman(bal.total_due);
    if (elProf) elProf.textContent = formatToman(bal.profit_accrual);

    // 2. Dashboard Golden Equality Badge
    const goldenBadge = document.getElementById('dashGoldenBadge');
    if (goldenBadge) {
      if (bal.is_golden_equation_balanced) {
        goldenBadge.className = 'inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-bold bg-green-50 text-green-800 border border-green-200';
        goldenBadge.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-green-500"></span><span>تراز طلایی برقرار است ✓</span>';
      } else {
        goldenBadge.className = 'inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-bold bg-rose-50 text-rose-800 border border-rose-200';
        goldenBadge.innerHTML = '<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span><span>ناهمگونی در تراز طلایی ✗</span>';
      }
    }

    // 3. Visual Charts (Composition Bars)
    renderDashboardCharts(bal);

    // 4. Partner Share Table
    renderPartnerBreakdown(bal);

    // 5. Report Tab
    renderReportTab(bal);
  } catch (err) {
    console.error('Error loading project balance:', err);
  }
}

function renderDashboardCharts(bal) {
  const maxVal = Math.max(bal.win, bal.inc, bal.exp, bal.ps + bal.pd, 1);

  const setBar = (valId, barId, val) => {
    const elVal = document.getElementById(valId);
    const elBar = document.getElementById(barId);
    if (elVal) elVal.textContent = formatToman(val);
    if (elBar) {
      const pct = Math.min(100, Math.round((Math.max(0, val) / maxVal) * 100));
      elBar.style.width = pct + '%';
    }
  };

  setBar('chartValWin', 'chartBarWin', bal.win);
  setBar('chartValInc', 'chartBarInc', bal.inc);
  setBar('chartValExp', 'chartBarExp', bal.exp);
  setBar('chartValPayouts', 'chartBarPayouts', bal.ps + bal.pd);
}

function renderPartnerBreakdown(bal) {
  const tbody = document.getElementById('dashPartnerTable');
  if (!tbody) return;
  tbody.innerHTML = '';

  const personIds = Object.keys(bal.person_balances || {});
  if (personIds.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" class="p-4 text-center text-gray-400">اطلاعاتی ثبت نشده است</td></tr>';
    return;
  }

  personIds.forEach(pid => {
    const pBal = bal.person_balances[pid];
    const person = personsCache.find(p => p.id === pid);
    const pName = person ? person.name : pid;

    const tr = document.createElement('tr');
    tr.className = 'hover:bg-gray-50 transition';
    tr.innerHTML = `
      <td class="p-2.5 font-bold text-gray-900">${pName}</td>
      <td class="p-2.5 ${pBal.pay > 0 ? 'text-rose-600 font-bold' : 'text-gray-600'}">${formatToman(pBal.pay)}</td>
      <td class="p-2.5 text-blue-700 font-bold">${formatToman(pBal.share)}</td>
      <td class="p-2.5 ${pBal.custody !== 0 ? 'text-amber-700 font-bold' : 'text-gray-400'}">${formatToman(pBal.custody)}</td>
      <td class="p-2.5 font-bold ${pBal.due > 0 ? 'text-orange-700' : 'text-gray-700'}">${formatToman(pBal.due)}</td>
    `;
    tbody.appendChild(tr);
  });
}

// ----------------------------------------------------------------------------
// Reports Tab & Sub-Tabs
// ----------------------------------------------------------------------------
function renderReportTab(bal) {
  const elProj = document.getElementById('reportProjectName');
  if (elProj) elProj.textContent = currentProject ? currentProject.name : 'پروژه';

  const setIfExists = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  };

  setIfExists('repWin', formatToman(bal.win));
  setIfExists('repWout', formatToman(bal.wout));
  setIfExists('repExp', formatToman(bal.exp));
  setIfExists('repProfitAcc', formatToman(bal.profit_accrual));

  setIfExists('repInc', formatToman(bal.inc));
  setIfExists('repCashExp', formatToman(bal.exp));
  setIfExists('repPs', formatToman(bal.ps));
  setIfExists('repProfitCash', formatToman(bal.profit_cash));

  setIfExists('repEqCash', formatToman(bal.total_project_accounts_balance));
  setIfExists('repEqRec', formatToman(bal.total_receivables));
  setIfExists('repEqDue', formatToman(bal.total_due));
  setIfExists('repGoldenStatus', bal.is_golden_equation_balanced ? 'برقرار است ✓' : 'نامتعادل ✗');

  // Sub-Tab 1: Clients Table
  renderReportClientsTable(bal);
  // Sub-Tab 2: Payees Table
  renderReportPayeesTable(bal);
  // Sub-Tab 3: Partners Table
  renderReportPartnersTable(bal);
}

function renderReportClientsTable(bal) {
  const tbody = document.getElementById('repClientsTable');
  if (!tbody) return;
  tbody.innerHTML = '';

  const clientIds = Object.keys(bal.receivables || {});
  if (clientIds.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="p-3 text-center text-gray-400">هیچ طلبی از کارفرمایان ثبت نشده است</td></tr>';
    return;
  }

  clientIds.forEach(cid => {
    const person = personsCache.find(p => p.id === cid);
    const name = person ? person.name : cid;
    const dueAmount = bal.receivables[cid] || 0;

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="p-2.5 font-bold text-gray-900">${name}</td>
      <td class="p-2.5 font-mono text-gray-700">${formatToman(bal.win)}</td>
      <td class="p-2.5 font-mono text-gray-700">${formatToman(bal.inc)}</td>
      <td class="p-2.5 font-bold font-mono text-indigo-700">${formatToman(dueAmount)}</td>
    `;
    tbody.appendChild(tr);
  });
}

function renderReportPayeesTable(bal) {
  const tbody = document.getElementById('repPayeesTable');
  if (!tbody) return;
  tbody.innerHTML = '';

  const payees = personsCache.filter(p => p.kind === 'driver' || p.kind === 'worker');
  if (payees.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="p-3 text-center text-gray-400">طرف‌حساب راننده یا پرسنلی ثبت نشده است</td></tr>';
    return;
  }

  payees.forEach(p => {
    const pBal = (bal.person_balances && bal.person_balances[p.id]) || { pay: 0, due: 0 };
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="p-2.5 font-bold text-gray-900">${p.name} (${p.kind === 'driver' ? 'راننده' : 'پرسنل'})</td>
      <td class="p-2.5 font-mono text-gray-700">${formatToman(bal.wout)}</td>
      <td class="p-2.5 font-mono text-gray-700">${formatToman(bal.ps)}</td>
      <td class="p-2.5 font-bold font-mono text-rose-700">${formatToman(pBal.due)}</td>
    `;
    tbody.appendChild(tr);
  });
}

function renderReportPartnersTable(bal) {
  const tbody = document.getElementById('repPartnersTable');
  if (!tbody) return;
  tbody.innerHTML = '';

  const partners = personsCache.filter(p => p.kind === 'partner');
  if (partners.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" class="p-3 text-center text-gray-400">شریکی در سامانه ثبت نشده است</td></tr>';
    return;
  }

  partners.forEach(p => {
    const alloc = (bal.partner_allocations && bal.partner_allocations[p.id]) || { claimable_share: 0, distribution_payouts: 0 };
    const pBal = (bal.person_balances && bal.person_balances[p.id]) || { custody: 0, due: 0 };

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="p-2.5 font-bold text-gray-900">${p.name}</td>
      <td class="p-2.5 font-bold font-mono text-blue-700">${formatToman(alloc.claimable_share)}</td>
      <td class="p-2.5 font-mono text-gray-700">${formatToman(alloc.distribution_payouts)}</td>
      <td class="p-2.5 font-mono ${pBal.custody !== 0 ? 'text-amber-700 font-bold' : 'text-gray-400'}">${formatToman(pBal.custody)}</td>
      <td class="p-2.5 font-bold font-mono text-orange-700">${formatToman(pBal.due)}</td>
    `;
    tbody.appendChild(tr);
  });
}

window.switchReportSubTab = function(sub) {
  const tabs = ['clients', 'payees', 'partners'];
  tabs.forEach(t => {
    const btn = document.getElementById('subTabBtn' + t.charAt(0).toUpperCase() + t.slice(1));
    const content = document.getElementById('subTab' + t.charAt(0).toUpperCase() + t.slice(1));
    if (t === sub) {
      if (btn) btn.className = 'py-2 border-b-2 border-blue-600 text-blue-600 font-bold cursor-pointer';
      if (content) content.classList.remove('hidden');
    } else {
      if (btn) btn.className = 'py-2 border-b-2 border-transparent text-gray-500 hover:text-gray-800 cursor-pointer';
      if (content) content.classList.add('hidden');
    }
  });
};

window.setReportDateFilter = async function(preset) {
  document.querySelectorAll('.rep-date-btn').forEach(btn => {
    if (btn.dataset.preset === preset) {
      btn.className = 'rep-date-btn px-3 py-1.5 rounded-lg bg-blue-600 text-white font-bold transition cursor-pointer';
    } else {
      btn.className = 'rep-date-btn px-3 py-1.5 rounded-lg bg-gray-100 hover:bg-gray-200 text-gray-700 transition cursor-pointer';
    }
  });

  const periodLabel = document.getElementById('reportPeriodLabel');
  if (preset === 'all') {
    currentReportDateFilter = { preset: 'all', startIso: null, endIso: null, label: 'کل دوره مالی' };
  } else if (preset === 'current_month') {
    currentReportDateFilter = { preset: 'current_month', startIso: '2026-10-23', endIso: '2026-11-21', label: 'ماه جاری (آبان ۱۴۰۵)' };
  } else if (preset === 'last_90_days') {
    currentReportDateFilter = { preset: 'last_90_days', startIso: '2026-08-23', endIso: '2026-11-21', label: '۳ ماه اخیر' };
  } else if (preset === 'current_year') {
    currentReportDateFilter = { preset: 'current_year', startIso: '2026-03-21', endIso: '2027-03-20', label: 'سال مالی ۱۴۰۵' };
  }

  if (periodLabel) periodLabel.textContent = `صورت وضعیت مالی — بازه گزارش: ${currentReportDateFilter.label}`;
  await loadProjectBalance();
};

// ----------------------------------------------------------------------------
// Persons / Counterparties
// ----------------------------------------------------------------------------
async function loadPersons() {
  try {
    const list = await invoke('list_persons', { activeOnly: false });
    personsCache = list || [];
    renderPersonsTable();
  } catch (err) {
    console.error('Error loading persons:', err);
  }
}

window.setPersonFilter = function(filter) {
  currentPersonFilter = filter;
  document.querySelectorAll('.person-pill-btn').forEach(btn => {
    if (btn.dataset.filter === filter) {
      btn.className = 'person-pill-btn px-3 py-1.5 rounded-lg bg-blue-600 text-white font-bold cursor-pointer';
    } else {
      btn.className = 'person-pill-btn px-3 py-1.5 rounded-lg bg-gray-100 text-gray-700 hover:bg-gray-200 cursor-pointer';
    }
  });
  renderPersonsTable();
};

function renderPersonsTable() {
  const tbody = document.getElementById('personsTableBody');
  const mobileContainer = document.getElementById('personsCardsMobile');
  if (tbody) tbody.innerHTML = '';
  if (mobileContainer) mobileContainer.innerHTML = '';

  const filtered = personsCache.filter(p => {
    if (currentPersonFilter === 'all') return true;
    return p.kind === currentPersonFilter;
  });

  if (filtered.length === 0) {
    if (tbody) tbody.innerHTML = '<tr><td colspan="5" class="p-6 text-center text-gray-400">طرف‌حسابی با این فیلتر یافت نشد</td></tr>';
    if (mobileContainer) mobileContainer.innerHTML = '<div class="p-6 text-center text-gray-400 bg-white rounded-2xl border border-gray-200 text-xs">طرف‌حسابی با این فیلتر یافت نشد</div>';
    return;
  }

  const kindMeta = {
    partner: { label: 'شریک تجاری', bg: 'bg-purple-50 text-purple-700' },
    client: { label: 'کارفرما / مشتری', bg: 'bg-blue-50 text-blue-700' },
    driver: { label: 'راننده جرثقیل', bg: 'bg-orange-50 text-orange-800' },
    worker: { label: 'کارگر / پرسنل', bg: 'bg-teal-50 text-teal-700' },
    other: { label: 'سایر', bg: 'bg-gray-100 text-gray-700' },
  };

  filtered.forEach(p => {
    const meta = kindMeta[p.kind] || { label: p.kind, bg: 'bg-gray-100 text-gray-700' };
    
    // Desktop Table Row
    if (tbody) {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-gray-50 transition';
      tr.innerHTML = `
        <td class="p-3 font-bold text-gray-900">${p.name}</td>
        <td class="p-3"><span class="px-2 py-0.5 rounded text-xs font-bold ${meta.bg}">${meta.label}</span></td>
        <td class="p-3 text-gray-500 font-mono">${p.code || '-'}</td>
        <td class="p-3 text-gray-500">${p.note || '-'}</td>
        <td class="p-3"><span class="text-xs font-bold ${p.is_active ? 'text-green-600' : 'text-gray-400'}">${p.is_active ? 'فعال' : 'غیرفعال'}</span></td>
      `;
      tbody.appendChild(tr);
    }

    // Mobile Touch Card
    if (mobileContainer) {
      const card = document.createElement('div');
      card.className = 'bg-white p-3.5 rounded-2xl border border-gray-200 shadow-xs flex flex-col gap-2';
      card.innerHTML = `
        <div class="flex items-center justify-between">
          <div class="font-bold text-gray-900 text-sm">${p.name}</div>
          <span class="px-2.5 py-0.5 rounded-full text-xs font-bold ${meta.bg}">${meta.label}</span>
        </div>
        <div class="flex items-center justify-between text-xs text-gray-500">
          <div>کد: <span class="font-mono font-bold text-gray-700">${p.code || '-'}</span></div>
          <span class="font-bold ${p.is_active ? 'text-green-600' : 'text-gray-400'}">${p.is_active ? '● فعال' : '○ غیرفعال'}</span>
        </div>
        ${p.note ? `<div class="text-xs text-gray-600 bg-gray-50 p-2 rounded-xl border border-gray-100">${p.note}</div>` : ''}
      `;
      mobileContainer.appendChild(card);
    }
  });
}

// ----------------------------------------------------------------------------
// Cash Accounts & Wallets
// ----------------------------------------------------------------------------
async function loadCashAccounts() {
  try {
    const accounts = await invoke('list_cash_accounts');
    cashAccountsCache = accounts || [];
  } catch (err) {
    console.error('Error loading accounts:', err);
  }
}

function renderAccountsModal() {
  const tbody = document.getElementById('accountsTableBody');
  if (!tbody) return;
  tbody.innerHTML = '';

  if (cashAccountsCache.length === 0) {
    tbody.innerHTML = '<tr><td colspan="3" class="p-3 text-center text-gray-400">حسابی ثبت نشده است</td></tr>';
  } else {
    cashAccountsCache.forEach(acc => {
      let holderName = '-';
      if (acc.holder_person_id) {
        const holder = personsCache.find(p => p.id === acc.holder_person_id);
        holderName = holder ? holder.name : acc.holder_person_id;
      }
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="p-2 font-bold text-gray-800">${acc.name}</td>
        <td class="p-2"><span class="px-2 py-0.5 rounded text-xs ${acc.kind === 'project' ? 'bg-teal-50 text-teal-700 font-bold' : 'bg-blue-50 text-blue-700'}">${acc.kind === 'project' ? 'صندوق پروژه' : 'جیب شخصی شریک'}</span></td>
        <td class="p-2 text-gray-600">${holderName}</td>
      `;
      tbody.appendChild(tr);
    });
  }

  const partners = personsCache.filter(p => p.kind === 'partner');
  populateSelect('accInputHolder', partners);
  document.getElementById('accInputName').value = '';
  document.getElementById('accInputKind').value = 'project';
  window.toggleAccountHolder();
}

// ----------------------------------------------------------------------------
// Transactions Management
// ----------------------------------------------------------------------------
async function loadTransactions() {
  if (!currentProjectId) return;
  try {
    const txs = await invoke('list_transactions', {
      projectId: currentProjectId,
      includeDeleted: false,
    });
    allTransactions = txs || [];
    filterAndRenderTransactions();
    renderRecentTransactionsDashboard();
  } catch (err) {
    console.error('Error loading transactions:', err);
  }
}

const TX_TYPE_LABELS = {
  work_in: { label: 'کارکرد (طلب از کارفرما)', bg: 'bg-indigo-50', text: 'text-indigo-700' },
  work_out: { label: 'کارکرد (بدهی شخص)', bg: 'bg-rose-50', text: 'text-rose-700' },
  income: { label: 'دریافتی وجه', bg: 'bg-teal-50', text: 'text-teal-700' },
  expense: { label: 'هزینه پروژه', bg: 'bg-amber-50', text: 'text-amber-700' },
  payout: { label: 'پرداخت', bg: 'bg-blue-50', text: 'text-blue-700' },
  transfer: { label: 'انتقال حساب', bg: 'bg-gray-100', text: 'text-gray-700' },
};

function filterAndRenderTransactions() {
  const searchInput = document.getElementById('txSearchInput');
  const typeFilterEl = document.getElementById('txFilterType');
  const search = searchInput ? searchInput.value.trim().toLowerCase() : '';
  const typeFilter = typeFilterEl ? typeFilterEl.value : '';

  const filtered = allTransactions.filter(t => {
    const tType = t.tx_type || t.type;
    if (typeFilter && tType !== typeFilter) return false;
    if (search && !(t.description || '').toLowerCase().includes(search)) return false;
    return true;
  });

  const txCountEl = document.getElementById('txCount');
  const dashTxCount = document.getElementById('dashTxCount');
  if (txCountEl) txCountEl.textContent = toFaDigits(filtered.length);
  if (dashTxCount) dashTxCount.textContent = toFaDigits(allTransactions.length);

  const tbody = document.getElementById('txTableBody');
  const mobileContainer = document.getElementById('txCardsMobile');
  if (tbody) tbody.innerHTML = '';
  if (mobileContainer) mobileContainer.innerHTML = '';

  if (filtered.length === 0) {
    if (tbody) tbody.innerHTML = '<tr><td colspan="6" class="p-8 text-center text-gray-400">تراکنشی یافت نشد</td></tr>';
    if (mobileContainer) mobileContainer.innerHTML = '<div class="p-8 text-center text-gray-400 bg-white rounded-2xl border border-gray-200 text-xs">تراکنشی یافت نشد</div>';
    return;
  }

  filtered.forEach(tx => {
    const txType = tx.tx_type || tx.type || 'expense';
    const meta = TX_TYPE_LABELS[txType] || { label: txType, bg: 'bg-gray-100', text: 'text-gray-700' };

    let party = '-';
    if (tx.client_id) {
      party = personsCache.find(p => p.id === tx.client_id)?.name || 'کارفرما';
    } else if (tx.person_id) {
      party = personsCache.find(p => p.id === tx.person_id)?.name || 'شخص';
    } else if (tx.from_account_id && tx.to_account_id) {
      const from = cashAccountsCache.find(a => a.id === tx.from_account_id)?.name || 'مبدأ';
      const to = cashAccountsCache.find(a => a.id === tx.to_account_id)?.name || 'مقصد';
      party = `${from} ➔ ${to}`;
    } else if (tx.cash_account_id) {
      party = cashAccountsCache.find(a => a.id === tx.cash_account_id)?.name || 'صندوق';
    }

    const isPositive = txType === 'work_in' || txType === 'income';
    const amountColor = isPositive ? 'text-teal-700' : 'text-rose-700';
    const amountSign = isPositive ? '+' : '-';
    const dateFormatted = formatDisplayDate(tx.date);

    // Desktop Table Row
    if (tbody) {
      const tr = document.createElement('tr');
      tr.className = 'hover:bg-gray-50 transition';
      tr.innerHTML = `
        <td class="p-3 text-gray-700 font-mono">${dateFormatted}</td>
        <td class="p-3"><span class="px-2 py-0.5 rounded-full text-xs font-bold ${meta.bg} ${meta.text}">${meta.label}</span></td>
        <td class="p-3 font-bold text-gray-900">${formatToman(tx.amount)}</td>
        <td class="p-3 text-gray-600 font-bold">${party}</td>
        <td class="p-3 text-gray-500">${tx.description || '-'}</td>
        <td class="p-3 text-center">
          <button onclick="openDeleteTxModal('${tx.id}')" class="text-rose-500 hover:text-rose-700 text-xs font-bold px-2 py-1 rounded hover:bg-rose-50 transition cursor-pointer" title="حذف نرم با ثبت دلیل">
            حذف
          </button>
        </td>
      `;
      tbody.appendChild(tr);
    }

    // Mobile Touch Card
    if (mobileContainer) {
      const card = document.createElement('div');
      card.className = 'bg-white p-3.5 rounded-2xl border border-gray-200 shadow-xs active:bg-gray-50 transition flex flex-col gap-2';
      card.innerHTML = `
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="px-2.5 py-0.5 rounded-full text-[11px] font-bold ${meta.bg} ${meta.text}">${meta.label}</span>
            <span class="text-xs text-gray-500 font-mono">${dateFormatted}</span>
          </div>
          <button onclick="openDeleteTxModal('${tx.id}')" class="p-1.5 text-gray-400 hover:text-rose-600 active:text-rose-700 rounded-lg hover:bg-rose-50 transition cursor-pointer" title="حذف تراکنش">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
          </button>
        </div>
        <div class="flex items-baseline justify-between pt-0.5">
          <div class="font-bold text-gray-900 text-sm truncate max-w-[55%]">${party}</div>
          <div class="font-bold font-mono text-sm sm:text-base ${amountColor}">
            <span>${amountSign}</span><span>${formatToman(tx.amount)}</span>
          </div>
        </div>
        ${tx.description ? `<div class="text-xs text-gray-500 bg-gray-50 p-2 rounded-xl border border-gray-100">${tx.description}</div>` : ''}
      `;
      mobileContainer.appendChild(card);
    }
  });
}

function renderRecentTransactionsDashboard() {
  const container = document.getElementById('dashRecentTxList');
  if (!container) return;
  container.innerHTML = '';

  const recent = allTransactions.slice(0, 5);
  if (recent.length === 0) {
    container.innerHTML = '<div class="p-4 text-center text-gray-400 text-xs">هنوز تراکنشی در این دوره ثبت نشده است.</div>';
    return;
  }

  recent.forEach(tx => {
    const txType = tx.tx_type || tx.type || 'expense';
    const isPositive = txType === 'work_in' || txType === 'income';
    const color = isPositive ? 'text-green-700' : 'text-red-700';
    const sign = isPositive ? '+' : '-';
    const meta = TX_TYPE_LABELS[txType] || { label: txType };
    const dateFormatted = formatDisplayDate(tx.date);

    const div = document.createElement('div');
    div.className = 'py-3 flex items-center justify-between';
    div.innerHTML = `
      <div class="flex items-center gap-3">
        <span class="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold ${isPositive ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}">
          ${isPositive ? '↓' : '↑'}
        </span>
        <div>
          <div class="font-bold text-xs text-gray-900">${tx.description || meta.label}</div>
          <div class="text-[11px] text-gray-400 font-mono">${dateFormatted}</div>
        </div>
      </div>
      <div class="font-bold text-xs font-mono ${color}">
        ${sign}${formatToman(tx.amount)}
      </div>
    `;
    container.appendChild(div);
  });
}

// ----------------------------------------------------------------------------
// Backups Management & Safe Restore
// ----------------------------------------------------------------------------
window.handleCreateBackup = async function() {
  try {
    const meta = await invoke('create_backup_cmd', { targetDir: './backups', projectName: currentProject?.name });
    const statusBox = document.getElementById('backupStatus');
    statusBox.classList.remove('hidden');
    statusBox.innerHTML = `
      <div class="font-bold text-green-700">✓ فایل پشتیبان ایمن ایجاد گردید</div>
      <div class="mt-1">نام فایل: <span class="font-mono text-gray-800">${meta.file_name}</span></div>
      <div class="mt-0.5">هش SHA-256: <span class="font-mono text-gray-600">${meta.sha256}</span></div>
    `;
    await loadBackupsList();
  } catch (err) {
    alert('خطا در ایجاد پشتیبان: ' + err);
  }
};

window.loadBackupsList = async function() {
  const tbody = document.getElementById('backupsListBody');
  if (!tbody) return;
  tbody.innerHTML = '<tr><td colspan="3" class="p-3 text-center text-gray-400">در حال دریافت لیست...</td></tr>';

  try {
    const list = await invoke('list_backups_cmd', { targetDir: './backups' });
    tbody.innerHTML = '';
    if (!list || list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="3" class="p-3 text-center text-gray-400">هیچ فایل پشتیبانی در پوشه یافت نشد</td></tr>';
      return;
    }
    list.forEach(b => {
      const kb = Math.round(b.file_size / 1024);
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td class="p-2 font-bold font-mono text-gray-800">${b.file_name}</td>
        <td class="p-2 font-mono text-gray-600">${toFaDigits(kb)} KB</td>
        <td class="p-2 font-mono text-gray-400 text-[10px]">${b.sha256.substring(0, 16)}...</td>
      `;
      tbody.appendChild(tr);
    });
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="3" class="p-3 text-center text-red-500">خطا: ${err}</td></tr>`;
  }
};

// ----------------------------------------------------------------------------
// Excel Import Wizard (3-Step Flow)
// ----------------------------------------------------------------------------
let currentExcelSheets = [];
let currentExcelReport = null;
let mappingRefreshTimeout = null;

function setExcelWizardStep(step) {
  const step1 = document.getElementById('excelWizardStep1');
  const step2 = document.getElementById('excelWizardStep2');
  const step3 = document.getElementById('excelWizardStep3');

  const ind1 = document.getElementById('wizardStepIndicator1');
  const ind2 = document.getElementById('wizardStepIndicator2');
  const ind3 = document.getElementById('wizardStepIndicator3');

  const btnBack = document.getElementById('btnExcelBack');
  const btnNext = document.getElementById('btnExcelNext');
  const btnCommit = document.getElementById('btnExcelCommit');
  const btnFinish = document.getElementById('btnExcelFinish');

  if (step === 1) {
    if (step1) step1.classList.remove('hidden');
    if (step2) step2.classList.add('hidden');
    if (step3) step3.classList.add('hidden');

    if (ind1) {
      ind1.className = 'flex items-center gap-2 text-blue-600 font-bold';
      const s = ind1.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-blue-600 text-white flex items-center justify-center text-[10px]';
    }
    if (ind2) {
      ind2.className = 'flex items-center gap-2 text-gray-500';
      const s = ind2.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-gray-300 text-gray-600 flex items-center justify-center text-[10px]';
    }
    if (ind3) {
      ind3.className = 'flex items-center gap-2 text-gray-500';
      const s = ind3.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-gray-300 text-gray-600 flex items-center justify-center text-[10px]';
    }

    if (btnBack) btnBack.classList.add('hidden');
    if (btnNext) btnNext.classList.remove('hidden');
    if (btnCommit) btnCommit.classList.add('hidden');
    if (btnFinish) btnFinish.classList.add('hidden');
  } else if (step === 2) {
    if (step1) step1.classList.add('hidden');
    if (step2) step2.classList.remove('hidden');
    if (step3) step3.classList.add('hidden');

    if (ind1) {
      ind1.className = 'flex items-center gap-2 text-green-600 font-bold';
      const s = ind1.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-green-600 text-white flex items-center justify-center text-[10px]';
    }
    if (ind2) {
      ind2.className = 'flex items-center gap-2 text-blue-600 font-bold';
      const s = ind2.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-blue-600 text-white flex items-center justify-center text-[10px]';
    }
    if (ind3) {
      ind3.className = 'flex items-center gap-2 text-gray-500';
      const s = ind3.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-gray-300 text-gray-600 flex items-center justify-center text-[10px]';
    }

    if (btnBack) btnBack.classList.remove('hidden');
    if (btnNext) btnNext.classList.add('hidden');
    if (btnCommit) {
      btnCommit.classList.remove('hidden');
      btnCommit.disabled = false;
      btnCommit.innerHTML = '<span>تأیید و وارد کردن قطعی تراکنش‌ها به دفتر ✓</span>';
    }
    if (btnFinish) btnFinish.classList.add('hidden');
  } else if (step === 3) {
    if (step1) step1.classList.add('hidden');
    if (step2) step2.classList.add('hidden');
    if (step3) step3.classList.remove('hidden');

    if (ind1) {
      ind1.className = 'flex items-center gap-2 text-green-600 font-bold';
      const s = ind1.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-green-600 text-white flex items-center justify-center text-[10px]';
    }
    if (ind2) {
      ind2.className = 'flex items-center gap-2 text-green-600 font-bold';
      const s = ind2.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-green-600 text-white flex items-center justify-center text-[10px]';
    }
    if (ind3) {
      ind3.className = 'flex items-center gap-2 text-green-600 font-bold';
      const s = ind3.querySelector('span');
      if (s) s.className = 'w-5 h-5 rounded-full bg-green-600 text-white flex items-center justify-center text-[10px]';
    }

    if (btnBack) btnBack.classList.add('hidden');
    if (btnNext) btnNext.classList.add('hidden');
    if (btnCommit) btnCommit.classList.add('hidden');
    if (btnFinish) btnFinish.classList.remove('hidden');
  }
}

window.handleInspectExcel = async function() {
  const path = document.getElementById('excelFilePath').value.trim();
  if (!path) {
    alert('لطفاً مسیر فایل اکسل را مشخص کنید.');
    return;
  }
  const area = document.getElementById('excelStep1SheetArea');
  const select = document.getElementById('excelSheetSelect');
  const btnNext = document.getElementById('btnExcelNext');

  try {
    const sheets = await invoke('inspect_excel_cmd', { path });
    currentExcelSheets = sheets || [];
    if (currentExcelSheets.length === 0) {
      alert('هیچ شیتی در فایل اکسل یافت نشد.');
      return;
    }
    select.innerHTML = currentExcelSheets.map((s, idx) => `
      <option value="${s.name}" ${idx === 0 ? 'selected' : ''}>
        ${s.name} (${toFaDigits(s.row_count)} سطر، ${toFaDigits(s.col_count)} ستون)
      </option>
    `).join('');

    if (area) area.classList.remove('hidden');
    if (btnNext) btnNext.classList.remove('hidden');
  } catch (err) {
    alert('خطا در خواندن فایل اکسل: ' + err);
  }
};

window.handleSelectExcelSheet = function() {
  currentExcelReport = null;
};

window.handleExcelWizardNext = async function() {
  const path = document.getElementById('excelFilePath').value.trim();
  const select = document.getElementById('excelSheetSelect');
  const sheetName = select ? select.value : '';

  if (!path || !sheetName) {
    alert('لطفاً ابتدا فایل و شیت مورد نظر را مشخص کنید.');
    return;
  }
  if (!currentProjectId) {
    alert('هیچ پروژه‌ای انتخاب نشده است. لطفاً ابتدا پروژه مقصد را انتخاب کنید.');
    return;
  }

  const btnNext = document.getElementById('btnExcelNext');
  if (btnNext) {
    btnNext.disabled = true;
    btnNext.textContent = 'در حال تحلیل شیت و نگاشت ستون‌ها...';
  }

  try {
    const report = await invoke('preview_excel_import_cmd', {
      path,
      sheetName,
      mapping: null,
      projectId: currentProjectId,
      limit: 15
    });

    currentExcelReport = report;

    // Update Counters
    const elValid = document.getElementById('prevValidCount');
    const elTotal = document.getElementById('prevTotalAmount');
    const elInvalid = document.getElementById('prevInvalidCount');
    const elParties = document.getElementById('prevPartiesCount');

    if (elValid) elValid.textContent = toFaDigits(report.valid_rows_count);
    if (elTotal) elTotal.textContent = formatToman(report.total_amount_toman);
    if (elInvalid) elInvalid.textContent = toFaDigits(report.invalid_rows_count);
    if (elParties) elParties.textContent = toFaDigits(report.identified_parties.length) + ' نفر';

    // Populate Column Mapping Dropdowns
    const currentSheetMeta = currentExcelSheets.find(s => s.name === sheetName);
    const headers = (currentSheetMeta && currentSheetMeta.sample_headers && currentSheetMeta.sample_headers.length > 0)
      ? currentSheetMeta.sample_headers
      : [];

    populateMappingSelects(headers, report.detected_mapping);

    // Populate Preview Rows Table
    renderExcelPreviewRows(report.sample_rows);

    setExcelWizardStep(2);
  } catch (err) {
    alert('خطا در پیش‌نمایش فایل اکسل: ' + err);
  } finally {
    if (btnNext) {
      btnNext.disabled = false;
      btnNext.textContent = 'مرحله بعد: بازبینی و نگاشت ستون‌ها →';
    }
  }
};

function populateMappingSelects(headers, mapping) {
  const mappingFields = [
    { id: 'mapColDate', val: mapping?.date_col },
    { id: 'mapColDesc', val: mapping?.desc_col },
    { id: 'mapColAmount', val: mapping?.amount_col },
    { id: 'mapColType', val: mapping?.type_col },
    { id: 'mapColParty', val: mapping?.party_col },
    { id: 'mapColAccount', val: mapping?.account_col }
  ];

  mappingFields.forEach(({ id, val }) => {
    const el = document.getElementById(id);
    if (!el) return;
    let html = '<option value="">-- بدون ستون --</option>';
    headers.forEach((h, idx) => {
      const isSelected = val === idx;
      const title = h ? `ستون ${toFaDigits(idx + 1)}: ${h}` : `ستون ${toFaDigits(idx + 1)}`;
      html += `<option value="${idx}" ${isSelected ? 'selected' : ''}>${title}</option>`;
    });
    el.innerHTML = html;
    el.onchange = handleMappingChange;
  });
}

function getExcelCurrentMapping() {
  const parseVal = (id) => {
    const el = document.getElementById(id);
    if (!el || el.value === '' || el.value === null) return null;
    const n = parseInt(el.value, 10);
    return isNaN(n) ? null : n;
  };
  return {
    date_col: parseVal('mapColDate'),
    desc_col: parseVal('mapColDesc'),
    amount_col: parseVal('mapColAmount'),
    type_col: parseVal('mapColType'),
    party_col: parseVal('mapColParty'),
    account_col: parseVal('mapColAccount'),
    partner_col: null,
    has_header: document.getElementById('excelHasHeader')?.checked ?? true
  };
}

async function handleMappingChange() {
  if (mappingRefreshTimeout) clearTimeout(mappingRefreshTimeout);
  mappingRefreshTimeout = setTimeout(async () => {
    const path = document.getElementById('excelFilePath').value.trim();
    const select = document.getElementById('excelSheetSelect');
    const sheetName = select ? select.value : '';
    const mapping = getExcelCurrentMapping();

    try {
      const report = await invoke('preview_excel_import_cmd', {
        path,
        sheetName,
        mapping,
        projectId: currentProjectId,
        limit: 15
      });
      currentExcelReport = report;
      const elValid = document.getElementById('prevValidCount');
      const elTotal = document.getElementById('prevTotalAmount');
      const elInvalid = document.getElementById('prevInvalidCount');
      const elParties = document.getElementById('prevPartiesCount');

      if (elValid) elValid.textContent = toFaDigits(report.valid_rows_count);
      if (elTotal) elTotal.textContent = formatToman(report.total_amount_toman);
      if (elInvalid) elInvalid.textContent = toFaDigits(report.invalid_rows_count);
      if (elParties) elParties.textContent = toFaDigits(report.identified_parties.length) + ' نفر';

      renderExcelPreviewRows(report.sample_rows);
    } catch (err) {
      console.error('Mapping update preview error:', err);
    }
  }, 300);
}

function renderExcelPreviewRows(rows) {
  const tbody = document.getElementById('excelPreviewTableBody');
  if (!tbody) return;
  if (!rows || rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" class="p-4 text-center text-gray-400">سطری برای نمایش وجود ندارد</td></tr>';
    return;
  }

  tbody.innerHTML = rows.map(r => {
    const txTypeMap = {
      'work_in': '<span class="text-blue-700 font-bold">کارکرد (درآمد)</span>',
      'expense': '<span class="text-rose-700 font-bold">هزینه کارگاه</span>',
      'payout': '<span class="text-purple-700 font-bold">تسویه شریک/پرسنل</span>',
      'income': '<span class="text-teal-700 font-bold">دریافتی کارفرما</span>',
      'work_out': '<span class="text-indigo-700 font-bold">کارکرد راننده</span>',
      'transfer': '<span class="text-amber-700 font-bold">انتقال داخلی</span>',
    };
    const typeLabel = txTypeMap[r.tx_type] || r.tx_type;
    const amtStr = r.amount ? formatToman(r.amount) : '<span class="text-gray-400">–</span>';

    let statusBadge = '';
    if (r.is_valid) {
      statusBadge = '<span class="px-2 py-0.5 rounded-md bg-green-100 text-green-800 text-[10px] font-bold">✓ آماده ورود</span>';
    } else if (r.is_duplicate) {
      statusBadge = '<span class="px-2 py-0.5 rounded-md bg-amber-100 text-amber-800 text-[10px] font-bold">تکراری (ثبت شده)</span>';
    } else {
      statusBadge = `<span class="px-2 py-0.5 rounded-md bg-rose-100 text-rose-800 text-[10px] font-bold" title="${r.error_message || ''}">✗ ${r.error_message || 'بدون مبلغ'}</span>`;
    }

    return `
      <tr class="hover:bg-gray-50 border-b border-gray-100 text-right">
        <td class="p-2 text-gray-500 font-mono">${toFaDigits(r.row_index)}</td>
        <td class="p-2 text-gray-700 whitespace-nowrap font-mono">${r.raw_date || '–'}</td>
        <td class="p-2 whitespace-nowrap">${typeLabel}</td>
        <td class="p-2 font-bold text-gray-900 whitespace-nowrap font-mono">${amtStr}</td>
        <td class="p-2 text-gray-800 font-bold">${r.party_name || r.partner_name || '–'}</td>
        <td class="p-2 text-gray-600">${r.account_name || '–'}</td>
        <td class="p-2 text-gray-500 max-w-xs truncate" title="${r.description}">${r.description || '–'}</td>
        <td class="p-2 text-center whitespace-nowrap">${statusBadge}</td>
      </tr>
    `;
  }).join('');
}

window.handleExcelWizardBack = function() {
  setExcelWizardStep(1);
};

window.handleCommitExcelImport = async function() {
  const path = document.getElementById('excelFilePath').value.trim();
  const select = document.getElementById('excelSheetSelect');
  const sheetName = select ? select.value : '';
  const mapping = getExcelCurrentMapping();

  if (!path || !sheetName) {
    alert('اطلاعات شیت اکسل نامعتبر است.');
    return;
  }
  if (!currentProjectId) {
    alert('پروژه مقصد انتخاب نشده است.');
    return;
  }

  const btnCommit = document.getElementById('btnExcelCommit');
  if (btnCommit) {
    btnCommit.disabled = true;
    btnCommit.innerHTML = '<span>در حال درج تراکنش‌ها و ثبت در ترازنامه پایگاه‌داده...</span>';
  }

  try {
    const result = await invoke('commit_excel_import_cmd', {
      path,
      sheetName,
      mapping,
      projectId: currentProjectId
    });

    // Populate Step 3 Success Results
    const elProc = document.getElementById('resTotalProcessed');
    const elImp = document.getElementById('resImportedCount');
    const elDup = document.getElementById('resDuplicatesSkipped');
    const elInv = document.getElementById('resInvalidSkipped');
    const elAmt = document.getElementById('resTotalAmount');
    const elParties = document.getElementById('resNewParties');

    if (elProc) elProc.textContent = toFaDigits(result.total_rows_processed);
    if (elImp) elImp.textContent = toFaDigits(result.imported_count);
    if (elDup) elDup.textContent = toFaDigits(result.duplicates_skipped);
    if (elInv) elInv.textContent = toFaDigits(result.invalid_skipped);
    if (elAmt) elAmt.textContent = formatToman(result.total_imported_amount);
    if (elParties) elParties.textContent = `${toFaDigits(result.new_parties_created)} طرف‌حساب جدید، ${toFaDigits(result.new_accounts_created)} حساب`;

    setExcelWizardStep(3);
  } catch (err) {
    alert('خطا در ثبت تراکنش‌ها در پایگاه‌داده: ' + err);
    if (btnCommit) {
      btnCommit.disabled = false;
      btnCommit.innerHTML = '<span>تأیید و وارد کردن قطعی تراکنش‌ها به دفتر ✓</span>';
    }
  }
};

window.handleFinishExcelImport = async function() {
  window.closeModal('modalExcel');
  await refreshApp();
  window.switchTab('transactions');
};

// ----------------------------------------------------------------------------
// Form Handlers
// ----------------------------------------------------------------------------
function setupFormHandlers() {
  const txFilter = document.getElementById('txFilterType');
  if (txFilter) txFilter.onchange = filterAndRenderTransactions;

  const txSearch = document.getElementById('txSearchInput');
  if (txSearch) txSearch.oninput = filterAndRenderTransactions;

  // 1. New Transaction Form
  const formNewTx = document.getElementById('formNewTx');
  if (formNewTx) {
    formNewTx.onsubmit = async (e) => {
      e.preventDefault();
      const type = document.getElementById('txInputType').value;
      const amount = parseTomanInput(document.getElementById('txInputAmount').value);
      const dateInput = document.getElementById('txInputDate').value;
      const desc = document.getElementById('txInputDesc').value.trim();

      if (!amount || amount <= 0) {
        alert('مبلغ باید بزرگ‌تر از صفر باشد.');
        return;
      }

      let dateIso = dateInput.trim();
      if (dateInput.includes('/')) {
        const parts = normalizeDigits(dateInput).split('/');
        if (parts.length === 3) {
          try {
            dateIso = await invoke('jalali_to_iso_val', {
              y: parseInt(parts[0], 10),
              m: parseInt(parts[1], 10),
              d: parseInt(parts[2], 10),
            });
          } catch {
            dateIso = '2026-11-07';
          }
        }
      }

      const valOrNull = (id) => {
        const el = document.getElementById(id);
        const v = el ? el.value.trim() : '';
        return v ? v : null;
      };

      const clientId = (type === 'work_in' || type === 'income') ? valOrNull('txInputClient') : null;
      const personId = (type === 'work_out' || type === 'payout') ? valOrNull('txInputPerson') : null;
      const cashAccountId = (type === 'income' || type === 'expense' || type === 'payout') ? valOrNull('txInputCashAccount') : null;
      const fromAccountId = type === 'transfer' ? valOrNull('txInputFromAccount') : null;
      const toAccountId = type === 'transfer' ? valOrNull('txInputToAccount') : null;
      const purpose = type === 'payout' ? valOrNull('txInputPurpose') : null;
      const overrideReason = type === 'payout' ? valOrNull('txInputOverride') : null;

      // Accounting Integrity Validations (Standard 43 / Accounter)
      if ((type === 'work_in' || type === 'income') && !clientId) {
        alert('انتخاب کارفرما برای این تراکنش الزامی است.');
        return;
      }
      if ((type === 'work_out' || type === 'payout') && !personId) {
        alert('انتخاب طرف‌حساب برای این تراکنش الزامی است.');
        return;
      }
      if ((type === 'income' || type === 'expense' || type === 'payout') && !cashAccountId) {
        alert('انتخاب حساب بانکی یا صندوق برای این تراکنش الزامی است.');
        return;
      }
      if (type === 'transfer' && (!fromAccountId || !toAccountId || fromAccountId === toAccountId)) {
        alert('برای انتقال وجه باید دو حساب متفاوت (مبدأ و مقصد) انتخاب شوند.');
        return;
      }

      const txPayload = {
        project_id: currentProjectId,
        tx_type: type,
        amount,
        date: dateIso,
        description: desc || null,
        client_id: clientId,
        person_id: personId,
        cash_account_id: cashAccountId,
        from_account_id: fromAccountId,
        to_account_id: toAccountId,
        purpose,
        override_reason: overrideReason,
      };

      try {
        await invoke('create_transaction', { tx: txPayload });
        window.closeModal('modalNewTx');
        await loadProjectBalance();
        await loadTransactions();
      } catch (err) {
        alert('خطا در ثبت تراکنش: ' + err);
      }
    };
  }

  // 2. New Project Form
  const formNewProject = document.getElementById('formNewProject');
  if (formNewProject) {
    formNewProject.onsubmit = async (e) => {
      e.preventDefault();
      const name = document.getElementById('projInputName').value.trim();
      const startDate = document.getElementById('projInputStartDate').value.trim() || null;
      const endDate = document.getElementById('projInputEndDate').value.trim() || null;

      if (!name) {
        alert('نام پروژه الزامی است.');
        return;
      }

      try {
        const created = await invoke('create_project', {
          name,
          startDate,
          endDate,
          start_date: startDate,
          end_date: endDate,
        });
        window.closeModal('modalNewProject');
        await loadProjects();
        window.selectActiveProject(created.id);
      } catch (err) {
        alert('خطا در ایجاد پروژه: ' + err);
      }
    };
  }

  // 3. New Person Form
  const formNewPerson = document.getElementById('formNewPerson');
  if (formNewPerson) {
    formNewPerson.onsubmit = async (e) => {
      e.preventDefault();
      const name = document.getElementById('personInputName').value.trim();
      const kind = document.getElementById('personInputKind').value;
      const code = document.getElementById('personInputCode').value.trim() || null;
      const note = document.getElementById('personInputNote').value.trim() || null;

      if (!name) {
        alert('نام شخص الزامی است.');
        return;
      }

      try {
        await invoke('create_person', {
          name,
          kind,
          phone: code,
          nationalId: null,
          notes: note,
        });
        window.closeModal('modalNewPerson');
        await loadPersons();
      } catch (err) {
        alert('خطا در افزودن شخص: ' + err);
      }
    };
  }

  // 4. New Cash Account Form
  const formNewAccount = document.getElementById('formNewAccount');
  if (formNewAccount) {
    formNewAccount.onsubmit = async (e) => {
      e.preventDefault();
      const name = document.getElementById('accInputName').value.trim();
      const kind = document.getElementById('accInputKind').value;
      const holder = kind === 'personal' ? document.getElementById('accInputHolder').value : null;

      if (!name) {
        alert('نام حساب الزامی است.');
        return;
      }

      try {
        await invoke('create_cash_account', {
          name,
          kind,
          holderPersonId: holder,
          projectId: currentProjectId,
        });
        await loadCashAccounts();
        renderAccountsModal();
      } catch (err) {
        alert('خطا در تعریف حساب: ' + err);
      }
    };
  }

  // 5. Fiscal Year Rollover Form
  const formRollover = document.getElementById('formRollover');
  if (formRollover) {
    formRollover.onsubmit = async (e) => {
      e.preventDefault();
      const targetName = document.getElementById('rolloverTargetName').value.trim();
      const startDate = document.getElementById('rolloverStartDate').value.trim() || '۱۴۰۶/۰۱/۰۱';
      const lockSource = document.getElementById('rolloverLockSource')?.checked ?? true;

      if (!targetName) {
        alert('نام سال مالی جدید الزامی است.');
        return;
      }

      try {
        const srcId = window._rolloverSourceProjectId || currentProjectId;
        const created = await invoke('rollover_project_cmd', {
          sourceProjectId: srcId,
          targetName: targetName,
          startDate: startDate,
          lockSource: lockSource,
        });
        window.closeModal('modalFiscalYears');
        await loadProjects();
        if (created && created.id) {
          window.selectActiveProject(created.id);
        }
        if (typeof window.renderFiscalYearsTab === 'function') {
          await window.renderFiscalYearsTab();
        }
        alert('سال مالی جدید با موفقیت ایجاد گردید و اسناد افتتاحیه منتقل شدند.');
      } catch (err) {
        alert('خطا در بستن دوره و افتتاح سال جدید: ' + err);
      }
    };
  }

  // 5b. Inline New Cash Account Form
  const formInlineAcc = document.getElementById('formNewAccountInline');
  if (formInlineAcc) {
    formInlineAcc.onsubmit = async (e) => {
      e.preventDefault();
      const name = document.getElementById('accInlineName').value.trim();
      const kind = document.getElementById('accInlineKind').value;
      const holder = kind === 'personal' ? (document.getElementById('accInlineHolder').value || null) : null;
      if (!name) return;
      try {
        await invoke('create_cash_account', {
          name,
          kind,
          code: null,
          holderPersonId: holder,
        });
        window.closeNewAccountInlineForm();
        await window.renderAccountsTab();
        await loadCashAccounts();
        alert('حساب یا صندوق جدید با موفقیت تعریف گردید.');
      } catch (err) {
        alert('خطا در ایجاد حساب: ' + err);
      }
    };
  }

  // 5c. Project Settings & Partner Shares Form
  const formProjSettings = document.getElementById('formProjectSettingsAndShares');
  if (formProjSettings) {
    formProjSettings.onsubmit = window.handleSaveProjectSettingsAndShares;
  }

  // 6. Custom Date Filter Form
  const formCustomDate = document.getElementById('formCustomDate');
  if (formCustomDate) {
    formCustomDate.onsubmit = async (e) => {
      e.preventDefault();
      const start = document.getElementById('custDateStart').value.trim();
      const end = document.getElementById('custDateEnd').value.trim();

      currentReportDateFilter = {
        preset: 'custom',
        startIso: start.replaceAll('/', '-'),
        endIso: end.replaceAll('/', '-'),
        label: `از ${start} تا ${end}`,
      };

      const periodLabel = document.getElementById('reportPeriodLabel');
      if (periodLabel) periodLabel.textContent = `صورت وضعیت مالی — بازه گزارش: ${currentReportDateFilter.label}`;
      window.closeModal('modalCustomDate');
      await loadProjectBalance();
    };
  }

  // 7. Confirm Soft Delete
  const btnConfirmDelete = document.getElementById('btnConfirmDelete');
  if (btnConfirmDelete) {
    btnConfirmDelete.onclick = async () => {
      const txId = document.getElementById('deleteTxId').value;
      const reason = document.getElementById('deleteTxReason').value.trim();
      if (!reason) {
        alert('ثبت دلیل حذف تراکنش الزامی است.');
        return;
      }
      try {
        await invoke('soft_delete_transaction', { txId, deletedReason: reason });
        window.closeModal('modalDeleteTx');
        await loadProjectBalance();
        await loadTransactions();
      } catch (err) {
        alert('خطا در حذف تراکنش: ' + err);
      }
    };
  }
}

// ----------------------------------------------------------------------------
// Refresh Application
// ----------------------------------------------------------------------------
async function refreshApp() {
  await loadProjects();
  await loadPersons();
  await loadCashAccounts();
  if (currentProjectId) {
    await loadProjectBalance();
    await loadTransactions();
  }
}
window.refreshApp = refreshApp;

// ----------------------------------------------------------------------------
// Init Entrypoint
// ----------------------------------------------------------------------------
function init() {
  setupTabs();
  setupFormHandlers();
  refreshApp();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
