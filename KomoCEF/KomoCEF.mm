// KomoCEF bridge implementation — embeds the Chromium engine (CEF) into komo.

#import <Cocoa/Cocoa.h>

#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

#include "KomoCEF.h"

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/cef_request_handler.h"
#include "include/cef_resource_request_handler.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

const char* komo_cef_version(void) {
  return CEF_VERSION;
}

// ---------------------------------------------------------------------------
// NSApplication subclass required by CEF (CefAppProtocol). Installed via the
// app bundle's Info.plist NSPrincipalClass = "KomoCEFApplication".
// ---------------------------------------------------------------------------
@interface KomoCEFApplication : NSApplication <CefAppProtocol> {
 @private
  BOOL handlingSendEvent_;
}
@end

@implementation KomoCEFApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}
- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}
@end

// ---------------------------------------------------------------------------
// CefApp — drives the external message pump so CEF cooperates with komo's run
// loop instead of owning it.
// ---------------------------------------------------------------------------
namespace {

// ---------------------------------------------------------------------------
// Ad/tracker blocklist. Written from the main thread (komo_cef_set_blocklist),
// read on CEF's IO thread (OnBeforeResourceLoad) — guarded by a mutex.
// ---------------------------------------------------------------------------
std::mutex g_blocklist_mtx;
std::unordered_set<std::string> g_blocklist;

// True if `host` equals, or is a subdomain of, any blocked domain. Walks the
// host's parent domains ("a.b.example.com" -> "b.example.com" -> ...).
bool IsBlockedHost(const std::string& host) {
  std::lock_guard<std::mutex> lock(g_blocklist_mtx);
  if (g_blocklist.empty()) {
    return false;
  }
  std::string h = host;
  while (true) {
    if (g_blocklist.count(h)) {
      return true;
    }
    const size_t dot = h.find('.');
    if (dot == std::string::npos) {
      break;
    }
    h = h.substr(dot + 1);
  }
  return false;
}

class KomoCefClient;

// Receives a downloaded favicon image and hands it to its client. Holds a
// strong ref so the client outlives the async download.
class FaviconDownloadCallback : public CefDownloadImageCallback {
 public:
  explicit FaviconDownloadCallback(CefRefPtr<KomoCefClient> client)
      : client_(client) {}
  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override;

 private:
  CefRefPtr<KomoCefClient> client_;
  IMPLEMENT_REFCOUNTING(FaviconDownloadCallback);
};

class KomoCefApp : public CefApp, public CefBrowserProcessHandler {
 public:
  KomoCefApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

 private:
  IMPLEMENT_REFCOUNTING(KomoCefApp);
};

// CefClient for a single browser. Forwards state changes to Swift callbacks.
class KomoCefClient : public CefClient,
                      public CefDisplayHandler,
                      public CefLoadHandler,
                      public CefLifeSpanHandler,
                      public CefRequestHandler,
                      public CefResourceRequestHandler {
 public:
  KomoCefClient(void* user_data, KomoBrowserCallbacks cbs)
      : user_data_(user_data), cbs_(cbs) {}

  // Keep the host NSView alive for the browser's whole lifetime — the Swift Tab
  // (which owns it) can dealloc before CEF finishes its async CloseBrowser.
  void SetHostView(void* nsview) {
    if (nsview) {
      host_view_ = CFBridgingRetain((__bridge id)nsview);
    }
  }
  // Stop forwarding callbacks into Swift once the tab is going away.
  void ClearCallbacks() {
    user_data_ = nullptr;
    cbs_ = KomoBrowserCallbacks{};
  }

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

  // CefRequestHandler — supply ourselves as the resource handler for every
  // request so we can filter (ad/tracker blocking).
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request,
      bool is_navigation,
      bool is_download,
      const CefString& request_initiator,
      bool& disable_default_handling) override {
    return this;
  }

  // CefResourceRequestHandler — cancel blocked hosts before they hit the net.
  cef_return_value_t OnBeforeResourceLoad(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      CefRefPtr<CefRequest> request,
      CefRefPtr<CefCallback> callback) override {
    CefURLParts parts;
    if (CefParseURL(request->GetURL(), parts)) {
      const std::string host = CefString(&parts.host).ToString();
      if (IsBlockedHost(host)) {
        return RV_CANCEL;
      }
    }
    return RV_CONTINUE;
  }

