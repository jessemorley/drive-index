//
//  DuplicatesWebPane.swift
//  DriveIndex
//
//  Prototype: the duplicates cards drawn by WebKit, for CSS animation. The toolbar, data and actions
//  stay in DuplicatesView; this pane only renders and posts clicks back
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
        let webView = WKWebView(frame: .zero, configuration: config)
        // Let the window background show through, like the native ScrollView
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html, baseURL: nil)
        context.coordinator.webView = webView
        return webView
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
            let name, size, wasted: String
            let copies: Int
            let files: [File]
        }
        struct File: Encodable {
            let id: Int64
            let drive, path, date: String
            let connected: Bool
        }
        let folders: Bool
        let groups: [Group]
    }

    fileprivate func payload() -> String {
        let connected = Set(drives.filter(\.isConnected).map(\.id))
        let payload = Payload(folders: kind == .folders, groups: groups.map { group in
            Payload.Group(
                id: group.cardID,
                name: group.name,
                size: ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file),
                wasted: ByteCountFormatter.string(fromByteCount: group.wastedBytes, countStyle: .file),
                copies: group.files.count,
                files: group.files.map { file in
                    Payload.File(id: file.id, drive: file.driveName, path: file.relativePath,
                                 date: file.modifiedAt?.formatted(.dateTime.day().month().year()) ?? "",
                                 connected: connected.contains(file.driveUUID))
                })
        })
        return String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
    }

    // MARK: - Bridge

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: DuplicatesWebPane
        weak var webView: WKWebView?
        private var loaded = false
        private var sent: String?

        init(_ parent: DuplicatesWebPane) { self.parent = parent }

        /// Hands the page the current groups; it diffs them against what it shows and animates the change
        func send() {
            guard loaded, let webView else { return }
            let json = parent.payload()
            guard json != sent else { return }
            sent = json
            webView.callAsyncJavaScript("render(JSON.parse(json))", arguments: ["json": json], in: nil, in: .page)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            send()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
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

    // MARK: - Page

    // ponytail: inline so the prototype is one file; move to bundled .html/.css/.js (or a Vite build) if it stays
    private static let html = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <style>
    :root {
      color-scheme: light dark;
      --label: light-dark(#000000d9, #ffffffd9);
      --secondary: light-dark(#00000080, #ffffff8c);
      --tertiary: light-dark(#00000040, #ffffff40);
      --separator: light-dark(#0000001a, #ffffff1a);
      --card: light-dark(#00000008, #ffffff0a);
      --card-border: light-dark(#00000014, #ffffff14);
      --hover: light-dark(#0000000d, #ffffff12);
      --orange: light-dark(#ff9500, #ff9f0a);
      --ease: cubic-bezier(.2, .8, .2, 1);
    }
    html, body { margin: 0; background: transparent; }
    body {
      font: 13px -apple-system, system-ui; color: var(--label);
      padding: 16px; user-select: none; -webkit-user-select: none; cursor: default;
    }
    .card {
      background: var(--card); border: 0.5px solid var(--card-border); border-radius: 10px;
      margin-bottom: 8px; overflow: hidden;
      /* Thousands of cards: skip layout and paint for the ones off screen */
      content-visibility: auto; contain-intrinsic-size: auto 42px;
    }
    .header { display: flex; align-items: center; gap: 8px; padding: 10px 12px; }
    .header .name { flex: 0 1 auto; }
    .spacer { flex: 1; }
    .chev { width: 10px; height: 10px; flex: none; color: var(--secondary); transition: rotate .3s var(--ease); }
    .open .chev { rotate: 90deg; }
    .body { display: grid; grid-template-rows: 0fr; transition: grid-template-rows .35s var(--ease); }
    .open .body { grid-template-rows: 1fr; }
    .rows { overflow: hidden; min-height: 0; padding: 0 4px; }
    .open .rows { padding-bottom: 6px; }
    .row {
      position: relative; display: flex; align-items: center; gap: 8px;
      padding: 5px 8px; border-radius: 6px; transition: background-color .15s;
    }
    .row::before { content: ""; position: absolute; top: 0; left: 8px; right: 8px; border-top: 0.5px solid var(--separator); }
    .row:hover { background: var(--hover); }
    .row:hover::before, .row:hover + .row::before { opacity: 0; }
    .name, .path { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
    .path { flex: 1; color: var(--secondary); }
    .secondary { color: var(--secondary); white-space: nowrap; }
    .off .drive, .off .path { color: var(--tertiary); }
    svg.icon { width: 16px; height: 16px; flex: none; color: var(--secondary); }
    button {
      all: unset; display: grid; place-items: center; width: 22px; height: 22px; border-radius: 5px;
      color: var(--secondary); transition: background-color .15s, transform .15s var(--ease);
    }
    button:hover { background: var(--hover); color: var(--label); }
    button:active { transform: scale(.88); }
    button:disabled { opacity: .35; pointer-events: none; }
    button.compare { color: var(--orange); }
    button svg { width: 14px; height: 14px; }
    </style></head>
    <body><div id="list"></div>
    <script>
    const ICON = {
      chev: '<svg class="chev" viewBox="0 0 10 10"><path d="M3.5 1.5 7 5l-3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      file: '<svg class="icon" viewBox="0 0 16 16"><path d="M4 1.5h5L12.5 5v9a.5.5 0 0 1-.5.5H4a.5.5 0 0 1-.5-.5V2a.5.5 0 0 1 .5-.5Z M9 1.5V5h3.5" fill="none" stroke="currentColor"/></svg>',
      folder: '<svg class="icon" viewBox="0 0 16 16"><path d="M1.5 4a1 1 0 0 1 1-1h3.6l1.4 1.5h6a1 1 0 0 1 1 1V12a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1Z" fill="none" stroke="currentColor"/></svg>',
      drive: '<svg class="icon" viewBox="0 0 16 16"><rect x="1.5" y="4.5" width="13" height="7" rx="1.5" fill="none" stroke="currentColor"/><circle cx="12" cy="8" r=".9" fill="currentColor"/></svg>',
      trash: '<svg viewBox="0 0 16 16"><path d="M2.5 4h11M6 4V2.5h4V4M4 4l.7 9.5h6.6L12 4" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      compare: '<svg viewBox="0 0 16 16"><path d="M5 13V3M2.5 5.5 5 3l2.5 2.5M11 3v10m-2.5-2.5L11 13l2.5-2.5" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };
    const EASE = 'cubic-bezier(.2, .8, .2, 1)';
    const list = document.getElementById('list');
    const cards = new Map();  // group id → { el, g, rows: Map(file id → { el, button }), refs }
    let folders = null;

    const post = message => webkit.messageHandlers.native.postMessage(message);
    // WebKit's own menu (Reload, Inspect Element) gives the page away; rows ask for a native one
    document.addEventListener('contextmenu', e => e.preventDefault());

    function el(tag, cls, html) {
      const node = document.createElement(tag);
      if (cls) node.className = cls;
      if (html) node.innerHTML = html;  // only ever our own ICON markup
      return node;
    }
    function text(cls, value) { const node = el('span', cls); node.textContent = value; return node; }
    function button(icon, title, cls, onClick) {
      const b = el('button', cls, icon);
      b.title = title;
      b.addEventListener('click', e => { e.stopPropagation(); onClick(); });
      b.addEventListener('dblclick', e => e.stopPropagation());
      return b;
    }

    /// Shrinks a card or row away, so what's under it slides up
    function collapse(node) {
      if (node.dataset.leaving) return;
      node.dataset.leaving = '1';
      node.style.pointerEvents = 'none';
      node.animate([
        { height: node.offsetHeight + 'px', opacity: 1 },
        { height: '0px', opacity: 0, marginBottom: '0px', paddingTop: '0px', paddingBottom: '0px', borderWidth: '0px' },
      ], { duration: 300, easing: EASE }).finished.then(() => node.remove());
    }

    function makeCard(g) {
      const c = { g, rows: new Map(), el: el('div', 'card') };
      c.el.dataset.id = g.id;
      const header = el('div', 'header', ICON.chev + (folders ? ICON.folder : ICON.file));
      c.refs = { name: text('name', ''), size: text('secondary', ''), copies: text('secondary', ''), wasted: text('', '') };
      header.append(c.refs.name, c.refs.size, el('span', 'spacer'), c.refs.copies, c.refs.wasted);
      if (folders) header.append(button(ICON.compare, 'Compare the folders above these copies', 'compare', () => post({ action: 'compare', group: c.g.id })));
      header.addEventListener('click', () => {
        const open = c.el.classList.toggle('open');
        if (open) syncRows(c);
      });
      const body = el('div', 'body');
      c.rowsEl = el('div', 'rows');
      body.append(c.rowsEl);
      c.el.append(header, body);
      return c;
    }

    function updateCard(c, g) {
      c.g = g;
      c.refs.name.textContent = g.name;
      c.refs.size.textContent = g.size;
      c.refs.copies.textContent = g.copies + ' copies';
      c.refs.wasted.textContent = g.wasted + ' wasted';
      // Rows are built on first open: most cards never are
      if (c.el.classList.contains('open') || c.rows.size) syncRows(c);
    }

    function syncRows(c) {
      const ids = new Set(c.g.files.map(f => f.id));
      for (const [id, r] of c.rows) if (!ids.has(id)) { c.rows.delete(id); collapse(r.el); }
      for (const f of c.g.files) {
        let r = c.rows.get(f.id);
        if (!r) {
          r = { el: el('div', 'row', ICON.drive) };
          r.button = button(ICON.trash, 'Move this copy to the Trash', '', () => post({ action: 'trash', group: c.g.id, file: f.id }));
          r.el.append(text('drive', f.drive), text('path', f.path), text('secondary', f.date), r.button);
          r.el.addEventListener('dblclick', () => post({ action: 'reveal', group: c.g.id, file: f.id }));
          r.el.addEventListener('contextmenu', () => post({ action: 'menu', group: c.g.id, file: f.id }));
          c.rows.set(f.id, r);
          c.rowsEl.append(r.el);
        }
        r.el.classList.toggle('off', !f.connected);
        r.button.disabled = !f.connected;
      }
    }

    function render(data) {
      // Files ↔ Folders is a different list, not a change to this one
      const fresh = data.folders !== folders;
      if (fresh) { folders = data.folders; cards.clear(); list.replaceChildren(); }

      const ids = new Set(data.groups.map(g => g.id));
      const shownOrder = [...list.children].filter(n => !n.dataset.leaving && ids.has(+n.dataset.id)).map(n => +n.dataset.id);
      const reordered = shownOrder.join() !== data.groups.map(g => g.id).filter(id => cards.has(id)).join();

      // First (FLIP): where each kept card is before the change
      const before = new Map();
      for (const [id, c] of cards) if (ids.has(id)) before.set(id, c.el.getBoundingClientRect().top);

      for (const [id, c] of cards) {
        if (ids.has(id)) continue;
        cards.delete(id);
        // ponytail: a re-sort drops leavers instantly; collapsing in place only works while order holds
        reordered ? c.el.remove() : collapse(c.el);
      }

      const added = [];
      for (const g of data.groups) {
        let c = cards.get(g.id);
        if (!c) { c = makeCard(g); cards.set(g.id, c); added.push(c); }
        updateCard(c, g);
      }

      // Back to front, so each card goes in before the one after it; when the order holds, only new ones move
      let next = null;
      for (let i = data.groups.length - 1; i >= 0; i--) {
        const c = cards.get(data.groups[i].id);
        if (reordered || !c.el.isConnected) list.insertBefore(c.el, next);
        next = c.el;
      }

      // Last, Invert, Play: slide moved cards from where they were. Only on-screen ones; the rest can't be seen
      const h = innerHeight;
      for (const [id, top] of before) {
        const node = cards.get(id).el;
        const now = node.getBoundingClientRect().top;
        if (top === now || (top > h && now > h) || (top < -60 && now < -60)) continue;
        node.animate([{ transform: `translateY(${top - now}px)` }, { transform: 'none' }], { duration: 450, easing: EASE });
      }

      added.forEach((c, i) => {
        if (c.el.getBoundingClientRect().top > h) return;
        c.el.animate([{ opacity: 0, transform: 'translateY(8px) scale(.98)' }, { opacity: 1, transform: 'none' }],
                     { duration: 400, delay: fresh ? Math.min(i, 20) * 25 : 0, easing: EASE, fill: 'backwards' });
      });
    }
    </script></body></html>
    """#
}
