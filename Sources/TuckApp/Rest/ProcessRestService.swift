import AppKit
import CoreAudio
import Darwin
import TuckCore

/// The experimental Rest setting, off by default. Pausing needs it on; waking never does, so turning
/// Rest off can never leave an app stuck paused.
enum RestSwitch {
    static let key = "restEnabled"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Same-user process facts and signals for Rest. Pausing is a stop signal to the app's own process
/// and waking is a continue signal: public, reversible, no privileges, nothing system-wide.
///
/// `pause` refuses to send anything unless the Rest setting is on. `resume` is always allowed: it can
/// only ever undo a pause, and `RestController` checks the process identity before calling it.
final class POSIXProcessControl: ProcessControl {
    func identity(of pid: Int32) -> ProcessIdentity? {
        guard let info = bsdInfo(pid) else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let start = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        return ProcessIdentity(pid: pid, startTime: start, executablePath: String(cString: path), bundleID: bundleID)
    }

    func pause(_ pid: Int32) -> Bool {
        guard RestSwitch.isOn, pid > 1, pid != getpid() else { return false }
        return kill(pid, SIGSTOP) == 0
    }

    func resume(_ pid: Int32) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        return kill(pid, SIGCONT) == 0
    }

    func isPaused(_ pid: Int32) -> Bool? {
        bsdInfo(pid).map { $0.pbi_status == UInt32(SSTOP) }
    }

    /// CPU time the process has used so far, in nanoseconds.
    func cpuTime(of pid: Int32) -> UInt64? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = usage.ri_user_time + usage.ri_system_time
        return ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }
}

/// Whether a process is playing or recording audio, from Core Audio's public per-process objects
/// (macOS 14.2 and later). Nil when it cannot be told.
enum AudioActivity {
    static func isUsingAudio(pid: pid_t) -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        for object in objects {
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                        mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var objectPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &objectPID) == noErr,
                  objectPID == pid else { continue }
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunning,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr else { return nil }
            return running != 0
        }
        return false
    }
}

/// Rest for real apps: live facts for the safety policy, a short busy-ness measurement, and pause and
/// wake through `RestController`, which checks the process identity before every signal. Available
/// only while the experimental Rest setting is on.
final class ProcessRestService: RestService {
    var isEnabled: Bool { RestSwitch.isOn }
    private let control = POSIXProcessControl()

    /// What the safety policy says, whether or not the setting is on; the model offers to turn Rest
    /// on when the setting is the only thing in the way.
    func eligibility(for app: AppIdentity) -> RestEligibility {
        RestSafetyPolicy.eligibility(for: app, context: context(for: app, live: false, recentCPUPercent: nil))
    }

    func currentEligibility(for app: AppIdentity) -> RestEligibility {
        RestSafetyPolicy.eligibility(for: app, context: context(for: app, live: true, recentCPUPercent: nil))
    }

    func rest(_ app: AppIdentity, confirmedStrongly: Bool, acknowledged: Bool,
              completion: @escaping (Result<RestState, RestFailure>) -> Void) {
        guard isEnabled else { return completion(.failure(.disabled)) }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first,
              let identity = control.identity(of: running.processIdentifier) else {
            return completion(.failure(.processGone))
        }
        // How busy it is: CPU time used over a short, non-blocking interval.
        let pid = running.processIdentifier
        let before = control.cpuTime(of: pid)
        let interval = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            let after = self.control.cpuTime(of: pid)
            let percent = zip2(before, after).map { Double($1 &- $0) / (interval * 1_000_000_000) * 100 }
            let eligibility = RestSafetyPolicy.eligibility(for: app, context: self.context(for: app, live: true, recentCPUPercent: percent))
            completion(RestController.rest(expected: identity, eligibility: eligibility, confirmedStrongly: confirmedStrongly,
                                           acknowledged: acknowledged, isEnabled: self.isEnabled, control: self.control))
        }
    }

    func wake(_ state: RestState) -> WakeOutcome {
        RestController.wake(state, control: control)
    }

    func wakeAll(_ states: [String: RestState]) -> [String: RestState] {
        RestController.wakeAll(states, control: control)
    }

    /// What is true of the app right now. `live` adds the checks that ask the app and Core Audio, kept
    /// for the moment the person asks. Without Accessibility the app's windows cannot be counted, which
    /// counts as having windows on screen: Rest stays unavailable rather than guessing.
    private func context(for app: AppIdentity, live: Bool, recentCPUPercent: Double?) -> RestContext {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first
        let pid = running?.processIdentifier
        guard live else {
            return RestContext(isOwnApp: pid == getpid() || app.bundleID == Bundle.main.bundleIdentifier,
                               isFrontmost: pid != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
        }
        var visible = 1
        if running?.isHidden == true {
            // Hidden (its windows tucked by hiding it): nothing of it is on screen.
            visible = 0
        } else if let pid, AX.isTrusted {
            visible = AX.elements(AX.application(pid), kAXWindowsAttribute).filter {
                AX.string($0, kAXSubroleAttribute) == CandidatePolicy.standardSubrole
                    && AX.bool($0, kAXMinimizedAttribute) != true && !AX.isOutOfSight($0)
            }.count
        }
        return RestContext(
            isOwnApp: pid == getpid() || app.bundleID == Bundle.main.bundleIdentifier,
            isFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && pid != nil,
            visibleWindowCount: running == nil ? 0 : visible,
            isUsingAudio: pid.flatMap { AudioActivity.isUsingAudio(pid: $0) },
            recentCPUPercent: recentCPUPercent
        )
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
