/**
 * ============================================================================
 * PRODUCTION TASK BOARD - FRONTEND CLIENT & CONTROLLER
 * ============================================================================
 */

// Application Defaults & Fallbacks
const FALLBACK_CONFIG = {
  taskTypes: [
    "Photos", "Video", "Design", "Carousel Photos",
    "Carousel Video", "Match Coverage", "Script", "Presentation"
  ],
  graphicSizes: [
    "Reel 9:16", "Wide 16:9", "Square 1:1", "Portrait 3:4", "Portrait 4:5"
  ],
  clients: [
    "MINNOWS", "Palm Hills", "APT Padel", "Potential Client / Pitching"
  ],
  priorities: [
    "Low", "Medium", "High", "Urgent"
  ],
  statuses: [
    "Not Started", "Work in Progress", "Submitted for Review", "Completed"
  ],
  taskCategories: [
    "New Task", "Existing Task"
  ],
  departments: [
    "Social", "Marketing"
  ]
};

const FALLBACK_SUPABASE = {
  url: 'https://ldsevaytazsnfvsdxrno.supabase.co',
  anonKey: 'sb_publishable_W2y6fRzN9rJRN_Gn0wRXBA_dD4ybYRv'
};

// Application State
let supabaseClient = null;
let isConnected = false;
let tasks = [];
let filteredTasks = [];
let config = Object.assign({}, FALLBACK_CONFIG, window.DEFAULT_CONFIG || {});
if (!config.statuses || !Array.isArray(config.statuses) || !config.statuses.length) {
  config.statuses = FALLBACK_CONFIG.statuses.slice();
}
let activeView = 'board';
let currentTaskId = null; // internal UUID or ID
let sortCol = 'taskId';
let sortAsc = true;
let realtimeChannel = null;
let revChannel = null;
let revisions = {};        // taskId -> [saved edits]
let revisionsReady = true; // false when the task_revisions table is missing
let revDraft = null;       // unsaved new edit for the open task
let revDirty = false;      // user is typing in the Edits panel

// DOM Helper
const $ = (id) => document.getElementById(id);
const el = (tag, cls = '', text = null) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== null && text !== undefined) e.textContent = text;
  return e;
};
const isUrl = (s) => /^https?:\/\//i.test(String(s || '').trim());

// Field mapping between JS camelCase and DB snake_case & Form IDs
const FIELD_DEFS = [
  { js: 'taskName', db: 'task_name', form: 'form-name', required: true },
  { js: 'description', db: 'description', form: 'form-description' },
  { js: 'copyMessage', db: 'copy_message', form: 'form-copy' },
  { js: 'department', db: 'department', form: 'form-dept', required: true },
  { js: 'taskCategory', db: 'task_category', form: 'form-category', required: true },
  { js: 'owner', db: 'owner', form: 'form-owner' },
  { js: 'assignedTo', db: 'assigned_to', form: 'form-assigned' },
  { js: 'client', db: 'client', form: 'form-client' },
  { js: 'taskType', db: 'task_type', form: 'form-type' },
  { js: 'graphicSize', db: 'graphic_size', form: 'form-size' },
  { js: 'priority', db: 'priority', form: 'form-priority' },
  { js: 'status', db: 'status', form: 'form-status' },
  { js: 'dueDate', db: 'due_date', form: 'form-due', isDate: true },
  { js: 'postingDate', db: 'posting_date', form: 'form-posting', isDate: true },
  { js: 'brandGuidelineLink', db: 'brand_guideline_link', form: 'form-brand-link' },
  { js: 'brandGuidelineNote', db: 'brand_guideline_note', form: 'form-brand-note' },
  { js: 'referenceLink', db: 'reference_link', form: 'form-reference' },
  { js: 'referenceNote', db: 'reference_note', form: 'form-reference-note' },
  { js: 'sourceLink', db: 'source_link', form: 'form-source' },
  { js: 'sourceNote', db: 'source_note', form: 'form-source-note' },
  { js: 'finishedLink', db: 'finished_link', form: 'form-finished' },
  { js: 'finishedNote', db: 'finished_note', form: 'form-finished-note' }
];

