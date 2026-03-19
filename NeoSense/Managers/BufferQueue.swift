import Foundation
import CoreMotion
import Combine
import UIKit
import ARKit
import CoreLocation

class BufferQueue: ObservableObject {
    static let shared = BufferQueue()
    var logController: LogController? // Will be injected from App root
    
    // Writers (Lazy)
    private var accelWriter: DataFileWriter?; private var gyroWriter: DataFileWriter?
    private var locationWriter: DataFileWriter?; private var pressureWriter: DataFileWriter?
    private var faceWriter: DataFileWriter?; private var systemHealthWriter: DataFileWriter? // renamed
    private var headingWriter: DataFileWriter?; private var cameraMetaWriter: DataFileWriter?
    private var audioWriter: DataFileWriter?; private var meshWriter: DataFileWriter?
    private var brightnessWriter: DataFileWriter?; private var proximityWriter: DataFileWriter?
    private var activityWriter: DataFileWriter?
    private var actuatorWriter: DataFileWriter? // Action (a) logging
    
    // Buffers
    private var accelBuffer: [String] = []; private var gyroBuffer: [String] = []
    private var locationBuffer: [String] = []; private var pressureBuffer: [String] = []
    private var faceBuffer: [String] = []; private var systemHealthBuffer: [String] = []
    private var headingBuffer: [String] = []; private var cameraMetaBuffer: [String] = []
    private var audioBuffer: [String] = []; private var meshBuffer: [String] = []
    private var brightnessBuffer: [String] = []; private var proximityBuffer: [String] = []
    private var activityBuffer: [String] = []
    private var actuatorBuffer: [String] = []
    
    private let writeInterval: TimeInterval = 0.5
    private var timer: Timer?
    let schemaHeader = "hw_timestamp,sys_timestamp,target_hz,sys_hz,thermal_state,"
    private var currentSessionURL: URL?
    private var isRecording = false
    var isRecordingActive: Bool { isRecording }
    
    func startRecording(targetHz: Int = 800) {
        guard !isRecording else { return }
        isRecording = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd_HHmmss"
        let sessionID = formatter.string(from: Date())
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionURL = docURL.appendingPathComponent("sessions/\(sessionID)")
        self.currentSessionURL = sessionURL
        createSessionMetadata(at: sessionURL, sessionID: sessionID)
        clearBuffers()
        timer = Timer.scheduledTimer(withTimeInterval: writeInterval, repeats: true) { [weak self] _ in self?.flushBuffers() }
    }
    
    private func clearBuffers() {
        accelBuffer.removeAll(); gyroBuffer.removeAll(); locationBuffer.removeAll(); pressureBuffer.removeAll()
        faceBuffer.removeAll(); systemHealthBuffer.removeAll(); headingBuffer.removeAll(); cameraMetaBuffer.removeAll()
        audioBuffer.removeAll(); meshBuffer.removeAll(); brightnessBuffer.removeAll(); proximityBuffer.removeAll()
        activityBuffer.removeAll(); actuatorBuffer.removeAll()
    }
    
    private func createSessionMetadata(at url: URL, sessionID: String) {
        let metadata: [String: Any] = ["session_id": sessionID, "device": UIDevice.current.model, "timestamp": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            try? data.write(to: url.appendingPathComponent("session_info.json"))
        }
    }
    
    func flushBuffers() {
        flush(writer: accelWriter, buffer: &accelBuffer); flush(writer: gyroWriter, buffer: &gyroBuffer)
        flush(writer: locationWriter, buffer: &locationBuffer); flush(writer: pressureWriter, buffer: &pressureBuffer)
        flush(writer: faceWriter, buffer: &faceBuffer); flush(writer: systemHealthWriter, buffer: &systemHealthBuffer)
        flush(writer: headingWriter, buffer: &headingBuffer); flush(writer: cameraMetaWriter, buffer: &cameraMetaBuffer)
        flush(writer: audioWriter, buffer: &audioBuffer); flush(writer: meshWriter, buffer: &meshBuffer)
        flush(writer: brightnessWriter, buffer: &brightnessBuffer); flush(writer: proximityWriter, buffer: &proximityBuffer)
        flush(writer: activityWriter, buffer: &activityBuffer); flush(writer: actuatorWriter, buffer: &actuatorBuffer)
    }
    
