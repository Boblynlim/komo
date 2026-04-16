const tabManager = new TabManager();
const linkStore = new LinkStore();

let activeTabId = null;
let commandBarSelectedIndex = 0;
let commandBarResults = [];
let contextMenu = null;
let currentView = 'tabs'; // 'tabs' | 'scout' | 'library'
let scoutFeedback = {}; // { itemId: 'liked' | 'disliked' }
let libraryFilter = 'inbox'; // 'inbox' | 'archive' | 'tag'
let libraryTagFilter = null;
let librarySearchQuery = '';
let activeTagPopover = null;

// --- Init ---
async function init() {
  await tabManager.loadState();
  await linkStore.loadLinks();
  render();

  // Listen for tab changes
  const onTabChange = () => { render(); refreshCommandBarIfOpen(); };
  chrome.tabs.onUpdated.addListener(onTabChange);
  chrome.tabs.onRemoved.addListener(onTabChange);
  chrome.tabs.onActivated.addListener((info) => {
    activeTabId = info.tabId;
    onTabChange();
  });
  chrome.tabs.onMoved.addListener(onTabChange);
  chrome.tabs.onCreated.addListener(onTabChange);

  // Get current active tab
  const active = await tabManager.getActiveTab();
  if (active) activeTabId = active.id;

  // Listen for commands from background
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'toggle-command-bar') toggleCommandBar();
    if (msg.type === 'save-current-link') openSaveLinkPanel();
  });

  // Keyboard shortcut in sidebar
  document.addEventListener('keydown', (e) => {
    if (e.metaKey && (e.key === 'k' || e.key === 't')) { e.preventDefault(); toggleCommandBar(); }
    if (e.metaKey && e.key === 'd') { e.preventDefault(); openSaveLinkPanel(); }
  });

  // Close context menu on click
  document.addEventListener('click', () => removeContextMenu());

  // New tab button
  document.getElementById('new-tab-btn').addEventListener('click', toggleCommandBar);

  // Downloads
  document.getElementById('downloads-btn').addEventListener('click', toggleDownloads);

  // New folder
  document.getElementById('new-folder-btn').addEventListener('click', () => {
    const name = prompt('Folder name:');
    if (name && name.trim()) {
      tabManager.createFolder(name.trim());
      render();
    }
  });

  // Scout toggle
  document.getElementById('scout-btn').addEventListener('click', () => toggleView('scout'));

  // Library toggle
  document.getElementById('library-btn').addEventListener('click', () => toggleView('library'));

  // Load scout feedback from storage
  const fbData = await chrome.storage.local.get('scoutFeedback');
  scoutFeedback = fbData.scoutFeedback || {};

  render();
}

// --- Render ---
async function render() {
  const tabs = await tabManager.getTabs();
  const folderedIds = tabManager.getFolderedTabIds();

  // Update tab count
  document.getElementById('tab-count').textContent = tabs.length;

  // Render folders
  const foldersContainer = document.getElementById('folders-container');
  foldersContainer.innerHTML = '';
  tabManager.folders.forEach(folder => {
    const folderTabs = folder.tabIds
      .map(id => tabs.find(t => t.id === id))
      .filter(Boolean);

    const section = document.createElement('div');
    section.className = 'folder-section';

    const header = document.createElement('div');
    header.className = 'folder-header';
    header.innerHTML = `
      <span class="chevron ${folder.collapsed ? 'collapsed' : ''}">▼</span>
      <span class="folder-icon">📁</span>
      <span class="folder-name">${escapeHtml(folder.name)}</span>
      <span class="count-badge">${folderTabs.length}</span>
    `;
    header.addEventListener('click', () => {
      tabManager.toggleFolderCollapse(folder.id);
      render();
    });
    header.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      showContextMenu(e, [
        { label: 'Rename', action: () => { const n = prompt('New name:', folder.name); if (n) { tabManager.renameFolder(folder.id, n); render(); } } },
        { divider: true },
        { label: 'Delete Folder', danger: true, action: () => { tabManager.deleteFolder(folder.id); render(); } },
      ]);
    });

    const tabsDiv = document.createElement('div');
    tabsDiv.className = `folder-tabs ${folder.collapsed ? 'collapsed' : ''}`;
    folderTabs.forEach(tab => tabsDiv.appendChild(createTabRow(tab)));

    section.appendChild(header);
    section.appendChild(tabsDiv);
    foldersContainer.appendChild(section);
  });

  // Render unfoldered tabs
  const tabList = document.getElementById('tab-list');
  tabList.innerHTML = '';
  tabs.filter(t => !folderedIds.has(t.id)).forEach(tab => {
    tabList.appendChild(createTabRow(tab));
  });
}

