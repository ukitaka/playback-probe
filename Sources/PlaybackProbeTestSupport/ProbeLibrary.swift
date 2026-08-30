import Darwin
import Foundation

/// Locates the probe library on disk so a test can inject it.
public enum ProbeLibrary {
    /// Environment variable dyld reads to load extra libraries into a process.
    ///
    /// Honoured on the simulator only. A device rejects a library whose Team ID
    /// does not match the host application, and dyld ignores the variable
    /// without reporting anything.
    public static let insertLibrariesKey = "DYLD_INSERT_LIBRARIES"

    /// Path of the loaded probe library.
    ///
    /// Resolved by asking dyld which image defines the probe's entry point,
    /// rather than by guessing at build product layout: Xcode's Swift Package
    /// Manager integration has shipped the dynamic product both as a bare
    /// `.dylib` and as a framework under `PackageFrameworks/`, in a directory
    /// that is not adjacent to the test bundle.
    ///
    /// Requires that the test target links the dynamic `PlaybackProbe` product,
    /// so that the library is present in the test runner's own process.
    public static func url() throws -> URL {
        // RTLD_DEFAULT searches every image already loaded into this process.
        let searchAllImages = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(searchAllImages, "playback_probe_start") else {
            throw ProbeLibraryError.notLoaded
        }

        var info = Dl_info()
        guard dladdr(symbol, &info) != 0, let imagePath = info.dli_fname else {
            throw ProbeLibraryError.imageNotResolvable
        }

        let url = URL(fileURLWithPath: String(cString: imagePath))
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProbeLibraryError.imageMissing(path: url.path)
        }
        return url
    }
}

public enum ProbeLibraryError: Error, CustomStringConvertible {
    case notLoaded
    case imageNotResolvable
    case imageMissing(path: String)

    public var description: String {
        switch self {
        case .notLoaded:
            """
            The PlaybackProbe library is not loaded in this process. Link the \
            dynamic PlaybackProbe product into the UI test target.
            """
        case .imageNotResolvable:
            "dyld could not report which image defines playback_probe_start."
        case let .imageMissing(path):
            "dyld reports the probe at \(path), but no file exists there."
        }
    }
}
