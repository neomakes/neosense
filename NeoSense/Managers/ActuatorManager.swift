import Foundation
import UIKit
import AVFoundation
import Combine

class ActuatorManager: ObservableObject {
    @Published var flashlightLevel: Float = 0.0
    
    init() {
        // Haptics removed per user request due to system-level interference in Chaos State
    }
    
    func setFlashlight(level: Float) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if level > 0 {
                try device.setTorchModeOn(level: level)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            flashlightLevel = level
            
            // Log the motor command
            let sysTimestamp = Date().timeIntervalSince1970
            BufferQueue.shared.enqueueActuatorEvent(name: "torch_intensity", value: Double(level), sysTimestamp: sysTimestamp)
        } catch {
            print("🔴 Flashlight Error: \(error)")
        }
    }
    
    // playHapticImpact removed to simplify focus on reliable sensors
}