// Sample Initial Demo Tasks (Used when Supabase is not configured yet)
const DEMO_TASKS = [
  {
    id: 'demo-1',
    taskId: 'T-0001',
    taskName: 'Summer Campaign Teaser Reel',
    description: 'Create an energetic 15s teaser for the upcoming summer tournament.',
    copyMessage: 'Get ready for the biggest padel showdown this summer! 🎾🔥',
    department: 'Social',
    taskCategory: 'New Task',
    owner: 'Ahmed Salem',
    assignedTo: 'Karim Omar',
    client: 'APT Padel',
    taskType: 'Reel 9:16',
    graphicSize: 'Reel 9:16',
    priority: 'Urgent',
    status: 'Work in Progress',
    dueDate: getRelativeDate(2),
    postingDate: getRelativeDate(4),
    brandGuidelineLink: 'https://drive.google.com',
    brandGuidelineNote: 'Use primary brand palette',
    referenceLink: 'https://instagram.com',
    referenceNote: 'Similar pacing to 2023 teaser',
    sourceLink: 'https://dropbox.com',
    sourceNote: 'Raw footage in /Tournaments/Summer',
    finishedLink: '',
    finishedNote: ''
  },
  {
    id: 'demo-2',
    taskId: 'T-0002',
    taskName: 'Palm Hills Community Match Coverage',
    description: 'Edit 4 photo highlights and 1 recap carousel from community match.',
    copyMessage: 'Unforgettable moments on the court today! 🌟',
    department: 'Marketing',
    taskCategory: 'Existing Task',
    owner: 'Sara Nabil',
    assignedTo: 'Mona Zaki',
    client: 'Palm Hills',
    taskType: 'Carousel Photos',
    graphicSize: 'Square 1:1',
    priority: 'High',
    status: 'Submitted for Review',
    dueDate: getRelativeDate(1),
    postingDate: getRelativeDate(3),
    brandGuidelineLink: 'https://drive.google.com',
    brandGuidelineNote: '',
    referenceLink: '',
    referenceNote: '',
    sourceLink: 'https://drive.google.com',
    sourceNote: '',
    finishedLink: 'https://drive.google.com',
    finishedNote: 'Review draft v1'
  },
  {
    id: 'demo-3',
    taskId: 'T-0003',
    taskName: 'Minnows Brand Launch Graphic',
    description: 'Main banner design for Minnows product launch campaign across digital ads.',
    copyMessage: 'Pure freshness in every drop. Discover Minnows now.',
    department: 'Social',
    taskCategory: 'New Task',
    owner: 'Alaadin',
    assignedTo: 'Tamer Hosny',
    client: 'MINNOWS',
    taskType: 'Design',
    graphicSize: 'Wide 16:9',
    priority: 'Medium',
    status: 'Not Started',
    dueDate: getRelativeDate(5),
    postingDate: getRelativeDate(7),
    brandGuidelineLink: 'https://brand.minnows.com',
    brandGuidelineNote: 'Use new vector logo',
    referenceLink: 'https://pinterest.com',
    referenceNote: 'Modern minimal aesthetic',
    sourceLink: '',
    sourceNote: '',
    finishedLink: '',
    finishedNote: ''
  },
  {
    id: 'demo-4',
    taskId: 'T-0004',
    taskName: 'Sponsorship Presentation Pitch Deck',
    description: 'Prepare the 12-slide pitch deck for prospective partners.',
    copyMessage: '',
    department: 'Marketing',
    taskCategory: 'New Task',
    owner: 'Sara Nabil',
    assignedTo: 'Ahmed Salem',
    client: 'Potential Client / Pitching',
    taskType: 'Presentation',
    graphicSize: 'Wide 16:9',
    priority: 'Low',
    status: 'Completed',
    dueDate: getRelativeDate(-1),
    postingDate: getRelativeDate(10),
    brandGuidelineLink: '',
    brandGuidelineNote: '',
    referenceLink: '',
    referenceNote: '',
    sourceLink: 'https://drive.google.com',
    sourceNote: 'Partner specs',
    finishedLink: 'https://canva.com',
    finishedNote: 'Final PDF exported'
  }
];

function getRelativeDate(daysOffset) {
  const d = new Date();
  d.setDate(d.getDate() + daysOffset);
  return d.toISOString().split('T')[0];
}

// Toast System
let toastTimer;
function showToast(msg, type = 'info') {
  const t = $('toast');
  t.textContent = msg;
  t.className = 'toast show';
  if (type === 'error') t.classList.add('error');
  if (type === 'success') t.classList.add('success');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.className = 'toast'; }, 3500);
}

// Date helpers
function formatIsoToDisplay(isoStr) {
  if (!isoStr) return '';
  try {
    const parts = String(isoStr).split('T')[0].split('-');
    if (parts.length === 3) {
      return `${parts[2]}/${parts[1]}/${parts[0]}`; // DD/MM/YYYY
    }
  } catch (e) {}
  return String(isoStr);
}

function parseDateToIso(val) {
  if (!val) return null;
  val = String(val).trim();
  // If already YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}$/.test(val)) return val;
  // If DD/MM/YYYY
  const parts = val.split('/');
  if (parts.length === 3) {
    const y = parts[2].padStart(4, '20');
    const m = parts[1].padStart(2, '0');
    const d = parts[0].padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return val;
}

function isTaskOverdue(t) {
  if (t.status === 'Completed' || !t.dueDate) return false;
  const iso = parseDateToIso(t.dueDate);
  if (!iso) return false;
  const due = new Date(iso + 'T23:59:59');
  return due.getTime() < Date.now();
}

/* -------------------------------------------------------------------------- */
/* SUPABASE CLIENT & INITIALIZATION                                           */
/* -------------------------------------------------------------------------- */
function getSupabaseCredentials() {
  const storedUrl = localStorage.getItem('sb_url') || (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.url) || FALLBACK_SUPABASE.url;
  const storedKey = localStorage.getItem('sb_key') || (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.anonKey) || FALLBACK_SUPABASE.anonKey;
  let cleanUrl = String(storedUrl || '').trim();
  cleanUrl = cleanUrl.replace(/\/rest\/v1\/?$/i, '').replace(/\/+$/, '');
  return {
    url: cleanUrl,
    key: String(storedKey || '').trim()
  };
}

async function initSupabase() {
  const creds = getSupabaseCredentials();

  if (creds.url && creds.key && window.supabase) {
    try {
      supabaseClient = window.supabase.createClient(creds.url, creds.key);
      // Quick test query to verify table access
      const { data, error } = await supabaseClient.from('tasks').select('id').limit(1);

      if (error) {
        console.warn('Supabase query error:', error);
        setConnectionState(false, 'Supabase error: ' + error.message);
      } else {
        setConnectionState(true, 'Supabase Connected 🟢');
        setupRealtimeSubscription();
        await loadDynamicSettings();
        await refreshData();
        return;
      }
    } catch (e) {
      console.error('Supabase init failed:', e);
      setConnectionState(false, 'Connection failed');
    }
  }

  // Fallback to Demo Mode
  setConnectionState(false, 'Demo Mode (Offline)');
  loadDemoTasks();
}

function setConnectionState(connected, text) {
  isConnected = connected;
  const badge = $('conn-badge');
  const badgeText = $('conn-status-text');
  const banner = $('setup-banner');

  badgeText.textContent = text;
  badge.className = 'conn-badge ' + (connected ? 'connected' : 'demo');
  banner.style.display = connected ? 'none' : 'flex';
}

function setupRealtimeSubscription() {
  if (!supabaseClient) return;
  try {
    if (realtimeChannel) supabaseClient.removeChannel(realtimeChannel);

    realtimeChannel = supabaseClient
      .channel('tasks-live-channel')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' }, (payload) => {
        console.log('Realtime update received:', payload);
        refreshData(true); // silent refresh
      })
      .subscribe();

    // Separate channel so a problem with edits can never affect task updates
    if (revChannel) supabaseClient.removeChannel(revChannel);
    revChannel = supabaseClient
      .channel('revisions-live-channel')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task_revisions' }, () => {
        refreshData(true);
      })
      .subscribe();
  } catch (err) {
    console.warn('Realtime subscribe warning:', err);
  }
}

