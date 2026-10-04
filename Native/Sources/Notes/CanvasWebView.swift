import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class CanvasWebController: NSObject, ObservableObject {
    private weak var document: NotebookDocument?
    private var pendingPageID: String?
    private var ready = false
    private var loadedPageID: String?
    private var pendingFocusObjectID: String?
    private var reportedWebFailure = false
    private let assetHandler = NotebookAssetSchemeHandler()
    private let webAppHandler = CanvasWebAppSchemeHandler()

    lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: "notebook-asset")
        configuration.setURLSchemeHandler(webAppHandler, forURLScheme: "notes-canvas")
        configuration.userContentController.add(self, name: "notesBridge")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              const report = (message) => window.webkit?.messageHandlers?.notesBridge?.postMessage({
                version: 1,
                type: "error",
                body: { message: String(message) },
              });
              window.addEventListener("error", (event) => {
                const detail = event.error?.stack ? `${event.message || "Canvas script failed."}\n${event.error.stack}` : event.message;
                report(detail || "Canvas script failed to load.");
              });
              window.addEventListener("unhandledrejection", (event) => report(event.reason?.stack || event.reason || "Canvas startup failed."));
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = self
        return view
    }()

    func connect(document: NotebookDocument) {
        guard self.document !== document else { return }
        self.document = document
        assetHandler.update(package: document.package)
        webAppHandler.update(package: document.package)
        loadedPageID = nil
        if ready { load(pageID: document.selectedPageID) }
    }

    func loadWebApp() {
        guard webView.url == nil else { return }
        if Bundle.main.url(forResource: "native-canvas", withExtension: "html", subdirectory: "CanvasWeb") != nil,
           let url = URL(string: "notes-canvas://app/native-canvas.html") {
            webView.load(URLRequest(url: url))
        } else {
            let fallback = "<html><body style='font: 16px -apple-system; padding: 32px'>Canvas resources are missing. Build the native canvas bundle and reopen Notes.</body></html>"
            webView.loadHTMLString(fallback, baseURL: nil)
        }
    }

    func selectPage(_ pageID: String) {
        guard let document, document.page(id: pageID) != nil, pageID != document.selectedPageID else { return }
        pendingPageID = pageID
        send(type: "flushPage", body: ["pageID": .string(document.selectedPageID)])
    }

    func refreshCurrentPage() {
        guard let document else { return }
        load(pageID: document.selectedPageID)
    }

    func flush() {
        guard let document else { return }
        send(type: "flushPage", body: ["pageID": .string(document.selectedPageID)])
    }

    func navigate(pageID: String?, objectID: String) {
        guard let document else { return }
        pendingFocusObjectID = objectID
        if let pageID, document.page(id: pageID) != nil, pageID != document.selectedPageID {
            selectPage(pageID)
        } else {
            focusPendingObject()
        }
    }

    private func load(pageID: String) {
        guard ready, let document,
              let metadata = document.page(id: pageID),
              let payload = document.package.pagePayloads[pageID] else { return }
        document.selectedPageID = pageID
        loadedPageID = pageID
        send(type: "loadPage", body: [
            "pageID": .string(pageID),
            "revision": .number(Double(payload.revision)),
            "width": .number(metadata.width),
            "height": .number(metadata.height),
            "canvas": Self.runtimeCanvas(payload.canvas),
        ])
        focusPendingObject()
    }

    private func focusPendingObject() {
        guard ready, loadedPageID != nil, let objectID = pendingFocusObjectID else { return }
        pendingFocusObjectID = nil
        send(type: "focusObject", body: ["objectID": .string(objectID)])
    }

    private func finishPendingPageSwitch() {
        guard let target = pendingPageID else { return }
        pendingPageID = nil
        load(pageID: target)
    }

    private func handle(message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        let body = message["body"] as? [String: Any] ?? [:]
        switch type {
        case "ready":
            ready = true
            if let document {
                let pageID = document.selectedPageID
                DispatchQueue.main.async { [weak self] in
                    self?.load(pageID: pageID)
                }
            }
        case "pageChanged":
            handlePageChanged(body)
        case "flushComplete":
            finishPendingPageSwitch()
        case "previewGenerated":
            handlePreview(body)
        case "cardTierPreviewsGenerated":
            handleCardTierPreviews(body)
        case "importAsset":
            importAsset(body)
        case "importAssetData":
            importAssetData(body)
        case "openLinkedNotebook":
            openLinkedNotebook(body)
        case "listPluginPeople":
            listPluginPeople(body)
        case "savePluginPerson":
            savePluginPerson(body)
        case "listPluginNotebooks":
            listPluginNotebooks(body)
        case "error":
            let message = body["message"] as? String ?? "The canvas reported an unknown error."
            NotificationCenter.default.post(name: .notebookCanvasError, object: message)
        default:
            break
        }
    }

    private func handlePageChanged(_ body: [String: Any]) {
        guard let document,
              let pageID = body["pageID"] as? String,
              loadedPageID == pageID,
              let revision = body["revision"] as? Int,
              let canvasObject = body["canvas"],
              let canvas = try? JSONValue(any: canvasObject) else { return }
        let storedCanvas = Self.storedCanvas(canvas)
        if let nextRevision = document.updateCanvas(pageID: pageID, expectedRevision: revision, canvas: storedCanvas) {
            send(type: "pageSaved", body: [
                "pageID": .string(pageID),
                "revision": .number(Double(nextRevision)),
            ])
        } else if let current = document.package.pagePayloads[pageID] {
            send(type: "staleRevision", body: [
                "pageID": .string(pageID),
                "revision": .number(Double(current.revision)),
                "canvas": Self.runtimeCanvas(current.canvas),
            ])
        }
    }

    private func handlePreview(_ body: [String: Any]) {
        guard let document,
              let pageID = body["pageID"] as? String,
              let dataURL = body["dataURL"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return }
        document.storePreview(pageID: pageID, data: data)
    }

    private func handleCardTierPreviews(_ body: [String: Any]) {
        guard let document,
              let pageID = body["pageID"] as? String,
              let cardID = body["cardID"] as? String,
              let values = body["previews"] as? [[String: Any]] else { return }
        let previews = values.compactMap { value -> (tierID: String, revision: Int, data: Data)? in
            guard let tierID = value["tierId"] as? String,
                  let revision = value["tierRevision"] as? Int,
                  let dataURL = value["dataUrl"] as? String,
                  let comma = dataURL.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
            return (tierID, revision, data)
        }
        document.storeCardTierPreviews(pageID: pageID, cardID: cardID, previews: previews)
    }

    private func importAsset(_ body: [String: Any]) {
        guard let document, let requestID = body["requestID"] as? String else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = body["kind"] as? String == "video" ? [.movie] : [.image]
        guard panel.runModal() == .OK, let url = panel.url else {
            send(type: "assetImportCancelled", body: ["requestID": .string(requestID)])
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            send(type: "assetImportFailed", body: [
                "requestID": .string(requestID),
                "message": .string("The selected file could not be read."),
            ])
            return
        }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "application/octet-stream"
        let metadata = document.importAsset(data: data, originalFilename: url.lastPathComponent, mediaType: type)
        assetHandler.update(package: document.package)
        webAppHandler.update(package: document.package)
        let size = imageSize(data: data, mediaType: type)
        send(type: "assetImported", body: [
            "requestID": .string(requestID),
            "hash": .string(metadata.hash),
            "filename": .string(metadata.filename),
            "mediaType": .string(metadata.mediaType),
            "url": .string(Self.runtimeAssetURL(filename: metadata.filename)),
            "width": .number(size.width),
            "height": .number(size.height),
        ])
    }

    private func importAssetData(_ body: [String: Any]) {
        guard let document,
              let requestID = body["requestID"] as? String,
              let dataURL = body["dataURL"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
            if let requestID = body["requestID"] as? String {
                send(type: "assetImportFailed", body: [
                    "requestID": .string(requestID),
                    "message": .string("The pasted image data is invalid."),
                ])
            }
            return
        }
        let header = String(dataURL[..<comma])
        let mediaType = header
            .dropFirst("data:".count)
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? "image/png"
        let name = (body["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Pasted Image.png"
        let metadata = document.importAsset(data: data, originalFilename: name, mediaType: mediaType)
        assetHandler.update(package: document.package)
        webAppHandler.update(package: document.package)
        let size = imageSize(data: data, mediaType: mediaType)
        send(type: "assetImported", body: [
            "requestID": .string(requestID),
            "hash": .string(metadata.hash),
            "filename": .string(metadata.filename),
            "mediaType": .string(metadata.mediaType),
            "url": .string(Self.runtimeAssetURL(filename: metadata.filename)),
            "width": .number(size.width),
            "height": .number(size.height),
        ])
    }

    private func imageSize(data: Data, mediaType: String) -> (width: Double, height: Double) {
        guard mediaType.contains("image"), let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return (640, 360)
        }
        return (image.size.width, image.size.height)
    }

    private func openLinkedNotebook(_ body: [String: Any]) {
        guard let targetID = body["notebookID"] as? String, let store = try? ReviewFileStore() else { return }
        if let registrations = try? store.registeredNotebooks(),
           let registration = registrations.first(where: { $0.notebookID == targetID }),
           let url = store.resolve(registration) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            return
        }

        let panel = NSOpenPanel()
        panel.message = "Locate the linked notebook. Its contents will be checked before the link is updated."
        panel.prompt = "Locate"
        panel.allowedContentTypes = [.productivityNotebook]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let package = try? NotebookPackageIO.read(at: url),
              package.manifest.notebookID == targetID else {
            send(type: "linkedNotebookMissing", body: ["notebookID": .string(targetID)])
            return
        }
        try? store.register(notebookURL: url, manifest: package.manifest)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func listPluginPeople(_ body: [String: Any]) {
        guard let requestID = body["requestID"] as? String else { return }
        do {
            let store = try ReviewFileStore()
            let people = try store.pluginPeople(query: body["query"] as? String ?? "")
            let values = people.map { person in
                JSONValue.object([
                    "id": .string(person.id),
                    "name": .string(person.name),
                    "role": .string(person.role),
                    "organization": .string(person.organization),
                    "notes": .string(person.notes),
                    "createdAt": .number(person.createdAt),
                    "updatedAt": .number(person.updatedAt),
                ])
            }
            resolveNativeRequest(requestID, value: .array(values))
        } catch {
            rejectNativeRequest(requestID, error: error)
        }
    }

    private func savePluginPerson(_ body: [String: Any]) {
        guard let requestID = body["requestID"] as? String,
              let input = body["person"] as? [String: Any],
              let id = input["id"] as? String,
              let name = input["name"] as? String else { return }
        do {
            let person = try ReviewFileStore().savePluginPerson(
                id: id,
                name: name,
                role: input["role"] as? String ?? "",
                organization: input["organization"] as? String ?? "",
                notes: input["notes"] as? String ?? ""
            )
            resolveNativeRequest(requestID, value: .object([
                "id": .string(person.id),
                "name": .string(person.name),
                "role": .string(person.role),
                "organization": .string(person.organization),
                "notes": .string(person.notes),
                "createdAt": .number(person.createdAt),
                "updatedAt": .number(person.updatedAt),
            ]))
        } catch {
            rejectNativeRequest(requestID, error: error)
        }
    }

    private func listPluginNotebooks(_ body: [String: Any]) {
        guard let requestID = body["requestID"] as? String else { return }
        do {
            let store = try ReviewFileStore()
            let values = try store.registeredNotebooks().map { notebook in
                JSONValue.object([
                    "id": .string(notebook.notebookID),
                    "title": .string(notebook.displayName),
                    "project": .string(""),
                    "canvasType": .string("notebook"),
                    "icon": .string("📓"),
                    "starred": .bool(false),
                    "createdAt": .number(notebook.updatedAt.timeIntervalSince1970 * 1_000),
                    "updatedAt": .number(notebook.updatedAt.timeIntervalSince1970 * 1_000),
                    "revision": .number(0),
                    "previewDataUrl": .null,
                    "coverMediaId": .null,
                ])
            }
            resolveNativeRequest(requestID, value: .array(values))
        } catch {
            rejectNativeRequest(requestID, error: error)
        }
    }

    private func resolveNativeRequest(_ requestID: String, value: JSONValue) {
        send(type: "nativeRequestResolved", body: [
            "requestID": .string(requestID),
            "value": value,
        ])
    }

    private func rejectNativeRequest(_ requestID: String, error: Error) {
        send(type: "nativeRequestRejected", body: [
            "requestID": .string(requestID),
            "message": .string(error.localizedDescription),
        ])
    }

    private func send(type: String, body: [String: JSONValue]) {
        let envelope: JSONValue = .object([
            "version": .number(Double(NotebookFormat.bridgeVersion)),
            "type": .string(type),
            "body": .object(body),
        ])
        guard let data = try? NotebookCoding.encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.notesNative?.receive(\(json));") { [weak self] _, error in
            guard let self, let error, !self.reportedWebFailure else { return }
            self.reportedWebFailure = true
            NotificationCenter.default.post(
                name: .notebookCanvasError,
                object: "The notebook canvas could not receive page data. \(error.localizedDescription)"
            )
        }
    }

    private static func runtimeAssetURL(filename: String) -> String {
        "notes-canvas://app/notebook-assets/\(filename)"
    }

    private static func runtimeCanvas(_ value: JSONValue) -> JSONValue {
        replacingStrings(in: value) { string in
            guard string.hasPrefix("notebook-asset://asset/") else { return string }
            return runtimeAssetURL(filename: String(string.dropFirst("notebook-asset://asset/".count)))
        }
    }

    private static func storedCanvas(_ value: JSONValue) -> JSONValue {
        replacingStrings(in: value) { string in
            let prefix = "notes-canvas://app/notebook-assets/"
            guard string.hasPrefix(prefix) else { return string }
            return "notebook-asset://asset/\(string.dropFirst(prefix.count))"
        }
    }

    private static func replacingStrings(
        in value: JSONValue,
        transform: (String) -> String
    ) -> JSONValue {
        switch value {
        case let .string(string):
            return .string(transform(string))
        case let .array(values):
            return .array(values.map { replacingStrings(in: $0, transform: transform) })
        case let .object(values):
            return .object(values.mapValues { replacingStrings(in: $0, transform: transform) })
        default:
            return value
        }
    }
}

