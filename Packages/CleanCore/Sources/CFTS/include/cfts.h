#ifndef CFTS_H
#define CFTS_H

#include <fts.h>
#include <sys/stat.h>

// Swift can't call the fts() family directly because FTSENT contains a
// recursive pointer layout (fts_cycle, fts_parent) that doesn't import
// cleanly. This shim re-exposes the same calls under names Swift can see
// as plain opaque-pointer APIs, with no behavior change.

static inline FTS *cfts_open(char * const *pathArgv, int options) {
    return fts_open(pathArgv, options, NULL);
}

static inline FTSENT *cfts_read(FTS *ftsp) {
    return fts_read(ftsp);
}

static inline int cfts_close(FTS *ftsp) {
    return fts_close(ftsp);
}

static inline const char *cfts_entry_path(const FTSENT *ent) {
    return ent->fts_path;
}

static inline short cfts_entry_info(const FTSENT *ent) {
    return ent->fts_info;
}

static inline off_t cfts_entry_size(const FTSENT *ent) {
    return ent->fts_statp ? ent->fts_statp->st_size : 0;
}

static inline time_t cfts_entry_atime(const FTSENT *ent) {
    return ent->fts_statp ? ent->fts_statp->st_atime : 0;
}

static inline time_t cfts_entry_mtime(const FTSENT *ent) {
    return ent->fts_statp ? ent->fts_statp->st_mtime : 0;
}

#endif /* CFTS_H */
