import Darwin
import Foundation

@main
struct NotebookExporter {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--help" || arguments.first == "-h" {
            print("Usage: notebook-exporter <database.sqlite3> <destination-folder>")
            return
        }

        guard arguments.count == 2 else {
            writeError("Usage: notebook-exporter <database.sqlite3> <destination-folder>")
            exit(64)
        }

        let databaseURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let destinationURL = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            writeError("Database not found: \(databaseURL.path)")
            exit(66)
        }

        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            let result = try await LegacyNotebookMigrator(
                databaseURL: databaseURL,
                destinationURL: destinationURL
            ).run()
            print("Exported \(result.imported) notebook(s) to \(destinationURL.path).")
            if result.skipped > 0 {
                print("Skipped \(result.skipped) notebook(s) that were already exported.")
            }
        } catch {
            writeError("Export failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
