import Foundation
import Photos
import CryptoKit

class USBExportManager: ObservableObject {
    @Published var progress = ExportProgress()
    @Published var isExporting = false
    
    // STEP 4: EXPORT TO USB-C DRIVE
    func exportToUSB(items: [MediaItem], to destinationURL: URL, photoManager: PhotoLibraryManager, completion: @escaping (Bool) -> Void) {
        isExporting = true
        progress = ExportProgress(total: items.count, completed: 0, currentFile: "Starting...")
        
        let fileManager = FileManager.default
        
        // Create organized structure on USB
        let photosDir = destinationURL.appendingPathComponent("iPhone16_Photos", isDirectory: true)
        let videosDir = destinationURL.appendingPathComponent("iPhone16_Videos", isDirectory: true)
        let organizedDir = destinationURL.appendingPathComponent("Organized_By_Date", isDirectory: true)
        
        try? fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: organizedDir, withIntermediateDirectories: true)
        
        // Hash log for verification
        var hashLog: [String] = []
        let hashLogURL = destinationURL.appendingPathComponent("verification_hashes.txt")
        
        let group = DispatchGroup()
        var exportErrors: [String] = []
        var completedCount = 0
        
        for (index, item) in items.enumerated() {
            group.enter()
            
            DispatchQueue.main.async {
                self.progress.completed = completedCount
                self.progress.currentFile = item.fileName
            }
            
            photoManager.requestOriginalFile(for: item.asset) { tempURL in
                defer { group.leave() }
                
                guard let tempURL = tempURL else {
                    exportErrors.append("Failed: \(item.fileName)")
                    return
                }
                
                // Determine destination by type and date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM"
                let dateFolder = item.creationDate != nil ? dateFormatter.string(from: item.creationDate!) : "Unknown_Date"
                
                let dateDir = organizedDir.appendingPathComponent(dateFolder, isDirectory: true)
                try? fileManager.createDirectory(at: dateDir, withIntermediateDirectories: true)
                
                let destByType: URL
                if item.type == .video {
                    destByType = videosDir.appendingPathComponent(item.fileName)
                } else {
                    destByType = photosDir.appendingPathComponent(item.fileName)
                }
                
                let destByDate = dateDir.appendingPathComponent(item.fileName)
                
                do {
                    if fileManager.fileExists(atPath: destByType.path) {
                        try fileManager.removeItem(at: destByType)
                    }
                    try fileManager.copyItem(at: tempURL, to: destByType)
                    
                    if !fileManager.fileExists(atPath: destByDate.path) {
                        try fileManager.copyItem(at: tempURL, to: destByDate)
                    }
                    
                    if let data = try? Data(contentsOf: destByType) {
                        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                        hashLog.append("\(hash)  \(item.fileName)")
                    }
                    
                    try? fileManager.removeItem(at: tempURL)
                    completedCount += 1
                } catch {
                    exportErrors.append("\(item.fileName): \(error.localizedDescription)")
                }
            }
            
            // Throttle to avoid memory pressure
            if index % 4 == 0 {
                group.wait()
            }
        }
        
        group.notify(queue: .main) {
            let logContent = hashLog.joined(separator: "\n")
            try? logContent.write(to: hashLogURL, atomically: true, encoding: .utf8)
            
            let summary = """
            iPhone 16+ Photo Recovery Export - Finding App
            Date: \(Date())
            Total: \(items.count)
            Completed: \(completedCount)
            Errors: \(exportErrors.count)
            \(exportErrors.joined(separator: "\n"))
            """
            let summaryURL = destinationURL.appendingPathComponent("EXPORT_SUMMARY.txt")
            try? summary.write(to: summaryURL, atomically: true, encoding: .utf8)
            
            self.progress.errors = exportErrors
            self.progress.completed = completedCount
            self.isExporting = false
            completion(exportErrors.isEmpty)
        }
    }
}
