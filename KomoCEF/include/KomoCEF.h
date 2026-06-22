// KomoCEF — Objective-C++ bridge exposing the Chromium engine (CEF) to komo's
// Swift code. Start minimal: prove komo's build can compile against CEF headers
// and link the CEF wrapper. The browser-embedding API grows from here.

#ifndef KOMO_CEF_H
#define KOMO_CEF_H

#ifdef __cplusplus
extern "C" {
#endif

// Returns the CEF version string komo was built against (e.g. "149.0.4+...").
const char* komo_cef_version(void);

#ifdef __cplusplus
}
#endif

#endif  // KOMO_CEF_H
