import Foundation

enum IWADValidator {
    static func error(for url: URL) -> String? {
        guard url.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.int64Value >= 12,
              let file = try? FileHandle(forReadingFrom: url) else {
            return "IWAD is missing or unreadable: \(url.path)"
        }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 12), header.count == 12,
              String(data: header.prefix(4), encoding: .ascii) == "IWAD" else {
            return "The selected file is not a Doom IWAD."
        }
        func word(_ offset: Int) -> Int64 {
            let b = Array(header)
            return Int64(UInt32(b[offset]) | UInt32(b[offset+1]) << 8 |
                         UInt32(b[offset+2]) << 16 | UInt32(b[offset+3]) << 24)
        }
        let count = word(4), directory = word(8)
        guard count > 0, count < 100_000, directory >= 12,
              directory + count * 16 <= size.int64Value else {
            return "The IWAD directory is damaged or incomplete."
        }
        return nil
    }
}

extension IWADValidator {
    // The map the engine warps to at launch: E1M1 for Doom 1 IWADs, MAP01 otherwise.
    static func mapTables(for url: URL) -> Result<MapTablesV1, MapTablesFailure> {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .failure(.malformed("IWAD became unreadable"))
        }
        do {
            let map = try MapTablesV1.containsLump("E1M1", in: data) ? "E1M1" : "MAP01"
            return .success(try MapTablesV1.decode(wad: data, map: map))
        } catch let failure as MapTablesFailure { return .failure(failure) }
        catch { return .failure(.malformed(error.localizedDescription)) }
    }

    // User WAD paths are never logged: only the basename and a short content fingerprint.
    static func redactedDescription(of url: URL, tables: MapTablesV1) -> String {
        "\(url.lastPathComponent) [sha256 \(tables.wadSHA256.prefix(12))]"
    }
}
