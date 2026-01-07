import SwiftUI
import WebKit

struct PlayerView: View {
    @ObservedObject var musicService: MusicService
    @State private var selectedTab: Int = 0
    @State private var searchText: String = ""
    @State private var isSeeking: Bool = false
    @State private var seekTime: Double = 0
    
    // Fixed dimensions
    private let windowWidth: CGFloat = 340
    private let windowHeight: CGFloat = 510
    private let headerHeight: CGFloat = 48
    private var contentHeight: CGFloat { windowHeight - headerHeight }
    
    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Background (Absolute Fill)
            backgroundView
                .frame(width: windowWidth, height: windowHeight)
                .ignoresSafeArea()
                .clipped()
            
            // MARK: - Audio Engine Keep-Alive (1x1 Pixel)
            // Kaset Logic: Must be at least 1x1 to keep the renderer/audio active
            WebViewWrapper(webView: musicService.webView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // MARK: - Header (Pinned & Solid)
                headerView
                    .frame(height: headerHeight)
                    .background(.ultraThinMaterial)
                    .overlay(
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(.white.opacity(0.1))
                                .frame(height: 0.5)
                        }
                    )
                
                // MARK: - Content Area
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1)) // Subtle tint to differentiate content
            }
            .ignoresSafeArea()
            
            // MARK: - Loading Overlay
            if musicService.isInitializing {
                loadingOverlay
            }
        } // End ZStack
        .frame(width: windowWidth, height: windowHeight)
        .background(Color.black) // Fallback
        .ignoresSafeArea()
        .clipped()
    }

    
    // MARK: - Background
    
    private var backgroundView: some View {
        ZStack {
            // Dynamic blur from artwork
            if let artworkURL = musicService.trackInfo.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: windowWidth + 40, height: windowHeight + 40) // More overfill
                            .blur(radius: 60)
                            .overlay(Color.black.opacity(0.45))
                    } else {
                        Color(white: 0.1)
                    }
                }
            } else {
                LinearGradient(
                    colors: [Color(white: 0.2), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            
            // Glass overlay
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Menu button
            Menu {
                Button("Sign Out") { musicService.signOut() }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36, height: 36)
            
            Spacer()
            
            // Tab picker
            HStack(spacing: 16) {
                TabButton(icon: "music.note", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(icon: "list.bullet", isSelected: selectedTab == 1) { selectedTab = 1 }
                TabButton(icon: "magnifyingglass", isSelected: selectedTab == 2) { selectedTab = 2 }
                TabButton(icon: "books.vertical", isSelected: selectedTab == 3) {
                    selectedTab = 3
                    musicService.fetchLibrary()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            
            Spacer()
            
            // Dummy frame to balance the menu button on the left
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            NowPlayingView(musicService: musicService, isSeeking: $isSeeking, seekTime: $seekTime)
                .transition(.opacity)
        case 1:
            QueueView(musicService: musicService)
                .transition(.opacity)
        case 2:
            SearchView(musicService: musicService, searchText: $searchText)
                .transition(.opacity)
        case 3:
            LibraryView(musicService: musicService)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.5))
            
            VStack(spacing: 24) {
                // Animated music icon
                Image(systemName: "music.note")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .pulseAnimationEffect()
                
                VStack(spacing: 8) {
                    Text("SoundBite")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Connecting...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                    .tint(.white)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: musicService.isInitializing)
    }
}


// MARK: - Components

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(), value: isSelected)
    }
}

struct LoadingView: View {
    @State private var animate = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 3, height: animate ? CGFloat.random(in: 8...20) : 6)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.1),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

struct NowPlayingView: View {
    @ObservedObject var musicService: MusicService
    @Binding var isSeeking: Bool
    @Binding var seekTime: Double
    
    // Fixed heights for stable layout
    private let artworkSize: CGFloat = 210
    private let infoHeight: CGFloat = 50
    private let seekBarHeight: CGFloat = 50
    private let controlsHeight: CGFloat = 80
    private let topPadding: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            // Top spacing
            Color.clear.frame(height: topPadding)
            
            // Artwork
            artworkView
                .frame(width: artworkSize, height: artworkSize)
                .frame(maxWidth: .infinity)
            
            // Spacing
            Color.clear.frame(height: 18)
            
            // Track Info
            trackInfoView
                .frame(height: infoHeight)
                .frame(maxWidth: .infinity)
            
            
            // Spacing
            Color.clear.frame(height: 10)
            
            // Seek Bar
            seekBarView
                .frame(height: seekBarHeight)
                .padding(.horizontal, 22)
            
            // Flexible space pushes controls to bottom
            Spacer(minLength: 8)
            
            // Controls
            controlsView
                .frame(height: controlsHeight)
            