function createTabRow(tab) {
  const row = document.createElement('div');
  row.className = `tab-row ${tab.id === activeTabId ? 'active' : ''}`;
  row.dataset.tabId = tab.id;

  const isFav = tabManager.isFavorite(tab.id);

  let iconHtml;
  if (isFav) {
    iconHtml = '<span class="star">★</span>';
  } else if (tab.favIconUrl) {
    iconHtml = `<img class="favicon" src="${escapeHtml(tab.favIconUrl)}" onerror="this.outerHTML='<span class=\\'favicon-placeholder\\'>◎</span>'">`;
  } else {
    iconHtml = '<span class="favicon-placeholder">◎</span>';
  }

  row.innerHTML = `
    ${iconHtml}
    <span class="tab-title">${escapeHtml(tab.title || 'New Tab')}</span>
    <button class="close-btn" title="Close tab">✕</button>
  `;

  row.addEventListener('click', (e) => {
    if (e.target.classList.contains('close-btn')) {
      tabManager.closeTab(tab.id);
    } else {
      tabManager.switchToTab(tab.id);
    }
  });

  row.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    const items = [
      { label: isFav ? 'Unfavorite' : 'Favorite', action: () => { tabManager.toggleFavorite(tab.id); render(); } },
    ];
    if (tabManager.folders.length > 0) {
      items.push({ divider: true });
      tabManager.folders.forEach(f => {
        items.push({ label: `Move to ${f.name}`, action: () => { tabManager.moveTabToFolder(tab.id, f.id); render(); } });
      });
      items.push({ label: 'Remove from Folder', action: () => { tabManager.removeTabFromFolder(tab.id); render(); } });
    }
    items.push({ divider: true });
    items.push({ label: 'Close Tab', danger: true, action: () => { tabManager.closeTab(tab.id); } });
    showContextMenu(e, items);
  });

  // Drag support
  row.draggable = true;
  row.addEventListener('dragstart', (e) => {
    e.dataTransfer.setData('text/plain', tab.id.toString());
  });

  return row;
}

// --- Command Bar ---
function refreshCommandBarIfOpen() {
  const overlay = document.getElementById('command-bar-overlay');
  if (!overlay.classList.contains('hidden')) updateCommandBarResults();
}

function toggleCommandBar() {
  const overlay = document.getElementById('command-bar-overlay');
  const input = document.getElementById('command-bar-input');
  const isOpening = overlay.classList.contains('hidden');
  overlay.classList.toggle('hidden');
  if (isOpening) {
    input.value = '';
    input.focus();
    commandBarSelectedIndex = 0;
    updateCommandBarResults();
    input.addEventListener('input', onCommandBarInput);
    overlay.addEventListener('keydown', handleCommandBarKeys);
  } else {
    input.removeEventListener('input', onCommandBarInput);
    overlay.removeEventListener('keydown', handleCommandBarKeys);
  }
}

function onCommandBarInput() {
  commandBarSelectedIndex = 0;
  updateCommandBarResults();
}

