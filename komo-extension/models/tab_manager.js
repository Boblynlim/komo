class TabManager {
  constructor() {
    this.folders = [];
    this.favorites = new Set();
    this.onUpdate = null;
    this.loadState();
  }

  async loadState() {
    const data = await chrome.storage.local.get(['folders', 'favorites']);
    this.folders = data.folders || [];
    this.favorites = new Set(data.favorites || []);
  }

  async saveState() {
    await chrome.storage.local.set({
      folders: this.folders,
      favorites: Array.from(this.favorites),
    });
  }

  async getTabs() {
    return chrome.tabs.query({ currentWindow: true });
  }

  async getActiveTab() {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    return tab;
  }

  async switchToTab(tabId) {
    await chrome.tabs.update(tabId, { active: true });
  }

  async closeTab(tabId) {
    await chrome.tabs.remove(tabId);
  }

  async createTab(url) {
    await chrome.tabs.create({ url });
  }

  // Folders
  createFolder(name) {
    const folder = { id: crypto.randomUUID(), name, tabIds: [], collapsed: false };
    this.folders.push(folder);
    this.saveState();
    return folder;
  }

  deleteFolder(folderId) {
    this.folders = this.folders.filter(f => f.id !== folderId);
    this.saveState();
  }

  renameFolder(folderId, name) {
    const folder = this.folders.find(f => f.id === folderId);
    if (folder) { folder.name = name; this.saveState(); }
  }

  toggleFolderCollapse(folderId) {
    const folder = this.folders.find(f => f.id === folderId);
    if (folder) { folder.collapsed = !folder.collapsed; this.saveState(); }
  }

  moveTabToFolder(tabId, folderId) {
    // Remove from all folders first
    this.folders.forEach(f => f.tabIds = f.tabIds.filter(id => id !== tabId));
    const folder = this.folders.find(f => f.id === folderId);
    if (folder) { folder.tabIds.push(tabId); this.saveState(); }
  }

  removeTabFromFolder(tabId) {
    this.folders.forEach(f => f.tabIds = f.tabIds.filter(id => id !== tabId));
    this.saveState();
  }

  getFolderForTab(tabId) {
    return this.folders.find(f => f.tabIds.includes(tabId));
  }

  getFolderedTabIds() {
    return new Set(this.folders.flatMap(f => f.tabIds));
  }

  // Favorites
  toggleFavorite(tabId) {
    if (this.favorites.has(tabId)) {
      this.favorites.delete(tabId);
    } else {
      this.favorites.add(tabId);
    }
    this.saveState();
  }

  isFavorite(tabId) {
    return this.favorites.has(tabId);
  }
}
