import SwiftUI

struct ContentView: View {
    @ObservedObject var musicService: MusicService
    
    var body: some View {
        ZStack {
            // MARK: - Playback WebView (Kaset-style backgrounding)
            // We keep it visible to the system behind our glass UI
            // to prevent throttle/muting, but out of hit-testing range.
            WebViewContainer(webView: musicService.webView)
                .frame(width: 340, height: 510)
                .allowsHitTesting(false)
            
            if musicService.isAuthenticated {
                PlayerView(musicService: musicService)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            } else {
                OnboardingView(musicService: musicService)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: musicService.isAuthenticated)
        .ignoresSafeArea()
    }
}
