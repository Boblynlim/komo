// komo swiftcef — CefApp that embeds a Chromium browser into a Swift-built view.
// Based on CEF's cefsimple sample (BSD-style license).

#include "tests/swiftcef/simple_app.h"

#include <string>

#include "include/cef_browser.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"
#include "tests/swiftcef/simple_handler.h"

// Implemented in main.swift (C ABI). Builds the NSWindow + content view on the
// macOS main thread and returns the content NSView* for CEF to parent into.
extern "C" void* komo_build_browser_window();

SimpleApp::SimpleApp() = default;

void SimpleApp::OnContextInitialized() {
  CEF_REQUIRE_UI_THREAD();

  CefRefPtr<CefCommandLine> command_line =
      CefCommandLine::GetGlobalCommandLine();

  // Alloy style is what lets us embed the browser inside an app-provided view.
  CefRefPtr<SimpleHandler> handler(new SimpleHandler(/*is_alloy_style=*/true));

  CefBrowserSettings browser_settings;

  std::string url = command_line->GetSwitchValue("url");
  if (url.empty()) {
    url = "https://example.com";
  }

  // Ask the Swift layer to build the window + content view, then parent a
  // Chromium browser into that Swift-created NSView.
  void* nsview = komo_build_browser_window();

  CefWindowInfo window_info;
  CefRect bounds(0, 0, 1000, 700);
  window_info.SetAsChild(static_cast<CefWindowHandle>(nsview), bounds);
  window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

  CefBrowserHost::CreateBrowser(window_info, handler, url, browser_settings,
                                nullptr, nullptr);
}

CefRefPtr<CefClient> SimpleApp::GetDefaultClient() {
  return SimpleHandler::GetInstance();
}
