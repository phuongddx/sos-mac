#include "cyara.h"
#include <yara.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char **identifiers;
    int count;
    int capacity;
} CYaraCollector;

static void cyara_collector_init(CYaraCollector *collector) {
    collector->identifiers = NULL;
    collector->count = 0;
    collector->capacity = 0;
}

static void cyara_collector_free(CYaraCollector *collector) {
    for (int i = 0; i < collector->count; i++) {
        free(collector->identifiers[i]);
    }
    free(collector->identifiers);
    collector->identifiers = NULL;
    collector->count = 0;
    collector->capacity = 0;
}

// Returns 0 on success, non-zero if a malloc failure prevented recording the
// match — the scan itself continues either way (a dropped match on OOM is
// preferable to aborting the whole scan).
static int cyara_collector_append(CYaraCollector *collector, const char *identifier) {
    if (collector->count == collector->capacity) {
        int newCapacity = collector->capacity == 0 ? 4 : collector->capacity * 2;
        char **grown = (char **)realloc(collector->identifiers, sizeof(char *) * (size_t)newCapacity);
        if (!grown) return 1;
        collector->identifiers = grown;
        collector->capacity = newCapacity;
    }
    char *copy = strdup(identifier);
    if (!copy) return 1;
    collector->identifiers[collector->count] = copy;
    collector->count += 1;
    return 0;
}

static int cyara_scan_callback(YR_SCAN_CONTEXT *context, int message, void *message_data, void *user_data) {
    (void)context;
    if (message == CALLBACK_MSG_RULE_MATCHING) {
        YR_RULE *rule = (YR_RULE *)message_data;
        CYaraCollector *collector = (CYaraCollector *)user_data;
        cyara_collector_append(collector, rule->identifier);
    }
    return CALLBACK_CONTINUE;
}

int cyara_initialize(void) {
    return yr_initialize();
}

int cyara_finalize(void) {
    return yr_finalize();
}

int cyara_compiler_create(CYaraCompiler **outCompiler) {
    return yr_compiler_create((YR_COMPILER **)outCompiler);
}

void cyara_compiler_destroy(CYaraCompiler *compiler) {
    if (compiler) yr_compiler_destroy((YR_COMPILER *)compiler);
}

int cyara_compiler_add_rule(CYaraCompiler *compiler, const char *ruleSource, char **errorMessage) {
    int errors = yr_compiler_add_string((YR_COMPILER *)compiler, ruleSource, NULL);
    if (errors != 0 && errorMessage != NULL) {
        char buffer[512];
        char *message = yr_compiler_get_error_message((YR_COMPILER *)compiler, buffer, sizeof(buffer));
        *errorMessage = strdup(message ? message : "YARA rule compilation failed");
    }
    return errors;
}

int cyara_compiler_get_rules(CYaraCompiler *compiler, CYaraRules **outRules) {
    return yr_compiler_get_rules((YR_COMPILER *)compiler, (YR_RULES **)outRules);
}

void cyara_rules_destroy(CYaraRules *rules) {
    if (rules) yr_rules_destroy((YR_RULES *)rules);
}

int cyara_scan_file(CYaraRules *rules, const char *filename, int timeoutSeconds, CYaraMatchList *outMatches) {
    CYaraCollector collector;
    cyara_collector_init(&collector);

    int result = yr_rules_scan_file(
        (YR_RULES *)rules, filename, 0, cyara_scan_callback, &collector, timeoutSeconds);

    if (result != ERROR_SUCCESS) {
        cyara_collector_free(&collector);
        outMatches->identifiers = NULL;
        outMatches->count = 0;
        return result;
    }

    outMatches->identifiers = collector.identifiers;
    outMatches->count = collector.count;
    return ERROR_SUCCESS;
}

void cyara_free_match_list(CYaraMatchList *list) {
    if (!list || !list->identifiers) return;
    for (int i = 0; i < list->count; i++) {
        free(list->identifiers[i]);
    }
    free(list->identifiers);
    list->identifiers = NULL;
    list->count = 0;
}

void cyara_free_string(char *s) {
    if (s) free(s);
}
