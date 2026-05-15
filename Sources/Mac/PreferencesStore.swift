import Foundation

public enum PreferencesStore {
    private static let stagingDirKey = "stagingDirectoryPath"

    public static var stagingDirectory: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: stagingDirKey), !s.isEmpty {
                return URL(fileURLWithPath: s)
            }
            // Default to the largest available external drive — never write big media to the
            // internal SSD (locked rule). Order tried: 4TB T5, 1tb projects drive, then
            // internal Caches as a last-resort fallback (with a warning logged).
            let candidates: [String] = [
                "/Volumes/new t5 4tb/spatial-field-converter-staging",
                "/Volumes/1tb /claude code projects /spatial-field-converter-staging"
            ]
            for path in candidates {
                let parent = (path as NSString).deletingLastPathComponent
                if FileManager.default.fileExists(atPath: parent) {
                    return URL(fileURLWithPath: path)
                }
            }
            // Fallback — should never hit if either external is mounted.
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return cache
                .appendingPathComponent("SpatialFieldConverter")
                .appendingPathComponent("staging")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: stagingDirKey) }
    }
}