  // Encode a downloaded favicon as PNG and forward it to Swift. Called on the
  // UI thread (same as ClearCallbacks), so the cbs_ check is race-free.
  void DeliverFavicon(CefRefPtr<CefImage> image) {
    if (!cbs_.onFaviconChange || !image) {
      return;
    }
    int width = 0, height = 0;
    CefRefPtr<CefBinaryValue> png =
        image->GetAsPNG(1.0f, /*with_transparency=*/true, width, height);
    if (!png) {
      return;
    }
    const size_t size = png->GetSize();
    if (size == 0) {
      return;
    }
    std::vector<unsigned char> buf(size);
    png->GetData(buf.data(), size, 0);
    cbs_.onFaviconChange(user_data_, buf.data(), static_cast<int>(size));
  }

  // CefLifeSpanHandler
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    // When embedded in SwiftUI's hosting layer, CEF can think the browser is
    // hidden/occluded and skip painting. Force it visible + lay it out.
    browser->GetHost()->WasHidden(false);
    browser->GetHost()->WasResized();
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    browser_ = nullptr;
    if (host_view_) {
      CFRelease(host_view_);
      host_view_ = nullptr;
    }
  }

  // CefDisplayHandler
  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    if (cbs_.onTitleChange) {
      const std::string s = title.ToString();
      cbs_.onTitleChange(user_data_, s.c_str());
    }
  }
  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (frame->IsMain() && cbs_.onURLChange) {
      const std::string s = url.ToString();
      cbs_.onURLChange(user_data_, s.c_str());
    }
  }
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString>& icon_urls) override {
    if (!cbs_.onFaviconChange || icon_urls.empty() || !browser) {
      return;
    }
    // Download the first icon (CEF picks a sensible one), capped at 32px.
    browser->GetHost()->DownloadImage(icon_urls.front(), /*is_favicon=*/true,
                                      /*max_image_size=*/32,
                                      /*bypass_cache=*/false,
                                      new FaviconDownloadCallback(this));
  }

  // CefLoadHandler
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    if (cbs_.onLoadingChange) {
      cbs_.onLoadingChange(user_data_, isLoading);
    }
    if (cbs_.onCanGoBackChange) {
      cbs_.onCanGoBackChange(user_data_, canGoBack);
    }
    if (cbs_.onCanGoForwardChange) {
      cbs_.onCanGoForwardChange(user_data_, canGoForward);
    }
  }

  CefRefPtr<CefBrowser> browser() { return browser_; }

 private:
  void* user_data_;
  KomoBrowserCallbacks cbs_;
  CefRefPtr<CefBrowser> browser_;
  CFTypeRef host_view_ = nullptr;

  IMPLEMENT_REFCOUNTING(KomoCefClient);
};

void FaviconDownloadCallback::OnDownloadImageFinished(
    const CefString& image_url,
    int http_status_code,
    CefRefPtr<CefImage> image) {
  if (image) {
    client_->DeliverFavicon(image);
  }
}

std::string BundleSubPath(const char* sub) {
  NSString* base = [[NSBundle mainBundle] bundlePath];
  NSString* full = [base stringByAppendingString:[NSString stringWithUTF8String:sub]];
  return std::string([full UTF8String]);
}

}  // namespace

