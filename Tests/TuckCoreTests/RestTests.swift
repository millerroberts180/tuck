import Foundation
import Testing
@testable import TuckCore

/// Records every signal, so tests prove what Rest would send without sending anything.
final class FakeProcessControl: ProcessControl {
    var processes: [Int32: ProcessIdentity] = [:]
    var paused: Set<Int32> = []
    var pauseAccepted = true
    var resumeAccepted = true
    var pauseTakesEffect = true
    private(set) var signals: [String] = []

    func identity(of pid: Int32) -> ProcessIdentity? { processes[pid] }
    func pause(_ pid: Int32) -> Bool {
        signals.append("stop \(pid)")
        guard pauseAccepted else { return false }
        if pauseTakesEffect { paused.insert(pid) }
        return true
    }
    func resume(_ pid: Int32) -> Bool {
        signals.append("cont \(pid)")
        guard resumeAccepted else { return false }
        paused.remove(pid)
        return true
    }
    func isPaused(_ pid: Int32) -> Bool? { processes[pid] == nil ? nil : paused.contains(pid) }
}

let preview = AppIdentity(bundleID: "com.apple.Preview", name: "Preview")
let previewProcess = ProcessIdentity(pid: 4242, startTime: 1_700_000_000.25, executablePath: "/System/Applications/Preview.app/Contents/MacOS/Preview", bundleID: "com.apple.Preview")

@Suite("Rest eligibility")
struct RestEligibilityTests {
    let calm = RestContext(isUsingAudio: false, recentCPUPercent: 0.4)

    @Test func allowListedOfflineAppsAreEligibleWhenQuiet() {
        #expect(RestSafetyPolicy.eligibility(for: preview, context: calm) == .eligible)
    }

    @Test func riskyCategoriesAreRefusedWithAReason() {
        for (bundleID, category) in [("com.apple.Music", RestRiskCategory.media), ("us.zoom.xos", .calls),
                                     ("com.apple.Terminal", .terminal), ("com.apple.dt.Xcode", .developerTools),
                                     ("com.getdropbox.dropbox", .sync), ("com.apple.ScreenSharing", .remoteDesktop),
                                     ("com.apple.ActivityMonitor", .system), ("com.transmissionbt.Transmission", .transfers)] {
            let result = RestSafetyPolicy.eligibility(for: AppIdentity(bundleID: bundleID, name: "X"), context: calm)
            #expect(result == .unavailable(reason: "Not safe to rest \(category.label) apps."))
        }
    }

    @Test func unknownAppsAreRefusedBecauseTheyAreAmbiguous() {
        let result = RestSafetyPolicy.eligibility(for: AppIdentity(bundleID: "com.example.Unknown", name: "U"), context: calm)
        guard case .unavailable = result else { Issue.record("unknown app was allowed"); return }
    }

    @Test func liveFactsBlockOrRaiseTheBar() {
        func check(_ context: RestContext) -> RestEligibility { RestSafetyPolicy.eligibility(for: preview, context: context) }
        guard case .unavailable = check(RestContext(isOwnApp: true)) else { Issue.record("own app"); return }
        guard case .unavailable = check(RestContext(isFrontmost: true)) else { Issue.record("frontmost"); return }
        guard case .unavailable = check(RestContext(visibleWindowCount: 1)) else { Issue.record("visible windows"); return }
        guard case .unavailable = check(RestContext(isUsingAudio: true)) else { Issue.record("audio"); return }
        guard case .needsStrongConfirmation = check(RestContext(isUsingAudio: nil)) else { Issue.record("unknown audio"); return }
        guard case .needsStrongConfirmation = check(RestContext(isUsingAudio: false, recentCPUPercent: 40)) else { Issue.record("busy"); return }
        let unidentified = RestSafetyPolicy.eligibility(for: AppIdentity(bundleID: "", name: "X"), context: calm)
        guard case .unavailable = unidentified else { Issue.record("no bundle id"); return }
    }

    @Test func theFirstUseExplanationIsTheAgreedWording() {
        #expect(RestSafetyPolicy.firstUseExplanation
                == "Rest pauses this app to reduce active CPU work. It stays in memory and may pause playback, calls, downloads, syncing, terminals, or network activity.")
    }
}

