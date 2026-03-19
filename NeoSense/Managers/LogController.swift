import Foundation
import Combine

class LogController: ObservableObject {
    @Published var isLoggingAll: Bool = false
    @Published var expandedCategory: String? = "Exteroception" // Default expand first
    
    // Detailed Flags for Phase 1 (Modular Isolation)
    @Published var logFace: Bool = false
    @Published var logLiDAR: Bool = false
    @Published var logCameraMeta: Bool = false
    @Published var logAudio: Bool = false
    @Published var logAccel: Bool = false
    @Published var logGyro: Bool = false
    @Published var logActivity: Bool = false
    @Published var logGPS: Bool = false
    @Published var logHeading: Bool = false
    @Published var logBarometer: Bool = false
    @Published var logALS: Bool = false
    @Published var logProximity: Bool = false
    @Published var logSystemMetrics: Bool = false
    
    // Active Sensing & Actuator States
    @Published var torchLevel: Float = 0.0
    @Published var isExposureLocked: Bool = false
    @Published var exposureDuration: Double = 0.05 // 1/20s default
    @Published var zoomFactor: Double = 1.0
    
    @Published var isVaryingFrequencyActive: Bool = false
    
    private var frequencyTimer: Timer?
    var motionLogger: MotionLogger? // Injected from View
    
    func toggleCategory(_ category: String) {
        if expandedCategory == category {
            expandedCategory = nil
        } else {
            expandedCategory = category
        }
    }
    
    func startAll() {
        isLoggingAll = true
        logFace = true; logLiDAR = true; logCameraMeta = true; logAudio = true
        logAccel = true; logGyro = true; logActivity = true
        logGPS = true; logHeading = true
        logBarometer = true; logALS = true; logProximity = true
        logSystemMetrics = true
    }
    
    func stopAll() {
        isLoggingAll = false
        stopFrequencyModulation() // Ensure this stops too
        logFace = false; logLiDAR = false; logCameraMeta = false; logAudio = false
        logAccel = false; logGyro = false; logActivity = false
        logGPS = false; logHeading = false
        logBarometer = false; logALS = false; logProximity = false
        logSystemMetrics = false
    }
    
    func toggleFrequencyModulation() {
        if isVaryingFrequencyActive {
            stopFrequencyModulation()
            stopAll() // Turn off all sensors when frequency modulation stops
        } else {
            startFrequencyModulation()
        }
    }
    
    private func startFrequencyModulation() {
        guard !isVaryingFrequencyActive else { return }
        isVaryingFrequencyActive = true
        
        // Turn on all individual logging flags for the test (but don't set isLoggingAll to keep UI independent)
        logFace = true; logLiDAR = true; logCameraMeta = true; logAudio = true
        logAccel = true; logGyro = true; logActivity = true
        logGPS = true; logHeading = true
        logBarometer = true; logALS = true; logProximity = true
        logSystemMetrics = true
        
        let randomizeBlock = { [weak self] in
            guard let self = self else { return }
            let randomAccel = [100, 200, 400, 800].randomElement() ?? 800
            let randomGyro = [50, 100, 200].randomElement() ?? 200
            
            self.motionLogger?.updateFrequency(accelHz: randomAccel, gyroHz: randomGyro)
            
            // Log the events individually to the new target
            let now = Date().timeIntervalSince1970
            BufferQueue.shared.enqueueActuatorEvent(name: "target_accel_hz", value: Double(randomAccel), sysTimestamp: now)
            BufferQueue.shared.enqueueActuatorEvent(name: "target_gyro_hz", value: Double(randomGyro), sysTimestamp: now)
        }
        
        // Execute immediately
        randomizeBlock()
        
        // Randomize every 1 second (speeding up from 3.0 for better data density)
        frequencyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            randomizeBlock()
        }
    }
    
    private func stopFrequencyModulation() {
        isVaryingFrequencyActive = false
        frequencyTimer?.invalidate()
        frequencyTimer = nil
        
        // Reset to defaults
        motionLogger?.updateFrequency(accelHz: 800, gyroHz: 200)
    }
    
    var anyActive: Bool {
        logFace || logLiDAR || logCameraMeta || logAudio || logAccel || logGyro || logActivity || logGPS || logHeading || logBarometer || logALS || logProximity || logSystemMetrics || isVaryingFrequencyActive
    }
}
