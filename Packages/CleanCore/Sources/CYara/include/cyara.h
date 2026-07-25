#ifndef CYARA_H
#define CYARA_H

#ifdef __cplusplus
extern "C" {
#endif

// libyara's real types (YR_COMPILER, YR_RULES, YR_RULE, YR_SCAN_CONTEXT) are
// never exposed here — several contain anonymous unions and non-recursive but
// still Swift-unfriendly layouts, the same category of problem `CFTS` solves
// for `FTSENT`. Swift only ever holds these as opaque `void *` handles; every
// libyara struct access happens inside cyara.c.
typedef void CYaraCompiler;
typedef void CYaraRules;

typedef struct {
    char **identifiers; // owned; release via cyara_free_match_list
    int count;
} CYaraMatchList;

int cyara_initialize(void);
int cyara_finalize(void);

int cyara_compiler_create(CYaraCompiler **outCompiler);
void cyara_compiler_destroy(CYaraCompiler *compiler);

// Compiles one YARA rule source string into `compiler`'s default namespace.
// Returns libyara's compilation error count (0 == success). On failure, if
// `errorMessage` is non-NULL it receives a malloc'd description the caller
// must release via `cyara_free_string`.
int cyara_compiler_add_rule(CYaraCompiler *compiler, const char *ruleSource, char **errorMessage);

// Finalizes `compiler`'s accumulated rules into a scannable `CYaraRules`.
// Returns a libyara error code (0 == success). `compiler` remains owned by
// the caller and must still be destroyed separately.
int cyara_compiler_get_rules(CYaraCompiler *compiler, CYaraRules **outRules);

void cyara_rules_destroy(CYaraRules *rules);

// Scans `filename` against `rules`. Returns a libyara error code (0 ==
// success, regardless of match count). On success `*outMatches` holds every
// matching rule's identifier and the caller must release it with
// `cyara_free_match_list`; left zeroed on failure.
int cyara_scan_file(CYaraRules *rules, const char *filename, int timeoutSeconds, CYaraMatchList *outMatches);

void cyara_free_match_list(CYaraMatchList *list);
void cyara_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif /* CYARA_H */