async function updateCommandBarResults() {
  const query = document.getElementById('command-bar-input').value.toLowerCase();
  const tabs = await tabManager.getTabs();
  const resultsDiv = document.getElementById('command-bar-results');
  commandBarResults = [];
  let html = '';

  // Open tabs
  const matchingTabs = tabs.filter(t => t.url && (
    !query || t.title?.toLowerCase().includes(query) || t.url.toLowerCase().includes(query)
  ));
  if (matchingTabs.length > 0) {
    html += '<div class="result-section-label">Open Tabs</div>';
    matchingTabs.slice(0, 5).forEach(tab => {
      const idx = commandBarResults.length;
      commandBarResults.push({ type: 'tab', data: tab });
      const host = safeHost(tab.url);
      html += `<div class="result-row ${idx === commandBarSelectedIndex ? 'selected' : ''}" data-index="${idx}">
        <span class="result-icon">◎</span>
        <div class="result-info">
          <div class="result-title">${escapeHtml(tab.title || 'New Tab')}</div>
          <div class="result-subtitle">${escapeHtml(host)}</div>
        </div>
        <span class="result-badge">Tab</span>
      </div>`;
    });
  }

  // Folders
  const matchingFolders = tabManager.folders.filter(f =>
    !query || f.name.toLowerCase().includes(query)
  );
  if (matchingFolders.length > 0) {
    html += '<div class="result-section-label">Folders</div>';
    matchingFolders.forEach(f => {
      const idx = commandBarResults.length;
      commandBarResults.push({ type: 'folder', data: f });
      html += `<div class="result-row ${idx === commandBarSelectedIndex ? 'selected' : ''}" data-index="${idx}">
        <span class="result-icon">📁</span>
        <div class="result-info">
          <div class="result-title">${escapeHtml(f.name)}</div>
          <div class="result-subtitle">${f.tabIds.length} tabs</div>
        </div>
        <span class="result-badge">Folder</span>
        <span class="chevron-right">›</span>
      </div>`;
    });
  }

  // Saved links
  if (query) {
    const matchingLinks = linkStore.search(query).slice(0, 5);
    if (matchingLinks.length > 0) {
      html += '<div class="result-section-label">Saved Links</div>';
      matchingLinks.forEach(link => {
        const idx = commandBarResults.length;
        commandBarResults.push({ type: 'link', data: link });
        html += `<div class="result-row ${idx === commandBarSelectedIndex ? 'selected' : ''}" data-index="${idx}">
          <span class="result-icon">🔖</span>
          <div class="result-info">
            <div class="result-title">${escapeHtml(link.title)}</div>
            <div class="result-subtitle">${escapeHtml(safeHost(link.url))}</div>
          </div>
          <span class="result-badge">Saved</span>
        </div>`;
      });
    }
  }

  // Navigate action
  if (query.trim()) {
    const idx = commandBarResults.length;
    commandBarResults.push({ type: 'navigate', data: query });
    html += `<div class="result-row ${idx === commandBarSelectedIndex ? 'selected' : ''}" data-index="${idx}">
      <span class="result-icon">🔍</span>
      <div class="result-info">
        <div class="result-title">${escapeHtml(query)}</div>
      </div>
      <span class="result-badge">Go</span>
    </div>`;
  }

  resultsDiv.innerHTML = html;

  // Click handlers
  resultsDiv.querySelectorAll('.result-row').forEach(row => {
    row.addEventListener('click', () => {
      executeCommandBarResult(parseInt(row.dataset.index));
    });
  });
}

function handleCommandBarKeys(e) {
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    commandBarSelectedIndex = Math.min(commandBarResults.length - 1, commandBarSelectedIndex + 1);
    updateCommandBarSelection();
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    commandBarSelectedIndex = Math.max(0, commandBarSelectedIndex - 1);
    updateCommandBarSelection();
  } else if (e.key === 'Enter') {
    e.preventDefault();
    executeCommandBarResult(commandBarSelectedIndex);
  } else if (e.key === 'Escape') {
    e.preventDefault();
    toggleCommandBar();
  }
}

function updateCommandBarSelection() {
  const resultsDiv = document.getElementById('command-bar-results');
  resultsDiv.querySelectorAll('.result-row').forEach(row => {
    row.classList.toggle('selected', parseInt(row.dataset.index) === commandBarSelectedIndex);
  });
  const selected = resultsDiv.querySelector('.result-row.selected');
  if (selected) selected.scrollIntoView({ block: 'nearest' });
}

function executeCommandBarResult(index) {
  if (index >= commandBarResults.length) return;
  const result = commandBarResults[index];

  switch (result.type) {
    case 'tab':
      tabManager.switchToTab(result.data.id);
      break;
    case 'link':
      tabManager.createTab(result.data.url);
      break;
    case 'folder':
      // Could drill into folder — for now just toggle collapse
      tabManager.toggleFolderCollapse(result.data.id);
      render();
      break;
    case 'navigate':
      const input = result.data.trim();
      let url;
      if (input.includes('.') && !input.includes(' ')) {
        url = input.startsWith('http') ? input : `https://${input}`;
      } else {
        url = `https://duckduckgo.com/?q=${encodeURIComponent(input)}`;
      }
      tabManager.createTab(url);
      break;
  }
  toggleCommandBar();
}

