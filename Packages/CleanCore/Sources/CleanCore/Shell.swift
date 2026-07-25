import Foundation

public enum ShellError: Error, Sendable {
    case timedOut
    case nonZeroExit(code: Int32, stderr: String)
    case launchFailed(String)
}

/// Centralizes every `Process` invocation the suite needs (`purge`,
/// `dscacheutil -flushcache`, etc.) behind one timeout/error-handling path so
/// call sites never launch a process unsupervised.
public enum Shell {
    public static func run(
        _ executable: String,
        args: [String] = [],
        timeout: TimeInterval = 30
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timedOut = TimeoutFlag()

        // Drain both pipes concurrently *while the process runs*, not after
        // waitUntilExit(): a child that writes more than the OS pipe buffer
        // (~64KB) before exiting would otherwise block on the write syscall
        // forever with nothing reading the other end, and waitUntilExit()
        // would deadlock waiting for a child stuck mid-write.
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutReader = Task.detached(priority: .utility) { () -> Data in
            var collected = Data()
            while true {
                let chunk = stdoutHandle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
            }
            return collected
        }
        let stderrReader = Task.detached(priority: .utility) { () -> Data in
            var collected = Data()
            while true {
                let chunk = stderrHandle.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
            }
            return collected
        }

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(error.localizedDescription)
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                await timedOut.mark()
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = await stdoutReader.value
        let stderrData = await stderrReader.value

        // `timedOut` alone is racy: the process can finish normally in the
        // narrow window between the timeout task's isRunning check and its
        // terminate() call, which would otherwise misreport a successful run
        // as a timeout. terminationReason is the authoritative signal — a
        // real timeout-kill ends in .uncaughtSignal, a normal exit does not.
        if await timedOut.value, process.terminationReason == .uncaughtSignal {
            throw ShellError.timedOut
        }

        guard process.terminationStatus == 0 else {
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw ShellError.nonZeroExit(code: process.terminationStatus, stderr: stderrString)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}

/// Actor-isolated instead of a plain var so the timeout task (racing against
/// `waitUntilExit` off the calling task) can't create a data race under
/// Swift 6 strict concurrency — and so we can tell "we killed it" apart from
/// any other signal that might end the process.
private actor TimeoutFlag {
    private(set) var value = false
    func mark() { value = true }
}
