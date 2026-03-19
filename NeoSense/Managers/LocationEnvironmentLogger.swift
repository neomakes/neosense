import Foundation
import CoreLocation
import CoreMotion
import Combine
import UIKit

class LocationEnvironmentLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    
    @Published var isLogging = false
    @Published var currentGPSHz: Int = 0
    @Published var lastLocation: CLLocation?
    @Published var lastAltitude: Double = 0
    @Published var isProximityClose: Bool = false
    @Published var brightness: Double = 0.0
    
    private var gpsTickCount = 0
    private var hzTimer: Timer?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func startLogging() {
        DispatchQueue.main.async {
            guard !self.isLogging else { return }
            self.isLogging = true
            
            self.locationManager.requestWhenInUseAuthorization()
            self.locationManager.startUpdatingLocation()
            self.locationManager.startUpdatingHeading()
            
            // Proximity Sensor
            UIDevice.current.isProximityMonitoringEnabled = true
            NotificationCenter.default.addObserver(self, selector: #selector(self.proximityStateDidChange), name: UIDevice.proximityStateDidChangeNotification, object: nil)
            
            self.startAltimeter()
            self.startHzTimer()
        }
    }
    
    func stopLogging() {
        DispatchQueue.main.async {
            self.isLogging = false
            self.locationManager.stopUpdatingLocation()
            self.locationManager.stopUpdatingHeading()
            self.altimeter.stopRelativeAltitudeUpdates()
            
            UIDevice.current.isProximityMonitoringEnabled = false
            NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
            
            self.hzTimer?.invalidate()
            self.hzTimer = nil
            self.currentGPSHz = 0
        }
    }
    
    @objc private func proximityStateDidChange() {
        self.isProximityClose = UIDevice.current.proximityState
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        
        BufferQueue.shared.enqueue(proximityData: self.isProximityClose, sysTimestamp: sysTimestamp, thermalState: thermal)
    }
    
    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            let sysTimestamp = Date().timeIntervalSince1970
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            
            // Log altitude/pressure data
            BufferQueue.shared.enqueue(pressureData: data, sysTimestamp: sysTimestamp, thermalState: thermal)
            self.lastAltitude = data.relativeAltitude.doubleValue
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLogging, let location = locations.last else { return }
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        
        BufferQueue.shared.enqueue(locationBatch: locations, sysTimestamp: sysTimestamp, thermalState: thermal)
        
        self.lastLocation = location
        self.gpsTickCount += locations.count
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isLogging else { return }
        let sysTimestamp = Date().timeIntervalSince1970
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        
        BufferQueue.shared.enqueue(headingData: newHeading, sysTimestamp: sysTimestamp, thermalState: thermal)
    }
    
    private func startHzTimer() {
        hzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentGPSHz = self.gpsTickCount
            self.gpsTickCount = 0
            
            // Log Brightness (ALS Proxy) every second
            self.brightness = UIScreen.main.brightness
            let sysTimestamp = Date().timeIntervalSince1970
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            BufferQueue.shared.enqueue(brightnessData: self.brightness, sysTimestamp: sysTimestamp, thermalState: thermal)
        }
    }
}