// --- Save Link Panel ---
async function openSaveLinkPanel() {
  const tab = await tabManager.getActiveTab();
  if (!tab?.url) return;

  document.getElementById('save-link-url').textContent = tab.url;
  document.getElementById('save-link-title').value = tab.title || '';
  document.getElementById('save-link-notes').value = '';
  document.getElementById('save-link-tag-input').value = '';

  // Suggestions
  const suggestions = linkStore.suggestTags(tab.url);
  const sugDiv = document.getElementById('save-link-suggestions');
  sugDiv.innerHTML = '';
  suggestions.forEach(tag => {
    const btn = document.createElement('button');
    btn.className = 'tag-suggestion';
    btn.textContent = `#${tag}`;
    btn.addEventListener('click', () => addSaveTag(tag));
    sugDiv.appendChild(btn);
  });

  currentSaveTags = [...suggestions];
  renderSaveTags();

  document.getElementById('save-link-overlay').classList.remove('hidden');

  // Wire up events
  document.getElementById('save-link-close').onclick = closeSaveLinkPanel;
  document.getElementById('save-link-cancel').onclick = closeSaveLinkPanel;
  document.getElementById('save-link-save').onclick = doSaveLink;
  document.getElementById('save-link-tag-input').onkeydown = (e) => {
    if (e.key === 'Enter') { e.preventDefault(); addSaveTag(e.target.value); e.target.value = ''; }
  };
}

let currentSaveTags = [];

function renderSaveTags() {
  const container = document.getElementById('save-link-tags');
  container.innerHTML = '';
  currentSaveTags.forEach(tag => {
    const pill = document.createElement('span');
    pill.className = 'tag-pill';
    pill.innerHTML = `#${escapeHtml(tag)} <span class="remove-tag">✕</span>`;
    pill.querySelector('.remove-tag').addEventListener('click', () => {
      currentSaveTags = currentSaveTags.filter(t => t !== tag);
      renderSaveTags();
    });
    container.appendChild(pill);
  });
}

function addSaveTag(tag) {
  tag = tag.trim().toLowerCase().replace('#', '');
  if (tag && !currentSaveTags.includes(tag)) {
    currentSaveTags.push(tag);
    renderSaveTags();
  }
}

async function doSaveLink() {
  const url = document.getElementById('save-link-url').textContent;
  const title = document.getElementById('save-link-title').value;
  const notes = document.getElementById('save-link-notes').value;
  await linkStore.save(url, title, currentSaveTags, notes);
  closeSaveLinkPanel();
}

function closeSaveLinkPanel() {
  document.getElementById('save-link-overlay').classList.add('hidden');
}

// --- Downloads ---
function toggleDownloads() {
  const popover = document.getElementById('downloads-popover');
  popover.classList.toggle('hidden');
  if (!popover.classList.contains('hidden')) {
    renderDownloads();
  }
}

async function renderDownloads() {
  const downloads = await chrome.downloads.search({ limit: 10, orderBy: ['-startTime'] });
  const list = document.getElementById('downloads-list');
  if (downloads.length === 0) {
    list.innerHTML = '<div style="padding:16px;text-align:center;color:var(--text-tertiary);font-size:11px">No downloads yet</div>';
    return;
  }
  list.innerHTML = '';
  downloads.forEach(dl => {
    const name = dl.filename.split('/').pop();
    const ago = timeAgo(new Date(dl.startTime));
    const row = document.createElement('div');
    row.className = 'download-row';
    row.innerHTML = `<span class="download-name">${escapeHtml(name)}</span><span class="download-time">${ago}</span>`;
    row.addEventListener('click', () => chrome.downloads.show(dl.id));
    list.appendChild(row);
  });
}

// --- Context Menu ---
function showContextMenu(e, items) {
  removeContextMenu();
  contextMenu = document.createElement('div');
  contextMenu.className = 'context-menu';
  contextMenu.style.left = `${e.clientX}px`;
  contextMenu.style.top = `${e.clientY}px`;

  items.forEach(item => {
    if (item.divider) {
      const div = document.createElement('div');
      div.className = 'context-menu-divider';
      contextMenu.appendChild(div);
    } else {
      const btn = document.createElement('button');
      btn.className = `context-menu-item ${item.danger ? 'danger' : ''}`;
      btn.textContent = item.label;
      btn.addEventListener('click', (e) => { e.stopPropagation(); item.action(); removeContextMenu(); });
      contextMenu.appendChild(btn);
    }
  });

  document.body.appendChild(contextMenu);
}

