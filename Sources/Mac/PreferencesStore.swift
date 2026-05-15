import Foundation

public enum PreferencesStore {
    private static let stagingDirKey = "stagingDirectoryPath"

    public static var stagingDirectory: URL {
        get {
            if let s = UserDefaults.standard.string(forKey: stagingDirKey), !s.isEmpty {
                return URL(fileURLWithPath: s)
            }
            // Default to the user's existing "field recordings" folder on the 4TB T5 drive —
            // never write big media to the internal SSD (locked rule). Bounces live alongside
            // source recordings on the same drive.
            let candidates: [String] = [
                "/Volumes/new t5 4tb/field recordings",
                "/Volumes/1tb /claude code projects /spatial-field-converter-staging"
            ]
            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
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
