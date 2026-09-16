import Photos
import UIKit

class PhotoLibraryManager: ObservableObject {
    @Published var auditResult = AuditResult()
    @Published var allItems: [MediaItem] = []
    
    // STEP 1: AUDIT - including hidden
    func auditLibrary(completion: @escaping (AuditResult) -> Void) {
        checkAuthorization { authorized in
            guard authorized else { return }
            
            var result = AuditResult()
            
            // Fetch ALL including hidden
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeHiddenAssets = true
            fetchOptions.includeAllBurstAssets = true
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            
            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            result.totalLocal = allAssets.count
            
            // Count by type
            allAssets.enumerateObjects { asset, _, _ in
                if asset.isHidden { result.totalHidden += 1 }
                if asset.mediaType == .video { result.totalVideos += 1 }
                if asset.mediaType == .image { result.totalPhotos += 1 }
            }
            
            // Fetch Hidden album specifically
            let hiddenAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
            if let hiddenCollection = hiddenAlbums.firstObject {
                let hiddenAssets = PHAsset.fetchAssets(in: hiddenCollection, options: nil)
                result.totalHidden = hiddenAssets.count
            }
            
            // Fetch Recently Deleted
            let deletedAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumRecentlyDeleted, options: nil)
            if let deletedCollection = deletedAlbums.firstObject {
                let deletedAssets = PHAsset.fetchAssets(in: deletedCollection, options: nil)
                result.totalRecentlyDeleted = deletedAssets.count
            }
            
            DispatchQueue.main.async {
                self.auditResult = result
                completion(result)
            }
        }
    }
    
    // STEP 2: UNHIDE EVERYTHING
    func unhideAll(completion: @escaping (Int, Error?) -> Void) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true
        fetchOptions.predicate = NSPredicate(format: "hidden == YES")
        
        let hiddenAssets = PHAsset.fetchAssets(with: fetchOptions)
        guard hiddenAssets.count > 0 else {
            completion(0, nil)
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            hiddenAssets.enumerateObjects { asset, _, _ in
                let request = PHAssetChangeRequest(for: asset)
                request.isHidden = false
            }
        }) { success, error in
            DispatchQueue.main.async {
                completion(hiddenAssets.count, error)
            }
        }
    }
    
    // STEP 3: ORGANIZE - Build MediaItem list sorted by date
    func organizeLibrary(completion: @escaping ([MediaItem]) -> Void) {
        var items: [MediaItem] = []
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false // now unhidden, so false is all visible
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        assets.enumerateObjects { asset, _, _ in
            let type: MediaItem.MediaType
            if asset.mediaType == .video {
                type = .video
            } else if asset.mediaSubtypes.contains(.photoLive) {
                type = .livePhoto
            } else {
                type = .photo
            }
            
            let resources = PHAssetResource.assetResources(for: asset)
            let fileName = resources.first?.originalFilename ?? "IMG_\(asset.creationDate?.timeIntervalSince1970 ?? 0)"
            
            let item = MediaItem(
                asset: asset,
                fileName: fileName,
                type: type,
                creationDate: asset.creationDate,
                isHidden: asset.isHidden,
                fileSize: nil
            )
            items.append(item)
        }
        
        DispatchQueue.main.async {
            self.allItems = items
            completion(items)
        }
    }
    
    // Helper: Request original file URL for export
    func requestOriginalFile(for asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else {
            completion(nil)
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(resource.originalFilename)
        
        // Remove existing
        try? FileManager.default.removeItem(at: tempURL)
        
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true // for iCloud photos
        
        PHAssetResourceManager.default().writeData(for: resource, toFile: tempURL, options: options) { error in
            if error != nil {
                completion(nil)
            } else {
                completion(tempURL)
            }
        }
    }
    
    private func checkAuthorization(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            completion(true)
        } else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        }
    }
}
