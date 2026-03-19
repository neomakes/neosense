import Foundation
import Combine
import UIKit
import MachO
import Metal

class SystemMetricsMonitor: ObservableObject {
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = -1.0
    @Published var cpuUsage: Double = 0.0
    @Published var gpuUsage: Double = 0.0
    @Published var memoryUsageMB: Double = 0.0
    @Published var aneUsage: Double = 0.0 // Estimation or placeholder
    
    private var timer: Timer?
    private var device: MTLDevice?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalState = ProcessInfo.processInfo.thermalState
        self.device = MTLCreateSystemDefaultDevice()
        setupThermalObserver()
    }
    
    func startMonitoring() {
        updateMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func setupThermalObserver() {
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    private func updateMetrics() {
        let battery = UIDevice.current.batteryLevel
        let cpu = getCPUUsage()
        let mem = getMemoryUsage()
        let gpu = estimateGPUUsage()
        let ane = estimateANEUsage()
        let currentThermal = thermalState
        
        DispatchQueue.main.async {
            self.batteryLevel = battery
            self.cpuUsage = cpu
            self.memoryUsageMB = mem
            self.gpuUsage = gpu
            self.aneUsage = ane
        }
        
        let sysTimestamp = Date().timeIntervalSince1970
        BufferQueue.shared.enqueue(systemHealth: [
            "battery": battery,
            "cpu": cpu,
            "gpu": gpu,
            "ane": ane,
            "memory": mem,
            "thermal": Double(currentThermal.rawValue)
        ], sysTimestamp: sysTimestamp)
    }
    
    // Mach kernel based CPU calculation
    private func getCPUUsage() -> Double {
        var thread_list: thread_act_array_t?
        var thread_count: mach_msg_type_number_t = 0
        let kr = task_threads(mach_task_self_, &thread_list, &thread_count)
        guard kr == KERN_SUCCESS, let threads = thread_list else { return 0.0 }
        
        var total_cpu: Double = 0
        for i in 0..<Int(thread_count) {
            var thinfo = thread_basic_info()
            var thinfo_count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let thread_kr = withUnsafeMutablePointer(to: &thinfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(thinfo_count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &thinfo_count)
                }
            }
            if thread_kr == KERN_SUCCESS && (thinfo.flags & TH_FLAGS_IDLE) == 0 {
                total_cpu += Double(thinfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(thread_count * UInt32(MemoryLayout<thread_t>.stride)))
        return total_cpu
    }
    
    private func getMemoryUsage() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return (kerr == KERN_SUCCESS) ? Double(taskInfo.resident_size) / (1024.0 * 1024.0) : 0.0
    }
    
    // GPU usage is not directly exposed via public API on iOS.
    // We estimate it based on Metal device reporting if available or heat/thermal proxy.
    private func estimateGPUUsage() -> Double {
        // Placeholder: AI models can learn the correlation between ThermalState and CPU/GPU load
        return (thermalState == .critical || thermalState == .serious) ? 85.0 : 15.0
    }
    
    private func estimateANEUsage() -> Double {
        // Placeholder for ANE load estimation
        return (thermalState == .critical) ? 90.0 : 5.0
    }
}
