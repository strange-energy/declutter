import SwiftUI
import WebKit

/// Interactive, zero-config Google Photos Sign-In, Folder Picker, and Guided Deletion Assistant sheet.
/// Users simply sign in with their Google Account (just like Safari), open any album/folder,
/// and tap "Swipe This Folder" to load its photos into SwipeDeck's 120Hz card stack.
public struct GooglePhotosBrowserSheet: View {
    public enum Mode: String, CaseIterable {
        case folderPicker = "Pick Folder"
        case deletionAssistant = "To Delete Queue"
    }

    public let initialMode: Mode
    public let onFolderImported: (DeckFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var googleService = GooglePhotosCloudService.shared
    @State private var mode: Mode
    @State private var webController = GooglePhotosWebController()
    @State private var deletionIndex: Int = 0

    public init(
        initialMode: Mode = .folderPicker,
        onFolderImported: @escaping (DeckFilter) -> Void
    ) {
        self.initialMode = initialMode
        self.onFolderImported = onFolderImported
        _mode = State(initialValue: initialMode)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SwipeDeckTheme.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    topControlHeader

                    ZStack(alignment: .bottom) {
                        GooglePhotosWebViewRepresentable(controller: webController)
                            .ignoresSafeArea(edges: .bottom)

                        if mode == .folderPicker {
                            folderPickerBottomDock
                        } else {
                            deletionAssistantBottomDock
                        }
                    }
                }
            }
            .navigationTitle("Google Photos Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        webController.stopAutoScroll()
                        dismiss()
                    }
                    .foregroundStyle(SwipeDeckTheme.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        googleService.loadSampleCloudFolders()
                        webController.stopAutoScroll()
                        if let first = googleService.albums.first {
                            onFolderImported(.googlePhotosAlbum(albumID: first.id, title: first.title))
                        }
                        dismiss()
                    } label: {
                        Text("Sample Folders")
                            .font(SwipeDeckTypography.roundedCounter(12))
                            .foregroundStyle(SwipeDeckTheme.accentDefer)
                    }
                }
            }
            .onAppear {
                if mode == .deletionAssistant,
                   let firstURL = googleService.stagedForDeletionItems.first?.productUrl {
                    webController.navigate(to: firstURL)
                } else {
                    webController.navigate(to: "https://photos.google.com/albums")
                }
            }
            .onDisappear {
                webController.stopAutoScroll()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Control Header

    private var topControlHeader: some View {
        VStack(spacing: 8) {
            if !googleService.stagedForDeletionItems.isEmpty {
                Picker("Mode", selection: $mode) {
                    Text("Pick Folder to Swipe").tag(Mode.folderPicker)
                    Text("To Delete (\(googleService.stagedForDeletionItems.count))").tag(Mode.deletionAssistant)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .onChange(of: mode) { _, newMode in
                    webController.stopAutoScroll()
                    if newMode == .deletionAssistant {
                        deletionIndex = 0
                        openCurrentDeletionItem()
                    } else {
                        webController.navigate(to: "https://photos.google.com/albums")
                    }
                }
            }

            if mode == .folderPicker {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quickNavPill(title: "Albums / Folders", icon: "folder.fill", url: "https://photos.google.com/albums")
                        quickNavPill(title: "All Photos", icon: "photo.on.rectangle", url: "https://photos.google.com")
                        quickNavPill(title: "Favorites", icon: "star.fill", url: "https://photos.google.com/favorites")
                        quickNavPill(title: "Search", icon: "magnifyingglass", url: "https://photos.google.com/search")
                        quickNavPill(title: "Trash", icon: "trash", url: "https://photos.google.com/trash")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(SwipeDeckTheme.surfaceElevated)
    }

    private func quickNavPill(title: String, icon: String, url: String) -> some View {
        Button {
            webController.stopAutoScroll()
            webController.navigate(to: url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(SwipeDeckTypography.roundedHeadline(12, weight: .semibold))
            }
            .foregroundStyle(SwipeDeckTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SwipeDeckTheme.surfaceSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Dock: Folder Picker Mode

    private var folderPickerBottomDock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(webController.detectedFolderTitle)
                        .font(SwipeDeckTypography.roundedHeadline(15, weight: .bold))
                        .foregroundStyle(SwipeDeckTheme.textPrimary)
                        .lineLimit(1)

                    if webController.capturedItems.isEmpty {
                        Text("Sign in & open any folder/album above to detect photos")
                            .font(SwipeDeckTypography.body(12))
                            .foregroundStyle(SwipeDeckTheme.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("\(webController.capturedItems.count) photos ready • Scroll or tap Auto-Scroll for more")
                            .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentKeep)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !webController.capturedItems.isEmpty {
                    Button {
                        webController.toggleAutoScroll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: webController.isAutoScrolling ? "pause.fill" : "arrow.down.circle.fill")
                            Text(webController.isAutoScrolling ? "Stop" : "Auto-Scroll")
                        }
                        .font(SwipeDeckTypography.roundedHeadline(12, weight: .bold))
                        .foregroundStyle(webController.isAutoScrolling ? .black : SwipeDeckTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            webController.isAutoScrolling ? SwipeDeckTheme.accentUndo : SwipeDeckTheme.surfaceSecondary,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                webController.stopAutoScroll()
                let filter = googleService.importCapturedFolder(
                    title: webController.detectedFolderTitle,
                    folderURLString: webController.currentURLString,
                    items: webController.capturedItems
                )
                HapticEngine.shared.fireKeepSnap()
                onFolderImported(filter)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill.badge.play")
                    Text(
                        webController.capturedItems.isEmpty
                            ? "Open a Folder Above to Load Photos"
                            : "Swipe This Folder (\(webController.capturedItems.count) Photos)"
                    )
                    .font(SwipeDeckTypography.roundedHeadline(16, weight: .bold))
                }
                .foregroundStyle(webController.capturedItems.isEmpty ? SwipeDeckTheme.textTertiary : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    webController.capturedItems.isEmpty
                        ? SwipeDeckTheme.surfaceSecondary
                        : SwipeDeckTheme.accentKeep,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(webController.capturedItems.isEmpty)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Bottom Dock: Guided Deletion Assistant Mode

    private var deletionAssistantBottomDock: some View {
        let items = googleService.stagedForDeletionItems
        let safeIndex = min(max(0, deletionIndex), max(0, items.count - 1))

        return VStack(spacing: 10) {
            if items.isEmpty {
                Text("All staged Google Photos items have been cleared!")
                    .font(SwipeDeckTypography.roundedHeadline(14, weight: .semibold))
                    .foregroundStyle(SwipeDeckTheme.accentKeep)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO DELETE IN GOOGLE PHOTOS (\(safeIndex + 1) of \(items.count))")
                            .exifMonoStyle(size: 11, color: SwipeDeckTheme.accentDelete)
                        Text("Tap the Trash icon in Google Photos above, then tap Next Photo")
                            .font(SwipeDeckTypography.body(12))
                            .foregroundStyle(SwipeDeckTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        if deletionIndex > 0 {
                            deletionIndex -= 1
                            openCurrentDeletionItem()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SwipeDeckTheme.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(SwipeDeckTheme.surfaceSecondary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(deletionIndex == 0)

                    Button {
                        let currentID = items[safeIndex].id
                        googleService.removeSingleStagedDeletionItem(id: currentID)
                        if googleService.stagedForDeletionItems.isEmpty {
                            mode = .folderPicker
                        } else {
                            deletionIndex = min(deletionIndex, googleService.stagedForDeletionItems.count - 1)
                            openCurrentDeletionItem()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(safeIndex + 1 < items.count ? "Done • Next Trashed Photo →" : "Finish Last Photo")
                                .font(SwipeDeckTypography.roundedHeadline(14, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(SwipeDeckTheme.accentKeep, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        googleService.clearStagedForDeletionItems()
                        mode = .folderPicker
                    } label: {
                        Text("Clear All")
                            .font(SwipeDeckTypography.roundedHeadline(12, weight: .semibold))
                            .foregroundStyle(SwipeDeckTheme.accentDelete)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(SwipeDeckTheme.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(SwipeDeckTheme.borderSubtle, lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func openCurrentDeletionItem() {
        let items = googleService.stagedForDeletionItems
        guard !items.isEmpty else { return }
        let idx = min(max(0, deletionIndex), items.count - 1)
        if let url = items[idx].productUrl, !url.isEmpty {
            webController.navigate(to: url)
        } else {
            webController.navigate(to: "https://photos.google.com")
        }
    }
}

// MARK: - WKWebView Controller & Live DOM Extractor

@MainActor
@Observable
final class GooglePhotosWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var detectedFolderTitle: String = "Google Photos"
    var currentURLString: String = "https://photos.google.com/albums"
    var capturedItems: [CapturedGooglePhotoItem] = []
    var isAutoScrolling: Bool = false

    fileprivate var webView: WKWebView?
    private var scanTimer: Timer?
    private var autoScrollTimer: Timer?

    override init() {
        super.init()
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        startPeriodicScan()
    }

    func navigate(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        currentURLString = urlString
        webView?.load(URLRequest(url: url))
    }

    func toggleAutoScroll() {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            isAutoScrolling = true
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.webView?.evaluateJavaScript("window.scrollBy({ top: 650, behavior: 'smooth' });", completionHandler: nil)
                    self?.scanCurrentPage()
                }
            }
        }
    }

    func stopAutoScroll() {
        isAutoScrolling = false
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func startPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanCurrentPage()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURLString = webView.url?.absoluteString ?? currentURLString
        Task {
            await GooglePhotosCloudService.shared.syncWebViewCookiesToURLSession()
            scanCurrentPage()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}

    /// Runs a lightweight DOM inspection inside `photos.google.com` to accumulate all visible photos
    /// in the current folder/album into `window.__swipedeckCapturedMap` so virtualized rows aren't lost on scroll.
    private func scanCurrentPage() {
        guard let webView else { return }

        let script = """
        (function() {
            var currentPath = location.pathname;
            if (window.__swipedeckLastPath !== currentPath) {
                window.__swipedeckLastPath = currentPath;
                window.__swipedeckCapturedMap = {};
            }
            if (!window.__swipedeckCapturedMap) {
                window.__swipedeckCapturedMap = {};
            }

            // 1. Detect folder / album title
            var folderTitle = "Google Photos Stream";
            var rawTitle = (document.title || "").replace(/\\s*-\\s*Google Photos$/i, "").trim();
            if (rawTitle && rawTitle.toLowerCase() !== "google photos" && rawTitle.toLowerCase() !== "sign in - google accounts") {
                folderTitle = rawTitle;
            } else {
                var headings = document.querySelectorAll('h1, [role="heading"]');
                for (var h = 0; h < headings.length; h++) {
                    var txt = (headings[h].innerText || "").trim();
                    if (txt && txt.length > 1 && txt.length < 70 && txt.toLowerCase() !== "photos" && txt.toLowerCase() !== "albums") {
                        folderTitle = txt;
                        break;
                    }
                }
                if (currentPath.indexOf("/albums") === 0) {
                    folderTitle = "Google Photos Albums";
                } else if (currentPath.indexOf("/favorites") !== -1) {
                    folderTitle = "Google Photos Favorites";
                }
            }

            function addCandidateUrl(rawUrl, linkEl, w, h) {
                if (!rawUrl || rawUrl.indexOf("googleusercontent.com") === -1) return;
                // Exclude tiny profile avatars
                if (rawUrl.indexOf("/a/") !== -1 || rawUrl.indexOf("/a-/") !== -1) return;
                if (rawUrl.indexOf("=s32") !== -1 || rawUrl.indexOf("=s48") !== -1 || rawUrl.indexOf("=s64") !== -1) return;

                var cleanBase = rawUrl.split("=")[0];
                var idPart = cleanBase.split("/").pop() || cleanBase;
                if (idPart.length < 8) return;

                var productHref = null;
                if (linkEl && linkEl.href) {
                    productHref = linkEl.href;
                }

                // Skip album covers when standing on the top-level /albums index unless inside a specific album
                if (currentPath === "/albums" && productHref && productHref.indexOf("/album/") !== -1 && productHref.indexOf("/photo/") === -1) {
                    return;
                }

                window.__swipedeckCapturedMap[idPart] = {
                    id: idPart,
                    baseUrl: cleanBase,
                    rawImageUrl: rawUrl,
                    productUrl: productHref || location.href,
                    width: Math.max(720, (w || 1080) * 3),
                    height: Math.max(960, (h || 1440) * 3)
                };
            }

            // 2. Scan all <img> elements
            var imgs = document.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) {
                var img = imgs[i];
                var rect = img.getBoundingClientRect();
                if (rect.width < 52 && rect.height < 52) continue;
                var src = img.currentSrc || img.src || "";
                var parentLink = img.closest('a');
                addCandidateUrl(src, parentLink, Math.round(rect.width), Math.round(rect.height));
            }

            // 3. Scan CSS background-image tiles used by Google Photos grid
            var bgNodes = document.querySelectorAll('[style*="googleusercontent.com"]');
            for (var j = 0; j < bgNodes.length; j++) {
                var node = bgNodes[j];
                var rect2 = node.getBoundingClientRect();
                if (rect2.width < 52 && rect2.height < 52) continue;
                var styleStr = node.getAttribute('style') || "";
                var match = styleStr.match(/url\\(["']?(https:\\/\\/[^"')]+googleusercontent\\.com[^"')]+)["']?\\)/);
                if (match && match[1]) {
                    var link2 = node.closest('a');
                    addCandidateUrl(match[1], link2, Math.round(rect2.width), Math.round(rect2.height));
                }
            }

            var itemsList = Object.values(window.__swipedeckCapturedMap);
            return JSON.stringify({
                title: folderTitle,
                url: location.href,
                items: itemsList
            });
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self,
                  let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(ScrapedPagePayload.self, from: data) else {
                return
            }

            self.detectedFolderTitle = payload.title
            self.currentURLString = payload.url
            self.capturedItems = payload.items
        }
    }

    private struct ScrapedPagePayload: Decodable {
        let title: String
        let url: String
        let items: [CapturedGooglePhotoItem]
    }
}

// MARK: - UIViewRepresentable Wrapper

private struct GooglePhotosWebViewRepresentable: UIViewRepresentable {
    let controller: GooglePhotosWebController

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Standard iOS Mobile Safari user-agent so Google Sign-In works smoothly without OAuth client restrictions
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = controller
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 150, right: 0)

        controller.attach(webView: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
