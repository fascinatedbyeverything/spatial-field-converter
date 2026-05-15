import Foundation

public enum PreferencesStore {
    private static let stagingDirKey = "stagingDirectoryPath"

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
}
