import Foundation
import CryptoKit

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

// Automatic Group Google Takeouts Import - ON-DEVICE UNZIP - NO COMPUTER NEEDED
class TakeoutImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var progressText = ""
    @Published var importedGroups: [TakeoutGroup] = []
    @Published var totalImported = 0
    @Published var currentUnzipProgress: Double = 0
    
    struct TakeoutGroup: Identifiable {
        let id = UUID()
        let accountEmail: String
        let albumName: String
        let year: String
        var files: [URL] = []
        var count: Int { files.count }
    }
    
    func importTakeouts(from sourceURLs: [URL], to destinationBaseURL: URL, completion: @escaping ([TakeoutGroup]) -> Void) {
        isImporting = true
        progressText = "Starting Takeout import - \(sourceURLs.count) file(s)..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            var groups: [String: TakeoutGroup] = [:]
            var tempDirsToClean: [URL] = []
            
            for sourceURL in sourceURLs {
                let didStart = sourceURL.startAccessingSecurityScopedResource()
                defer { if didStart { sourceURL.stopAccessingSecurityScopedResource() } }
                
                DispatchQueue.main.async { self.progressText = "Scanning \(sourceURL.lastPathComponent)..." }
                
                let workingURL: URL
                if sourceURL.pathExtension.lowercased() == "zip" {
                    DispatchQueue.main.async { self.progressText = "Unzipping \(sourceURL.lastPathComponent) on iPhone..." }
                    workingURL = self.unzipTakeoutOnDevice(zipURL: sourceURL)
                    tempDirsToClean.append(workingURL)
                } else {
                    workingURL = sourceURL
                }
                
                let email = self.detectEmailFromTakeout(at: workingURL) ?? self.detectEmailFromPath(sourceURL.lastPathComponent)
                
                let fileManager = FileManager.default
                guard let enumerator = fileManager.enumerator(at: workingURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                
                for case let fileURL as URL in enumerator {
                    guard fileURL.isFileURL else { continue }
                    let ext = fileURL.pathExtension.lowercased()
                    guard ["jpg","jpeg","png","heic","heif","mp4","mov","avi","mkv","3gp","webp"].contains(ext) else { continue }
                    
                    let components = fileURL.pathComponents
                    var year = "Unknown_Year"
                    var album = "Unknown_Album"
                    
                    for comp in components {
                        if comp.contains("Photos from") {
                            year = comp.replacingOccurrences(of: "Photos from ", with: "")
                            album = "All Photos"
                            break
                        }
                        if comp.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
                            year = comp
                        }
                    }
                    
                    if let parent = fileURL.deletingLastPathComponent().lastPathComponent as String? {
                        if !parent.contains("Google Photos") && !parent.contains("Takeout") && parent != year && parent != "All Photos" {
                            album = parent
                        }
                    }
                    
                    let key = "\(email)-\(year)-\(album)"
                    if groups[key] == nil {
                        groups[key] = TakeoutGroup(accountEmail: email, albumName: album, year: year, files: [])
                    }
                    groups[key]?.files.append(fileURL)
                }
            }
            
            let groupedArray = Array(groups.values)
            var finalGroups: [TakeoutGroup] = []
            var total = 0
            
            for group in groupedArray {
                DispatchQueue.main.async { self.progressText = "Copying \(group.accountEmail) - \(group.year) - \(group.albumName) (\(group.count) files)" }
                
                let destDir = destinationBaseURL
                    .appendingPathComponent("GoogleTakeout_Groups", isDirectory: true)
                    .appendingPathComponent(self.sanitize(group.accountEmail), isDirectory: true)
                    .appendingPathComponent(group.year, isDirectory: true)
                    .appendingPathComponent(self.sanitize(group.albumName), isDirectory: true)
                
                try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                
                var copiedFiles: [URL] = []
                for src in group.files {
                    let dest = destDir.appendingPathComponent(src.lastPathComponent)
                    if FileManager.default.fileExists(atPath: dest.path) { continue }
                    do {
                        try FileManager.default.copyItem(at: src, to: dest)
                        copiedFiles.append(dest)
                        total += 1
                        DispatchQueue.main.async { self.totalImported = total }
                    } catch {
                        print("Copy failed \(src) -> \(error)")
                    }
                }
                
                var newGroup = group
                newGroup.files = copiedFiles
                finalGroups.append(newGroup)
            }
            
            self.writeSummary(groups: finalGroups, to: destinationBaseURL, total: total)
            
            for dir in tempDirsToClean {
                try? FileManager.default.removeItem(at: dir)
            }
            
            DispatchQueue.main.async {
                self.importedGroups = finalGroups
                self.totalImported = total
                self.isImporting = false
                self.progressText = "Imported \(total) files in \(finalGroups.count) groups"
                completion(finalGroups)
            }
        }
    }
    
    private func unzipTakeoutOnDevice(zipURL: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Finding_Takeout_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        #if canImport(ZIPFoundation)
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            var totalEntries = 0
            for _ in archive { totalEntries += 1 }
            var current = 0
            for entry in archive {
                current += 1
                DispatchQueue.main.async {
                    self.currentUnzipProgress = Double(current) / Double(totalEntries)
                    self.progressText = "Unzipping \(current)/\(totalEntries): \(entry.path)"
                }
                let destinationURL = tempDir.appendingPathComponent(entry.path)
                if entry.type == .directory {
                    try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    let parent = destinationURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: destinationURL)
                }
            }
            return tempDir
        } catch {
            print("ZIPFoundation unzip failed: \(error)")
            return tempDir
        }
        #else
        return tempDir
        #endif
    }
    
    private func detectEmailFromTakeout(at url: URL) -> String? {
        let candidates = [
            url.appendingPathComponent("archive_browser.html"),
            url.appendingPathComponent("Takeout").appendingPathComponent("archive_browser.html")
        ]
        for browserURL in candidates {
            if let content = try? String(contentsOf: browserURL, encoding: .utf8) {
                let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) {
                    let email = (content as NSString).substring(with: match.range)
                    if email.contains("@") { return email }
                }
            }
        }
        return nil
    }
    
    private func detectEmailFromPath(_ path: String) -> String {
        if path.contains("@") {
            let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) {
                return (path as NSString).substring(with: match.range)
            }
        }
        return "GoogleAccount_Unknown"
    }
    
    private func sanitize(_ str: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return str.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func writeSummary(groups: [TakeoutGroup], to baseURL: URL, total: Int) {
        var summary = "Finding App - Google Takeout Groups Import (On-Device)\nDate: \(Date())\nTotal: \(total)\nGroups: \(groups.count)\n\n"
        for g in groups { summary += "\(g.accountEmail) / \(g.year) / \(g.albumName) : \(g.count) files\n" }
        let base = baseURL.appendingPathComponent("GoogleTakeout_Groups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let summaryURL = base.appendingPathComponent("TAKEOUT_GROUPS_SUMMARY.txt")
        try? summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        var hashLog = ""
        for g in groups {
            for file in g.files {
                if let data = try? Data(contentsOf: file) {
                    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    hashLog += "\(hash)  \(g.accountEmail)/\(g.year)/\(g.albumName)/\(file.lastPathComponent)\n"
                }
            }
        }
        let hashURL = base.appendingPathComponent("TAKEOUT_VERIFICATION_HASHES.txt")
        try? hashLog.write(to: hashURL, atomically: true, encoding: .utf8)
    }
}
