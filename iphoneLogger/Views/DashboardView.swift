import SwiftUI
import Combine

struct DashboardView: View {
    @EnvironmentObject var logController: LogController
    
    // Independent Managers
    @StateObject private var motionLogger = MotionLogger()
    @StateObject private var locationLogger = LocationEnvironmentLogger()
    @StateObject private var visionManager = VisionManager()
    @StateObject private var audioManager = AudioMetaManager()
    @StateObject private var metricsMonitor = SystemMetricsMonitor()
    @StateObject private var actuatorManager = ActuatorManager()
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(white: 0.1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        statusBar
                        chaosButton
                        
                        VStack(spacing: 20) {
                            // 1. EXTEROCEPTION (External World)
                            categorySection(
                                title: "Exteroception", subTitle: "EXTERNAL SENSORY", icon: "eye.fill", color: .purple,
                                items: [
                                    subSensorRow(name: "Vision (Face/LiDAR)", status: "\(visionManager.faceTrackingHz)Hz", isOn: .init(get: { logController.logFace || logController.logLiDAR }, set: { v in logController.logFace = v; logController.logLiDAR = v }), onToggle: { sync() }),
                                    subSensorRow(name: "Vision Meta (ISO/Exp)", status: "Active", isOn: $logController.logCameraMeta, onToggle: { sync() }),
                                    subSensorRow(name: "Auditory (Mic)", status: String(format: "%.1f dB", audioManager.micLevel), isOn: $logController.logAudio, onToggle: { sync() }),
                                    subSensorRow(name: "Location (GPS/Heading)", status: "\(locationLogger.currentGPSHz)Hz", isOn: .init(get: { logController.logGPS || logController.logHeading }, set: { v in logController.logGPS = v; logController.logHeading = v }), onToggle: { sync() }),
                                    subSensorRow(name: "Env (Pressure/ALS)", status: String(format: "%.1f Lux", locationLogger.brightness), isOn: .init(get: { logController.logBarometer || logController.logALS }, set: { v in logController.logBarometer = v; logController.logALS = v }), onToggle: { sync() }),
                                    subSensorRow(name: "Contact (Proximity)", status: locationLogger.isProximityClose ? "CLOSE" : "FAR", isOn: $logController.logProximity, onToggle: { sync() })
                                ]
                            )
                            
                            // 2. PROPRIOCEPTION (Self & Motor)
                            categorySection(
                                title: "Proprioception", subTitle: "SELF STATE & MOTOR", icon: "gyroscope", color: .orange,
                                items: [
                                    subSensorRow(name: "Pose (IMU)", status: "\(motionLogger.currentAccelHz)Hz", isOn: .init(get: { logController.logAccel || logController.logGyro }, set: { v in logController.logAccel = v; logController.logGyro = v }), onToggle: { sync() }),
                                    subSensorRow(name: "Motion Activity", status: motionLogger.currentActivity.uppercased(), isOn: $logController.logActivity, onToggle: { sync() }),
                                    AnyView(Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 20)),
                                    actuatorSliderRow(name: "Motor: Torch", value: $logController.torchLevel, range: 0...1, onChanged: { actuatorManager.setFlashlight(level: logController.torchLevel) }),
                                    actuatorSliderRow(name: "Motor: Zoom", value: $logController.zoomFactor, range: 1...40.0, onChanged: { visionManager.applyActiveControl() }),
                                    AnyView(
                                        HStack {
                                            Text("Motor: Exposure Lock").font(.subheadline).foregroundColor(.white)
                                            Spacer()
                                            Toggle("", isOn: $logController.isExposureLocked).labelsHidden().tint(.orange).onChange(of: logController.isExposureLocked) { visionManager.applyActiveControl() }
                                        }.padding(.horizontal, 20)
                                    ),
                                ]
                            )
                            
                            // 3. INTEROCEPTION (Internal Health)
                            categorySection(
                                title: "Interoception", subTitle: "INTERNAL HEALTH", icon: "cpu", color: .green,
                                items: [
                                    subSensorRow(name: "System Monitoring", status: "Health logging", isOn: $logController.logSystemMetrics, onToggle: { sync() }),
                                    AnyView(Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 20)),
                                    subSensorRow(name: "CPU Intensity", status: String(format: "%.1f %%", metricsMonitor.cpuUsage), isOn: .constant(true), onToggle: {}, isReadOnly: true),
                                    subSensorRow(name: "GPU/ANE Load", status: String(format: "G:%.0f%% A:%.0f%%", metricsMonitor.gpuUsage, metricsMonitor.aneUsage), isOn: .constant(true), onToggle: {}, isReadOnly: true),
                                    subSensorRow(name: "RAM Consumption", status: String(format: "%.1f MB", metricsMonitor.memoryUsageMB), isOn: .constant(true), onToggle: {}, isReadOnly: true),
                                    subSensorRow(name: "Thermal Intensity", status: thermalStateShort, isOn: .constant(true), onToggle: {}, isReadOnly: true),
                                    subSensorRow(name: "Battery Status", status: batteryString, isOn: .constant(true), onToggle: {}, isReadOnly: true)
                                ]
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.vertical)
                }
            }
        }
        .onAppear {
            visionManager.logController = logController
            audioManager.logController = logController
            logController.motionLogger = motionLogger
            metricsMonitor.startMonitoring()
            BufferQueue.shared.logController = logController
        }
    }
    
    // MARK: - Orchestration Logic
    
    private func sync() {
        if logController.anyActive {
            let startingNew = !BufferQueue.shared.isRecordingActive
            BufferQueue.shared.startRecording()
            
            if startingNew {
                // [Phase 3] Precise Motor Logging: Capture initial actuator state as the first 'Motor Control' data points
                let now = Date().timeIntervalSince1970
                BufferQueue.shared.enqueueActuatorEvent(name: "motor_torch_initial", value: Double(logController.torchLevel), sysTimestamp: now)
                BufferQueue.shared.enqueueActuatorEvent(name: "motor_zoom_initial", value: logController.zoomFactor, sysTimestamp: now)
                BufferQueue.shared.enqueueActuatorEvent(name: "motor_exposure_locked_initial", value: logController.isExposureLocked ? 1.0 : 0.0, sysTimestamp: now)
            }

            // Sync managers. They handle their own internal thread safety and backgrounding.
            self.visionManager.updateState()
            self.audioManager.updateState()
            
            if logController.logAccel || logController.logGyro || logController.logActivity {
                self.motionLogger.startLogging()
            } else {
                self.motionLogger.stopLogging()
            }
            
            if logController.logGPS || logController.logHeading || logController.logBarometer || logController.logALS || logController.logProximity {
                self.locationLogger.startLogging()
            } else {
                self.locationLogger.stopLogging()
            }
        } else {
            BufferQueue.shared.stopRecording()
            visionManager.updateState()
            audioManager.updateState()
            motionLogger.stopLogging()
            locationLogger.stopLogging()
        }
    }
    
    private func toggleAll() {
        withAnimation(.spring()) {
            if logController.isLoggingAll { logController.stopAll() }
            else { logController.startAll() }
        }
        sync()
    }
    
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("IPHONE SENSOR-MOTOR TESTBED").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.blue)
            Text("MULTIMODAL DATASET LAB").font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.white)
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity).background(Color.black.opacity(0.4))
    }
    
    private var statusBar: some View {
        HStack(spacing: 12) {
            statusPill(title: "THERMAL", value: thermalStateShort, color: thermalColor)
            statusPill(title: "BATT", value: batteryString, color: metricsMonitor.batteryLevel > 0.2 ? .green : .red)
            statusPill(title: "DEVICE", value: "iP16Pro", color: .orange)
        }
        .padding(.horizontal)
    }
    
    private func statusPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 7, weight: .black)).foregroundColor(.gray)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
    
    private var chaosButton: some View {
        VStack(spacing: 12) {
            Button(action: { logController.toggleFrequencyModulation(); sync() }) {
                HStack {
                    Image(systemName: "waveform.path.ecg").font(.headline).foregroundColor(logController.isVaryingFrequencyActive ? .blue : .gray)
                    VStack(alignment: .leading) {
                        Text("TESTING VARYING FREQUENCY").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        Text("Randomly modulate target C Hz").font(.caption2).foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding().background(RoundedRectangle(cornerRadius: 16).fill(logController.isVaryingFrequencyActive ? Color.blue.opacity(0.1) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(logController.isVaryingFrequencyActive ? Color.blue.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
            }
            
            Button(action: { toggleAll() }) {
                HStack {
                    Image(systemName: logController.isLoggingAll ? "stop.circle.fill" : "bolt.shield.fill").font(.headline).foregroundColor(logController.isLoggingAll ? .white : .red)
                    VStack(alignment: .leading) {
                        Text(logController.isLoggingAll ? "STOP ALL CHANNELS" : "LOGGING ALL DATA").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        Text("Temporally-aligned multimodal logging").font(.caption2).foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding().background(RoundedRectangle(cornerRadius: 16).fill(logController.isLoggingAll ? Color.red.opacity(0.1) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(logController.isLoggingAll ? Color.red.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
            }
        }
        .padding(.horizontal)
    }
    
    private func categorySection(title: String, subTitle: String, icon: String, color: Color, items: [AnyView?]) -> some View {
        let isExpanded = logController.expandedCategory == title
        return VStack(spacing: 0) {
            Button(action: { withAnimation { logController.toggleCategory(title) } }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: icon).foregroundColor(color).font(.system(size: 18, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).foregroundColor(.white)
                        Text(subTitle).font(.system(size: 10, weight: .bold)).foregroundColor(color.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.gray).rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
            }
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { i in
                        if let item = items[i] { item }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isExpanded ? color.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
    }
    
    private func subSensorRow(name: String, status: String, isOn: Binding<Bool>, onToggle: @escaping () -> Void, isReadOnly: Bool = false) -> AnyView? {
        AnyView(
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline).foregroundColor(.white.opacity(0.9))
                    Text(status).font(.system(size: 10, design: .monospaced)).foregroundColor(.blue)
                }
                Spacer()
                if !isReadOnly {
                    Toggle("", isOn: isOn).labelsHidden().tint(.blue).onChange(of: isOn.wrappedValue) { onToggle() }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        )
    }
    
    private func actuatorSliderRow(name: String, value: Binding<Float>, range: ClosedRange<Float>, onChanged: @escaping () -> Void) -> AnyView? {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.subheadline).foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.2f", value.wrappedValue)).font(.system(size: 10, design: .monospaced)).foregroundColor(.yellow)
                }
                Slider(value: value, in: range, onEditingChanged: { _ in onChanged() }).tint(.orange)
            }
            .padding(.horizontal, 20)
        )
    }

    private func actuatorSliderRow(name: String, value: Binding<Double>, range: ClosedRange<Double>, onChanged: @escaping () -> Void) -> AnyView? {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.subheadline).foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1fx", value.wrappedValue)).font(.system(size: 10, design: .monospaced)).foregroundColor(.yellow)
                }
                Slider(value: value, in: range, onEditingChanged: { _ in onChanged() }).tint(.orange)
            }
            .padding(.horizontal, 20)
        )
    }
    
    private var thermalColor: Color {
        switch metricsMonitor.thermalState {
        case .nominal: return .green; case .fair: return .yellow; case .serious: return .orange; case .critical: return .red; @unknown default: return .gray
        }
    }
    private var thermalStateShort: String {
        switch metricsMonitor.thermalState {
        case .nominal: return "NOMINAL"; case .fair: return "FAIR"; case .serious: return "SERIOUS"; case .critical: return "CRITICAL"; @unknown default: return "UNKNOWN"
        }
    }
    private var batteryString: String { metricsMonitor.batteryLevel < 0 ? "N/A" : "\(Int(metricsMonitor.batteryLevel * 100))%" }
}