async function loadDynamicSettings() {
  if (!supabaseClient) return;
  try {
    const { data } = await supabaseClient.from('app_settings').select('value').eq('key', 'dropdowns').single();
    if (data && data.value) {
      Object.keys(data.value).forEach((k) => {
        if (Array.isArray(data.value[k]) && data.value[k].length) {
          config[k] = data.value[k];
        }
      });
      fillDropdowns();
    }
  } catch (e) {
    // Keep defaults
  }
}

function loadDemoTasks() {
  const local = localStorage.getItem('demo_tasks');
  if (local) {
    try {
      tasks = JSON.parse(local);
    } catch (e) {
      tasks = DEMO_TASKS.slice();
    }
  } else {
    tasks = DEMO_TASKS.slice();
    localStorage.setItem('demo_tasks', JSON.stringify(tasks));
  }
  loadRevisionsLocal();
  applyFilters();
  refreshRevisionPanel();
}

/* -------------------------------------------------------------------------- */
/* DATA FETCHING & SYNCHRONIZATION                                            */
/* -------------------------------------------------------------------------- */
async function refreshData(silent = false) {
  if (!silent) showToast('Syncing tasks...', 'info');

  if (isConnected && supabaseClient) {
    try {
      const { data, error } = await supabaseClient
        .from('tasks')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;

      tasks = (data || []).map((row) => {
        const item = { id: row.id, taskId: row.task_id };
        FIELD_DEFS.forEach((f) => {
          item[f.js] = row[f.db] !== null && row[f.db] !== undefined ? String(row[f.db]) : '';
        });
        return item;
      });

      await loadRevisions();
      applyFilters();
      refreshRevisionPanel();
      if (!silent) showToast(`Synced ${tasks.length} tasks from Supabase`, 'success');
      return;
    } catch (err) {
      console.error('Fetch tasks error:', err);
      showToast('Could not fetch from Supabase: ' + err.message, 'error');
    }
  }

  // Demo fallback
  loadDemoTasks();
  if (!silent) showToast('Refreshed local demo data', 'info');
}

/* -------------------------------------------------------------------------- */
/* DROPDOWNS & FILTERS                                                        */
/* -------------------------------------------------------------------------- */
function populateSelect(id, options, includeAll = false, allLabel = '') {
  const s = $(id);
  if (!s) return;
  const currentVal = s.value;
  s.innerHTML = '';
  if (includeAll) {
    const o = el('option', '', allLabel);
    o.value = '';
    s.appendChild(o);
  }
  (options || []).forEach((opt) => {
    const o = el('option', '', opt);
    o.value = opt;
    s.appendChild(o);
  });
  if (currentVal) s.value = currentVal;
}

function fillDropdowns() {
  populateSelect('form-client', config.clients);
  populateSelect('form-type', config.taskTypes);
  populateSelect('form-size', config.graphicSizes);
  populateSelect('form-priority', config.priorities);
  populateSelect('form-status', config.statuses);
  populateSelect('form-category', config.taskCategories);
  populateSelect('form-dept', config.departments);

  populateSelect('filter-client', config.clients, true, 'All Clients');
  populateSelect('filter-type', config.taskTypes, true, 'All Task Types');
  populateSelect('filter-priority', config.priorities, true, 'All Priorities');
  populateSelect('filter-status', config.statuses, true, 'All Statuses');
  populateSelect('filter-dept', config.departments, true, 'All Depts');
  populateSelect('filter-category', config.taskCategories, true, 'All Categories');
}

function applyFilters() {
  const q = $('filter-search').value.toLowerCase().trim();
  const client = $('filter-client').value;
  const dept = $('filter-dept').value;
  const cat = $('filter-category').value;
  const type = $('filter-type').value;
  const status = $('filter-status').value;
  const prio = $('filter-priority').value;
  const asg = $('filter-assigned').value.toLowerCase().trim();

  filteredTasks = tasks.filter((t) => {
    const matchQ = !q ||
      (t.taskName || '').toLowerCase().includes(q) ||
      (t.taskId || '').toLowerCase().includes(q) ||
      (t.description || '').toLowerCase().includes(q);

    const matchClient = !client || t.client === client;
    const matchDept = !dept || t.department === dept;
    const matchCat = !cat || t.taskCategory === cat;
    const matchType = !type || t.taskType === type;
    const matchStatus = !status || t.status === status;
    const matchPrio = !prio || t.priority === prio;
    const matchAsg = !asg || (t.assignedTo || '').toLowerCase().includes(asg);

    return matchQ && matchClient && matchDept && matchCat && matchType && matchStatus && matchPrio && matchAsg;
  });

  updateMetrics();
  renderCurrentView();
}

