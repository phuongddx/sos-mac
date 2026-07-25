import CYara
import Foundation

public enum YaraScannerError: Error, Sendable, Equatable {
    case libraryInitializationFailed(Int32)
    case compilerCreationFailed(Int32)
    case ruleCompilationFailed(String)
    case rulesUnavailable(Int32)
    case scanFailed(Int32)
}

/// One matched YARA rule identifier for a scanned file.
public struct YaraMatch: Sendable, Hashable {
    public let ruleIdentifier: String

    public init(ruleIdentifier: String) {
        self.ruleIdentifier = ruleIdentifier
    }
}

/// Compiles YARA rule sources via `libyara` (through the `CYara` C shim) and
/// scans files for pattern matches beyond exact hash equality. All of
/// libyara's own struct complexity (`YR_COMPILER`, `YR_RULES`, the scan
/// callback) stays inside the shim — this type only ever holds an opaque
/// `CYaraRules` pointer.
///
/// `yr_initialize`/`yr_finalize` are process-global per libyara's own
/// contract, so initialization happens exactly once per process via a
/// `static let` (Swift guarantees single, thread-safe execution).
public final class YaraScanner: @unchecked Sendable {
    private static let initializeOnce: Bool = {
        let result = cyara_initialize()
        return result == 0
    }()

    private let rules: UnsafeMutableRawPointer

    /// Compiles `ruleSources` (one or more YARA rule-file contents) into a
    /// single scannable ruleset. Throws on the first rule that fails to
    /// compile, surfacing libyara's own error message.
    public init(ruleSources: [String]) throws {
        guard Self.initializeOnce else {
            throw YaraScannerError.libraryInitializationFailed(-1)
        }

        var rawCompiler: UnsafeMutableRawPointer?
        let createResult = cyara_compiler_create(&rawCompiler)
        guard createResult == 0, let compiler = rawCompiler else {
            throw YaraScannerError.compilerCreationFailed(createResult)
        }
        defer { cyara_compiler_destroy(compiler) }

        for source in ruleSources {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let errorCount = source.withCString { cString in
                cyara_compiler_add_rule(compiler, cString, &errorMessage)
            }
            if errorCount != 0 {
                let message = errorMessage.map { String(cString: $0) } ?? "unknown YARA compilation error"
                if let errorMessage { cyara_free_string(errorMessage) }
                throw YaraScannerError.ruleCompilationFailed(message)
            }
        }

        var rawRules: UnsafeMutableRawPointer?
        let rulesResult = cyara_compiler_get_rules(compiler, &rawRules)
        guard rulesResult == 0, let compiledRules = rawRules else {
            throw YaraScannerError.rulesUnavailable(rulesResult)
        }
        self.rules = compiledRules
    }

    deinit {
        cyara_rules_destroy(rules)
    }

    /// Scans one file at `path`, returning every YARA rule that matched.
    /// `timeoutSeconds` bounds a single pathological rule/file combination
    /// (e.g. a catastrophic-backtracking pattern against a huge file) from
    /// hanging the whole Protection scan.
    public func scan(filePath path: String, timeoutSeconds: Int32 = 30) throws -> [YaraMatch] {
        var matchList = CYaraMatchList(identifiers: nil, count: 0)
        let result = path.withCString { cPath in
            cyara_scan_file(rules, cPath, timeoutSeconds, &matchList)
        }
        guard result == 0 else {
            throw YaraScannerError.scanFailed(result)
        }
        defer { cyara_free_match_list(&matchList) }

        guard let identifiers = matchList.identifiers else { return [] }
        return (0..<Int(matchList.count)).map { index in
            YaraMatch(ruleIdentifier: String(cString: identifiers[index]!))
        }
    }
}
