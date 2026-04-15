const tabManager = new TabManager();
const linkStore = new LinkStore();

let activeTabId = null;
let commandBarSelectedIndex = 0;
let commandBarResults = [];
let contextMenu = null;

// --- Init ---
async function init() {
  await tabManager.loadState();
  await linkStore.loadLinks();
  render();

  // Listen for tab changes
  chrome.tabs.onUpdated.addListener(() => render());
  chrome.tabs.onRemoved.addListener(() => render());
  chrome.tabs.onActivated.addListener((info) => {
    activeTabId = info.tabId;
    render();
  });
  chrome.tabs.onMoved.addListener(() => render());

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
    if (e.metaKey && e.key === 'k') { e.preventDefault(); toggleCommandBar(); }
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
function toggleCommandBar() {
  const overlay = document.getElementById('command-bar-overlay');
  overlay.classList.toggle('hidden');
  if (!overlay.classList.contains('hidden')) {
    const input = document.getElementById('command-bar-input');
    input.value = '';
    input.focus();
    commandBarSelectedIndex = 0;
    updateCommandBarResults();
    input.addEventListener('input', updateCommandBarResults);
    input.addEventListener('keydown', handleCommandBarKeys);
  }
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
    updateCommandBarResults();
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    commandBarSelectedIndex = Math.max(0, commandBarSelectedIndex - 1);
    updateCommandBarResults();
  } else if (e.key === 'Enter') {
    e.preventDefault();
    executeCommandBarResult(commandBarSelectedIndex);
  } else if (e.key === 'Escape') {
    e.preventDefault();
    toggleCommandBar();
  }
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

// --- Start ---
init();