function removeContextMenu() {
  if (contextMenu) { contextMenu.remove(); contextMenu = null; }
}

// --- Helpers ---
function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function safeHost(url) {
  try { return new URL(url).hostname.replace('www.', ''); } catch { return ''; }
}

function timeAgo(date) {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

// --- Drop targets on folders ---
document.addEventListener('dragover', (e) => e.preventDefault());
document.addEventListener('drop', (e) => {
  e.preventDefault();
  const tabId = parseInt(e.dataTransfer.getData('text/plain'));
  const folderHeader = e.target.closest('.folder-header');
  if (folderHeader) {
    const section = folderHeader.closest('.folder-section');
    const idx = Array.from(document.querySelectorAll('.folder-section')).indexOf(section);
    if (idx >= 0 && idx < tabManager.folders.length) {
      tabManager.moveTabToFolder(tabId, tabManager.folders[idx].id);
      render();
    }
  }
});

// --- View Switching ---
function toggleView(view) {
  if (currentView === view) {
    currentView = 'tabs';
  } else {
    currentView = view;
  }
  applyView();
}

function applyView() {
  const tabsView = document.getElementById('tabs-view');
  const scoutView = document.getElementById('scout-view');
  const libraryView = document.getElementById('library-view');
  const scoutBtn = document.getElementById('scout-btn');
  const libraryBtn = document.getElementById('library-btn');

  tabsView.classList.toggle('hidden', currentView !== 'tabs');
  scoutView.classList.toggle('hidden', currentView !== 'scout');
  libraryView.classList.toggle('hidden', currentView !== 'library');

  scoutBtn.classList.toggle('active', currentView === 'scout');
  libraryBtn.classList.toggle('active', currentView === 'library');

  if (currentView === 'scout') renderScout();
  if (currentView === 'library') renderLibrary();
}

// --- Scout ---
const SCOUT_ITEMS = [
  {
    id: 's1', title: 'Bartosz Ciechanowski', url: 'https://ciechanow.ski',
    domain: 'ciechanow.ski', category: 'Interactive & Visual',
    description: 'Deep, beautifully animated explanations of how things work — GPS, cameras, mechanical watches. Each post takes months to craft and it shows.',
    reason: 'The gold standard for interactive technical writing'
  },
  {
    id: 's2', title: 'Explorable Explanations', url: 'https://explorabl.es',
    domain: 'explorabl.es', category: 'Interactive & Visual',
    description: 'A curated hub of interactive articles that teach through play — math, science, systems thinking, economics. Learning by doing.',
    reason: 'Interactive learning meets curiosity'
  },
  {
    id: 's3', title: 'Neal.fun', url: 'https://neal.fun',
    domain: 'neal.fun', category: 'Interactive & Visual',
    description: 'Playful interactive experiments — the size of space, spend Bill Gates\' money, the deep sea. Each one is a tiny, perfect rabbit hole.',
    reason: 'Delightful, shareable rabbit holes'
  },
  {
    id: 's4', title: 'Marginalia Search', url: 'https://search.marginalia.nu',
    domain: 'search.marginalia.nu', category: 'Indie Web & Discovery',
    description: 'A search engine that intentionally surfaces small, independent websites instead of SEO-optimized content farms. The anti-Google.',
    reason: 'Rediscover the weird, personal web'
  },
  {
    id: 's5', title: 'Hundred Rabbits', url: 'https://100r.co',
    domain: '100r.co', category: 'Indie Web & Discovery',
    description: 'Two artists living on a sailboat, building open-source creative tools that run on minimal hardware. Software as a lifestyle philosophy.',
    reason: 'Indie software meets unconventional living'
  },
  {
    id: 's6', title: 'The Pudding', url: 'https://pudding.cool',
    domain: 'pudding.cool', category: 'Data & Storytelling',
    description: 'Visual essays on culture, language, music, and trends — each one is a small interactive masterpiece backed by real data.',
    reason: 'Data journalism with craft and taste'
  },
  {
    id: 's7', title: 'Low Tech Magazine', url: 'https://solar.lowtechmagazine.com',
    domain: 'solar.lowtechmagazine.com', category: 'Unconventional Tech',
    description: 'A solar-powered website about sustainable technology and forgotten innovations. When the sun doesn\'t shine, the site goes down. On purpose.',
    reason: 'Technology criticism that practices what it preaches'
  },
  {
    id: 's8', title: 'Algorithms by Jeff Erickson', url: 'https://jeffe.cs.illinois.edu/teaching/algorithms/',
    domain: 'jeffe.cs.illinois.edu', category: 'CS & Learning',
    description: 'A free, beautifully written algorithms textbook used at top CS programs. Clear prose, no hand-waving, excellent exercises.',
    reason: 'The algorithms textbook you wish you\'d had'
  }
];

function getScoutCategories() {
  const seen = [];
  SCOUT_ITEMS.forEach(item => {
    if (!seen.includes(item.category)) seen.push(item.category);
  });
  return seen;
}

function renderScout() {
  const container = document.getElementById('scout-content');
  const categories = getScoutCategories();
  const today = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });

  // Build pixel divider (40 segments, alternating)
  let pixelDivider = '';
  for (let i = 0; i < 40; i++) {
    pixelDivider += `<span class="px ${i % 2 === 0 ? 'on' : ''}"></span>`;
  }

  let html = `
    <div class="scout-masthead">
      <div class="scout-dots">
        <span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="dot"></span>
      </div>
      <div class="scout-title">SCOUT</div>
      <div class="scout-pixel-divider">${pixelDivider}</div>
      <div class="scout-date">${today}</div>
    </div>
  `;

  categories.forEach((cat, catIdx) => {
    if (catIdx > 0) {
      // Section divider
      let divPx = '';
      for (let i = 0; i < 60; i++) divPx += `<span class="px ${i % 3 === 0 ? 'on' : ''}"></span>`;
      html += `<div class="scout-section-divider">${divPx}</div>`;
    }

    const items = SCOUT_ITEMS.filter(it => it.category === cat);

    // Category header dots
    let dots = '';
    for (let i = 0; i < 30; i++) dots += '<span class="d"></span>';

    html += `<div class="scout-category">`;
    html += `<div class="scout-category-header">
      <span class="block"></span>
      <span class="label">${escapeHtml(cat)}</span>
      <div class="dots">${dots}</div>
    </div>`;

    items.forEach((item, idx) => {
      if (idx > 0) {
        let sep = '';
        for (let i = 0; i < 20; i++) sep += '<span class="d"></span>';
        html += `<div class="scout-item-sep">${sep}</div>`;
      }

      const fb = scoutFeedback[item.id];
      const isSaved = linkStore.isSaved(item.url);

      html += `
        <div class="scout-item" data-scout-id="${item.id}" data-url="${escapeHtml(item.url)}">
          <div class="scout-item-title-row">
            <span class="scout-item-title">${escapeHtml(item.title)}</span>
            <span class="scout-item-domain">${escapeHtml(item.domain)}</span>
          </div>
          <div class="scout-item-desc">${escapeHtml(item.description)}</div>
          <div class="scout-item-reason">
            <span class="px"></span>
            <span class="reason-text">${escapeHtml(item.reason)}</span>
          </div>
          <div class="scout-item-actions">
            <div class="hover-actions">
              <button class="scout-action-btn open-btn" data-action="open" data-url="${escapeHtml(item.url)}">&#8599; open</button>
              <button class="scout-action-btn ${isSaved ? 'saved-btn' : 'save-btn'}" data-action="save" data-url="${escapeHtml(item.url)}" data-title="${escapeHtml(item.title)}">${isSaved ? '&#9733; saved' : '&#9734; save'}</button>
            </div>
            <span class="spacer"></span>
            <button class="scout-thumb-btn ${fb === 'liked' ? 'liked' : ''}" data-action="like" data-id="${item.id}">&#128077;</button>
            <button class="scout-thumb-btn ${fb === 'disliked' ? 'disliked' : ''}" data-action="dislike" data-id="${item.id}">&#128078;</button>
          </div>
        </div>
      `;
    });

    html += `</div>`;
  });

  // Footer
  let footerDivider = '';
  for (let i = 0; i < 40; i++) footerDivider += `<span class="px ${i % 2 === 0 ? 'on' : ''}"></span>`;

  html += `
    <div class="scout-footer">
      <div class="scout-pixel-divider">${footerDivider}</div>
      <div class="scout-footer-row">
        <button class="scout-footer-btn" id="scout-refresh-btn">&#8635; refresh</button>
        <span class="scout-footer-sep">//</span>
        <span class="scout-footer-label">scouted for you</span>
      </div>
    </div>
  `;

  container.innerHTML = html;

  // Wire up events
  container.querySelectorAll('.scout-item').forEach(row => {
    row.addEventListener('click', (e) => {
      if (e.target.closest('button')) return;
      chrome.tabs.create({ url: row.dataset.url });
    });
  });

  container.querySelectorAll('.scout-action-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      if (btn.dataset.action === 'open') {
        chrome.tabs.create({ url: btn.dataset.url });
      } else if (btn.dataset.action === 'save') {
        await linkStore.save(btn.dataset.url, btn.dataset.title);
        renderScout();
      }
    });
  });

  container.querySelectorAll('.scout-thumb-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const id = btn.dataset.id;
      const action = btn.dataset.action;
      if (action === 'like') {
        scoutFeedback[id] = scoutFeedback[id] === 'liked' ? null : 'liked';
      } else {
        scoutFeedback[id] = scoutFeedback[id] === 'disliked' ? null : 'disliked';
      }
      if (!scoutFeedback[id]) delete scoutFeedback[id];
      await chrome.storage.local.set({ scoutFeedback });
      renderScout();
    });
  });

  const refreshBtn = document.getElementById('scout-refresh-btn');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', () => renderScout());
  }
}