            // Bottom buffer
            Color.clear.frame(height: 12)
        }
    }
    
    // MARK: - Subviews
    
    private var artworkView: some View {
        ZStack {
            // Always show the same container
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
            
            // Overlay with actual image or placeholder
            if let artwork = musicService.trackInfo.artworkURL {
                AsyncImage(url: artwork) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        // Loading state
                        Image(systemName: "music.note")
                            .font(.system(size: 50))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            } else {
                // No URL - show loading
                LoadingView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var trackInfoView: some View {
        VStack(spacing: 4) {
            // Title - always show something
            Text(musicService.trackInfo.title == "Waiting for music..." ? "Loading..." : musicService.trackInfo.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(musicService.trackInfo.title == "Waiting for music..." ? .secondary : .primary)
            
            // Artist - always show something
            Text(musicService.trackInfo.artist.isEmpty ? "—" : musicService.trackInfo.artist)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
    }
    
    private var seekBarView: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekTime : musicService.currentTime },
                    set: { isSeeking = true; seekTime = $0 }
                ),
                in: 0...max(1, musicService.duration),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { musicService.seek(to: seekTime) }
                }
            )
            .accentColor(.white)
            .controlSize(.small)
            
            HStack {
                Text(formatTime(isSeeking ? seekTime : musicService.currentTime))
                Spacer()
                Text(formatTime(musicService.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 36) {
            ControlButton(icon: "backward.fill", size: 22) { musicService.previousTrack() }
                .opacity(musicService.canGoPrevious ? 1 : 0.3)
            
            Button(action: musicService.togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                    
                    Image(systemName: musicService.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            
            ControlButton(icon: "forward.fill", size: 22) { musicService.nextTrack() }
                .opacity(musicService.canGoNext ? 1 : 0.3)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }
}


struct QueueView: View {
    @ObservedObject var musicService: MusicService
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Up Next")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.horizontal)
                .padding(.top)
            
            if musicService.queue.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Queue empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(musicService.queue) { item in
                            Button(action: { musicService.playQueueItem(id: item.id) }) {
                                HStack(spacing: 12) {
                                    AsyncImage(url: item.artworkURL) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else { Color.white.opacity(0.1) }
                                    }
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)
                                        Text(item.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle()) // Make full row tappable
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

struct SearchView: View {
    @ObservedObject var musicService: MusicService
    @Binding var searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search songs, artists...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit { musicService.performSearch(searchText) }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 20)
            
            if musicService.isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                Spacer() // Keep search bar at top
            } else if !musicService.searchResults.isEmpty {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(musicService.searchResults) { result in
                            Button(action: { musicService.playTrack(id: result.id) }) {
                                HStack(spacing: 12) {
                                    AsyncImage(url: result.artworkURL) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else { Color.gray.opacity(0.3) }
                                    }
                                    .frame(width: 48, height: 48)
                                    .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                            .foregroundStyle(.white)
                                        Text(result.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .font(.title3)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Search YouTube Music")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .shadow(radius: 5)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func pulseAnimationEffect() -> some View {
        self.modifier(PulseEffect())
    }
}

struct PulseEffect: ViewModifier {
    @State private var animate = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.1 : 0.9)
            .opacity(animate ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
    }
}

struct LibraryView: View {
    @ObservedObject var musicService: MusicService
    @State private var selectedPlaylist: PlaylistItem?
    
    var columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 0) { // Zero spacing to allow header integration
            if let playlist = selectedPlaylist {
                PlaylistDetailView(musicService: musicService, playlist: playlist, onBack: {
                    selectedPlaylist = nil
                })
                .transition(.move(edge: .trailing))
            } else {
                VStack(spacing: 16) {
                    Text("Library")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.top)
                    
                    if musicService.isLoading && musicService.libraryPlaylists.isEmpty {
                        ProgressView()
                        Spacer()
                    } else if musicService.libraryPlaylists.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "books.vertical")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No playlists found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if !musicService.isAuthenticated {
                                 Text("Sign in to see your library")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 4)
                            }
                            Spacer()
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(musicService.libraryPlaylists) { item in
                                    Button(action: {
                                        selectedPlaylist = item
                                        musicService.fetchPlaylistDetails(id: item.id)
                                    }) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            AsyncImage(url: item.artworkURL) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Color.white.opacity(0.1)
                                                }
                                            }
                                            .frame(height: 120)
                                            .cornerRadius(8)
                                            .clipped()
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .lineLimit(1)
                                                Text(item.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedPlaylist)
    }
}

struct PlaylistDetailView: View {
    @ObservedObject var musicService: MusicService
    let playlist: PlaylistItem
    let onBack: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                
                Spacer()
                Text(playlist.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                
                // Play Button
                Button(action: { musicService.playPlaylist(id: playlist.id) }) {
                     Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
            .background(Color.black.opacity(0.2))
            
            if musicService.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(musicService.playlistDetails) { track in
                            Button(action: { musicService.playTrack(id: track.id) }) {
                                HStack(spacing: 12) {
                                    Text("\(musicService.playlistDetails.firstIndex(where: {$0.id == track.id})! + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    
                                    AsyncImage(url: track.artworkURL) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else { Color.gray.opacity(0.3) }
                                    }
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.001))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let webView: WKWebView
    
    func makeNSView(context: Context) -> WKWebView {
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