    private func flush(writer: DataFileWriter?, buffer: inout [String]) {
        guard !buffer.isEmpty else { return }
        let chunk = buffer; buffer.removeAll(); writer?.write(lines: chunk)
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false; timer?.invalidate(); timer = nil; flushBuffers()
        [accelWriter, gyroWriter, locationWriter, pressureWriter, faceWriter, systemHealthWriter, headingWriter, cameraMetaWriter, audioWriter, meshWriter, brightnessWriter, proximityWriter, activityWriter, actuatorWriter].forEach { $0?.close() }
        accelWriter = nil; gyroWriter = nil; locationWriter = nil; pressureWriter = nil; faceWriter = nil; systemHealthWriter = nil
        headingWriter = nil; cameraMetaWriter = nil; audioWriter = nil; meshWriter = nil; brightnessWriter = nil; proximityWriter = nil
        activityWriter = nil; actuatorWriter = nil
        currentSessionURL = nil
    }
    
    private func getWriter(_ writer: inout DataFileWriter?, name: String, header: String) -> DataFileWriter? {
        if writer == nil, let url = currentSessionURL { writer = DataFileWriter(sensorName: name, header: header, folderURL: url) }
        return writer
    }
    
    // MARK: - Enqueue with logController Check (Exteroception)
    func enqueue(accelerometerBatch: [CMAccelerometerData], sysTimestamp: Double, targetHz: Int, sysHz: Int, thermalState: Int) {
        guard isRecording, logController?.logAccel == true else { return }
        let lines = accelerometerBatch.map { "\(Swift.max(0, $0.timestamp)),\(sysTimestamp),\(targetHz),\(sysHz),\(thermalState),\($0.acceleration.x),\($0.acceleration.y),\($0.acceleration.z)" }
        accelBuffer.append(contentsOf: lines); _ = getWriter(&accelWriter, name: "proprio_imu_accel", header: schemaHeader + "x,y,z")
    }
    
    func enqueue(deviceMotionBatch: [CMDeviceMotion], sysTimestamp: Double, targetHz: Int, sysHz: Int, thermalState: Int) {
        guard isRecording, logController?.logGyro == true else { return }
        let lines = deviceMotionBatch.map { "\($0.timestamp),\(sysTimestamp),\(targetHz),\(sysHz),\(thermalState),\($0.attitude.pitch),\($0.attitude.roll),\($0.attitude.yaw)" }
        gyroBuffer.append(contentsOf: lines); _ = getWriter(&gyroWriter, name: "proprio_imu_gyro", header: schemaHeader + "pitch,roll,yaw")
    }
    
    func enqueue(locationBatch: [CLLocation], sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logGPS == true else { return }
        let lines = locationBatch.map { "\($0.timestamp.timeIntervalSince1970),\(sysTimestamp),1,1,\(thermalState),\($0.coordinate.latitude),\($0.coordinate.longitude),\($0.altitude),\($0.horizontalAccuracy)" }
        locationBuffer.append(contentsOf: lines); _ = getWriter(&locationWriter, name: "extero_gps_location", header: schemaHeader + "lat,lon,alt,acc")
    }
    
    func enqueue(pressureData: CMAltitudeData, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logBarometer == true else { return }
        let line = "\(pressureData.timestamp),\(sysTimestamp),10,10,\(thermalState),\(pressureData.pressure.doubleValue),\(pressureData.relativeAltitude.doubleValue)"
        pressureBuffer.append(line); _ = getWriter(&pressureWriter, name: "extero_env_pressure", header: schemaHeader + "pressure,rel_alt")
    }
    
    func enqueue(headingData: CLHeading, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logHeading == true else { return }
        let line = "\(headingData.timestamp.timeIntervalSince1970),\(sysTimestamp),30,30,\(thermalState),\(headingData.magneticHeading),\(headingData.trueHeading)"
        headingBuffer.append(line); _ = getWriter(&headingWriter, name: "extero_gps_heading", header: schemaHeader + "mag,true")
    }
    
    func enqueue(faceBatch: [ARFaceAnchor], hwTimestamp: Double, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logFace == true else { return }
        let lines = faceBatch.map { anchor in
            let shapes = anchor.blendShapes.mapValues { $0.floatValue }
            let json = try? JSONSerialization.data(withJSONObject: shapes)
            let jsonString = String(data: json ?? Data(), encoding: .utf8)?.replacingOccurrences(of: ",", with: ";") ?? ""
            return "\(hwTimestamp),\(sysTimestamp),60,60,\(thermalState),\(jsonString)"
        }
        faceBuffer.append(contentsOf: lines); _ = getWriter(&faceWriter, name: "extero_vision_face", header: schemaHeader + "blendshapes")
    }
    
