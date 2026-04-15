class LinkStore {
  constructor() {
    this.links = [];
    this.loadLinks();
  }

  async loadLinks() {
    const data = await chrome.storage.local.get('savedLinks');
    this.links = data.savedLinks || [];
  }

  async saveLinks() {
    await chrome.storage.local.set({ savedLinks: this.links });
  }

  async save(url, title, tags = [], notes = '') {
    if (this.links.find(l => l.url === url)) return; // no dupes
    const link = {
      id: crypto.randomUUID(),
      url, title, tags, notes,
      savedAt: Date.now(),
      isArchived: false,
    };
    this.links.unshift(link);
    await this.saveLinks();
    return link;
  }

  async remove(linkId) {
    this.links = this.links.filter(l => l.id !== linkId);
    await this.saveLinks();
  }

  async archive(linkId) {
    const link = this.links.find(l => l.id === linkId);
    if (link) { link.isArchived = true; await this.saveLinks(); }
  }

  async updateTags(linkId, tags) {
    const link = this.links.find(l => l.id === linkId);
    if (link) { link.tags = tags; await this.saveLinks(); }
  }

  search(query) {
    const q = query.toLowerCase();
    return this.links.filter(l =>
      l.title.toLowerCase().includes(q) ||
      l.url.toLowerCase().includes(q) ||
      l.tags.some(t => t.toLowerCase().includes(q))
    );
  }

  get allTags() {
    const tags = new Set(this.links.flatMap(l => l.tags));
    return Array.from(tags).sort();
  }

  getByTag(tag) {
    return this.links.filter(l => l.tags.includes(tag) && !l.isArchived);
  }

  suggestTags(url) {
    try {
      const host = new URL(url).hostname.replace('www.', '');
      const known = {
        'github.com': ['dev', 'code'],
        'dribbble.com': ['design'],
        'figma.com': ['design'],
        'medium.com': ['reading'],
        'youtube.com': ['video'],
        'twitter.com': ['social'],
        'x.com': ['social'],
        'reddit.com': ['social'],
        'news.ycombinator.com': ['dev', 'news'],
      };
      const suggestions = known[host] || [];
      // Also suggest tags from same domain
      const domainLinks = this.links.filter(l => {
        try { return new URL(l.url).hostname.replace('www.', '') === host; } catch { return false; }
      });
      domainLinks.forEach(l => l.tags.forEach(t => { if (!suggestions.includes(t)) suggestions.push(t); }));
      return suggestions;
    } catch { return []; }
  }
}
