import Foundation

public enum PreferencesStore {
    private static let uploaderPathKey = "cloudUploaderExecutablePath"
    private static let stagingDirKey = "stagingDirectoryPath"

    public static var cloudUploaderExecutableURL: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: uploaderPathKey), !s.isEmpty {
                return URL(fileURLWithPath: s)
            }
            return defaultUploaderPath()
        }
        set { UserDefaults.standard.set(newValue.path, forKey: uploaderPathKey) }
    }

    public static var stagingDirectory: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: stagingDirKey), !s.isEmpty {
                return URL(fileURLWithPath: s)
            }
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return cache
                .appendingPathComponent("SpatialFieldConverter")
                .appendingPathComponent("staging")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: stagingDirKey) }
    }

    /// Look for CloudUploader.app in the standard places.
    /// 1. /Applications/Cloud Uploader.app
    /// 2. Most-recent DerivedData Debug build
    /// 3. Fallback that doesn't exist (caller will surface an error)
    private static func defaultUploaderPath() -> URL {
        let appsPath = URL(fileURLWithPath: "/Applications/Cloud Uploader.app/Contents/MacOS/CloudUploader")
        if FileManager.default.fileExists(atPath: appsPath.path) {
            return appsPath
        }
        // DerivedData walk
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == "CloudUploader.app" && url.path.contains("Debug") {
                    return url.appendingPathComponent("Contents/MacOS/CloudUploader")
                }
            }
        }
        return appsPath   // fallback — will fail later with a clear error
    }
}
