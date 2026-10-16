import Foundation

func defaultDoomDataDirectory(environment: [String: String],
                              applicationSupportDirectory: URL,
                              directoryExists: (String) -> Bool) -> URL? {
    guard environment["HANDWIRED_DOOM_DATA_DIR"] == nil else { return nil }
    let legacy = applicationSupportDirectory.appendingPathComponent("HandwiredDoom", isDirectory: true)
    if directoryExists(legacy.path) { return legacy }
    return applicationSupportDirectory.appendingPathComponent("NeuralDoom", isDirectory: true)
}