// ---------------------------------------------------------------------------
// C API
// ---------------------------------------------------------------------------
bool komo_cef_initialize(void) {
  // Load the CEF framework at runtime (required by the macOS sandbox model).
  static CefScopedLibraryLoader loader;
  if (!loader.LoadInMain()) {
    return false;
  }

  CefMainArgs main_args(0, nullptr);

  CefSettings settings;
  settings.no_sandbox = true;

  // komo-specific cache dir, so CEF's process singleton is well-defined
  // (the default is shared and collides with other CEF apps/instances).
  NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  CefString(&settings.root_cache_path)
      .FromString(std::string(
          [[appSupport stringByAppendingPathComponent:@"komo/cef_cache"]
              UTF8String]));

  CefString(&settings.framework_dir_path)
      .FromString(BundleSubPath(
          "/Contents/Frameworks/Chromium Embedded Framework.framework"));
  CefString(&settings.main_bundle_path)
      .FromString(std::string([[[NSBundle mainBundle] bundlePath] UTF8String]));
  // Leave browser_subprocess_path unset: CEF auto-discovers the dedicated
  // helper apps ("komo Helper (Renderer).app" etc.) in Contents/Frameworks.
  // The renderer needs its dedicated helper — a single generic helper makes
  // the renderer fail to launch (navigation aborts, blank page).

  CefRefPtr<KomoCefApp> app(new KomoCefApp);
  if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
    return false;
  }

  // CEF owns no run loop of its own here — pump it from a main-thread timer so
  // browsers actually paint. ~60Hz keeps rendering smooth.
  static dispatch_source_t s_pump = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(s_pump, DISPATCH_TIME_NOW,
                            (uint64_t)(NSEC_PER_SEC / 60),
                            (uint64_t)(NSEC_PER_MSEC));
  dispatch_source_set_event_handler(s_pump, ^{
    CefDoMessageLoopWork();
  });
  dispatch_resume(s_pump);
  return true;
}

void komo_cef_shutdown(void) {
  CefShutdown();
}

void komo_cef_set_blocklist(const char* const* domains, int count) {
  std::lock_guard<std::mutex> lock(g_blocklist_mtx);
  g_blocklist.clear();
  for (int i = 0; i < count; ++i) {
    if (domains[i] && domains[i][0]) {
      g_blocklist.insert(domains[i]);
    }
  }
}

void* komo_cef_create_browser(void* nsview,
                              const char* url,
                              void* userData,
                              KomoBrowserCallbacks callbacks) {
  CefRefPtr<KomoCefClient> client(new KomoCefClient(userData, callbacks));
  client->SetHostView(nsview);

  NSView* view = (__bridge NSView*)nsview;
  const NSRect b = [view bounds];

  CefWindowInfo window_info;
  CefRect bounds(0, 0, static_cast<int>(b.size.width),
                 static_cast<int>(b.size.height));
  window_info.SetAsChild(static_cast<CefWindowHandle>(nsview), bounds);
  window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

  CefBrowserSettings browser_settings;
  if (!CefBrowserHost::CreateBrowser(window_info, client,
                                     std::string(url ? url : "about:blank"),
                                     browser_settings, nullptr, nullptr)) {
    return nullptr;
  }

  // Keep the client alive for the handle's lifetime (released in close).
  client->AddRef();
  return client.get();
}

void komo_cef_load_url(void* handle, const char* url) {
  if (!handle || !url) {
    return;
  }
  auto* client = static_cast<KomoCefClient*>(handle);
  if (CefRefPtr<CefBrowser> b = client->browser()) {
    b->GetMainFrame()->LoadURL(std::string(url));
  }
}

void komo_cef_go_back(void* handle) {
  if (!handle) return;
  if (CefRefPtr<CefBrowser> b = static_cast<KomoCefClient*>(handle)->browser()) {
    b->GoBack();
  }
}

void komo_cef_go_forward(void* handle) {
  if (!handle) return;
  if (CefRefPtr<CefBrowser> b = static_cast<KomoCefClient*>(handle)->browser()) {
    b->GoForward();
  }
}

void komo_cef_reload(void* handle) {
  if (!handle) return;
  if (CefRefPtr<CefBrowser> b = static_cast<KomoCefClient*>(handle)->browser()) {
    b->Reload();
  }
}

void komo_cef_stop_load(void* handle) {
  if (!handle) return;
  if (CefRefPtr<CefBrowser> b = static_cast<KomoCefClient*>(handle)->browser()) {
    b->StopLoad();
  }
}

void komo_cef_set_focus(void* handle, bool focused) {
  if (!handle) return;
  if (CefRefPtr<CefBrowser> b = static_cast<KomoCefClient*>(handle)->browser()) {
    b->GetHost()->SetFocus(focused);
  }
}

void komo_cef_close_browser(void* handle) {
  if (!handle) return;
  auto* client = static_cast<KomoCefClient*>(handle);
  client->ClearCallbacks();
  if (CefRefPtr<CefBrowser> b = client->browser()) {
    b->GetHost()->CloseBrowser(true);
  }
  client->Release();
}
