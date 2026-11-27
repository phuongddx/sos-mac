import Testing
@testable import CleanCore

/// `GateSmokeMode` is the contract between the three executables' startup
/// checks and `Scripts/verify-gate.sh` step 4. These tests pin the contract so
/// a rename fails here instead of silently turning the gate's smoke launch
/// into a real UI launch.
@Suite struct GateSmokeModeTests {
    @Test("Flag literal stays in sync with Scripts/verify-gate.sh")
    func flagIsStable() {
        #expect(GateSmokeMode.flag == "--gate-smoke")
    }

    @Test("Disabled without the flag in this process's arguments")
    func disabledByDefault() {
        #expect(!GateSmokeMode.isEnabled)
    }
}
