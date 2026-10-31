//
//  DuplicatesWebPane.swift
//  DriveIndex
//
//  Prototype: the duplicates cards drawn by WebKit (Web/duplicates.html), for CSS animation. The
//  toolbar, data and actions stay in DuplicatesView; this pane only renders and posts clicks back
//

import SwiftUI
import WebKit

struct DuplicatesWebPane: NSViewRepresentable {
    let groups: [DuplicateGroup]
    let kind: DuplicateKind
    let drives: [DriveInfo]
    /// The toolbar's height: the page lays out below it but scrolls under it
    let topInset: CGFloat
    let reveal: (DuplicateFile) -> Void
    let trash: (DuplicateFile) -> Void
    let compare: (DuplicateGroup) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "native")
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "icon")
        #if DEBUG
        // ⌘R (with the pane focused) reloads the page from the source folder
        config.userContentController.addUserScript(WKUserScript(
            source: "addEventListener('keydown', e => { if (e.metaKey && e.key === 'r') location.reload() })",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        let webView = WKWebView(frame: .zero, configuration: config)
        // Let the window background show through, like the native ScrollView
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        #if DEBUG
        // Safari > Develop > [this Mac] > DriveIndex attaches Web Inspector
        webView.isInspectable = true
        #endif
        webView.loadFileURL(Self.pageURL, allowingReadAccessTo: Self.pageURL.deletingLastPathComponent())
        context.coordinator.webView = webView
        return webView
    }

    /// In Debug, the page straight from the source folder, so edits show on reload without a rebuild
    private static var pageURL: URL {
        #if DEBUG
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Web/duplicates.html")
        #else
        Bundle.main.url(forResource: "duplicates", withExtension: "html", subdirectory: "Web")!
        #endif
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if webView.obscuredContentInsets.top != topInset {
            webView.obscuredContentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        }
        context.coordinator.send()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "native")
    }

    // MARK: - Data

    private struct Payload: Encodable {
        struct Group: Encodable {
            let id: Int64
            let name, icon, size, wasted: String
            let copies: Int
            let files: [File]
        }
        struct File: Encodable {
            let id: Int64
            let drive, driveIcon, path, date: String
            let connected: Bool
        }
        let folders: Bool
        let groups: [Group]
        /// Groups not sent yet
        let more: Int
    }

    /// The first `limit` groups
    fileprivate func payload(limit: Int) -> String {
        let connected = Set(drives.filter(\.isConnected).map(\.id))
        let payload = Payload(folders: kind == .folders, groups: groups.prefix(limit).map { group in
            Payload.Group(
                id: group.cardID,
                name: group.name,
                icon: Self.typeIconURL(name: group.name, isDirectory: kind == .folders),
                size: ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file),
                wasted: ByteCountFormatter.string(fromByteCount: group.wastedBytes, countStyle: .file),
                copies: group.files.count,
                files: group.files.map { file in
                    Payload.File(id: file.id, drive: file.driveName, driveIcon: "icon://drive/\(file.driveUUID)",
                                 path: file.relativePath,
                                 date: file.modifiedAt?.formatted(.dateTime.day().month().year()) ?? "",
                                 connected: connected.contains(file.driveUUID))
                })
        }, more: max(0, groups.count - limit))
        return String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
    }

    // MARK: - Icons

    /// One URL per file type, not per file, so WebKit fetches each icon once
    private static func typeIconURL(name: String, isDirectory: Bool) -> String {
        if isDirectory { return "icon://folder" }
        let ext = (name as NSString).pathExtension.lowercased()
        return "icon://type/" + (ext.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
    }

    /// The Finder icon an icon:// URL names, as a 32 px PNG (16 pt at 2x)
    fileprivate func iconPNG(for url: URL) -> Data? {
        let image: NSImage? = switch url.host() {
        case "folder": NSWorkspace.shared.listIcon(name: "", isDirectory: true)
        case "type": NSWorkspace.shared.listIcon(name: "x." + url.lastPathComponent, isDirectory: false)
        case "drive": drives.first { $0.id == url.lastPathComponent }?.finderIcon
        default: nil
        }
        guard let image, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Bridge

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
        var parent: DuplicatesWebPane
        weak var webView: WKWebView?
        private var loaded = false
        private var sent: String?
        // ponytail: pages of 200 keep each send small; Show More adds a page
        static let pageSize = 200
        private var limit = pageSize
        private var kind: DuplicateKind?

        init(_ parent: DuplicatesWebPane) { self.parent = parent }

        /// Hands the page the current groups; it diffs them against what it shows and animates the change
        func send() {
            guard loaded, let webView else { return }
            if parent.kind != kind { kind = parent.kind; limit = Self.pageSize }
            let json = parent.payload(limit: limit)
            guard json != sent else { return }
            sent = json
            webView.callAsyncJavaScript("render(JSON.parse(json))", arguments: ["json": json], in: nil, in: .page)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            // A reload starts the page empty
            sent = nil
            send()
        }

        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url, let png = parent.iconPNG(for: url) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            task.didReceive(URLResponse(url: url, mimeType: "image/png", expectedContentLength: png.count, textEncodingName: nil))
            task.didReceive(png)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if (message.body as? [String: Any])?["action"] as? String == "more" {
                limit += Self.pageSize
                send()
                return
            }
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String,
                  let groupID = (body["group"] as? NSNumber)?.int64Value,
                  let group = parent.groups.first(where: { $0.cardID == groupID }) else { return }
            let file = (body["file"] as? NSNumber).flatMap { id in group.files.first { $0.id == id.int64Value } }
            switch action {
            case "compare": parent.compare(group)
            case "reveal": file.map(parent.reveal)
            case "trash": file.map(parent.trash)
            case "menu": file.map(showMenu)
            default: break
            }
        }

        /// A real NSMenu instead of WebKit's (Reload, Inspect Element)
        private func showMenu(for file: DuplicateFile) {
            guard let webView, let window = webView.window else { return }
            let connected = parent.drives.first { $0.id == file.driveUUID }?.isConnected ?? false
            let menu = NSMenu()
            for (title, action) in [("Reveal in Finder", #selector(revealItem)), ("Move to Trash", #selector(trashItem))] {
                // No action leaves the item disabled
                let item = NSMenuItem(title: title, action: connected ? action : nil, keyEquivalent: "")
                item.target = self
                item.representedObject = file
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: webView.convert(window.mouseLocationOutsideOfEventStream, from: nil), in: webView)
        }

        @objc private func revealItem(_ item: NSMenuItem) { (item.representedObject as? DuplicateFile).map(parent.reveal) }
        @objc private func trashItem(_ item: NSMenuItem) { (item.representedObject as? DuplicateFile).map(parent.trash) }
    }
}
