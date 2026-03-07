import SwiftUI

// 임시 DashboardView (추후 상세 렌더링 추가)
struct DashboardView: View {
    @EnvironmentObject var logController: LogController
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edge AI Testbed")
                .font(.largeTitle)
                .bold()
                
            Text("Sensors Ready")
                .foregroundColor(.green)
            
            // 향후 여기에 [START ALL] 버튼과 상태 카드들이 추가됩니다.
        }
        .padding()
    }
}

// 임시 LogController (Orchestrator 뼈대)
class LogController: ObservableObject {
    @Published var isLoggingAll: Bool = false
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    
    // 시작/중지 등의 제어 메서드는 이후 추가
}