function resetFilters() {
  $('filter-search').value = '';
  $('filter-client').value = '';
  $('filter-dept').value = '';
  $('filter-category').value = '';
  $('filter-type').value = '';
  $('filter-status').value = '';
  $('filter-priority').value = '';
  $('filter-assigned').value = '';
  applyFilters();
}

function updateMetrics() {
  const count = (status) => tasks.filter((t) => t.status === status).length;
  $('count-total').textContent = tasks.length;
  $('count-wip').textContent = count('Work in Progress');
  $('count-review').textContent = count('Submitted for Review');
  $('count-completed').textContent = count('Completed');
  $('count-overdue').textContent = tasks.filter(isTaskOverdue).length;
}

/* -------------------------------------------------------------------------- */
/* VIEWS SWITCHER & RENDERERS                                                 */
/* -------------------------------------------------------------------------- */
function switchView(view) {
  activeView = view;
  ['board', 'table', 'timeline'].forEach((name) => {
    const btn = $('btn-tab-' + name);
    const viewEl = $('view-' + name);
    if (btn) btn.classList.toggle('active', name === view);
    if (viewEl) {
      viewEl.style.display = name === view ? (name === 'board' ? 'grid' : 'block') : 'none';
    }
  });
  renderCurrentView();
}

function renderCurrentView() {
  if (activeView === 'board') renderBoard();
  else if (activeView === 'table') renderTable();
  else renderTimeline();
}

/* --- KANBAN BOARD --- */
function normStatus(s) {
  return String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
}

function boardStatusOf(t) {
  const n = normStatus(t.status);
  const statuses = (config && Array.isArray(config.statuses) && config.statuses.length)
    ? config.statuses
    : FALLBACK_CONFIG.statuses;
  for (let i = 0; i < statuses.length; i++) {
    if (normStatus(statuses[i]) === n) return statuses[i];
  }
  return 'Other';
}

function renderBoard() {
  const container = $('view-board');
  if (!container) return;
  container.innerHTML = '';

  const statusList = (config && Array.isArray(config.statuses) && config.statuses.length)
    ? config.statuses
    : FALLBACK_CONFIG.statuses;
  const columns = statusList.slice();
  if (filteredTasks.some((t) => boardStatusOf(t) === 'Other')) {
    columns.push('Other');
  }

  columns.forEach((statusName) => {
    const col = el('div', 'kanban-col');

    // Drag over handlers
    col.addEventListener('dragover', (e) => {
      e.preventDefault();
      col.classList.add('drag-over');
    });
    col.addEventListener('dragleave', () => col.classList.remove('drag-over'));
    col.addEventListener('drop', (e) => {
      col.classList.remove('drag-over');
      handleDrop(e, statusName);
    });

    const colTasks = filteredTasks.filter((t) => boardStatusOf(t) === statusName);

    // Header
    const head = el('div', 'kanban-col-header');
    head.appendChild(el('span', '', statusName));
    const badge = el('span', 'col-badge', colTasks.length);
    head.appendChild(badge);
    col.appendChild(head);

    // Cards
    colTasks.forEach((t) => {
      const card = el('div', 'kanban-card' + (isTaskOverdue(t) ? ' overdue' : ''));
      card.draggable = true;
      card.addEventListener('dragstart', (e) => {
        e.dataTransfer.setData('text/plain', t.id || t.taskId);
      });
      card.addEventListener('click', (e) => {
        if (!['SELECT', 'OPTION', 'A'].includes(e.target.tagName)) {
          openTaskModal(t.id || t.taskId);
        }
      });

      // Top row (ID & Category)
      const top = el('div', 'card-top');
      top.appendChild(el('div', 'card-id', t.taskId || 'T-????'));
      if (t.taskCategory) {
        top.appendChild(el('span', 'tag ' + (t.taskCategory === 'New Task' ? 'tag-cat-new' : 'tag-cat-existing'), t.taskCategory));
      }
      card.appendChild(top);

      // Title
      card.appendChild(el('div', 'card-title', t.taskName || 'Untitled Task'));

      // Brief
      if (t.description) {
        card.appendChild(el('div', 'card-brief', t.description));
      }

      // Meta tags
      const meta = el('div', 'card-meta');
      if (t.client) meta.appendChild(el('span', 'tag tag-client', t.client));
      if (t.taskType) meta.appendChild(el('span', 'tag tag-type', t.taskType));
      if (t.graphicSize) meta.appendChild(el('span', 'tag tag-size', t.graphicSize));
      if (t.department) meta.appendChild(el('span', 'tag tag-dept', t.department));
      if (t.priority) meta.appendChild(el('span', 'tag tag-prio-' + t.priority, t.priority));
      const nEdits = (revisions[t.taskId] || []).length;
      if (nEdits) meta.appendChild(el('span', 'tag tag-edit', '✎ ' + nEdits + (nEdits > 1 ? ' edits' : ' edit')));
      card.appendChild(meta);

      // Footer
      const foot = el('div', 'card-footer');
      const info = el('div', '');
      info.appendChild(el('div', 'card-assignee', t.assignedTo ? '👤 ' + t.assignedTo : 'Unassigned'));

      const dueClass = isTaskOverdue(t) ? 'card-due-indicator overdue-text' : 'card-due-indicator';
      info.appendChild(el('div', dueClass, t.dueDate ? 'Due ' + formatIsoToDisplay(t.dueDate) : 'No due date'));
      foot.appendChild(info);

      // Status dropdown
      const sel = el('select', 'card-status-select');
      config.statuses.forEach((s) => {
        const o = el('option', '', s);
        o.value = s;
        if (s === boardStatusOf(t)) o.selected = true;
        sel.appendChild(o);
      });
      sel.addEventListener('click', (e) => e.stopPropagation());
      sel.addEventListener('change', () => {
        if (sel.value) updateTaskStatus(t.id || t.taskId, sel.value);
      });
      foot.appendChild(sel);

      card.appendChild(foot);
      col.appendChild(card);
    });

    container.appendChild(col);
  });
}

