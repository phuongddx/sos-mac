import Foundation

public enum ThermalState: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

/// Deliberately does NOT read raw SMC keys for CPU/GPU temperature or fan
/// speed. There is no public Apple API for SMC access — every "temperature"
/// reader in the wild uses an undocumented, reverse-engineered key-value
/// protocol whose key table differs across Intel and every Apple Silicon
/// generation (M1/M2/M3/M4). Getting a key wrong there doesn't fail loudly —
/// it silently returns a plausible-looking wrong number, which is worse than
/// this phase's own explicit fallback: "return nil/.unavailable rather than
/// throw on unsupported keys." `ProcessInfo.thermalState` is Apple's own
/// supported thermal-pressure signal, identical on both architectures, and
/// always available — used here instead.
public enum IOKitSensors {
    public static func isAppleSilicon() -> Bool {
        SysctlReader.isAppleSilicon()
    }

    public static func thermalState() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    /// No public API exists for GPU utilization without a private framework
    /// (IOAccelerator) — reporting unavailable rather than guessing.
    public static func gpuUtilizationPercent() -> Double? {
        nil
    }
}
