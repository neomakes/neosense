import Foundation
import CoreMotion
import Combine

class MotionLogger: ObservableObject {
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    
    @Published var isLogging = false
    @Published var currentAccelHz: Int = 0
    @Published var currentGyroHz: Int = 0
    @Published var currentActivity: String = "stationary"
    
    private var targetAccelHz: Int = 800
    private var targetGyroHz: Int = 200
    
    private var accelTickCount = 0
    private var gyroTickCount = 0
    private var hzTimer: Timer?
    
    // Dedicated background queue for high-bandwidth IMU streams
    private let imuQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.neomakes.neosense.imu"
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    func startLogging() {
        DispatchQueue.main.async {
            guard !self.isLogging else { return }
            self.isLogging = true
            
            // IMU
            self.targetAccelHz = 800
            self.targetGyroHz = 200
            self.motionManager.accelerometerUpdateInterval = 1.0 / Double(self.targetAccelHz)
            self.motionManager.deviceMotionUpdateInterval = 1.0 / Double(self.targetGyroHz)
            
            // Move to background queue to bypass .main thread's 100Hz cap and reduce Jitter
            self.motionManager.startAccelerometerUpdates(to: self.imuQueue) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                let sysTimestamp = Date().timeIntervalSince1970
                let thermal = ProcessInfo.processInfo.thermalState.rawValue
                BufferQueue.shared.enqueue(accelerometerBatch: [data], sysTimestamp: sysTimestamp, targetHz: self.targetAccelHz, sysHz: self.currentAccelHz, thermalState: thermal)
                
                DispatchQueue.main.async {
                    self.accelTickCount += 1
                }
            }
            
            self.motionManager.startDeviceMotionUpdates(to: self.imuQueue) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                let sysTimestamp = Date().timeIntervalSince1970
                let thermal = ProcessInfo.processInfo.thermalState.rawValue
                
                // BUG FIX: Corrected type to CMDeviceMotion to match BufferQueue expectation (pitch, roll, yaw)
                BufferQueue.shared.enqueue(deviceMotionBatch: [data], sysTimestamp: sysTimestamp, targetHz: self.targetGyroHz, sysHz: self.currentGyroHz, thermalState: thermal)
                
                DispatchQueue.main.async {
                    self.gyroTickCount += 1
                }
            }
            
            // Activity Recognition
            if CMMotionActivityManager.isActivityAvailable() {
                self.activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                    guard let self = self, let activity = activity else { return }
                    let type = activity.walking ? "walking" : (activity.running ? "running" : (activity.cycling ? "cycling" : (activity.automotive ? "automotive" : (activity.stationary ? "stationary" : "unknown"))))
                    self.currentActivity = type
                    
                    let sysTimestamp = Date().timeIntervalSince1970
                    let thermal = ProcessInfo.processInfo.thermalState.rawValue
                    BufferQueue.shared.enqueue(activityData: activity, sysTimestamp: sysTimestamp, thermalState: thermal)
                }
            }
            
            self.startHzTimer()
        }
    }
    
    func stopLogging() {
        DispatchQueue.main.async {
            self.isLogging = false
            self.motionManager.stopAccelerometerUpdates()
            self.motionManager.stopDeviceMotionUpdates()
            self.activityManager.stopActivityUpdates()
            self.hzTimer?.invalidate()
            self.hzTimer = nil
            self.currentAccelHz = 0
            self.currentGyroHz = 0
        }
    }
    
    private func startHzTimer() {
        hzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentAccelHz = self.accelTickCount
            self.currentGyroHz = self.gyroTickCount
            self.accelTickCount = 0
            self.gyroTickCount = 0
        }
    }
    
    func updateFrequency(accelHz: Int, gyroHz: Int) {
        self.targetAccelHz = accelHz
        self.targetGyroHz = gyroHz
        self.motionManager.accelerometerUpdateInterval = 1.0 / Double(accelHz)
        self.motionManager.deviceMotionUpdateInterval = 1.0 / Double(gyroHz)
        print("⚡️ Frequency updated to: Accel \(accelHz)Hz, Gyro \(gyroHz)Hz")
    }
}
