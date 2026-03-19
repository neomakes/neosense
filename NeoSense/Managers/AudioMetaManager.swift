import Foundation
import AVFoundation
import Combine

class AudioMetaManager: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var isConfigured = false
    
    private var audioInput: AVCaptureDeviceInput?
    private var videoInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    @Published var isLogging = false
    @Published var micLevel: Float = -100.0
    var logController: LogController?

    private let sessionQueue = DispatchQueue(label: "com.neomakes.neosense.sessionQueue", qos: .userInitiated)
    
    func updateState() {
        // Safe check on main thread, then move all intensive session work to a serial background queue
        DispatchQueue.main.async {
            guard let logController = self.logController else { return }
            
            let logAudio = logController.logAudio
            let logMeta = logController.logCameraMeta
            let isLiDARActive = logController.logLiDAR
            
            // Note: ARKit implicitly claims the camera when LiDAR or Face is on. 
            // We should NOT start an independent AVCaptureSession for the camera if ARKit is active.
            let needsMeta = logMeta && !isLiDARActive && !logController.logFace 
            let needsCapture = logAudio || needsMeta
            
            self.sessionQueue.async {
                if needsCapture {
                    if !self.isConfigured { self.setupSession() }
                    self.reconfigureInputs(needsAudio: logAudio, needsMeta: needsMeta)
                    
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                        print("🎙️ Audio/Meta Session Started (Audio: \(logAudio), Meta: \(needsMeta))")
                    }
                    DispatchQueue.main.async { self.isLogging = true }
                } else {
                    if self.captureSession.isRunning {
                        self.captureSession.stopRunning()
                        print("🛑 Audio/Meta Session Stopped")
                    }
                    DispatchQueue.main.async { self.isLogging = false }
                }
            }
        }
    }

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        
        // 1. Audio Setup
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: audioDevice) {
            audioInput = input
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.audio.queue"))
            audioOutput = output
        }
        
        // 2. Video Setup (Back Camera for Metadata)
        // ONLY configure this if we can actually get it (it might fail if ARKit is holding it tight)
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
             if let input = try? AVCaptureDeviceInput(device: videoDevice) {
                 videoInput = input
                 let output = AVCaptureVideoDataOutput()
                 output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.meta.queue"))
                 videoOutput = output
             } else {
                 print("⚠️ Cannot get back camera for Metadata. ARKit might be locking it.")
             }
        }
        
        captureSession.commitConfiguration()
        isConfigured = true
    }
    
    private func reconfigureInputs(needsAudio: Bool, needsMeta: Bool) {
        captureSession.beginConfiguration()
        
        // 1. Audio Handling
        if needsAudio {
            if let input = audioInput, !captureSession.inputs.contains(input) {
                if captureSession.canAddInput(input) { captureSession.addInput(input) }
            }
            if let output = audioOutput, !captureSession.outputs.contains(output) {
                if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
            }
        } else {
            if let input = audioInput { captureSession.removeInput(input) }
            if let output = audioOutput { captureSession.removeOutput(output) }
        }
        
        // 2. Metadata (Camera) Handling
        if needsMeta {
            if let input = videoInput, !captureSession.inputs.contains(input) {
                if captureSession.canAddInput(input) { captureSession.addInput(input) }
            }
            if let output = videoOutput, !captureSession.outputs.contains(output) {
                if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
            }
        } else {
            if let input = videoInput { captureSession.removeInput(input) }
            if let output = videoOutput { captureSession.removeOutput(output) }
        }
        
        captureSession.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue

        if output is AVCaptureAudioDataOutput && logController?.logAudio == true {
            let level = calculateAudioLevel(sampleBuffer)
            DispatchQueue.main.async { self.micLevel = level }
            BufferQueue.shared.enqueue(audioLevel: level, sysTimestamp: sysTimestamp, thermalState: thermal)
        } else if output is AVCaptureVideoDataOutput && logController?.logCameraMeta == true {
            // Check if LiDAR became active recently to drop metadata capture mid-stream
            if logController?.logLiDAR == true { return }
            
            if let device = (output as? AVCaptureVideoDataOutput)?.connections.first?.inputPorts.first?.input as? AVCaptureDevice {
                let metadata = ["iso": Double(device.iso), "exposure": device.exposureDuration.seconds, "lens": Double(device.lensPosition)]
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
        for i in 0..<data.count { let val = Float(data[i]) / 32768.0; sum += val * val }
        let rms = sqrt(sum / Float(Swift.max(1, data.count)))
        return 20 * log10(Swift.max(rms, 0.00001))
    }
}
