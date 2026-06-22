// KomoCEF bridge implementation.

#include "KomoCEF.h"

#include "include/cef_version.h"

extern "C" const char* komo_cef_version(void) {
  return CEF_VERSION;
}
