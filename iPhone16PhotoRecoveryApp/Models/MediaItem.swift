import Foundation
import Photos

struct MediaItem: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let fileName: String
    let type: MediaType
    let creationDate: Date?
    let isHidden: Bool
    let fileSize: Int64?
    
    enum MediaType {
        case photo, video, livePhoto, heic
    }
}

struct AuditResult {
    var totalLocal: Int = 0
    var totalHidden: Int = 0
    var totalRecentlyDeleted: Int = 0
    var totalVideos: Int = 0
    var totalPhotos: Int = 0
    var totalHEIC: Int = 0
    var googleAccounts: [String] = []
}

struct ExportProgress {
    var total: Int = 0
    var completed: Int = 0
    var currentFile: String = ""
    var errors: [String] = []
}