function handleDrop(e, targetStatus) {
  e.preventDefault();
  const id = e.dataTransfer.getData('text/plain');
  if (targetStatus === 'Other' || !id) return;
  updateTaskStatus(id, targetStatus);
}

/* --- TABLE VIEW --- */
function sortTable(col) {
  if (sortCol === col) {
    sortAsc = !sortAsc;
  } else {
    sortCol = col;
    sortAsc = true;
  }

  // Update headers sort indicators
  document.querySelectorAll('th span[id^="sort-"]').forEach((s) => (s.textContent = ''));
  const currentSpan = $('sort-' + col);
  if (currentSpan) currentSpan.textContent = sortAsc ? ' ▲' : ' ▼';

  renderTable();
}

function renderTable() {
  const body = $('table-body');
  body.innerHTML = '';

  const rows = filteredTasks.slice().sort((a, b) => {
    let x = a[sortCol];
    let y = b[sortCol];

    if (sortCol === 'dueDate' || sortCol === 'postingDate') {
      x = x ? new Date(parseDateToIso(x)).getTime() : 0;
      y = y ? new Date(parseDateToIso(y)).getTime() : 0;
    } else {
      x = String(x || '').toLowerCase();
      y = String(y || '').toLowerCase();
    }

    if (x < y) return sortAsc ? -1 : 1;
    if (x > y) return sortAsc ? 1 : -1;
    return 0;
  });

  if (!rows.length) {
    const tr = el('tr');
    const td = el('td', 'empty', 'No tasks match the current filters.');
    td.colSpan = 13;
    tr.appendChild(td);
    body.appendChild(tr);
    return;
  }

  rows.forEach((t) => {
    const tr = el('tr', isTaskOverdue(t) ? 'overdue-row' : '');
    tr.addEventListener('click', () => openTaskModal(t.id || t.taskId));

    const fields = [
      t.taskId || '',
      t.taskName || '',
      t.department || '',
      t.taskCategory || '',
      t.client || '',
      t.taskType || '',
      t.graphicSize || '',
      t.priority || '',
      t.status || '',
      t.assignedTo || '',
      formatIsoToDisplay(t.dueDate),
      formatIsoToDisplay(t.postingDate)
    ];

    fields.forEach((val) => tr.appendChild(el('td', '', val)));

    // Materials Links
    const tdMat = el('td');
    if (isUrl(t.sourceLink)) {
      const a = el('a', 'link-chip', 'Source');
      a.href = t.sourceLink.trim();
      a.target = '_blank';
      a.rel = 'noopener';
      a.addEventListener('click', (e) => e.stopPropagation());
      tdMat.appendChild(a);
    }
    if (isUrl(t.finishedLink)) {
      const a = el('a', 'link-chip', 'Finished');
      a.href = t.finishedLink.trim();
      a.target = '_blank';
      a.rel = 'noopener';
      a.addEventListener('click', (e) => e.stopPropagation());
      tdMat.appendChild(a);
    }
    tr.appendChild(tdMat);

    body.appendChild(tr);
  });
}

/* --- TIMELINE VIEW --- */
function renderTimeline() {
  const container = $('timeline-list');
  container.innerHTML = '';

  const list = filteredTasks.slice().sort((a, b) => {
    const x = a.dueDate ? new Date(parseDateToIso(a.dueDate)).getTime() : Infinity;
    const y = b.dueDate ? new Date(parseDateToIso(b.dueDate)).getTime() : Infinity;
    return x - y;
  });

  if (!list.length) {
    container.appendChild(el('div', 'empty', 'No tasks match the current filters.'));
    return;
  }

  list.forEach((t) => {
    const item = el('div', 'timeline-item');
    item.addEventListener('click', () => openTaskModal(t.id || t.taskId));

    const dates = el('div', 'timeline-dates' + (isTaskOverdue(t) ? ' late' : ''));
    dates.appendChild(el('div', '', t.dueDate ? 'Due: ' + formatIsoToDisplay(t.dueDate) : 'Due: not set'));
    dates.appendChild(el('div', '', t.postingDate ? 'Post: ' + formatIsoToDisplay(t.postingDate) : 'Post: not set'));
    item.appendChild(dates);

    const main = el('div', 'timeline-main');
    main.appendChild(el('div', 'card-title', (t.taskId || '') + ' · ' + t.taskName));
    main.appendChild(el('div', 'card-id', [t.client, t.taskType, t.assignedTo].filter(Boolean).join(' · ')));
    item.appendChild(main);

    item.appendChild(el('span', 'tag tag-prio-' + t.priority, t.priority));
    item.appendChild(el('span', 'tag tag-size', t.status));
    container.appendChild(item);
  });
}

/* -------------------------------------------------------------------------- */
/* TASK CRUD ACTIONS                                                          */
/* -------------------------------------------------------------------------- */
async function updateTaskStatus(taskIdentifier, newStatus) {
  const task = tasks.find((t) => t.id === taskIdentifier || t.taskId === taskIdentifier);
  if (!task || task.status === newStatus) return;

  const oldStatus = task.status;
  task.status = newStatus;
  applyFilters();

  if (isConnected && supabaseClient) {
    try {
      const query = supabaseClient.from('tasks').update({ status: newStatus });
      const { error } = task.id
        ? await query.eq('id', task.id)
        : await query.eq('task_id', task.taskId);

      if (error) throw error;
      showToast(`${task.taskId} updated to ${newStatus}`, 'success');
      return;
    } catch (err) {
      task.status = oldStatus;
      applyFilters();
      showToast('Status update failed: ' + err.message, 'error');
      return;
    }
  }

  // Demo Mode
  localStorage.setItem('demo_tasks', JSON.stringify(tasks));
  showToast(`${task.taskId} moved to ${newStatus} (Demo)`, 'info');
}

