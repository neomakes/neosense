import Foundation
import ARKit
import AVFoundation
import Combine

class VisionAudioLogger: NSObject, ObservableObject, ARSessionDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let arSession = ARSession()
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured = false
    
    @Published var isLogging = false
    @Published var faceTrackingHz: Int = 0
    @Published var micLevel: Float = -100.0
    
    private var faceTickCount = 0
    private var hzTimer: Timer?
    
    func startLogging() {
        guard !isLogging else { return }
        isLogging = true
        
        // 1. Setup ARSession (Face + LiDAR)
        let config = ARFaceTrackingConfiguration()
        if ARFaceTrackingConfiguration.supportsWorldTracking {
            config.isWorldTrackingEnabled = true
        }
        
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // 2. Setup Audio/Camera Metrics (Only once)
        if !isCaptureSessionConfigured {
            setupCaptureSession()
            isCaptureSessionConfigured = true
        }
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
        
        startHzTimer()
    }
    
    func stopLogging() {
        isLogging = false
        arSession.pause()
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        hzTimer?.invalidate()
        hzTimer = nil
        faceTrackingHz = 0
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        
        // Audio Input & Output
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
            
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.neomakes.neosense.audio.queue"))
            if captureSession.canAddOutput(audioOutput) {
                captureSession.addOutput(audioOutput)
            }
        }
        
        // Video Input & Output (Metadata only)
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
           captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.neomakes.neosense.video.metadata.queue"))
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - ARSessionDelegate (Face & LiDAR)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isLogging else { return }
        
        let hwTimestamp = frame.timestamp
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        
        // [A] Face BlendShapes
        let faceAnchors = frame.anchors.compactMap { $0 as? ARFaceAnchor }
        if !faceAnchors.isEmpty {
            BufferQueue.shared.enqueue(faceBatch: faceAnchors, hwTimestamp: hwTimestamp, sysTimestamp: sysTimestamp, thermalState: thermal)
            faceTickCount += faceAnchors.count
        }
        
        // [B] LiDAR / Scene Reconstruction (Vertices)
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        if !meshAnchors.isEmpty {
            BufferQueue.shared.enqueue(meshBatch: meshAnchors, hwTimestamp: hwTimestamp, sysTimestamp: sysTimestamp, thermalState: thermal)
        }
    }
    
    // MARK: - SampleBuffer Delegates
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isLogging else { return }
        
        if output is AVCaptureAudioDataOutput {
            let level = calculateAudioLevel(sampleBuffer)
            DispatchQueue.main.async { self.micLevel = level }
            
            let sysTimestamp = Date().timeIntervalSince1970
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            BufferQueue.shared.enqueue(audioLevel: level, sysTimestamp: sysTimestamp, thermalState: thermal)
        } else if output is AVCaptureVideoDataOutput {
            if let device = (output as? AVCaptureVideoDataOutput)?.connections.first?.inputPorts.first?.input as? AVCaptureDevice {
                let metadata = [
                    "iso": Double(device.iso),
                    "exposure": device.exposureDuration.seconds,
                    "lens": Double(device.lensPosition)
                ]
                let sysTimestamp = Date().timeIntervalSince1970
                let thermal = ProcessInfo.processInfo.thermalState.rawValue
                BufferQueue.shared.enqueue(cameraMetadata: metadata, sysTimestamp: sysTimestamp, thermalState: thermal)
            }
        }
    }
    
    private func calculateAudioLevel(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return -100.0 }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = [Int16](repeating: 0, count: length / 2)
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
        
        var sum: Float = 0
        for i in 0..<data.count {
            let val = Float(data[i]) / 32768.0
            sum += val * val
        }
        let rms = sqrt(sum / Float(Swift.max(1, data.count)))
        let dbfs = 20 * log10(Swift.max(rms, 0.00001))
        return dbfs
    }
    
    private func startHzTimer() {
        hzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.faceTrackingHz = self.faceTickCount
            faceTickCount = 0
        }
    }
}
