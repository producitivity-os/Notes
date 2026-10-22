import Foundation
#if os(macOS)
import Security
#endif

struct RegisteredNotebook: Codable, Identifiable, Equatable, Sendable {
    var id: String { notebookID }
    var notebookID: String
    var displayName: String
    var bookmark: Data
    var lastKnownPath: String
    var updatedAt: Date
}

private struct RegisteredNotebookFile: Codable, Sendable {
    var formatVersion: Int
    var notebooks: [RegisteredNotebook]
}

struct NotebookLaunchRequest: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var notebookID: String
    var bookmark: Data
    var requestedAt: Date
}

struct NotebookNavigationRequest: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var notebookID: String
    var pageID: String?
    var objectID: String
}

struct CardScheduleFile: Codable, Equatable, Sendable {
    var formatVersion: Int = 1
    var notebookID: String
    var updatedAt: Date
    var cards: [String: JSONValue]
}

enum ReviewRating: String, Codable, CaseIterable, Sendable {
    case again
    case good
    case easy
}

struct ReviewCardSchedule: Codable, Equatable, Sendable {
    var cardID: String
    var dueAt: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    var lapses: Int
    var algorithmID: String
    var algorithmVersion: Int
    var algorithmState: JSONValue
    var contentRevision: Int
}

struct ReviewScheduleFile: Codable, Equatable, Sendable {
    var formatVersion: Int = 2
    var notebookID: String
    var updatedAt: Date
    var cards: [String: ReviewCardSchedule]
    var ignoredCardIDs: Set<String>

    init(
        formatVersion: Int = 2,
        notebookID: String,
        updatedAt: Date,
        cards: [String: ReviewCardSchedule],
        ignoredCardIDs: Set<String> = []
    ) {
        self.formatVersion = formatVersion
        self.notebookID = notebookID
        self.updatedAt = updatedAt
        self.cards = cards
        self.ignoredCardIDs = ignoredCardIDs
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, notebookID, updatedAt, cards, ignoredCardIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 2
        notebookID = try values.decode(String.self, forKey: .notebookID)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        cards = try values.decodeIfPresent([String: ReviewCardSchedule].self, forKey: .cards) ?? [:]
        ignoredCardIDs = try values.decodeIfPresent(Set<String>.self, forKey: .ignoredCardIDs) ?? []
    }
}

struct ReviewEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var notebookID: String
    var cardID: String
    var rating: ReviewRating
    var reviewedAt: Date
    var previousDueAt: Date
    var nextDueAt: Date
    var intervalSeconds: Double
    var correct: Bool
    var algorithmID: String
    var algorithmVersion: Int
}

struct PluginPersonRecord: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var role: String
    var organization: String
    var notes: String
    var createdAt: Double
    var updatedAt: Double
}

struct ReviewFileStore: Sendable {
    static let appGroupIdentifier = "A44TG8C84Y.com.productivitysuite.shared"
    let rootURL: URL