    func enqueue(meshBatch: [ARMeshAnchor], hwTimestamp: Double, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logLiDAR == true else { return }
        let line = "\(hwTimestamp),\(sysTimestamp),15,15,\(thermalState),\(meshBatch.count)_anchors"
        meshBuffer.append(line); _ = getWriter(&meshWriter, name: "extero_vision_lidar", header: schemaHeader + "anchor_count")
    }
    
    func enqueue(cameraMetadata: [String: Double], sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logCameraMeta == true else { return }
        // Note: AVCaptureDevice metadata does not provide a separate hardware timestamp like ARFrame or CMMotion.
        // We use arrival time (sysTimestamp) for both to indicate it's a polled metric.
        let line = "\(sysTimestamp),\(sysTimestamp),30,30,\(thermalState),\(cameraMetadata["iso"] ?? 0),\(cameraMetadata["exposure"] ?? 0),\(cameraMetadata["lens"] ?? 0)"
        cameraMetaBuffer.append(line); _ = getWriter(&cameraMetaWriter, name: "extero_vision_meta", header: schemaHeader + "iso,exp,lens")
    }
    
    func enqueue(audioLevel: Float, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logAudio == true else { return }
        let line = "\(sysTimestamp),\(sysTimestamp),10,10,\(thermalState),\(audioLevel)"
        audioBuffer.append(line); _ = getWriter(&audioWriter, name: "extero_audio_mic", header: schemaHeader + "dbfs")
    }
    
    func enqueue(brightnessData: Double, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logALS == true else { return }
        let line = "\(sysTimestamp),\(sysTimestamp),1,1,\(thermalState),\(brightnessData)"
        brightnessBuffer.append(line); _ = getWriter(&brightnessWriter, name: "extero_env_brightness", header: schemaHeader + "lux_proxy")
    }
    
    func enqueue(proximityData: Bool, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logProximity == true else { return }
        let line = "\(sysTimestamp),\(sysTimestamp),0,0,\(thermalState),\(proximityData ? 1 : 0)"
        proximityBuffer.append(line); _ = getWriter(&proximityWriter, name: "extero_body_proximity", header: schemaHeader + "is_close")
    }
    
    func enqueue(activityData: CMMotionActivity, sysTimestamp: Double, thermalState: Int) {
        guard isRecording, logController?.logActivity == true else { return }
        let type = activityData.walking ? "walking" : (activityData.running ? "running" : (activityData.cycling ? "cycling" : (activityData.automotive ? "automotive" : (activityData.stationary ? "stationary" : "unknown"))))
        let line = "\(activityData.startDate.timeIntervalSince1970),\(sysTimestamp),1,1,\(thermalState),\(type),\(activityData.confidence.rawValue)"
        activityBuffer.append(line); _ = getWriter(&activityWriter, name: "proprio_motion_activity", header: schemaHeader + "type,confidence")
    }

    // MARK: - Interoception (Internal Survival State)
    func enqueue(systemHealth: [String: Any], sysTimestamp: Double) {
        guard isRecording, logController?.logSystemMetrics == true else { return }
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        let line = "\(sysTimestamp),\(sysTimestamp),1,1,\(thermal),\(systemHealth["battery"] ?? -1),\(systemHealth["cpu"] ?? 0),\(systemHealth["gpu"] ?? 0),\(systemHealth["ane"] ?? 0),\(systemHealth["memory"] ?? 0)"
        systemHealthBuffer.append(line); _ = getWriter(&systemHealthWriter, name: "intero_sys_health", header: schemaHeader + "battery,cpu,gpu,ane,mem_mb")
    }
    
    // MARK: - Action Feedback (Proprioception / Efferent Copy)
    func enqueueActuatorEvent(name: String, value: Double, sysTimestamp: Double) {
        guard isRecording else { return }
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        let line = "\(sysTimestamp),\(sysTimestamp),0,0,\(thermal),\(name),\(value)"
        actuatorBuffer.append(line); _ = getWriter(&actuatorWriter, name: "proprio_actuator_events", header: schemaHeader + "action_name,target_value")
    }
}
