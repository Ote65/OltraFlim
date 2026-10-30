import Foundation
import CoreGraphics

/// A folder in the library index. Contents are rescanned when the folder is
/// opened, so adding or removing files on disk is reflected without copying.
struct LibraryFolder: Identifiable {
    let url: URL
    var count: Int
    var subfolderCount: Int = 0
    var coverURL: URL?
    var cover: CGImage?

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }

    var countText: String {
        if count > 0 && subfolderCount > 0 {
            return T("\(count) 张照片 · \(subfolderCount) 个文件夹",
                     "\(count) photos · \(subfolderCount) folders")
        }
        if count > 0 {
            return T("\(count) 张照片", "\(count) photographs")
        }
        if subfolderCount > 0 {
            return T("\(subfolderCount) 个子文件夹", "\(subfolderCount) folders")
        }
        return T("空文件夹", "Empty folder")
    }
}