extension CanvasWebController: WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        handle(message: value)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak webView] in
            guard let self, let webView, !self.reportedWebFailure else { return }
            webView.evaluateJavaScript("({ bridge: typeof window.notesNative, page: Boolean(document.querySelector('.native-page-paper')) })") { value, error in
                guard !self.reportedWebFailure else { return }
                let status = value as? [String: Any]
                if self.ready, status?["page"] as? Bool == true { return }
                self.reportedWebFailure = true
                let detail = error?.localizedDescription
                    ?? "bridge=\(status?["bridge"] ?? "unavailable"), page=\(status?["page"] ?? false)"
                NotificationCenter.default.post(
                    name: .notebookCanvasError,
                    object: "The notebook canvas did not start. \(detail)"
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error)
    }

    private func reportNavigationFailure(_ error: Error) {
        guard !reportedWebFailure else { return }
        reportedWebFailure = true
        NotificationCenter.default.post(
            name: .notebookCanvasError,
            object: "The notebook canvas could not be loaded. \(error.localizedDescription)"
        )
    }
}

final class CanvasWebAppSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let rootURL = Bundle.main.resourceURL?.appendingPathComponent("CanvasWeb", isDirectory: true)
    private let lock = NSLock()
    private var assets: [String: Data] = [:]
    private var mediaTypes: [String: String] = [:]

    func update(package: NotebookPackage) {
        lock.lock()
        assets = package.assets
        mediaTypes = Dictionary(uniqueKeysWithValues: package.manifest.assets.map { ($0.filename, $0.mediaType) })
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let rootURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let relativePath = requestURL.path.removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if relativePath.hasPrefix("notebook-assets/") {
            let filename = String(relativePath.dropFirst("notebook-assets/".count))
            guard let (data, mediaType) = asset(filename: filename) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let response = URLResponse(
                url: requestURL,
                mimeType: mediaType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }
        let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/")
            ? rootURL.standardizedFileURL.path
            : rootURL.standardizedFileURL.path + "/"
        guard fileURL.path.hasPrefix(rootPath),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: Self.mimeType(for: fileURL.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: Self.isText(fileURL.pathExtension) ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func asset(filename: String) -> (Data, String)? {
        lock.lock()
        defer { lock.unlock() }
        guard !filename.contains("/"), let data = assets[filename] else { return nil }
        return (data, mediaTypes[filename] ?? "application/octet-stream")
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }

    private static func isText(_ pathExtension: String) -> Bool {
        ["html", "js", "mjs", "css", "json", "svg"].contains(pathExtension.lowercased())
    }
}

final class NotebookAssetSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var assets: [String: Data] = [:]
    private var mediaTypes: [String: String] = [:]

    func update(package: NotebookPackage) {
        lock.lock()
        assets = package.assets
        mediaTypes = Dictionary(uniqueKeysWithValues: package.manifest.assets.map { ($0.filename, $0.mediaType) })
        lock.unlock()
    }

    private func content(filename: String) -> (Data, String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = assets[filename] else { return nil }
        return (data, mediaTypes[filename] ?? "application/octet-stream")
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let filename = url.pathComponents.last,
              let (data, type) = content(filename: filename) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

struct CanvasWebView: NSViewRepresentable {
    @ObservedObject var document: NotebookDocument
    @ObservedObject var controller: CanvasWebController

    func makeNSView(context: Context) -> WKWebView {
        controller.connect(document: document)
        controller.loadWebApp()
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        controller.connect(document: document)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Void) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "notesBridge")
        nsView.stopLoading()
    }
}

extension Notification.Name {
    static let notebookCanvasError = Notification.Name("NotebookCanvasError")
}