@Suite("Rest pause and wake")
struct RestControllerTests {
    func control() -> FakeProcessControl {
        let control = FakeProcessControl()
        control.processes[previewProcess.pid] = previewProcess
        return control
    }

    func rest(_ control: FakeProcessControl, eligibility: RestEligibility = .eligible, strong: Bool = false,
              acknowledged: Bool = true, enabled: Bool = true, expected: ProcessIdentity? = previewProcess) -> Result<RestState, RestFailure> {
        RestController.rest(expected: expected, eligibility: eligibility, confirmedStrongly: strong,
                            acknowledged: acknowledged, isEnabled: enabled, control: control, now: Date(timeIntervalSince1970: 0))
    }

    @Test func switchedOffNothingIsEverSignalled() {
        let fake = control()
        #expect(rest(fake, enabled: false) == .failure(.disabled))
        #expect(fake.signals.isEmpty)
    }

    @Test func restingNeedsTheExplanationAndEligibility() {
        let fake = control()
        #expect(rest(fake, acknowledged: false) == .failure(.notAcknowledged))
        #expect(rest(fake, eligibility: .unavailable(reason: "no")) == .failure(.notEligible("no")))
        #expect(rest(fake, eligibility: .needsStrongConfirmation(reason: "busy")) == .failure(.needsStrongConfirmation("busy")))
        #expect(fake.signals.isEmpty)
        #expect(rest(fake, eligibility: .needsStrongConfirmation(reason: "busy"), strong: true)
                == .success(.resting(since: Date(timeIntervalSince1970: 0), process: previewProcess)))
    }

    @Test func aReusedPidIsNeverSignalled() {
        let fake = control()
        fake.processes[previewProcess.pid] = ProcessIdentity(pid: previewProcess.pid, startTime: 1_800_000_000,
                                                             executablePath: "/usr/bin/other", bundleID: "com.other")
        #expect(rest(fake) == .failure(.processChanged))
        fake.processes[previewProcess.pid] = nil
        #expect(rest(fake) == .failure(.processGone))
        #expect(fake.signals.isEmpty)
    }

    @Test func aPauseThatDoesNotTakeHoldIsUndone() {
        let fake = control()
        fake.pauseTakesEffect = false
        #expect(rest(fake) == .failure(.didNotTakeEffect))
        #expect(fake.signals == ["stop 4242", "cont 4242"])
        fake.pauseAccepted = false
        #expect(rest(fake) == .failure(.signalFailed))
    }

    @Test func wakingResumesTheSameProcessOnly() {
        let fake = control()
        let state = RestState.resting(since: Date(), process: previewProcess)
        fake.paused = [previewProcess.pid]
        #expect(RestController.wake(state, control: fake) == .woke)
        #expect(!fake.paused.contains(previewProcess.pid))
        #expect(RestController.wake(.awake, control: fake) == .wasAwake)
        fake.processes[previewProcess.pid] = nil
        #expect(RestController.wake(state, control: fake) == .stale)
        #expect(fake.signals == ["cont 4242"])
    }

    @Test func aFailedWakeIsReportedAndKeptForAnotherTry() {
        let fake = control()
        fake.resumeAccepted = false
        let states = ["com.apple.Preview": RestState.resting(since: Date(), process: previewProcess)]
        #expect(RestController.wake(states["com.apple.Preview"]!, control: fake) == .failed(.signalFailed))
        #expect(RestController.wakeAll(states, control: fake).count == 1)
        fake.resumeAccepted = true
        #expect(RestController.wakeAll(states, control: fake).isEmpty)
    }

    @Test func recoveryAfterACrashOnlyTouchesTheRecordedProcess() {
        let fake = control()
        let gone = ProcessIdentity(pid: 7, startTime: 1, executablePath: "/x", bundleID: "com.apple.TextEdit")
        let states = ["com.apple.Preview": RestState.resting(since: Date(), process: previewProcess),
                      "com.apple.TextEdit": RestState.resting(since: Date(), process: gone)]
        let left = RestController.wakeAll(states, control: fake)
        #expect(left.isEmpty)
        #expect(fake.signals == ["cont 4242"])
    }
}
