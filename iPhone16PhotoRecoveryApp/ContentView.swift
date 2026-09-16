import SwiftUI
import Photos
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var photoManager = PhotoLibraryManager()
    @StateObject private var usbManager = USBExportManager()
    @StateObject private var googleManager = GooglePhotosManager()
    @StateObject private var takeoutManager = TakeoutImportManager()
    
    @State private var currentStep = 1
    @State private var showDocumentPicker = false
    @State private var showTakeoutPicker = false
    @State private var exportURL: URL?
    @State private var statusMessage = "Ready - Finding will audit hidden + Google Takeouts"
    @State private var isProcessing = false
    @State private var selectedTakeoutURLs: [URL] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack {
                    Text("Finding").font(.largeTitle).bold()
                    Text("iPhone 16+ • USB • Google Takeout Groups")
                        .font(.caption).foregroundColor(.secondary)
                    ProgressView(value: Double(currentStep), total: 5.0)
                        .padding(.top, 8)
                    Text("Step \(currentStep) of 5").font(.caption)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StepCard(number: 1, title: "AUDIT LIBRARY", description: "Local + hidden + deleted", isActive: currentStep == 1, isCompleted: currentStep > 1) {
                            VStack(alignment: .leading) {
                                if isProcessing && currentStep == 1 { ProgressView() }
                                else {
                                    Text("Total: \(photoManager.auditResult.totalLocal)")
                                    Text("Hidden: \(photoManager.auditResult.totalHidden)").foregroundColor(.orange)
                                    Text("Recently Deleted: \(photoManager.auditResult.totalRecentlyDeleted)").foregroundColor(.red)
                                    Text("Photos: \(photoManager.auditResult.totalPhotos) Videos: \(photoManager.auditResult.totalVideos)")
                                }
                                Button("Audit Library") { runAudit() }
                                    .buttonStyle(.borderedProminent).disabled(isProcessing)
                            }
                        }
                        
                        StepCard(number: 2, title: "UNHIDE EVERYTHING", description: "iPhone Hidden + Google Archive", isActive: currentStep == 2, isCompleted: currentStep > 2) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("iPhone Hidden: \(photoManager.auditResult.totalHidden)")
                                Button("Unhide All iPhone Hidden") { runUnhide() }
                                    .buttonStyle(.borderedProminent).tint(.orange)
                                    .disabled(isProcessing || photoManager.auditResult.totalHidden == 0)
                                Divider()
                                Text(googleManager.getManualInstructions()).font(.caption2).padding(8).background(Color.yellow.opacity(0.2)).cornerRadius(8)
                            }
                        }
                        
                        StepCard(number: 3, title: "ORGANIZE", description: "Sort by date/type", isActive: currentStep == 3, isCompleted: currentStep > 3) {
                            VStack(alignment: .leading) {
                                Text("Organized: \(photoManager.allItems.count)")
                                Button("Organize Library") { runOrganize() }
                                    .buttonStyle(.borderedProminent).tint(.green).disabled(isProcessing)
                            }
                        }
                        
                        StepCard(number: 4, title: "GOOGLE TAKEOUTS - AUTO GROUP", description: "Import multiple Takeout zips, auto-group by account/year/album", isActive: currentStep == 4, isCompleted: currentStep > 4) {
                            VStack(alignment: .leading, spacing: 8) {
                                if takeoutManager.isImporting {
                                    ProgressView()
                                    Text(takeoutManager.progressText).font(.caption2)
                                } else {
                                    Text("Groups: \(takeoutManager.importedGroups.count) Total: \(takeoutManager.totalImported)")
                                    ForEach(takeoutManager.importedGroups.prefix(3)) { g in
                                        Text("\(g.accountEmail) / \(g.year) / \(g.albumName): \(g.count)").font(.caption2).lineLimit(1)
                                    }
                                }
                                Button("Select Takeout Zips/Folders") { showTakeoutPicker = true }
                                    .buttonStyle(.borderedProminent).tint(.purple).disabled(takeoutManager.isImporting)
                                Text("Select 1 or multiple Takeout .zip files from Files app (iCloud Drive or USB). App auto-detects email from archive_browser.html and groups.").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        
                        StepCard(number: 5, title: "EXPORT TO USB", description: "All to USB-C drive with verification", isActive: currentStep == 5, isCompleted: false) {
                            VStack(alignment: .leading, spacing: 8) {
                                if usbManager.isExporting {
                                    ProgressView(value: Double(usbManager.progress.completed), total: Double(usbManager.progress.total))
                                    Text("\(usbManager.progress.completed)/\(usbManager.progress.total): \(usbManager.progress.currentFile)").font(.caption2)
                                }
                                Button("Choose USB Drive & Export Everything") { showDocumentPicker = true }
                                    .buttonStyle(.borderedProminent).tint(.blue)
                                    .disabled(isProcessing || (photoManager.allItems.isEmpty && takeoutManager.importedGroups.isEmpty))
                                if let url = exportURL {
                                    Text("Exported to: \(url.lastPathComponent)").font(.caption).foregroundColor(.green)
                                }
                            }
                        }
                        
                        Text(statusMessage).font(.footnote).foregroundColor(.secondary).padding().frame(maxWidth: .infinity).background(Color(.secondarySystemBackground)).cornerRadius(8)
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(contentTypes: [.folder]) { url in
                    guard let url = url else { return }
                    exportURL = url
                    runExport(to: url)
                }
            }
            .sheet(isPresented: $showTakeoutPicker) {
                DocumentPickerMulti(contentTypes: [.zip, .folder]) { urls in
                    guard !urls.isEmpty else { return }
                    selectedTakeoutURLs = urls
                    // Need destination - ask for USB again or use same exportURL
                    if let dest = exportURL {
                        runTakeoutImport(sources: urls, dest: dest)
                    } else {
                        statusMessage = "Pick USB drive first, then Takeouts. Or Takeouts will import to temporary and then you export."
                        // If no USB yet, import to temp then user picks USB later
                        let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent("Finding_Takeout_Groups")
                        try? FileManager.default.createDirectory(at: tempDest, withIntermediateDirectories: true)
                        runTakeoutImport(sources: urls, dest: tempDest)
                    }
                }
            }
        }
    }
    
    func runAudit() {
        isProcessing = true
        statusMessage = "Auditing including hidden..."
        photoManager.auditLibrary { result in
            isProcessing = false
            statusMessage = "Audit: \(result.totalLocal) total, \(result.totalHidden) hidden"
            if result.totalHidden > 0 { currentStep = 2 } else if result.totalLocal > 0 { currentStep = 3 }
            googleManager.auditGoogleAccounts()
        }
    }
    
    func runUnhide() {
        isProcessing = true
        statusMessage = "Unhiding..."
        photoManager.unhideAll { count, error in
            isProcessing = false
            if let error = error { statusMessage = "Error: \(error.localizedDescription)" }
            else { statusMessage = "Unhid \(count)"; runAudit(); currentStep = 3 }
        }
    }
    
    func runOrganize() {
        isProcessing = true
        statusMessage = "Organizing..."
        photoManager.organizeLibrary { items in
            isProcessing = false
            statusMessage = "Organized \(items.count) ready"
            currentStep = 4
        }
    }
    
    func runTakeoutImport(sources: [URL], dest: URL) {
        statusMessage = "Importing \(sources.count) Takeout(s)..."
        takeoutManager.importTakeouts(from: sources, to: dest) { groups in
            statusMessage = "Takeout import done: \(groups.count) groups, \(self.takeoutManager.totalImported) files. Now export to USB."
            currentStep = 5
        }
    }
    
    func runExport(to url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        statusMessage = "Exporting to \(url.lastPathComponent)..."
        usbManager.exportToUSB(items: photoManager.allItems, to: url, photoManager: photoManager) { success in
            statusMessage = success ? "Export complete! Check EXPORT_SUMMARY.txt + TAKEOUT_GROUPS_SUMMARY.txt on USB" : "Export with errors"
        }
    }
}

struct StepCard<Content: View>: View {
    let number: Int; let title: String; let description: String; let isActive: Bool; let isCompleted: Bool; let content: Content
    init(number: Int, title: String, description: String, isActive: Bool, isCompleted: Bool, @ViewBuilder content: () -> Content) {
        self.number = number; self.title = title; self.description = description; self.isActive = isActive; self.isCompleted = isCompleted; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack { Circle().fill(isCompleted ? Color.green : (isActive ? Color.blue : Color.gray.opacity(0.3))).frame(width: 30, height: 30)
                    Text(isCompleted ? "✓" : "\(number)").foregroundColor(.white).bold()
                }
                VStack(alignment: .leading) { Text(title).bold(); Text(description).font(.caption).foregroundColor(.secondary) }
                Spacer()
            }
            if isActive || isCompleted { content.padding(.leading, 40) }
        }
        .padding().background(isActive ? Color.blue.opacity(0.05) : Color(.systemBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: isActive ? 2 : 1))
        .cornerRadius(12)
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.folder]
    var completion: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = false; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

struct DocumentPickerMulti: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.zip, .folder]
    var completion: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = true; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}