async function handleFormSubmit(e) {
  e.preventDefault();
  const formId = $('form-id').value;
  const taskId = $('form-task-id').value;

  const taskPayload = {};
  FIELD_DEFS.forEach((f) => {
    let val = $(f.form).value.trim();
    if (f.isDate) {
      val = val ? parseDateToIso(val) : null;
    }
    taskPayload[f.js] = val;
  });

  if (!taskPayload.taskName) {
    showToast('Task Name is required', 'error');
    return;
  }

  const saveBtn = $('btn-save-task');
  saveBtn.disabled = true;
  saveBtn.textContent = 'Saving...';

  try {
    if (formId || taskId) {
      // UPDATE EXISTING
      if (isConnected && supabaseClient) {
        const dbUpdate = {};
        FIELD_DEFS.forEach((f) => {
          dbUpdate[f.db] = taskPayload[f.js];
        });

        const query = supabaseClient.from('tasks').update(dbUpdate);
        const { error } = formId ? await query.eq('id', formId) : await query.eq('task_id', taskId);
        if (error) throw error;
      } else {
        const idx = tasks.findIndex((t) => t.id === formId || t.taskId === taskId);
        if (idx !== -1) {
          tasks[idx] = { ...tasks[idx], ...taskPayload };
          localStorage.setItem('demo_tasks', JSON.stringify(tasks));
        }
      }
      showToast('Task updated successfully', 'success');
    } else {
      // CREATE NEW
      if (isConnected && supabaseClient) {
        const dbInsert = {};
        FIELD_DEFS.forEach((f) => {
          dbInsert[f.db] = taskPayload[f.js];
        });

        const { data, error } = await supabaseClient.from('tasks').insert([dbInsert]).select().single();
        if (error) throw error;
        showToast(`Task created (${data.task_id})`, 'success');
      } else {
        const nextNum = tasks.length + 1;
        const newTaskId = 'T-' + String(nextNum).padStart(4, '0');
        const newTask = {
          id: 'demo-' + Date.now(),
          taskId: newTaskId,
          ...taskPayload
        };
        tasks.unshift(newTask);
        localStorage.setItem('demo_tasks', JSON.stringify(tasks));
        showToast(`Task created (${newTaskId}) in Demo`, 'success');
      }
    }

    closeModal();
    await refreshData(true);
  } catch (err) {
    console.error('Save task error:', err);
    showToast('Failed to save task: ' + err.message, 'error');
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = 'Save Task';
  }
}

async function handleDeleteTask() {
  if (!currentTaskId) return;
  const task = tasks.find((t) => t.id === currentTaskId || t.taskId === currentTaskId);
  if (!task) return;

  if (!confirm(`Are you sure you want to permanently delete task "${task.taskId} - ${task.taskName}"?`)) {
    return;
  }

  try {
    if (isConnected && supabaseClient) {
      const query = supabaseClient.from('tasks').delete();
      const { error } = task.id ? await query.eq('id', task.id) : await query.eq('task_id', task.taskId);
      if (error) throw error;
    } else {
      tasks = tasks.filter((t) => t.id !== currentTaskId && t.taskId !== currentTaskId);
      localStorage.setItem('demo_tasks', JSON.stringify(tasks));
      delete revisions[task.taskId];
      localStorage.setItem('demo_revisions', JSON.stringify(revisions));
    }

    closeModal();
    showToast(`Task ${task.taskId} deleted`, 'info');
    await refreshData(true);
  } catch (err) {
    showToast('Delete failed: ' + err.message, 'error');
  }
}

/* -------------------------------------------------------------------------- */
/* MODAL MANAGEMENT                                                           */
/* -------------------------------------------------------------------------- */
function setFormDisabled(disabled) {
  const f = $('task-form');
  f.classList.toggle('view-only', disabled);
  f.querySelectorAll('input, select, textarea').forEach((i) => {
    if (i.type !== 'hidden') i.disabled = disabled;
  });
  $('btn-save-task').style.display = disabled ? 'none' : 'inline-flex';
  $('btn-edit-mode').style.display = disabled && currentTaskId ? 'inline-flex' : 'none';
  $('btn-delete-task').style.display = currentTaskId ? 'inline-flex' : 'none';
  $('open-links').style.display = disabled ? 'flex' : 'none';
}

function openNewTask() {
  currentTaskId = null;
  $('task-form').reset();
  $('form-id').value = '';
  $('form-task-id').value = '';

  fillDropdowns();
  $('form-priority').value = 'Medium';
  $('form-status').value = config.statuses[0] || 'Not Started';
  $('form-category').value = 'New Task';
  $('form-dept').value = 'Social';
  $('modal-title').textContent = '+ New Task';
  revDraft = null;
  revDirty = false;
  $('rev-section').style.display = 'none';

  setFormDisabled(false);
  $('task-modal').classList.add('active');
  $('form-name').focus();
}

