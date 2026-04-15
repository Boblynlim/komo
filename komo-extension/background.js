// Open side panel when extension icon clicked
chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });

// Handle keyboard shortcuts
chrome.commands.onCommand.addListener((command) => {
  if (command === 'open-command-bar') {
    chrome.runtime.sendMessage({ type: 'toggle-command-bar' });
  } else if (command === 'save-link') {
    chrome.runtime.sendMessage({ type: 'save-current-link' });
  }
});

// Open side panel by default on install
chrome.runtime.onInstalled.addListener(() => {
  chrome.sidePanel.setOptions({ enabled: true });
});
