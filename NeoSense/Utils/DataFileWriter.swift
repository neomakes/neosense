import Foundation

class DataFileWriter {
    private let fileName: String
    private let fileURL: URL
    private let queue: DispatchQueue
    private var fileHandle: FileHandle?
    
    init(sensorName: String, header: String, folderURL: URL) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "\(sensorName)_\(formatter.string(from: Date())).csv"
        self.fileName = name
        self.fileURL = folderURL.appendingPathComponent(name)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        self.queue = DispatchQueue(label: "com.neomakes.neosense.writer.\(sensorName)", qos: .background)
        setupFile(header: header)
    }
    
    private func setupFile(header: String) {
        do {
            let headerLine = header + "\n"
            try headerLine.write(to: fileURL, atomically: true, encoding: .utf8)
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            self.fileHandle?.seekToEndOfFile()
            print("📄 [\(fileName)] 파일 생성 완료")
        } catch {
            print("🔴 파일 생성 에러: \(error)")
        }
    }
    
    func write(lines: [String]) {
        queue.async { [weak self] in
            guard let handle = self?.fileHandle else { return }
            let csvStr = lines.joined(separator: "\n") + "\n"
            if let data = csvStr.data(using: .utf8) {
                do {
                    if #available(iOS 13.4, *) {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } else {
                        handle.seekToEndOfFile()
                        handle.write(data)
                    }
                } catch {
                    print("🔴 파일 쓰기 에러: \(error)")
                }
            }
        }
    }
    
    private var isClosed = false
    
    deinit {
        if !isClosed {
            close()
        }
    }
    
    func close() {
        queue.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            do {
                try self.fileHandle?.close()
                self.fileHandle = nil
                self.isClosed = true
            } catch {
                print("🔴 파일 종료 에러: \(error)")
            }
        }
    }
}