function openTaskModal(identifier) {
  const t = tasks.find((item) => item.id === identifier || item.taskId === identifier);
  if (!t) return;

  currentTaskId = t.id || t.taskId;
  $('form-id').value = t.id || '';
  $('form-task-id').value = t.taskId || '';

  fillDropdowns();

  FIELD_DEFS.forEach((f) => {
    let val = t[f.js] || '';
    if (f.isDate) {
      val = parseDateToIso(val) || '';
    }
    const elem = $(f.form);
    if (elem) elem.value = val;
  });

  $('modal-title').textContent = `${t.taskId || ''} — ${t.taskName || 'Details'}`;

  // External Links section
  const linkBox = $('open-links');
  linkBox.innerHTML = '';
  const links = [
    { label: 'Brand Guideline', url: t.brandGuidelineLink },
    { label: 'Reference', url: t.referenceLink },
    { label: 'Source Materials', url: t.sourceLink },
    { label: 'Finished Task', url: t.finishedLink }
  ];

  links.forEach((l) => {
    if (isUrl(l.url)) {
      const a = el('a', '', `🔗 Open ${l.label}`);
      a.href = l.url.trim();
      a.target = '_blank';
      a.rel = 'noopener';
      linkBox.appendChild(a);
    }
  });

  setFormDisabled(true);
  revDraft = null;
  revDirty = false;
  $('rev-section').style.display = 'block';
  $('rev-section').open = false;
  renderRevisions(t.taskId);
  $('task-modal').classList.add('active');
}

function enableEditMode() {
  setFormDisabled(false);
}

function closeModal() {
  $('task-modal').classList.remove('active');
  revDraft = null;
  revDirty = false;
}

/* -------------------------------------------------------------------------- */
/* SETTINGS MODAL & SUPABASE CONFIG                                           */
/* -------------------------------------------------------------------------- */
function openSettingsModal() {
  const creds = getSupabaseCredentials();
  $('setting-supabase-url').value = creds.url;
  $('setting-supabase-key').value = creds.key;
  $('conn-test-result').style.display = 'none';
  $('settings-modal').classList.add('active');
}

function closeSettingsModal() {
  $('settings-modal').classList.remove('active');
}

async function testSupabaseConnection() {
  const url = $('setting-supabase-url').value.trim();
  const key = $('setting-supabase-key').value.trim();
  const resBox = $('conn-test-result');
  resBox.style.display = 'block';

  if (!url || !key) {
    resBox.style.background = '#fef2f2';
    resBox.style.color = '#991b1b';
    resBox.textContent = '❌ Please enter both Project URL and Public Anon Key.';
    return;
  }

  resBox.style.background = '#eff6ff';
  resBox.style.color = '#1d4ed8';
  resBox.textContent = '⏳ Testing connection to Supabase...';

  try {
    const testClient = window.supabase.createClient(url, key);
    const { data, error } = await testClient.from('tasks').select('id').limit(1);

    if (error) {
      if (error.code === '42P01') {
        resBox.style.background = '#fffbeb';
        resBox.style.color = '#92400e';
        resBox.textContent = '⚠️ Connected to Supabase, but the "tasks" table does not exist yet. Please run the supabase-schema.sql script in SQL Editor!';
      } else {
        resBox.style.background = '#fef2f2';
        resBox.style.color = '#991b1b';
        resBox.textContent = '❌ Connection failed: ' + error.message;
      }
    } else {
      resBox.style.background = '#ecfdf5';
      resBox.style.color = '#065f46';
      resBox.textContent = '✅ Success! Connected to Supabase and "tasks" table verified.';
    }
  } catch (err) {
    resBox.style.background = '#fef2f2';
    resBox.style.color = '#991b1b';
    resBox.textContent = '❌ Error testing connection: ' + err.message;
  }
}

function saveSupabaseSettings() {
  const url = $('setting-supabase-url').value.trim();
  const key = $('setting-supabase-key').value.trim();

  if (url && key) {
    localStorage.setItem('sb_url', url);
    localStorage.setItem('sb_key', key);
    showToast('Supabase settings saved! Reconnecting...', 'success');
  } else {
    localStorage.removeItem('sb_url');
    localStorage.removeItem('sb_key');
    showToast('Reset to demo mode', 'info');
  }

  closeSettingsModal();
  initSupabase();
}

function clearSupabaseSettings() {
  localStorage.removeItem('sb_url');
  localStorage.removeItem('sb_key');
  $('setting-supabase-url').value = '';
  $('setting-supabase-key').value = '';
  showToast('Cleared Supabase credentials. Switched to Demo Mode.', 'info');
  closeSettingsModal();
  initSupabase();
}

/* -------------------------------------------------------------------------- */
/* EDITS / REVISIONS (a task can have many)                                   */
/* -------------------------------------------------------------------------- */
function loadRevisionsLocal() {
  try {
    revisions = JSON.parse(localStorage.getItem('demo_revisions') || '{}') || {};
  } catch (e) {
    revisions = {};
  }
  revisionsReady = true;
}

async function loadRevisions() {
  if (!(isConnected && supabaseClient)) { loadRevisionsLocal(); return; }
  const { data, error } = await supabaseClient
    .from('task_revisions')
    .select('*')
    .order('revision_no', { ascending: true });

  if (error) {
    console.warn('Edits not available:', error);
    revisionsReady = false;
    revisions = {};
    return;
  }
  revisionsReady = true;
  revisions = {};
  (data || []).forEach((r) => {
    (revisions[r.task_id] = revisions[r.task_id] || []).push(r);
  });
}

function openTaskIdInModal() {
  return $('form-task-id').value || '';
}

function refreshRevisionPanel() {
  if (!$('task-modal').classList.contains('active')) return;
  const tid = openTaskIdInModal();
  if (!tid || revDirty) return; // do not wipe what the user is typing
  renderRevisions(tid);
}

function formatTs(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  if (isNaN(d.getTime())) return '';
  return String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear();
}