// --- Library ---
function renderLibrary() {
  const container = document.getElementById('library-content');

  // Get filtered links
  let links;
  if (libraryFilter === 'archive') {
    links = linkStore.getArchived();
  } else if (libraryFilter === 'tag' && libraryTagFilter) {
    links = linkStore.getByTag(libraryTagFilter);
  } else {
    links = linkStore.getInbox();
  }

  // Apply search
  if (librarySearchQuery) {
    const q = librarySearchQuery.toLowerCase();
    links = links.filter(l =>
      l.title.toLowerCase().includes(q) ||
      l.url.toLowerCase().includes(q) ||
      l.tags.some(t => t.toLowerCase().includes(q))
    );
  }

  const allTags = linkStore.allTags;

  let html = `
    <div class="library-header">
      <div class="library-title-row">
        <span class="block"></span>
        <span class="label">library</span>
      </div>
      <input class="library-search" type="text" placeholder="search links..." value="${escapeHtml(librarySearchQuery)}" id="library-search-input">
    </div>
    <div class="library-filters">
      <button class="library-filter-btn ${libraryFilter === 'inbox' ? 'active' : ''}" data-filter="inbox">inbox</button>
      <button class="library-filter-btn ${libraryFilter === 'archive' ? 'active' : ''}" data-filter="archive">archive</button>
      <button class="library-filter-btn ${libraryFilter === 'tag' ? 'active' : ''}" data-filter="tag">tag</button>
    </div>
  `;

  // Tag filter pills when tag filter is active
  if (libraryFilter === 'tag' && allTags.length > 0) {
    html += '<div class="library-tag-filters">';
    allTags.forEach(tag => {
      html += `<button class="library-tag-filter ${libraryTagFilter === tag ? 'active' : ''}" data-tag="${escapeHtml(tag)}">#${escapeHtml(tag)}</button>`;
    });
    html += '</div>';
  }

  if (links.length === 0) {
    html += `
      <div class="library-empty">
        <div class="library-empty-icon">&#9744;</div>
        <div class="library-empty-text">no links yet</div>
        <div class="library-empty-hint">save links with cmd+d</div>
      </div>
    `;
  } else {
    const grouped = linkStore.groupByDate(links);
    const order = ['today', 'yesterday', 'this week', 'older'];
    order.forEach(label => {
      const group = grouped[label];
      if (!group || group.length === 0) return;
      html += `<div class="library-date-group">`;
      html += `<div class="library-date-label">${label}</div>`;
      group.forEach(link => {
        const tagsHtml = link.tags.map(t => `<span class="library-link-tag">#${escapeHtml(t)}</span>`).join('');
        const domain = safeHost(link.url);
        const initial = domain ? domain[0].toUpperCase() : '?';
        html += `
          <div class="library-link-row" data-link-id="${link.id}" data-url="${escapeHtml(link.url)}">
            <div class="library-link-favicon">${initial}</div>
            <div class="library-link-info">
              <div class="library-link-title">${escapeHtml(link.title || 'Untitled')}</div>
              <div class="library-link-tags">${tagsHtml}</div>
            </div>
            <button class="library-link-menu-btn" data-link-id="${link.id}">&#8230;</button>
          </div>
        `;
      });
      html += '</div>';
    });
  }

  container.innerHTML = html;

  // Wire up events
  const searchInput = document.getElementById('library-search-input');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      librarySearchQuery = e.target.value;
      renderLibrary();
    });
    // Restore focus
    if (librarySearchQuery) {
      searchInput.focus();
      searchInput.setSelectionRange(searchInput.value.length, searchInput.value.length);
    }
  }

  container.querySelectorAll('.library-filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      libraryFilter = btn.dataset.filter;
      libraryTagFilter = null;
      renderLibrary();
    });
  });

  container.querySelectorAll('.library-tag-filter').forEach(btn => {
    btn.addEventListener('click', () => {
      libraryTagFilter = btn.dataset.tag;
      renderLibrary();
    });
  });

  container.querySelectorAll('.library-link-row').forEach(row => {
    row.addEventListener('click', (e) => {
      if (e.target.closest('.library-link-menu-btn')) return;
      chrome.tabs.create({ url: row.dataset.url });
    });
  });

  container.querySelectorAll('.library-link-menu-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const linkId = btn.dataset.linkId;
      const link = linkStore.links.find(l => l.id === linkId);
      if (!link) return;

      const rect = btn.getBoundingClientRect();
      const items = [
        { label: 'Open', action: () => chrome.tabs.create({ url: link.url }) },
        { label: 'Tag', action: () => showTagPopover(linkId, btn) },
        { divider: true },
        { label: link.isArchived ? 'Unarchive' : 'Archive', action: async () => {
          if (link.isArchived) await linkStore.unarchive(linkId);
          else await linkStore.archive(linkId);
          renderLibrary();
        }},
        { label: 'Delete', danger: true, action: async () => {
          await linkStore.remove(linkId);
          renderLibrary();
        }},
      ];
      showContextMenu(e, items);
    });
  });
}

