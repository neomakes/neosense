import Foundation
import ARKit
import Combine
import AVFoundation

class VisionManager: NSObject, ObservableObject, ARSessionDelegate {
    private let arSession = ARSession()
    @Published var isLogging = false
    @Published var faceTrackingHz: Int = 0
    
    private var faceTickCount = 0
    private var hzTimer: Timer?
    var logController: LogController?

    func updateState() {
        DispatchQueue.main.async {
            let needsAR = (self.logController?.logFace == true || self.logController?.logLiDAR == true)
            
            if needsAR && !self.isLogging {
                self.startAR()
            } else if !needsAR && self.isLogging {
                self.stopAR()
            }
        }
    }

    private func startAR() {
        isLogging = true
        let config: ARConfiguration
        
        if logController?.logLiDAR == true && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            let worldConfig = ARWorldTrackingConfiguration()
            worldConfig.sceneReconstruction = .mesh
            if logController?.logFace == true { worldConfig.userFaceTrackingEnabled = true }
            config = worldConfig
        } else {
            config = ARFaceTrackingConfiguration()
        }
        
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        startHzTimer()
    }

    private func stopAR() {
        isLogging = false
        arSession.pause()
        hzTimer?.invalidate()
        hzTimer = nil
        faceTrackingHz = 0
    }
    
    // Active Control for Lens
    func applyActiveControl() {
        guard let device = backCameraDevice,
              let logCtrl = logController else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Zoom
            let zoom = CGFloat(logCtrl.zoomFactor)
            device.videoZoomFactor = max(1.0, min(zoom, device.activeFormat.videoMaxZoomFactor))
            
            // Exposure
            if logCtrl.isExposureLocked {
                let duration = CMTime(seconds: logCtrl.exposureDuration, preferredTimescale: 1000)
                device.setExposureModeCustom(duration: duration, iso: AVCaptureDevice.currentISO, completionHandler: nil)
            } else {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
            
            // Log the intentional intervention
            let sysTimestamp = Date().timeIntervalSince1970
            BufferQueue.shared.enqueueActuatorEvent(name: "active_lens_control", value: logCtrl.zoomFactor, sysTimestamp: sysTimestamp)
        } catch {
            print("🔴 Active Lens Control Error: \(error)")
        }
    }

    private var backCameraDevice: AVCaptureDevice? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    private var lastMetadataLogTime: TimeInterval = 0

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isLogging else { return }
        let hwTimestamp = frame.timestamp
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue

        // [1] Face Mesh Data
        if logController?.logFace == true {
            let faceAnchors = frame.anchors.compactMap { $0 as? ARFaceAnchor }
            if !faceAnchors.isEmpty {
                BufferQueue.shared.enqueue(faceBatch: faceAnchors, hwTimestamp: hwTimestamp, sysTimestamp: sysTimestamp, thermalState: thermal)
                faceTickCount += faceAnchors.count
            }
        }

        // [2] LiDAR Mesh Data
        if logController?.logLiDAR == true {
            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            if !meshAnchors.isEmpty {
                BufferQueue.shared.enqueue(meshBatch: meshAnchors, hwTimestamp: hwTimestamp, sysTimestamp: sysTimestamp, thermalState: thermal)
            }
        }
        
        // [3] Joint Camera Metadata (Throttled to 10Hz to avoid Fig contention)
        if logController?.logCameraMeta == true && (sysTimestamp - lastMetadataLogTime) > 0.1 {
            if let device = backCameraDevice {
                let metadata = [
                    "iso": Double(device.iso),
                    "exposure": device.exposureDuration.seconds,
                    "lens": Double(device.lensPosition)
                ]
                BufferQueue.shared.enqueue(cameraMetadata: metadata, sysTimestamp: sysTimestamp, thermalState: thermal)
                lastMetadataLogTime = sysTimestamp
            }
        }
    }

    private func startHzTimer() {
        hzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.faceTrackingHz = self.faceTickCount
            self.faceTickCount = 0
        }
    }
}