function renderRevisions(taskId) {
  const box = $('rev-list');
  box.innerHTML = '';
  const saved = revisions[taskId] || [];
  $('rev-summary').textContent = 'Edits (' + saved.length + ')';
  $('btn-add-edit').style.display = revisionsReady ? 'inline-flex' : 'none';

  if (!revisionsReady) {
    box.appendChild(el('div', 'empty', 'Edits are not set up yet. Run supabase-add-revisions.sql in the Supabase SQL Editor, then refresh.'));
    return;
  }

  const items = saved.slice();
  if (revDraft) items.push(revDraft);
  if (!items.length) {
    box.appendChild(el('div', 'empty', 'No edits yet. Click "+ Add Edit" when the owner sends notes.'));
    return;
  }

  items.forEach((r) => {
    const isDraft = r === revDraft;
    const card = el('div', 'rev-card');

    const head = el('div', 'rev-head');
    head.appendChild(el('span', '', isDraft ? 'New edit' : 'Edit #' + r.revision_no));
    if (!isDraft && r.created_at) head.appendChild(el('span', 'rev-meta', formatTs(r.created_at)));
    card.appendChild(head);

    const mk = (label, tag, value, ph) => {
      const wrap = el('div');
      wrap.appendChild(el('label', '', label));
      const f = el(tag);
      if (tag === 'input') f.type = 'text';
      f.value = value || '';
      f.placeholder = ph;
      f.addEventListener('input', () => { revDirty = true; });
      wrap.appendChild(f);
      card.appendChild(wrap);
      return f;
    };

    const fOwner = mk('Owner Note (what needs to change)', 'textarea', r.owner_note, 'Feedback or requested changes...');
    const fLink = mk('New Delivery Link', 'input', r.delivery_link, 'https://drive.google.com/...');
    const fNote = mk('My Note', 'textarea', r.delivery_note, 'What was changed...');

    const act = el('div', 'rev-actions');
    if (!isDraft && isUrl(r.delivery_link)) {
      const a = el('a', '', '🔗 Open delivery');
      a.href = r.delivery_link.trim();
      a.target = '_blank';
      a.rel = 'noopener';
      act.appendChild(a);
    }
    const del = el('button', 'btn ' + (isDraft ? 'btn-secondary' : 'btn-danger'), isDraft ? 'Cancel' : 'Delete');
    del.type = 'button';
    del.addEventListener('click', () => deleteRevision(taskId, r));
    const save = el('button', 'btn btn-primary', 'Save');
    save.type = 'button';
    save.addEventListener('click', () => saveRevision(taskId, r, {
      owner_note: fOwner.value.trim(),
      delivery_link: fLink.value.trim(),
      delivery_note: fNote.value.trim()
    }, save));
    act.appendChild(del);
    act.appendChild(save);
    card.appendChild(act);

    box.appendChild(card);
  });
}

function addRevision() {
  const tid = openTaskIdInModal();
  if (!tid || revDraft) { if (revDraft) showToast('Save or cancel the new edit first', 'error'); return; }
  revDraft = { id: null, task_id: tid, owner_note: '', delivery_link: '', delivery_note: '' };
  $('rev-section').open = true;
  renderRevisions(tid);
}

async function saveRevision(taskId, rev, vals, btn) {
  if (!vals.owner_note && !vals.delivery_link && !vals.delivery_note) {
    showToast('Fill at least one field', 'error');
    return;
  }
  btn.disabled = true;
  btn.textContent = 'Saving...';
  const isDraft = rev === revDraft;

  try {
    if (isConnected && supabaseClient) {
      const q = isDraft
        ? supabaseClient.from('task_revisions').insert([{ task_id: taskId, ...vals }])
        : supabaseClient.from('task_revisions').update(vals).eq('id', rev.id);
      const { error } = await q;
      if (error) throw error;
    } else {
      const list = revisions[taskId] = revisions[taskId] || [];
      if (isDraft) {
        const next = list.reduce((m, r) => Math.max(m, r.revision_no), 0) + 1;
        list.push({ id: 'demo-rev-' + Date.now(), task_id: taskId, revision_no: next, created_at: new Date().toISOString(), ...vals });
      } else {
        Object.assign(rev, vals);
      }
      localStorage.setItem('demo_revisions', JSON.stringify(revisions));
    }

    if (isDraft) revDraft = null;
    revDirty = false;
    showToast(isDraft ? 'Edit added' : 'Edit saved', 'success');
    await refreshData(true);
    renderRevisions(taskId);
    applyFilters();
  } catch (err) {
    console.error('Save edit error:', err);
    showToast('Could not save edit: ' + err.message, 'error');
    btn.disabled = false;
    btn.textContent = 'Save';
  }
}

async function deleteRevision(taskId, rev) {
  if (rev === revDraft) {
    revDraft = null;
    revDirty = false;
    renderRevisions(taskId);
    return;
  }
  if (!confirm('Delete Edit #' + rev.revision_no + '?')) return;

  try {
    if (isConnected && supabaseClient) {
      const { error } = await supabaseClient.from('task_revisions').delete().eq('id', rev.id);
      if (error) throw error;
    } else {
      revisions[taskId] = (revisions[taskId] || []).filter((r) => r.id !== rev.id);
      localStorage.setItem('demo_revisions', JSON.stringify(revisions));
    }
    revDirty = false;
    await refreshData(true);
    renderRevisions(taskId);
    applyFilters();
  } catch (err) {
    showToast('Delete failed: ' + err.message, 'error');
  }
}

/* -------------------------------------------------------------------------- */
/* EVENT LISTENERS & LIFECYCLE                                                */
/* -------------------------------------------------------------------------- */
window.addEventListener('DOMContentLoaded', () => {
  fillDropdowns();
  initSupabase();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closeModal();
    closeSettingsModal();
  }
});

$('task-modal').addEventListener('mousedown', (e) => {
  if (e.target === $('task-modal')) closeModal();
});

$('settings-modal').addEventListener('mousedown', (e) => {
  if (e.target === $('settings-modal')) closeSettingsModal();
});