function showTagPopover(linkId, anchorBtn) {
  // Remove any existing tag popover
  closeTagPopover();

  const link = linkStore.links.find(l => l.id === linkId);
  if (!link) return;

  const row = anchorBtn.closest('.library-link-row');
  const popover = document.createElement('div');
  popover.className = 'tag-popover';
  popover.id = 'active-tag-popover';

  const allTags = linkStore.allTags;

  let tagsHtml = '';
  allTags.forEach(tag => {
    const active = link.tags.includes(tag);
    tagsHtml += `<button class="tag-popover-tag ${active ? 'active' : 'inactive'}" data-tag="${escapeHtml(tag)}">#${escapeHtml(tag)}</button>`;
  });

  popover.innerHTML = `
    <div class="tag-popover-title">tags</div>
    <input class="tag-popover-input" type="text" placeholder="add tag..." id="tag-popover-input">
    <div class="tag-popover-tags">${tagsHtml}</div>
  `;

  row.style.position = 'relative';
  row.appendChild(popover);
  activeTagPopover = popover;

  // Focus input
  const input = popover.querySelector('#tag-popover-input');
  setTimeout(() => input.focus(), 50);

  input.addEventListener('keydown', async (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const tag = input.value.trim().toLowerCase().replace('#', '');
      if (tag) {
        await linkStore.addTag(linkId, tag);
        input.value = '';
        closeTagPopover();
        renderLibrary();
      }
    }
    if (e.key === 'Escape') {
      closeTagPopover();
    }
  });

  popover.querySelectorAll('.tag-popover-tag').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const tag = btn.dataset.tag;
      if (link.tags.includes(tag)) {
        await linkStore.removeTag(linkId, tag);
      } else {
        await linkStore.addTag(linkId, tag);
      }
      closeTagPopover();
      renderLibrary();
    });
  });

  // Close on outside click
  setTimeout(() => {
    document.addEventListener('click', tagPopoverOutsideClick);
  }, 10);
}

function tagPopoverOutsideClick(e) {
  if (activeTagPopover && !activeTagPopover.contains(e.target)) {
    closeTagPopover();
  }
}

function closeTagPopover() {
  document.removeEventListener('click', tagPopoverOutsideClick);
  if (activeTagPopover) {
    activeTagPopover.remove();
    activeTagPopover = null;
  }
}

// --- Start ---
init();
