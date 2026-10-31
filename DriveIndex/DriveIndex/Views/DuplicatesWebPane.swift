//
//  DuplicatesWebPane.swift
//  DriveIndex
//
//  The duplicates cards drawn by WebKit (Web/duplicates.html), for CSS animation. The toolbar, data
//  and actions stay in DuplicatesView; this pane only renders, posts clicks back and shows native menus
//

import SwiftUI
import WebKit

struct DuplicatesWebPane: NSViewRepresentable {
    let sets: [FolderSet]
    let loose: [DuplicateGroup]
    let drives: [DriveInfo]
    /// The toolbar's height: the page lays out below it but scrolls under it
    let topInset: CGFloat
    let reveal: (DuplicateFile) -> Void
    let trash: (DuplicateFile) -> Void
    let revealFolder: (FolderLocation) -> Void
    let trashFolder: (FolderSet.Member) -> Void
    let compare: (FolderPair) -> Void

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
        struct Set: Encodable {
            let id, name, wasted: String
            let members: [Member]
        }
        struct Member: Encodable {
            let id, drive, driveIcon, path, summary, verdict: String
            let safe, connected, holdsAnother: Bool
            let files, shared, changed, onlyHere, unchecked: Int
        }
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
        let sets: [Set]
        let groups: [Group]
        /// Groups not sent yet
        let more: Int
    }

    /// Every set, and the first `limit` groups
    fileprivate func payload(limit: Int) -> String {
        let connected = Swift.Set(drives.filter(\.isConnected).map(\.id))
        func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
        let payload = Payload(sets: sets.map { set in
            Payload.Set(id: set.id, name: set.name, wasted: bytes(set.wastedBytes), members: set.members.map { m in
                Payload.Member(id: m.id, drive: m.folder.driveName, driveIcon: "icon://drive/\(m.folder.driveUUID)",
                               path: m.folder.relativePath, summary: "\(m.files.formatted()) files, \(bytes(m.bytes))",
                               verdict: m.verdict, safe: m.isSafeToRemove, connected: connected.contains(m.folder.driveUUID), holdsAnother: m.holdsAnother,
                               files: m.files, shared: m.shared, changed: m.changed, onlyHere: m.onlyHere, unchecked: m.unchecked)
            })
        }, groups: loose.prefix(limit).map { group in
            Payload.Group(
                id: group.cardID,
                name: group.name,
                icon: Self.typeIconURL(name: group.name),
                size: bytes(group.size),
                wasted: bytes(group.wastedBytes),
                copies: group.files.count,
                files: group.files.map { file in
                    Payload.File(id: file.id, drive: file.driveName, driveIcon: "icon://drive/\(file.driveUUID)",
                                 path: file.relativePath,
                                 date: file.modifiedAt?.formatted(.dateTime.day().month().year()) ?? "",
                                 connected: connected.contains(file.driveUUID))
                })
        }, more: max(0, loose.count - limit))
        return String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
    }

    // MARK: - Icons

    /// One URL per file type, not per file, so WebKit fetches each icon once
    private static func typeIconURL(name: String) -> String {
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

        init(_ parent: DuplicatesWebPane) { self.parent = parent }

        /// Hands the page the current cards; it diffs them against what it shows and animates the change
        func send() {
            guard loaded, let webView else { return }
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
            guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            if action == "more" {
                limit += Self.pageSize
                send()
                return
            }
            if let setID = body["set"] as? String, let set = parent.sets.first(where: { $0.id == setID }) {
                let member = (body["member"] as? String).flatMap { id in set.members.first { $0.id == id } }
                switch action {
                case "compare": compare(set)
                case "reveal": member.map { parent.revealFolder($0.folder) }
                case "trash": member.map(parent.trashFolder)
                case "menu": member.map { member in
                    let connected = isConnected(member.folder.driveUUID)
                    popUp([("Reveal in Finder", connected, { self.parent.revealFolder(member.folder) }),
                           ("Move to Trash…", connected && !member.holdsAnother, { self.parent.trashFolder(member) })])
                }
                default: break
                }
                return
            }
            guard let groupID = (body["group"] as? NSNumber)?.int64Value,
                  let group = parent.loose.first(where: { $0.cardID == groupID }),
                  let file = (body["file"] as? NSNumber).flatMap({ id in group.files.first { $0.id == id.int64Value } }) else { return }
            switch action {
            case "reveal": parent.reveal(file)
            case "trash": parent.trash(file)
            case "menu":
                let connected = isConnected(file.driveUUID)
                popUp([("Reveal in Finder", connected, { self.parent.reveal(file) }),
                       ("Move to Trash", connected, { self.parent.trash(file) })])
            default: break
            }
        }

        private func isConnected(_ driveUUID: String) -> Bool {
            parent.drives.first { $0.id == driveUUID }?.isConnected ?? false
        }

        /// Two folders open Folder Compare; more ask which two
        private func compare(_ set: FolderSet) {
            let folders = set.members.map(\.folder)
            guard folders.count > 2 else { parent.compare(FolderPair(a: folders[0], b: folders[1])); return }
            let pairs = folders.indices.flatMap { i in folders[(i + 1)...].map { (folders[i], $0) } }
            popUp(pairs.map { a, b in
                ("\(a.driveName): \(a.relativePath)  ↔  \(b.driveName): \(b.relativePath)", true,
                 { self.parent.compare(FolderPair(a: a, b: b)) })
            })
        }

        /// A real NSMenu at the mouse instead of WebKit's (Reload, Inspect Element)
        private func popUp(_ items: [(title: String, enabled: Bool, run: () -> Void)]) {
            guard let webView, let window = webView.window else { return }
            let menu = NSMenu()
            for item in items {
                // No action leaves the item disabled
                let menuItem = NSMenuItem(title: item.title, action: item.enabled ? #selector(run) : nil, keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.run
                menu.addItem(menuItem)
            }
            menu.popUp(positioning: nil, at: webView.convert(window.mouseLocationOutsideOfEventStream, from: nil), in: webView)
        }

        @objc private func run(_ item: NSMenuItem) { (item.representedObject as? () -> Void)?() }
    }
}
