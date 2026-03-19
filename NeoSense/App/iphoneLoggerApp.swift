import SwiftUI
import AVFoundation

@main
struct NeoSenseApp: App {
    // 앱의 전역 생명주기와 상태를 관리하는 컨트롤러를 최상위 환경 객체로 주입합니다.
    @StateObject private var logController = LogController()
    
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(logController)
                // 다크모드 고정 (배터리 및 발열 최적화)
                .preferredColorScheme(.dark)
                .onAppear {
                    // 앱 실행 시 필수 디렉토리 및 시스템 초기화
                    BufferQueue.shared.logController = logController
                    setupAppEnvironment()
                }
        }
    }
    
    private func setupAppEnvironment() {
        print("🚀 멀티모달 로깅 테스트베드 가동 준비 완료")
        
        // 1. Configure Audio Session for Haptics & System Sounds
        let session = AVAudioSession.sharedInstance()
        do {
            // Standard recording session setup
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            print("🎙️ Audio Session configured for Recording")
        } catch {
            print("🔴 Audio Session Setup Error: \(error)")
        }
        
        // 2. Ensure session directory exists
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionDir = docURL.appendingPathComponent("sessions")
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
    }
}
