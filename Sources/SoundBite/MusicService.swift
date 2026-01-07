import Foundation
import WebKit
import Combine
import SwiftUI
import os

// MARK: - Playback State
enum PlaybackState {
    case playing
    case paused
    case unknown
}

// MARK: - Track Info
struct TrackInfo: Equatable, Codable {
    var title: String = "Waiting for music..."
    var artist: String = ""
    var artworkURL: URL? = nil
}

struct SearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

struct QueueItem: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

struct PlaylistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
}

// MARK: - Music Service
@MainActor
class MusicService: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
    
    // Public State
    @Published var trackInfo: TrackInfo = TrackInfo()
    @Published var playbackState: PlaybackState = .unknown
    @Published var isLoading: Bool = true
    @Published var isInitializing: Bool = true
    @Published var canGoNext: Bool = false
    @Published var canGoPrevious: Bool = false
    @Published var searchResults: [SearchResult] = []
    @Published var libraryPlaylists: [PlaylistItem] = []
    @Published var playlistDetails: [SearchResult] = [] // For detail view
    @Published var isSearching: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var showLoginSheet: Bool = false
    
    // Time & Queue
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var queue: [QueueItem] = []
    
    // Debug
    
    // Internal State
    public var currentPlaylistId: String? = nil
    
    // Internal
    public let webView: WKWebView
    private var browserWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    private let logger = Logger(subsystem: "com.soundbite.app", category: "MusicService")
    private var metadataTimer: Timer?
    private var lastCommandTime: Date = .distantPast
    
    // API Service
    private var innertubeService: InnertubeService?
    
    // Helper for JS Injection
    private struct JSScript {
        static let playPause = """
            (function() {
                if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();
                const btn = document.querySelector('#play-pause-button') || 
                            document.querySelector('.play-pause-button.ytmusic-player-bar') ||
                            document.querySelector('ytmusic-player-bar .play-pause-button');
                if (btn) { btn.click(); return 'clicked'; }
                const video = document.querySelector('video');
                if (video) { 
                    if (video.paused) video.play(); 
                    else video.pause(); 
                    return 'video-toggled';
                }
                return 'not-found';
            })();
        """
        
        static let next = "document.querySelector('.next-button.ytmusic-player-bar')?.click();"
        static let previous = "document.querySelector('.previous-button.ytmusic-player-bar')?.click();"
        
        static let observer = """
            (function() {
                if (window.soundbiteObserverInstalled) return;
                window.soundbiteObserverInstalled = true;
                
                function post(type, data) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.soundbiteBridge) {
                        window.webkit.messageHandlers.soundbiteBridge.postMessage({ type: type, ...data });
                    }
                }
                
                function scrapeMetadata() {
                   var title = '', artist = '', img = '';
                   
                   if (navigator.mediaSession && navigator.mediaSession.metadata) {
                       title = navigator.mediaSession.metadata.title || '';
                       artist = navigator.mediaSession.metadata.artist || '';
                       if (navigator.mediaSession.metadata.artwork && navigator.mediaSession.metadata.artwork.length > 0) {
                          let list = navigator.mediaSession.metadata.artwork;
                          img = list[list.length - 1].src;
                       }
                   }
                   
                   // Fallback
                   if (!title) {
                        let el = document.querySelector('ytmusic-player-bar .title') || document.querySelector('ytmusic-player-bar .title-column');
                        if (el) title = el.innerText || el.textContent || '';
                   }
                   if (!artist) {
                        let el = document.querySelector('ytmusic-player-bar .byline') || document.querySelector('ytmusic-player-bar .subtitle');
                        if (el) artist = el.innerText || el.textContent || '';
                   }
                   if (!img) {
                        let el = document.querySelector('ytmusic-player-bar .image');
                        if (el) img = el.src || '';
                   }
                   
                   // New Fallback: Document Title
                   if (!title && document.title) {
                        title = document.title;
                        artist = ""; // Clean fallback
                   }
                   
                   // Upgrade Image Res
                   if (img) {
                       // Replace sizing params like w60-h60-l90-rj to higher res
                       // Common pattern: =w544-h544-l90-rj
                       if (img.indexOf('w60-h60') > -1) {
                           img = img.replace('w60-h60', 'w544-h544');
                       } else if (img.indexOf('w120-h120') > -1) {
                           img = img.replace('w120-h120', 'w544-h544');
                       } else if (img.indexOf('s60') > -1 || img.indexOf('s120') > -1) {
                           // sometimes it is s60-something
                           img = img.replace(/s[0-9]+-(c|p)?/, 's544-');
                       }
                   }
                   
                   const nextBtn = document.querySelector('.next-button.ytmusic-player-bar');
                   const prevBtn = document.querySelector('.previous-button.ytmusic-player-bar');
                   
                   const params = new URLSearchParams(window.location.search);
                   let videoId = params.get('v');
                   let playlistId = params.get('list') || '';
                   
                   // Try attribute if URL missing
                   if (!videoId) {
                        let p = document.querySelector('ytmusic-player');
                        if (p && p.getAttribute('video-id')) videoId = p.getAttribute('video-id');
                   }
                   videoId = videoId || '';
                   
                   // Force state sync
                   const video = document.querySelector('video');
                   const isPaused = video ? video.paused : true;
                   
                   post('metadata', {
                       title: title,
                       artist: artist,
                       artwork: img,
                       canNext: nextBtn ? !nextBtn.disabled : false,
                       canPrev: prevBtn ? !prevBtn.disabled : false,
                       videoId: videoId,
                       playlistId: playlistId,
                       isPaused: isPaused
                   });
                   
                   // Also send explicit state update to ensure sync
                   post('state', { isPaused: isPaused });
                }
                
                function attachVideoListener() {
                    const video = document.querySelector('video');
                    if (!video) return;
                    
                    if (video._soundbiteAttached) return;
                    video._soundbiteAttached = true;
                    
                    video.addEventListener('play', () => { 
                        scrapeMetadata(); 
                        post('state', { isPaused: false }); 
                        if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();
                    });
                    video.addEventListener('pause', () => { post('state', { isPaused: true }); });
                    video.addEventListener('loadeddata', () => scrapeMetadata());
                    video.addEventListener('timeupdate', () => {
                        post('time', { currentTime: video.currentTime, duration: video.duration });
                    });
                }
                
                // Volume Enforcement Logic (Ported from Kaset)
                let volumeEnforcementTimeout = null;
                let isEnforcingVolume = false;

                function setupVideoListeners() {
                    function attachVideoListeners() {
                        const video = document.querySelector('video');
                        if (!video) {
                            setTimeout(attachVideoListeners, 500);
                            return;
                        }

                        if (video._soundbiteListenersAttached) return;
                        video._soundbiteListenersAttached = true;

                        // Volume Police: Revert unauthorized changes
                        video.addEventListener('volumechange', () => {
                            if (isEnforcingVolume) return;
                            
                            // Check if specific target volume is set
                            if (typeof window.soundbiteTargetVolume === 'number') {
                                // Allow small float diffs
                                if (Math.abs(video.volume - window.soundbiteTargetVolume) > 0.01) {
                                    isEnforcingVolume = true;
                                    console.log('SoundBite: Detecting unauthorized volume change, reverting to ' + window.soundbiteTargetVolume);
                                    
                                    // 1. Revert HTML5 Video
                                    video.volume = window.soundbiteTargetVolume;
                                    video.muted = false;
                                    
                                    // 2. Revert YTM Internal API
                                    const player = document.querySelector('ytmusic-player');
                                    if (player && player.playerApi) {
                                        player.playerApi.setVolume(Math.round(window.soundbiteTargetVolume * 100));
                                    }
                                    
                                    // 3. Revert Legacy API
                                    const moviePlayer = document.getElementById('movie_player');
                                    if (moviePlayer && moviePlayer.setVolume) {
                                        moviePlayer.setVolume(Math.round(window.soundbiteTargetVolume * 100));
                                    }
                                    
                                    setTimeout(() => { isEnforcingVolume = false; }, 50);
                                }
                            } else {
                                // Default fallback: just ensure not muted if we think we should be playing
                                if (video.muted) video.muted = false;
                            }
                        });
                        
                        // Force initial sync
                        if (typeof window.soundbiteTargetVolume === 'number') {
                             video.volume = window.soundbiteTargetVolume;
                             video.muted = false;
                        }

                        video.addEventListener('play', () => { 
                            scrapeMetadata(); 
                            post('state', { isPaused: false }); 
                            if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();
                        });
                        video.addEventListener('pause', () => { post('state', { isPaused: true }); });
                        video.addEventListener('loadeddata', () => scrapeMetadata());
                        video.addEventListener('timeupdate', () => {
                            post('time', { currentTime: video.currentTime, duration: video.duration });
                        });
                    }
                    attachVideoListeners();
                    
                    // Watch for video replacement
                    const observer = new MutationObserver(() => {
                         const video = document.querySelector('video');
                         if (video && !video._soundbiteListenersAttached) {
                             attachVideoListeners();
                         }
                    });
                    observer.observe(document.body, { childList: true, subtree: true });
                }

                // Initial Setup
                setTimeout(() => {
                    scrapeMetadata();
                    setupVideoListeners();
                }, 1000);
                
                // Export
                window.scrapeMetadata = scrapeMetadata;

                // Resume Audio Context on interaction
                const soundbiteResumeAudio = () => {
                   const v = document.querySelector('video');
                   if (v) {
                       v.muted = false;
                       if (v.volume === 0) v.volume = 1.0;
                       
                       try {
                           const moviePlayer = document.getElementById('movie_player');
                           if (moviePlayer && moviePlayer.setVolume) moviePlayer.setVolume(100);
                           const player = document.querySelector('ytmusic-player');
                           if (player && player.playerApi) player.playerApi.setVolume(100);
                       } catch(e) {}
                   }
                   if (window.AudioContext || window.webkitAudioContext) {
                       try {
                          const ctx = new (window.AudioContext || window.webkitAudioContext)();
                          if (ctx.state === 'suspended') ctx.resume();
                       } catch(e) {}
                   }
                };
                window.addEventListener('click', soundbiteResumeAudio, { once: true });
                window.soundbiteResumeAudio = soundbiteResumeAudio;

                // Add a universal click listener to confirm interaction to Swift
                window.addEventListener('click', () => {
                    window.webkit.messageHandlers.soundbiteBridge.postMessage({ type: 'INTERACTION_CONFIRMED' });
                }, { once: true });
            })();
        """
    }

    override init() {
        // Configure WebView for media playback
        let config = WKWebViewConfiguration()
        
        // Use default persistent data store for session reliability (matches Kaset)
        config.websiteDataStore = .default()
        
        // Add Bridge BEFORE initializing WebView
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        // Media setup
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        
        // Inject observer script (at document end)
        let script = WKUserScript(
            source: JSScript.observer,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        
        
        // Use modern macOS Safari User Agent (Matches Kaset exactly)
        // This ensures YouTube Music serves the correct player version and doesn't restrict playback
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView.allowsBackForwardNavigationGestures = true
        
        // Allow content JS
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        super.init()
        
        // Register Self with the Controller
        contentController.add(self, name: "soundbiteBridge")
        
        self.webView.navigationDelegate = self
        config.websiteDataStore.httpCookieStore.add(self)
        self.innertubeService = InnertubeService(dataStore: self.webView.configuration.websiteDataStore)
        
        // Check for existing session
        self.checkLoginStatus()
        
        // Restore state or load default
        if let savedURL = UserDefaults.standard.url(forKey: "lastPlayedURL") {
            self.webView.load(URLRequest(url: savedURL))
        } else {
            self.loadMusic()
        }
        
    }
    
    func loadMusic() {
        // Hard reset: navigate to about:blank first to clear engine state
        self.webView.load(URLRequest(url: URL(string: "about:blank")!))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let request = URLRequest(url: URL(string: "https://music.youtube.com")!)
            self?.webView.load(request)
            
            // Re-inject audio context poke after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self?.evaluate(script: "if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();")
            }
            
        }
    }
    
    func saveState() {
        if let url = webView.url {
            UserDefaults.standard.set(url, forKey: "lastPlayedURL")
        }
    }
    
    func startLogin() {
        guard let url = URL(string: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F") else { return }
        let request = URLRequest(url: url)
        self.webView.load(request)
        self.showLoginSheet = true
    }
    
    func checkLoginStatus() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            // Look for Google Auth cookies (SAPISID, SSID, or HSID)
            let isAuth = cookies.contains { cookie in
                return (cookie.name == "SAPISID" || cookie.name == "SSID") && cookie.domain.contains("youtube.com")
            }
            
            DispatchQueue.main.async {
                // Only update if changed to avoid loops, but ensure we catch the transition
                if self?.isAuthenticated != isAuth {
                    self?.isAuthenticated = isAuth
                    if isAuth {
                        withAnimation {
                            self?.showLoginSheet = false
                        }
                        self?.logger.info("User Authenticated!")
                        
                        // FIX: Ensure the webview is "awakened" after login.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if let url = self?.webView.url, !url.absoluteString.contains("music.youtube.com") {
                                self?.webView.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
                            } else {
                                // Already on site, poke it hard.
                                self?.evaluate(script: "if (window.scrapeMetadata) window.scrapeMetadata();")
                                self?.evaluate(script: "if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();")
                                self?.evaluate(script: "const v = document.querySelector('video'); if (v) { v.muted = false; v.volume = 1.0; }")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        checkLoginStatus()
    }
    
    func signOut() {
        // Clear cookies
        let store = WKWebsiteDataStore.default()
        store.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { store.httpCookieStore.delete($0) }
        }
        // Clear storage
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                 DispatchQueue.main.async {
                     self.isAuthenticated = false
                     self.trackInfo = TrackInfo()
                     self.loadMusic() // Reload to show login page if needed
                 }
            }
        }
    }
    
    func hardReset() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                DispatchQueue.main.async {
                    self.isAuthenticated = false
                    self.trackInfo = TrackInfo()
                    self.loadMusic()
                }
            }
        }
    }
    
    // MARK: - Controls
    
    func togglePlayPause() {
        self.lastCommandTime = Date()
        // Optimistic update to match our guard logic
        let wasPlaying = (playbackState == .playing)
        self.playbackState = wasPlaying ? .paused : .playing
        evaluate(script: JSScript.playPause)
    }
    
    func nextTrack() {
        self.lastCommandTime = Date()
        evaluate(script: JSScript.next)
    }
    
    func previousTrack() {
        self.lastCommandTime = Date()
        evaluate(script: JSScript.previous)
    }
    func seek(to time: Double) {
        let script = "document.querySelector('video').currentTime = \(time);"
        evaluate(script: script)
    }
    
    func performSearch(_ query: String) {
        self.isSearching = true
        self.searchResults = []
        
        Task {
            do {
                if let results = try await self.innertubeService?.search(query: query) {
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                    }
                }
            } catch {
                self.logger.error("Search failed: \(error.localizedDescription)")
                await MainActor.run { self.isSearching = false }
            }
        }
    }
    
    func playTrack(id: String) {
        let urlStr = "https://music.youtube.com/watch?v=\(id)"
        if let url = URL(string: urlStr) {
            self.webView.load(URLRequest(url: url))
            // Do not clear search results so user can go back
            self.isSearching = false
            // Note: We don't manually set isLoading = true here because didStartProvisionalNavigation isn't hooked up to global isLoading
            // to avoid flickering. The UI will just transition naturally.
        }
    }
    
    func playQueueItem(id: String) {
        // Try to maintain playlist context
        if let listId = currentPlaylistId, !listId.isEmpty {
             let script = "window.location.href = 'https://music.youtube.com/watch?v=\(id)&list=\(listId)';"
             evaluate(script: script)
        } else {
             playTrack(id: id)
        }
    }

    func fetchLibrary() {
        self.isLoading = true
        Task {
            do {
                if let items = try await self.innertubeService?.getLibraryPlaylists() {
                    await MainActor.run {
                        self.libraryPlaylists = items
                        self.isLoading = false
                    }
                }
            } catch {
                self.logger.error("Library fetch failed: \(error.localizedDescription)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    func playPlaylist(id: String) {
        // Use /watch?list=... to start playback immediately
        let urlStr = "https://music.youtube.com/watch?list=\(id)"
        if let url = URL(string: urlStr) {
            self.webView.load(URLRequest(url: url))
        }
    }
    
    func fetchPlaylistDetails(id: String) {
        self.isLoading = true
        self.playlistDetails = []
        Task {
            do {
                if let tracks = try await self.innertubeService?.getPlaylist(id: id) {
                    await MainActor.run {
                        self.playlistDetails = tracks
                        self.isLoading = false
                    }
                }
            } catch {
                self.logger.error("Playlist detail fetch failed: \(error.localizedDescription)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    // Call this periodically or on track change
    func fetchQueue(videoId: String?, playlistId: String? = nil) {
        guard let vid = videoId, !vid.isEmpty else { return }
        logger.info("Fetching queue for videoId: \(vid), playlistId: \(playlistId ?? "nil")")
        
        Task {
            do {
                if let q = try await self.innertubeService?.getQueue(videoId: vid, playlistId: playlistId) {
                    await MainActor.run {
                        self.queue = q
                        // If queue is empty, log warning
                        if q.isEmpty { self.logger.warning("Fetched queue is empty") }
                    }
                }
            } catch {
                self.logger.error("Queue fetch failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func scrapeLibrary() {
       // Removed in favor of InnertubeService
    }
    
    private func scrapeSearchResults() {
        // Removed in favor of InnertubeService
    }
    
    // MARK: - Internal Logic
    
    private func evaluate(script: String) {
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                self?.logger.error("JS Error: \(error.localizedDescription)")
            }
        }
    }
    
    // Visibility Check
    var isUIVisible: (() -> Bool)?
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "soundbiteBridge", let body = message.body as? [String: Any] else { 
            logger.warning("Received invalid bridge message: \(message.name)")
            return 
        }
        
        guard let type = body["type"] as? String else { return }
        logger.debug("Bridge event: \(type)")
        
        switch type {
        case "metadata":
            handleMetadata(body)
        case "time":
            handleTime(body)
        case "state":
            handleState(body)
        default:
            break
        }
    }
    
    // MARK: - Handlers
    
    private func handleMetadata(_ data: [String: Any]) {
        let title = data["title"] as? String ?? ""
        let artist = data["artist"] as? String ?? ""
        let artworkStr = data["artwork"] as? String ?? ""
        let videoId = data["videoId"] as? String ?? ""
        let playlistId = data["playlistId"] as? String ?? ""
        
        // Track current playlist context
        if !playlistId.isEmpty {
            self.currentPlaylistId = playlistId
        }
        
        // Update Track Info
        if title != self.trackInfo.title || artist != self.trackInfo.artist {
            // Valid title check
            if !title.isEmpty && title != "Waiting for music..." {
                let artworkURL = URL(string: artworkStr)
                
                DispatchQueue.main.async {
                    self.trackInfo = TrackInfo(title: title, artist: artist, artworkURL: artworkURL)
                    
                    // If we still have the default loading text, change it to something friendly
                    if self.trackInfo.title == "Waiting for music..." {
                        self.trackInfo = TrackInfo(title: "SoundBite", artist: "Ready")
                    }
                    // Fetch Queue Immediately on song change
                    if !videoId.isEmpty {
                        self.fetchQueue(videoId: videoId, playlistId: playlistId.isEmpty ? nil : playlistId)
                    }
                    
                    // Once we have valid metadata, we are definitely initialized
                    self.isInitializing = false
                }
            }
        }
        
        // Update Buttons
        DispatchQueue.main.async {
             self.canGoNext = data["canNext"] as? Bool ?? false
             self.canGoPrevious = data["canPrev"] as? Bool ?? false
        }
    }
    
    private func handleTime(_ data: [String: Any]) {
        let cur = data["currentTime"] as? Double ?? 0
        let dur = data["duration"] as? Double ?? 1
        
        // Update UI only if changed significantly or playing
        if abs(cur - self.currentTime) > 0.5 || abs(dur - self.duration) > 1 {
            DispatchQueue.main.async {
                self.currentTime = cur
                self.duration = max(1, dur)
            }
        }
    }
    
    private func handleState(_ data: [String: Any]) {
        let isPaused = data["isPaused"] as? Bool ?? true
        let newState: PlaybackState = isPaused ? .paused : .playing
        
        // If we just sent a command, ignore any state that is DIFFERENT from our currently set state
        // for a brief period. This prevents the "back-and-forth" flicker from stale observer pokes.
        if Date().timeIntervalSince(lastCommandTime) < 0.8 {
            if newState != self.playbackState {
                return 
            }
        }
        
        DispatchQueue.main.async {
            if newState == .playing && self.playbackState != .playing {
                // Slight delay to allow pure-JS player to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.pumpVolume()
                }
            }
            self.playbackState = newState
        }
    }
    
    private func pumpVolume() {
        // Enforce max volume and set target for the police
        evaluate(script: """
            window.soundbiteTargetVolume = 1.0;
            const v = document.querySelector('video');
            if (v) {
                 v.muted = false;
                 v.volume = 1.0;
            }
            // Also poke internal APIs
            const player = document.querySelector('ytmusic-player');
            if (player && player.playerApi) player.playerApi.setVolume(100);
            
            const moviePlayer = document.getElementById('movie_player');
            if (moviePlayer && moviePlayer.setVolume) moviePlayer.setVolume(100);
        """)
        evaluate(script: "if (window.soundbiteResumeAudio) window.soundbiteResumeAudio();")
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoading = false
        self.logger.info("WebView finished loading")
        
        self.checkLoginStatus()
        
        // Immediately set target volume so the Police know what to enforce when video appears
        self.evaluate(script: "window.soundbiteTargetVolume = 1.0;")
        
        // Force a scrape to update the UI (title, artist, etc.) in case we missed a state event
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.evaluate(script: "if (window.scrapeMetadata) window.scrapeMetadata();")
            self.pumpVolume()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
        self.logger.error("WebView failed loading: \(error.localizedDescription)")
    }
}
