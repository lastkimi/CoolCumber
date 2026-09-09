import Foundation
import ServiceManagement
import Darwin
import ThermFlowCore

class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    #if !APPSTORE
    private enum HelperServiceIdentity {
        static let currentIdentifier = "com.slmcamp.CoolCumber.helper.v2"
        static let currentPlistName = "com.slmcamp.CoolCumber.helper.v2.plist"

        // The app never connects to or registers this identity. Its inert
        // embedded descriptor exists solely so SMAppService can retire an
        // enabled helper shipped before the v2 security boundary.
        static let legacyPlistName = "com.coolcumber.helper.plist"
        static let legacySystemPaths = [
            "/Library/LaunchDaemons/com.coolcumber.helper.plist",
            "/Library/LaunchDaemons/com.coolcumber.helper-fallback.plist",
            "/Library/PrivilegedHelperTools/com.coolcumber.helper"
        ]
    }
    #endif

    @Published var daemonStatus: String = "Not Installed"
    @Published var thermalStatus: String = "Unknown"
    @Published var fanSpeed: String = "Unavailable"
    @Published var temperatures: [String: Double] = [:]
    @Published var smartData: [String: Any] = [:]
    @Published var diskIO: [String: Double] = [:]

    // --- CoolCumber v2.0 Phase 1 Additions ---
    @Published var networkStats: [String: Double] = [:]
    @Published var memoryStats: [String: Double] = [:]
    @Published var cpuUsage: [String: Double] = [:]
    @Published var diskSpace: [String: Double] = [:]

    @Published var currentCpuPercent: Double = 0
    @Published var currentMemPercent: Double = 0

    /// Authoritative telemetry for new UI, diagnostics, and the Widget. Legacy
    /// publishers above remain as adapters until all existing views migrate.
    @Published private(set) var systemSnapshot: SystemSnapshot

    private var trustedState: TrustedTelemetryState
    private var cpuLoadCalculator = CPULoadCalculator()
    private var uploadRateCalculator = CounterRateCalculator()
    private var downloadRateCalculator = CounterRateCalculator()
    private let sharedSnapshotWriter = SharedSnapshotWriter()
    private let localBatteryCollector = LocalBatteryCollector()
    
    private var connection: NSXPCConnection?
    private var pollingTimer: Timer?
    private var helperMigrationInFlight = false
    private var privilegedPollGeneration: UInt64 = 0
    private var privilegedPollPendingReplies = 0
    private var privilegedPollTimeout: DispatchWorkItem?
    
    private static var distributionChannel: DistributionChannel {
        #if APPSTORE
        return .appStore
        #else
        return .direct
        #endif
    }

    init() {
        let now = Date()
        var initialState = TrustedTelemetryState(
            channel: Self.distributionChannel,
            at: now
        )
        systemSnapshot = initialState.makeSnapshot(capturedAt: now)
        trustedState = initialState
    }
    
    func installDaemonIfNeeded() {
        #if APPSTORE
        DispatchQueue.main.async {
            self.daemonStatus = "App Sandbox Safe Mode"
        }
        #else
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.installDaemonIfNeeded()
            }
            return
        }

        // This method is reached only from the user's explicit helper-setup
        // confirmation. Never mutate system service state merely by launching
        // the app or polling local telemetry.
        guard !helperMigrationInFlight else { return }
        helperMigrationInFlight = true
        disconnectFromHelper()
        migrateLegacyHelperThenRegisterCurrent()
        #endif
    }

    /// Revokes the pre-v2 root job during startup without installing or
    /// connecting to any helper. Registering v2 remains an explicit action.
    func retireLegacyHelperIfNeeded() {
        #if APPSTORE
        daemonStatus = "App Sandbox Safe Mode"
        #else
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.retireLegacyHelperIfNeeded()
            }
            return
        }
        guard !helperMigrationInFlight else { return }

        let legacy = SMAppService.daemon(plistName: HelperServiceIdentity.legacyPlistName)
        switch legacy.status {
        case .enabled, .requiresApproval:
            helperMigrationInFlight = true
            daemonStatus = "Retiring Legacy Helper"
            legacy.unregister { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.helperMigrationInFlight = false
                    if let error {
                        self.daemonStatus = "Legacy Helper Retirement Failed: \(error.localizedDescription)"
                    } else if legacy.status == .notRegistered || legacy.status == .notFound {
                        self.refreshHelperRegistrationStatus()
                    } else {
                        self.daemonStatus = "Legacy Helper Retirement Could Not Be Verified"
                    }
                }
            }
        case .notRegistered, .notFound:
            if hasLegacySystemInstallation {
                daemonStatus = "Legacy Helper Manual Removal Required"
            } else {
                refreshHelperRegistrationStatus()
            }
        @unknown default:
            daemonStatus = "Legacy Helper Status Unknown"
        }
        #endif
    }

    func refreshHelperRegistrationStatus() {
        #if APPSTORE
        daemonStatus = "App Sandbox Safe Mode"
        #else
        guard !helperMigrationInFlight else { return }

        let legacy = SMAppService.daemon(plistName: HelperServiceIdentity.legacyPlistName)
        switch legacy.status {
        case .enabled, .requiresApproval:
            daemonStatus = "Legacy Helper Requires Migration"
            return
        case .notRegistered, .notFound:
            guard !hasLegacySystemInstallation else {
                daemonStatus = "Legacy Helper Manual Removal Required"
                return
            }
        @unknown default:
            daemonStatus = "Helper Status Unknown"
            return
        }

        let current = SMAppService.daemon(plistName: HelperServiceIdentity.currentPlistName)
        switch current.status {
        case .enabled:
            daemonStatus = "Secure Helper v2 Enabled"
        case .requiresApproval:
            daemonStatus = "Approval Required in System Settings"
        case .notRegistered:
            daemonStatus = "Secure Helper v2 Not Installed"
        case .notFound:
            daemonStatus = "Secure Helper v2 Not Found"
        @unknown default:
            daemonStatus = "Helper Status Unknown"
        }
        #endif
    }

    #if !APPSTORE
    private func migrateLegacyHelperThenRegisterCurrent() {
        let legacy = SMAppService.daemon(plistName: HelperServiceIdentity.legacyPlistName)
        switch legacy.status {
        case .enabled, .requiresApproval:
            daemonStatus = "Removing Legacy Helper"
            legacy.unregister { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard error == nil else {
                        self.finishHelperMigrationFailure(
                            "Legacy Helper Removal Failed: \(error!.localizedDescription)"
                        )
                        return
                    }
                    guard legacy.status == .notRegistered || legacy.status == .notFound else {
                        self.finishHelperMigrationFailure("Legacy Helper Removal Could Not Be Verified")
                        return
                    }
                    guard !self.hasLegacySystemInstallation else {
                        self.finishHelperMigrationFailure("Legacy Helper Manual Removal Required")
                        return
                    }
                    self.replaceOrRegisterCurrentHelper()
                }
            }
        case .notRegistered, .notFound:
            guard !hasLegacySystemInstallation else {
                finishHelperMigrationFailure("Legacy Helper Manual Removal Required")
                return
            }
            replaceOrRegisterCurrentHelper()
        @unknown default:
            finishHelperMigrationFailure("Legacy Helper Status Unknown")
        }
    }

    private func replaceOrRegisterCurrentHelper() {
        let current = SMAppService.daemon(plistName: HelperServiceIdentity.currentPlistName)
        switch current.status {
        case .enabled, .requiresApproval:
            // Apple recommends unregistering before re-registering whenever
            // the embedded executable or plist changes. Waiting for this
            // completion also ensures the prior process has been reaped.
            daemonStatus = "Updating Secure Helper v2"
            current.unregister { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard error == nil else {
                        self.finishHelperMigrationFailure(
                            "Secure Helper v2 Update Failed: \(error!.localizedDescription)"
                        )
                        return
                    }
                    guard current.status == .notRegistered || current.status == .notFound else {
                        self.finishHelperMigrationFailure("Secure Helper v2 Removal Could Not Be Verified")
                        return
                    }
                    self.registerCurrentHelper()
                }
            }
        case .notRegistered, .notFound:
            registerCurrentHelper()
        @unknown default:
            finishHelperMigrationFailure("Secure Helper v2 Status Unknown")
        }
    }

    private func registerCurrentHelper() {
        let current = SMAppService.daemon(plistName: HelperServiceIdentity.currentPlistName)
        do {
            try current.register()
        } catch {
            // register() reports launch denial while status conveys the
            // actionable approval state. This is not a partial installation.
            guard current.status == .requiresApproval else {
                finishHelperMigrationFailure(
                    "Secure Helper v2 Registration Failed: \(error.localizedDescription)"
                )
                return
            }
        }

        helperMigrationInFlight = false
        switch current.status {
        case .enabled:
            daemonStatus = "Secure Helper v2 Enabled"
        case .requiresApproval:
            daemonStatus = "Approval Required in System Settings"
        case .notRegistered, .notFound:
            daemonStatus = "Secure Helper v2 Registration Could Not Be Verified"
        @unknown default:
            daemonStatus = "Secure Helper v2 Status Unknown"
        }
    }

    private func finishHelperMigrationFailure(_ status: String) {
        helperMigrationInFlight = false
        daemonStatus = status
    }

    private func disconnectFromHelper() {
        let oldConnection = connection
        connection = nil
        cancelPrivilegedPoll()
        oldConnection?.invalidate()
    }

    private var hasLegacySystemInstallation: Bool {
        HelperServiceIdentity.legacySystemPaths.contains {
            FileManager.default.fileExists(atPath: $0)
        }
    }
    #endif

    func connect(errorHandler: ((Error) -> Void)? = nil) -> CoolCumberMonitorV2Protocol? {
        #if APPSTORE
        return nil
        #else
        if connection == nil {
            let newConnection = NSXPCConnection(
                machServiceName: HelperServiceIdentity.currentIdentifier,
                options: .privileged
            )
            #if DEBUG
            newConnection.setCodeSigningRequirement(
                "identifier \"com.slmcamp.CoolCumber.helper.v2\" and anchor apple generic and certificate leaf[subject.OU] = \"BSKR6CQ765\""
            )
            #else
            newConnection.setCodeSigningRequirement(
                "identifier \"com.slmcamp.CoolCumber.helper.v2\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"BSKR6CQ765\""
            )
            #endif
            newConnection.remoteObjectInterface = NSXPCInterface(with: CoolCumberMonitorV2Protocol.self)
            newConnection.invalidationHandler = { [weak self, weak newConnection] in
                DispatchQueue.main.async {
                    guard let self, self.connection === newConnection else { return }
                    self.connection = nil
                    self.cancelPrivilegedPoll()
                    self.markPrivilegedTelemetryUnavailable(
                        reasonCode: "xpcInvalidated",
                        at: Date()
                    )
                    self.publishTrustedSnapshot()
                }
            }
            newConnection.interruptionHandler = { [weak self, weak newConnection] in
                DispatchQueue.main.async {
                    guard let self, self.connection === newConnection else { return }
                    self.connection = nil
                    self.cancelPrivilegedPoll()
                    self.markPrivilegedTelemetryUnavailable(
                        reasonCode: "xpcInterrupted",
                        at: Date()
                    )
                    self.publishTrustedSnapshot()
                }
            }
            newConnection.resume()
            self.connection = newConnection
        }
        
        return connection?.remoteObjectProxyWithErrorHandler { error in
            print("XPC Error: \(error)")
            DispatchQueue.main.async {
                self.thermalStatus = "XPC Error: \(error.localizedDescription)"
                self.markPrivilegedTelemetryUnavailable(
                    reasonCode: "xpcError",
                    at: Date()
                )
                self.publishTrustedSnapshot()
            }
            if let customHandler = errorHandler {
                customHandler(error)
            }
        } as? CoolCumberMonitorV2Protocol
        #endif
    }

    func verifyAndInstallHelper() {
        // Use SMAppService for modern, silent installation.
        installDaemonIfNeeded()
    }
    
    func checkThermalStatus() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkThermalStatus()
            }
            return
        }

        let observedAt = Date()
        updateLocalThermalPressure(at: observedAt)
        updateLocalMemory(at: observedAt)
        updateLocalDiskSpace(at: observedAt)
        updateLocalBatteryHealth(at: observedAt)

        if let usage = sampleLocalCPUTicks() {
            updateCPUUsage(with: usage, at: observedAt)
        } else {
            markCPUUnavailable(reasonCode: "machCPUReadFailed", at: observedAt)
        }
        if let counters = sampleLocalNetworkCounters() {
            updateNetworkCounters(counters, at: observedAt)
        } else {
            markNetworkUnavailable(reasonCode: "networkCounterReadFailed", at: observedAt)
        }

        #if APPSTORE
        markSandboxOnlyMetrics(at: observedAt)
        publishTrustedSnapshot(at: observedAt)
        #else
        guard let proxy = connect(errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.thermalStatus = "XPC Error: \(error.localizedDescription)"
            }
        }) else {
            thermalStatus = "Daemon Connection Failed"
            markPrivilegedTelemetryUnavailable(
                reasonCode: "helperUnavailable",
                at: observedAt
            )
            publishTrustedSnapshot(at: observedAt)
            return
        }

        // Publish local, non-privileged telemetry immediately. Privileged
        // temperature/fan replies update the same snapshot independently.
        publishTrustedSnapshot(at: observedAt)

        // Never stack privileged requests. Late XPC replies are discarded by
        // generation so an old measurement cannot be relabelled as current.
        guard privilegedPollPendingReplies == 0 else { return }
        privilegedPollGeneration &+= 1
        let generation = privilegedPollGeneration
        let sampledAt = observedAt
        privilegedPollPendingReplies = 2

        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  self.privilegedPollGeneration == generation,
                  self.privilegedPollPendingReplies > 0 else { return }
            self.privilegedPollPendingReplies = 0
            self.markPrivilegedTelemetryUnavailable(
                reasonCode: "helperRequestTimedOut",
                at: sampledAt
            )
            self.publishTrustedSnapshot()
        }
        privilegedPollTimeout?.cancel()
        privilegedPollTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)

        proxy.readFanSpeeds { speeds in
            DispatchQueue.main.async {
                guard self.acceptsPrivilegedReply(generation: generation) else { return }
                self.updateFanSpeeds(speeds, at: sampledAt)
                self.publishTrustedSnapshot()
                self.completePrivilegedReply(generation: generation)
            }
        }
        proxy.readTemperatures { temps in
            DispatchQueue.main.async {
                guard self.acceptsPrivilegedReply(generation: generation) else { return }
                self.updateTemperatures(temps, at: sampledAt)
                self.publishTrustedSnapshot()
                self.completePrivilegedReply(generation: generation)
            }
        }
        #endif
    }

    private func acceptsPrivilegedReply(generation: UInt64) -> Bool {
        generation == privilegedPollGeneration && privilegedPollPendingReplies > 0
    }

    private func completePrivilegedReply(generation: UInt64) {
        guard acceptsPrivilegedReply(generation: generation) else { return }
        privilegedPollPendingReplies -= 1
        if privilegedPollPendingReplies == 0 {
            privilegedPollTimeout?.cancel()
            privilegedPollTimeout = nil
        }
    }

    private func cancelPrivilegedPoll() {
        privilegedPollTimeout?.cancel()
        privilegedPollTimeout = nil
        privilegedPollPendingReplies = 0
        privilegedPollGeneration &+= 1
    }

    private func updateCPUUsage(with usage: [String: Double], at date: Date) {
        guard let user = unsignedCounter(usage["user"]),
              let system = unsignedCounter(usage["system"]),
              let idle = unsignedCounter(usage["idle"]),
              let nice = unsignedCounter(usage["nice"]) else {
            markCPUUnavailable(reasonCode: "invalidCPUCounters", at: date)
            return
        }

        cpuUsage = usage
        let sample = cpuLoadCalculator.sample(
            ticks: CPUTicks(user: user, system: system, idle: idle, nice: nice),
            capturedAt: date
        )
        trustedState.cpu = CPUSnapshot(usage: sample)
        trustedState.setCapability(
            .cpuUsage,
            from: sample.availability,
            reasonCode: sample.failure?.code,
            at: date
        )
        if let percent = sample.value?.value {
            currentCpuPercent = percent
        }
    }

    private func updateNetworkCounters(_ counters: [String: Double], at date: Date) {
        guard let upload = unsignedCounter(counters["upload"]),
              let download = unsignedCounter(counters["download"]) else {
            markNetworkUnavailable(reasonCode: "invalidNetworkCounters", at: date)
            return
        }

        let uploadSample = uploadRateCalculator.sample(
            counter: upload,
            capturedAt: date
        )
        let downloadSample = downloadRateCalculator.sample(
            counter: download,
            capturedAt: date
        )
        trustedState.network = NetworkSnapshot(
            uploadRate: uploadSample,
            downloadRate: downloadSample
        )

        let capabilityAvailability: MetricAvailability =
            uploadSample.availability == .available && downloadSample.availability == .available
            ? .available
            : .temporarilyUnavailable
        trustedState.setCapability(
            .networkRate,
            from: capabilityAvailability,
            reasonCode: uploadSample.failure?.code ?? downloadSample.failure?.code,
            at: date
        )

        if let uploadRate = uploadSample.value?.bytesPerSecond,
           let downloadRate = downloadSample.value?.bytesPerSecond {
            // Preserve both historical and corrected keys during migration.
            networkStats = [
                "upload": uploadRate,
                "download": downloadRate,
                "up": uploadRate,
                "down": downloadRate
            ]
        } else {
            networkStats = [:]
        }
    }

    private func updateLocalThermalPressure(at date: Date) {
        let pressure: ThermalPressure
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            pressure = .nominal
            thermalStatus = "Level Nominal"
        case .fair:
            pressure = .fair
            thermalStatus = "Level Fair"
        case .serious:
            pressure = .serious
            thermalStatus = "Level Serious"
        case .critical:
            pressure = .critical
            thermalStatus = "Level Critical"
        @unknown default:
            thermalStatus = "Unknown"
            let sample = MetricSample<ThermalPressure>.unknown(observedAt: date)
            trustedState.thermal = ThermalSnapshot(
                pressure: sample,
                cpuTemperature: trustedState.thermal.cpuTemperature,
                gpuTemperature: trustedState.thermal.gpuTemperature
            )
            trustedState.setCapability(
                .thermalPressure,
                from: .unknown,
                reasonCode: "unknownThermalState",
                at: date
            )
            return
        }

        let sample = MetricSample<ThermalPressure>.available(
            pressure,
            provenance: .reported(
                by: .processInfo,
                collectorID: "ProcessInfo.thermalState"
            ),
            observedAt: date
        )
        trustedState.thermal = ThermalSnapshot(
            pressure: sample,
            cpuTemperature: trustedState.thermal.cpuTemperature,
            gpuTemperature: trustedState.thermal.gpuTemperature
        )
        trustedState.setCapability(
            .thermalPressure,
            from: .available,
            at: date
        )
    }

    private func updateLocalMemory(at date: Date) {
        let provenance = MetricProvenance.measured(
            by: .machKernel,
            collectorID: "host_statistics64"
        )
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            memoryStats = [:]
            let failure = MetricFailure(code: "machMemoryReadFailed")
            trustedState.memory = MemorySnapshot(
                used: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                total: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                usage: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                pressure: .unknown(observedAt: date)
            )
            trustedState.setCapability(
                .memoryUsage,
                from: .failed,
                reasonCode: failure.code,
                at: date
            )
            return
        }

        let pageSize = Double(vm_kernel_page_size)
        let appPages = max(
            0,
            Double(stats.internal_page_count) - Double(stats.purgeable_count)
        )
        let usedValue = (
            appPages
            + Double(stats.wire_count)
            + Double(stats.compressor_page_count)
        ) * pageSize
        let totalValue = Double(ProcessInfo.processInfo.physicalMemory)

        guard let usedRaw = unsignedCounter(usedValue),
              let totalRaw = unsignedCounter(totalValue),
              totalRaw > 0 else {
            memoryStats = [:]
            let failure = MetricFailure(code: "invalidMemoryValues")
            trustedState.memory = MemorySnapshot(
                used: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                total: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                usage: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                pressure: .unknown(observedAt: date)
            )
            trustedState.setCapability(
                .memoryUsage,
                from: .failed,
                reasonCode: failure.code,
                at: date
            )
            return
        }

        let used = ByteCount(usedRaw)
        let total = ByteCount(totalRaw)
        let derivedProvenance = MetricProvenance.derived(
            collectorID: "MemoryUsageCalculator",
            from: [.machKernel]
        )
        let usageSample: MetricSample<Percent>
        if let percent = Percent(ratio: Double(usedRaw) / Double(totalRaw)) {
            usageSample = .available(
                percent,
                provenance: derivedProvenance,
                observedAt: date
            )
            currentMemPercent = percent.value
        } else {
            usageSample = .failed(
                code: "invalidMemoryPercentage",
                provenance: derivedProvenance,
                observedAt: date
            )
        }

        memoryStats = ["used": Double(usedRaw), "total": Double(totalRaw)]
        trustedState.memory = MemorySnapshot(
            used: .available(used, provenance: provenance, observedAt: date),
            total: .available(total, provenance: provenance, observedAt: date),
            usage: usageSample,
            pressure: .unknown(observedAt: date)
        )
        trustedState.setCapability(
            .memoryUsage,
            from: usageSample.availability,
            reasonCode: usageSample.failure?.code,
            at: date
        )
    }

    private func updateLocalDiskSpace(at date: Date) {
        let provenance = MetricProvenance.reported(
            by: .fileSystem,
            collectorID: "FileManager.attributesOfFileSystem"
        )
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let totalValue = (attributes[.systemSize] as? NSNumber)?.doubleValue,
              let availableValue = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
              let totalRaw = unsignedCounter(totalValue),
              let availableRaw = unsignedCounter(availableValue),
              totalRaw > 0,
              availableRaw <= totalRaw else {
            diskSpace = [:]
            let failure = MetricFailure(code: "fileSystemCapacityReadFailed")
            trustedState.storage = StorageSnapshot(
                total: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                available: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                usage: .unavailable(
                    .failed,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                )
            )
            trustedState.setCapability(
                .diskSpace,
                from: .failed,
                reasonCode: failure.code,
                at: date
            )
            return
        }

        let usedRaw = totalRaw - availableRaw
        let usage = Percent(ratio: Double(usedRaw) / Double(totalRaw))!
        let derivedProvenance = MetricProvenance.derived(
            collectorID: "DiskUsageCalculator",
            from: [.fileSystem]
        )
        diskSpace = [
            "total": Double(totalRaw),
            "used": Double(usedRaw),
            "available": Double(availableRaw)
        ]
        trustedState.storage = StorageSnapshot(
            total: .available(
                ByteCount(totalRaw),
                provenance: provenance,
                observedAt: date
            ),
            available: .available(
                ByteCount(availableRaw),
                provenance: provenance,
                observedAt: date
            ),
            usage: .available(
                usage,
                provenance: derivedProvenance,
                observedAt: date
            )
        )
        trustedState.setCapability(.diskSpace, from: .available, at: date)
    }

    private func updateTemperatures(_ values: [String: Double], at date: Date) {
        let provenance = MetricProvenance.measured(
            by: .smc,
            collectorID: "PrivilegedHelper.SMCSelectedSensor"
        )

        func sample(for key: String) -> MetricSample<TemperatureCelsius> {
            guard let rawValue = values[key] else {
                return .unavailable(
                    .temporarilyUnavailable,
                    provenance: provenance,
                    observedAt: date,
                    failure: MetricFailure(code: "sensorUnavailable")
                )
            }
            guard (10...120).contains(rawValue),
                  let temperature = TemperatureCelsius(rawValue) else {
                return .failed(
                    code: "invalidTemperature",
                    provenance: provenance,
                    observedAt: date
                )
            }
            return .available(
                temperature,
                provenance: provenance,
                observedAt: date
            )
        }

        let cpuSample = sample(for: "CPU")
        let gpuSample = sample(for: "GPU")
        trustedState.thermal = ThermalSnapshot(
            pressure: trustedState.thermal.pressure,
            cpuTemperature: cpuSample,
            gpuTemperature: gpuSample
        )
        trustedState.setCapability(
            .cpuTemperature,
            from: cpuSample.availability,
            reasonCode: cpuSample.failure?.code,
            at: date
        )
        trustedState.setCapability(
            .gpuTemperature,
            from: gpuSample.availability,
            reasonCode: gpuSample.failure?.code,
            at: date
        )

        var validated: [String: Double] = [:]
        if let cpu = cpuSample.value?.value { validated["CPU"] = cpu }
        if let gpu = gpuSample.value?.value { validated["GPU"] = gpu }
        temperatures = validated
    }

    private func updateFanSpeeds(_ speeds: [Int], at date: Date) {
        let provenance = MetricProvenance.measured(
            by: .smc,
            collectorID: "PrivilegedHelper.readFanSpeeds"
        )
        let validated = speeds.enumerated().compactMap { index, rawValue -> FanSnapshot? in
            guard rawValue <= 10_000, let rpm = FanRPM(rawValue) else { return nil }
            return FanSnapshot(
                id: index,
                currentSpeed: .available(
                    rpm,
                    provenance: provenance,
                    observedAt: date
                ),
                mode: .unknown(observedAt: date)
            )
        }

        guard !validated.isEmpty, validated.count == speeds.count else {
            fanSpeed = "Unavailable"
            trustedState.fans = []
            trustedState.setCapability(
                .fanRead,
                from: .temporarilyUnavailable,
                reasonCode: "fanTelemetryUnavailable",
                at: date
            )
            return
        }

        trustedState.fans = validated
        trustedState.setCapability(.fanRead, from: .available, at: date)
        if let first = validated.first?.currentSpeed.value?.value {
            fanSpeed = "\(first) RPM"
        }
    }

    private func markSandboxOnlyMetrics(at date: Date) {
        let unsupported = MetricProvenance(
            source: .unknown,
            quality: .unknown,
            collectorID: "AppStoreSandbox"
        )
        let temperature = MetricSample<TemperatureCelsius>.unavailable(
            .unsupported,
            provenance: unsupported,
            observedAt: date,
            failure: MetricFailure(code: "appSandbox")
        )
        trustedState.thermal = ThermalSnapshot(
            pressure: trustedState.thermal.pressure,
            cpuTemperature: temperature,
            gpuTemperature: temperature
        )
        trustedState.fans = []
        trustedState.setCapability(
            .cpuTemperature,
            from: .unsupported,
            reasonCode: "appSandbox",
            at: date
        )
        trustedState.setCapability(
            .gpuTemperature,
            from: .unsupported,
            reasonCode: "appSandbox",
            at: date
        )
        trustedState.setCapability(
            .fanRead,
            from: .unsupported,
            reasonCode: "appSandbox",
            at: date
        )
        temperatures = [:]
        fanSpeed = "Unavailable in App Store edition"
    }

    private func markPrivilegedTelemetryUnavailable(
        reasonCode: String,
        at date: Date
    ) {
        let provenance = MetricProvenance(
            source: .unknown,
            quality: .unknown,
            collectorID: "PrivilegedHelper"
        )
        let unavailableTemperature = MetricSample<TemperatureCelsius>.unavailable(
            .temporarilyUnavailable,
            provenance: provenance,
            observedAt: date,
            failure: MetricFailure(code: reasonCode)
        )
        trustedState.thermal = ThermalSnapshot(
            pressure: trustedState.thermal.pressure,
            cpuTemperature: unavailableTemperature,
            gpuTemperature: unavailableTemperature
        )
        trustedState.fans = []
        trustedState.setCapability(
            .cpuTemperature,
            from: .temporarilyUnavailable,
            reasonCode: reasonCode,
            at: date
        )
        trustedState.setCapability(
            .gpuTemperature,
            from: .temporarilyUnavailable,
            reasonCode: reasonCode,
            at: date
        )
        trustedState.setCapability(
            .fanRead,
            from: .temporarilyUnavailable,
            reasonCode: reasonCode,
            at: date
        )
        trustedState.setCapability(
            .fanControl,
            from: .temporarilyUnavailable,
            reasonCode: reasonCode,
            at: date
        )
        temperatures = [:]
        fanSpeed = "Unavailable"
    }

    private func markCPUUnavailable(reasonCode: String, at date: Date) {
        cpuUsage = [:]
        let sample = MetricSample<Percent>.failed(
            code: reasonCode,
            provenance: .measured(by: .machKernel, collectorID: "host_processor_info"),
            observedAt: date
        )
        trustedState.cpu = CPUSnapshot(usage: sample)
        trustedState.setCapability(
            .cpuUsage,
            from: sample.availability,
            reasonCode: reasonCode,
            at: date
        )
    }

    private func markNetworkUnavailable(reasonCode: String, at date: Date) {
        networkStats = [:]
        let provenance = MetricProvenance.measured(
            by: .networkInterface,
            collectorID: "getifaddrs"
        )
        let upload = MetricSample<ByteRate>.failed(
            code: reasonCode,
            provenance: provenance,
            observedAt: date
        )
        let download = MetricSample<ByteRate>.failed(
            code: reasonCode,
            provenance: provenance,
            observedAt: date
        )
        trustedState.network = NetworkSnapshot(
            uploadRate: upload,
            downloadRate: download
        )
        trustedState.setCapability(
            .networkRate,
            from: .failed,
            reasonCode: reasonCode,
            at: date
        )
    }

    private func updateLocalBatteryHealth(at date: Date) {
        let collection = localBatteryCollector.collect(at: date)
        trustedState.battery = collection.snapshot
        trustedState.setCapability(
            .batteryHealth,
            from: collection.availability,
            reasonCode: collection.failureCode,
            at: date
        )
    }

    private func markBatteryUnavailable(reasonCode: String, at date: Date) {
        let provenance = MetricProvenance(
            source: .unknown,
            quality: .unknown,
            collectorID: "BatteryCollector"
        )
        let failure = MetricFailure(code: reasonCode)
        trustedState.battery = BatterySnapshot(
            cycleCount: .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: date,
                failure: failure
            ),
            maximumCapacity: .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: date,
                failure: failure
            ),
            condition: .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: date,
                failure: failure
            )
        )
        trustedState.setCapability(
            .batteryHealth,
            from: .temporarilyUnavailable,
            reasonCode: reasonCode,
            at: date
        )
    }

    private func publishTrustedSnapshot(at date: Date = Date()) {
        guard sharedSnapshotWriter.canAccessContainer else {
            trustedState.setCapability(
                .widgetSync,
                from: .temporarilyUnavailable,
                reasonCode: "appGroupUnavailable",
                at: date
            )
            systemSnapshot = trustedState.makeSnapshot(capturedAt: date)
            return
        }

        trustedState.setCapability(.widgetSync, from: .available, at: date)
        let candidate = trustedState.makeSnapshot(capturedAt: date)
        do {
            try sharedSnapshotWriter.write(candidate, at: date)
            systemSnapshot = candidate
        } catch {
            trustedState.setCapability(
                .widgetSync,
                from: .temporarilyUnavailable,
                reasonCode: "snapshotWriteFailed",
                at: date
            )
            systemSnapshot = trustedState.makeSnapshot(capturedAt: date)
        }
    }

    private func unsignedCounter(_ value: Double?) -> UInt64? {
        guard let value,
              value.isFinite,
              value >= 0,
              value < Double(UInt64.max) else {
            return nil
        }
        return UInt64(value.rounded(.towardZero))
    }

    private func sampleLocalCPUTicks() -> [String: Double]? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var user = 0.0
        var system = 0.0
        var idle = 0.0
        var nice = 0.0
        for cpu in 0..<Int(numCPUs) {
            let index = cpu * Int(CPU_STATE_MAX)
            user += Double(cpuInfo[index + Int(CPU_STATE_USER)])
            system += Double(cpuInfo[index + Int(CPU_STATE_SYSTEM)])
            idle += Double(cpuInfo[index + Int(CPU_STATE_IDLE)])
            nice += Double(cpuInfo[index + Int(CPU_STATE_NICE)])
        }
        return ["user": user, "system": system, "idle": idle, "nice": nice]
    }

    private func sampleLocalNetworkCounters() -> [String: Double]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return nil }
        defer { freeifaddrs(firstAddress) }

        var upload = 0.0
        var download = 0.0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               (interface.ifa_flags & UInt32(IFF_UP)) != 0,
               let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                upload += Double(data.ifi_obytes)
                download += Double(data.ifi_ibytes)
            }
            pointer = interface.ifa_next
        }
        return ["upload": upload, "download": download]
    }

    func purgeMemory(completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Memory purge was removed because macOS manages memory pressure automatically.")
    }

    func manageProcessState(pid: Int32, action: String, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Process freezing and throttling are disabled pending a non-root safety redesign.")
    }
    
    func setBatteryChargeLimit(_ percent: Int, completion: @escaping (Bool, String?) -> Void) {
        _ = percent
        let now = Date()
        trustedState.setCapability(
            .batteryChargeLimit,
            from: .unsupported,
            reasonCode: "readOnlyProduct",
            at: now
        )
        publishTrustedSnapshot(at: now)
        completion(false, "Battery mutation is not part of the read-only product.")
    }
    
    func readBatteryHealth(completion: @escaping ([String: Any]) -> Void) {
        let now = Date()
        updateLocalBatteryHealth(at: now)
        publishTrustedSnapshot(at: now)
        var values: [String: Any] = [:]
        if let cycleCount = trustedState.battery.cycleCount.value {
            values["cycleCount"] = Int(cycleCount)
        }
        if let capacity = trustedState.battery.maximumCapacity.value {
            values["maxCapacityPercent"] = capacity.value
        }
        if let condition = trustedState.battery.condition.value {
            values["condition"] = condition.rawValue
        }
        completion(values)
    }
    
    func runMaintenance(type: String, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Privileged maintenance actions are disabled for safety.")
    }
    
    func startPolling() {
        stopPolling()
        refreshHelperRegistrationStatus()
        // Immediately fetch once
        checkThermalStatus()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkThermalStatus()
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        cancelPrivilegedPoll()
    }
    
    // Process Analysis
    func readTopProcesses(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        _ = count
        let now = Date()
        trustedState.setCapability(
            .processRead,
            from: .unsupported,
            reasonCode: "notCollectedByProduct",
            at: now
        )
        publishTrustedSnapshot(at: now)
        completion([])
    }
    
    func readTopMemoryProcesses(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        _ = count
        let now = Date()
        trustedState.setCapability(
            .processRead,
            from: .unsupported,
            reasonCode: "notCollectedByProduct",
            at: now
        )
        publishTrustedSnapshot(at: now)
        completion([])
    }
    
    func killProcess(pid: Int32, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Root-level process termination is disabled for safety.")
    }
    
    func setEcoMode(enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        _ = enabled
        completion(false, "Root-level process controls are disabled for safety.")
    }
}
