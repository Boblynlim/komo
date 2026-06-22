// KomoCEF — Objective-C++ bridge exposing the Chromium engine (CEF) to komo's
// Swift code: initialize the engine, embed a browser into an NSView, drive
// navigation, and report state changes back to Swift.

#ifndef KOMO_CEF_H
#define KOMO_CEF_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Version of CEF/Chromium komo was built against.
const char* komo_cef_version(void);

// Initialize CEF for the browser (main) process. Call ONCE, very early — from
// the app delegate's applicationWillFinishLaunching, after the custom
// NSApplication (NSPrincipalClass = KomoCEFApplication) is in place. Uses an
// external message pump so CEF cooperates with komo's existing run loop.
// Returns false on failure.
bool komo_cef_initialize(void);

// Shut CEF down (call on app termination).
void komo_cef_shutdown(void);

// Per-browser callbacks back into Swift. `userData` is the opaque pointer
// passed to komo_cef_create_browser (komo passes the Tab).
typedef void (*KomoStringCallback)(void* userData, const char* value);
typedef void (*KomoBoolCallback)(void* userData, bool value);

typedef struct {
  KomoStringCallback onTitleChange;
  KomoStringCallback onURLChange;
  KomoBoolCallback onLoadingChange;
  KomoBoolCallback onCanGoBackChange;
  KomoBoolCallback onCanGoForwardChange;
} KomoBrowserCallbacks;

// Create a Chromium browser parented into `nsview`, loading `url`.
// Returns an opaque browser handle (NULL on failure).
void* komo_cef_create_browser(void* nsview,
                              const char* url,
                              void* userData,
                              KomoBrowserCallbacks callbacks);

void komo_cef_load_url(void* browser, const char* url);
void komo_cef_go_back(void* browser);
void komo_cef_go_forward(void* browser);
void komo_cef_reload(void* browser);
void komo_cef_close_browser(void* browser);

#ifdef __cplusplus
}
#endif

#endif  // KOMO_CEF_H
