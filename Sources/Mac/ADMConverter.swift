import Foundation

public enum ADMConverterError: Error, CustomStringConvertible {
    case pythonNotFound
    case scriptNotBundled
    case scriptFailed(Int32, String)

    public var description: String {
        switch self {
        case .pythonNotFound: return "python3 not found"
        case .scriptNotBundled: return "adm_convert.py not in app bundle"
        case .scriptFailed(let code, let stderr): return "adm_convert.py failed (\(code)): \(stderr)"
        }
    }
}

/// Wraps the bundled adm_convert.py script. Given an ADM BWF input, produces a
/// staging folder containing bed.m4a + obj-NN.m4a + manifest.json.
///
/// argv pattern verified from cloud-uploader/Sources/MediaProcessor.swift::processADMBWF:
///   python3 adm_convert.py <input.wav> <output_dir> <name>
/// Output lands directly in output_dir (not a subdirectory).
///
/// Not thread-safe.
public final class ADMConverter {

    /// Runs adm_convert.py on the input ADM BWF, writing outputs to outputDirectory.
    /// Returns outputDirectory — the script writes directly there, not into a subdirectory.
    public static func convert(admBwfURL: URL, slug: String, outputDirectory: URL) async throws -> URL {
        guard let scriptURL = Bundle.main.url(forResource: "adm_convert", withExtension: "py") else {
            throw ADMConverterError.scriptNotBundled
        }

        let pythonPath = findPython() ?? "/usr/bin/python3"
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw ADMConverterError.pythonNotFound
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Invocation matches cloud-uploader/Sources/MediaProcessor.swift processADMBWF exactly:
        //   python3 adm_convert.py <input_path> <output_dir> <streamName>
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path, admBwfURL.path, outputDirectory.path, slug]

        // Inherit the full environment so ffmpeg/ffprobe are on PATH.
        var env = ProcessInfo.processInfo.environment
        // Ensure Homebrew bins are on PATH even in sandboxed-lite launch contexts.
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(existingPath)"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                cont.resume()
            }
        }

        let stdout = (try? outPipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let stderr = (try? errPipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        if process.terminationStatus != 0 {
            throw ADMConverterError.scriptFailed(process.terminationStatus, stderr)
        }

        print("[ADMConverter] \(stdout)")
        // adm_convert.py writes directly into output_dir.
        return outputDirectory
    }

    private static func findPython() -> String? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
