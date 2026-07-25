#include "cfts.h"

// All functionality lives in cfts.h as `static inline` — this translation
// unit exists only because Xcode's local-package build graph expects at
// least one compiled source per target (a header-only C target produces no
// object file, which breaks Xcode's link step even though `swift build`
// handles it fine).
