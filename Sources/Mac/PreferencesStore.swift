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

    /// Look for the Cloud Uploader executable in the standard places.
    /// 1. /Applications/Cloud Uploader v{N}.app — pick highest N
    /// 2. /Applications/Cloud Uploader.app (unversioned)
    /// 3. Most-recent DerivedData Debug build
    /// 4. Unversioned /Applications path as fallback (caller surfaces a clear error if missing)
    private static func defaultUploaderPath() -> URL {
        // 1. Glob /Applications for "Cloud Uploader v{N}.app" — pick highest version.
        if let versioned = highestVersionedAppInApplications() {
            return versioned.appendingPathComponent("Contents/MacOS/CloudUploader")
        }

        // 2. Unversioned /Applications path
        let appsPath = URL(fileURLWithPath: "/Applications/Cloud Uploader.app/Contents/MacOS/CloudUploader")
        if FileManager.default.fileExists(atPath: appsPath.path) {
            return appsPath
        }

        // 3. DerivedData walk
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == "Cloud Uploader.app" && url.path.contains("Debug") {
                    return url.appendingPathComponent("Contents/MacOS/CloudUploader")
                }
            }
        }

        return appsPath   // fallback — will fail later with a clear error
    }

    /// Returns the .app bundle URL with the highest version suffix among "Cloud Uploader v{N}.app".
    private static func highestVersionedAppInApplications() -> URL? {
        let applications = URL(fileURLWithPath: "/Applications")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: applications, includingPropertiesForKeys: nil) else {
            return nil
        }
        var bestVersion: Int = -1
        var bestURL: URL? = nil
        let regex = try? NSRegularExpression(pattern: #"^Cloud Uploader v(\d+)\.app$"#)
        for url in contents {
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if let match = regex?.firstMatch(in: name, range: range),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: name),
               let v = Int(name[r]) {
                if v > bestVersion {
                    bestVersion = v
                    bestURL = url
                }
            }
        }
        return bestURL
    }
}