    init(fileManager: FileManager = .default) throws {
        guard Self.canUseAppGroup,
              let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The Productivity Suite App Group is unavailable. Check the app signing configuration."
            ])
        }
        let rootURL = group.appendingPathComponent("ReviewStore", isDirectory: true)
        try NotebookReviewLegacyMigrator.migrateIfNeeded(to: rootURL, fileManager: fileManager)
        try self.init(rootURL: rootURL, fileManager: fileManager)
    }

    private static var canUseAppGroup: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.security.application-groups" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return groups.contains(appGroupIdentifier)
        #else
        return true
        #endif
    }

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: schedulesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchRequestsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: navigationRequestsURL, withIntermediateDirectories: true)
    }

    var registryURL: URL { rootURL.appendingPathComponent("notebooks.json") }
    var schedulesURL: URL { rootURL.appendingPathComponent("schedules", isDirectory: true) }
    var sessionsURL: URL { rootURL.appendingPathComponent("sessions", isDirectory: true) }
    var historyURL: URL { rootURL.appendingPathComponent("history", isDirectory: true) }
    var launchRequestsURL: URL { rootURL.appendingPathComponent("launch-requests", isDirectory: true) }
    var navigationRequestsURL: URL { rootURL.appendingPathComponent("navigation-requests", isDirectory: true) }
    var peopleURL: URL { rootURL.appendingPathComponent("people.json") }
    var migratedPeopleURL: URL { rootURL.appendingPathComponent("notes-migration/persons.json") }

    func register(notebookURL: URL, manifest: NotebookManifest) throws {
        var registry = try registeredNotebooks()
        let bookmark = try notebookURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let value = RegisteredNotebook(
            notebookID: manifest.notebookID,
            displayName: notebookURL.deletingPathExtension().lastPathComponent,
            bookmark: bookmark,
            lastKnownPath: notebookURL.path,
            updatedAt: Date()
        )
        registry.removeAll { $0.notebookID == value.notebookID }
        registry.append(value)
        let sorted = registry.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        try writeJSON(RegisteredNotebookFile(formatVersion: 2, notebooks: sorted), to: registryURL)
    }

    func registeredNotebooks() throws -> [RegisteredNotebook] {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return [] }
        let data = try Data(contentsOf: registryURL)
        if let file = try? NotebookCoding.decoder.decode(RegisteredNotebookFile.self, from: data) {
            return file.notebooks
        }
        return try NotebookCoding.decoder.decode([RegisteredNotebook].self, from: data)
    }

    func resolve(_ notebook: RegisteredNotebook) -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: notebook.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let fallback = URL(fileURLWithPath: notebook.lastKnownPath)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    func writeSchedule(_ schedule: CardScheduleFile) throws {
        try writeJSON(schedule, to: schedulesURL.appendingPathComponent("\(schedule.notebookID).json"))
    }

    func writeReviewSchedule(_ schedule: ReviewScheduleFile) throws {
        try writeJSON(schedule, to: schedulesURL.appendingPathComponent("\(schedule.notebookID).json"))
    }

    func reviewSchedule(notebookID: String) throws -> ReviewScheduleFile? {
        let url = schedulesURL.appendingPathComponent("\(notebookID).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try NotebookCoding.decoder.decode(ReviewScheduleFile.self, from: Data(contentsOf: url))
    }

    func setCard(_ cardID: String, in notebookID: String, ignoredInReview: Bool, now: Date = Date()) throws {
        var file = try reviewSchedule(notebookID: notebookID)
            ?? ReviewScheduleFile(notebookID: notebookID, updatedAt: now, cards: [:])
        if ignoredInReview {
            file.ignoredCardIDs.insert(cardID)
        } else {
            file.ignoredCardIDs.remove(cardID)
        }
        file.updatedAt = now
        try writeReviewSchedule(file)
    }

    func schedule(notebookID: String) throws -> CardScheduleFile? {
        let url = schedulesURL.appendingPathComponent("\(notebookID).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try NotebookCoding.decoder.decode(CardScheduleFile.self, from: Data(contentsOf: url))
    }

    func pluginPeople(query: String = "") throws -> [PluginPersonRecord] {
        var records = try normalizedPeople()
        if FileManager.default.fileExists(atPath: migratedPeopleURL.path),
           let values = try? NotebookCoding.decoder.decode([JSONValue].self, from: Data(contentsOf: migratedPeopleURL)) {
            let known = Set(records.map(\.id))
            records.append(contentsOf: values.compactMap(Self.person(from:)).filter { !known.contains($0.id) })
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            records = records.filter {
                "\($0.name) \($0.role) \($0.organization)".lowercased().contains(needle)
            }
        }
        return records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func savePluginPerson(id: String, name: String, role: String, organization: String, notes: String) throws -> PluginPersonRecord {
        var records = try pluginPeople()
        let now = Date().timeIntervalSince1970 * 1_000
        let createdAt = records.first(where: { $0.id == id })?.createdAt ?? now
        let record = PluginPersonRecord(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role,
            organization: organization,
            notes: notes,
            createdAt: createdAt,
            updatedAt: now
        )
        records.removeAll { $0.id == id }
        records.append(record)
        try writeJSON(records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, to: peopleURL)
        return record
    }

    func appendHistory(notebookID: String, event: JSONValue) throws {
        let url = historyURL.appendingPathComponent("\(notebookID).ndjson")
        var data = try NotebookCoding.encoder.encode(event)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func appendReviewEvent(_ event: ReviewEvent) throws {
        let url = historyURL.appendingPathComponent("\(event.notebookID).ndjson")
        var data = try NotebookCoding.encoder.encode(event)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func reviewEvents(notebookID: String) throws -> [ReviewEvent] {
        let url = historyURL.appendingPathComponent("\(notebookID).ndjson")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url)
            .split(separator: 0x0A)
            .map { try NotebookCoding.decoder.decode(ReviewEvent.self, from: Data($0)) }
    }

    func replaceHistory(notebookID: String, events: [JSONValue]) throws {
        let url = historyURL.appendingPathComponent("\(notebookID).ndjson")
        var data = Data()
        for event in events {
            data.append(try NotebookCoding.encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    func createLaunchRequest(notebookURL: URL, manifest: NotebookManifest) throws -> NotebookLaunchRequest {
        try register(notebookURL: notebookURL, manifest: manifest)
        let request = NotebookLaunchRequest(
            id: UUID().uuidString.lowercased(),
            notebookID: manifest.notebookID,
            bookmark: try notebookURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
            requestedAt: Date()
        )
        try writeJSON(request, to: launchRequestsURL.appendingPathComponent("\(request.id).json"))
        return request
    }

    func takeNavigationRequest(id: String) throws -> NotebookNavigationRequest {
        let url = navigationRequestsURL.appendingPathComponent("\(id).json")
        let request = try NotebookCoding.decoder.decode(NotebookNavigationRequest.self, from: Data(contentsOf: url))
        try FileManager.default.removeItem(at: url)
        return request
    }

    @discardableResult
    func createNavigationRequest(notebookID: String, pageID: String?, objectID: String) throws -> NotebookNavigationRequest {
        let request = NotebookNavigationRequest(
            id: UUID().uuidString.lowercased(),
            notebookID: notebookID,
            pageID: pageID,
            objectID: objectID
        )
        try writeJSON(request, to: navigationRequestsURL.appendingPathComponent("\(request.id).json"))
        return request
    }

    func takeLaunchRequest(id: String) throws -> NotebookLaunchRequest {
        let url = launchRequestsURL.appendingPathComponent("\(id).json")
        let request = try NotebookCoding.decoder.decode(NotebookLaunchRequest.self, from: Data(contentsOf: url))
        try FileManager.default.removeItem(at: url)
        return request
    }

    private func writeJSON<T: Encodable>(_ value: T, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try NotebookCoding.encoder.encode(value).write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private func normalizedPeople() throws -> [PluginPersonRecord] {
        guard FileManager.default.fileExists(atPath: peopleURL.path) else { return [] }
        return try NotebookCoding.decoder.decode([PluginPersonRecord].self, from: Data(contentsOf: peopleURL))
    }

    private static func person(from value: JSONValue) -> PluginPersonRecord? {
        guard let fields = value.objectValue,
              let id = fields["id"]?.stringValue,
              let name = fields["name"]?.stringValue else { return nil }
        let created = timestamp(fields["createdAt"] ?? fields["created_at"])
        let updated = timestamp(fields["updatedAt"] ?? fields["updated_at"])
        return .init(
            id: id,
            name: name,
            role: fields["role"]?.stringValue ?? "",
            organization: fields["organization"]?.stringValue ?? "",
            notes: fields["notes"]?.stringValue ?? "",
            createdAt: created,
            updatedAt: updated == 0 ? created : updated
        )
    }

    private static func timestamp(_ value: JSONValue?) -> Double {
        if let number = value?.numberValue {
            return number < 10_000_000_000 ? number * 1_000 : number
        }
        if let string = value?.stringValue, let date = ISO8601DateFormatter().date(from: string) {
            return date.timeIntervalSince1970 * 1_000
        }
        return 0
    }
}

private enum NotebookReviewLegacyMigrator {
    static func migrateIfNeeded(to destination: URL, fileManager: FileManager) throws {
        let marker = destination.appendingPathComponent(".legacy-migration-v1")
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let legacy = support.appendingPathComponent("Productivity OS/ReviewStore", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: legacy.path) {
            let backup = destination.appendingPathComponent("LegacyBackup", isDirectory: true)
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: legacy, to: backup)
            }
            try mergeDirectory(from: legacy, to: destination, fileManager: fileManager)
        }
        try Data("completed".utf8).write(to: marker, options: .atomic)
    }

    private static func mergeDirectory(from source: URL, to destination: URL, fileManager: FileManager) throws {
        for item in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                try mergeDirectory(from: item, to: target, fileManager: fileManager)
            } else if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }
}
