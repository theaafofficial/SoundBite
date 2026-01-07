import SwiftUI
import WebKit

struct OnboardingView: View {
    @ObservedObject var musicService: MusicService
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // MARK: - Animated Background
            LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.2), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .hueRotation(.degrees(animateGradient ? 45 : 0))
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animateGradient)
                .onAppear { animateGradient = true }
                .ignoresSafeArea()
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // MARK: - Logo Section
                ZStack {
                    Circle()
                        .fill(.purple.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)
                        .pulseAnimationEffect()
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(.linearGradient(colors: [.white, .white.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                
                VStack(spacing: 12) {
                    Text("SoundBite")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("The premium native experience for\nYouTube Music.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // MARK: - Connect Button
                Button(action: {
                    musicService.startLogin()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                        Text("Connect with Google")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 240, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                
                Text("Securely sign in to access your library and playlists.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 340, height: 510) // Match PlayerView dimensions
        .sheet(isPresented: $musicService.showLoginSheet) {
            LoginSheetView(musicService: musicService)
        }
    }
}

// MARK: - Login Sheet
struct LoginSheetView: View {
    @ObservedObject var musicService: MusicService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Native Header
            HStack {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                
                Spacer()
                
                Text("Sign In to YouTube Music")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                
                Spacer()
                
                // Balance the leading button
                if musicService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 16)
                } else {
                    Color.clear.frame(width: 60)
                }
            }
            .frame(height: 54)
            .background(.ultraThinMaterial)
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 0.5)
                }
            )
            
            // MARK: - Web Content
            ZStack {
                Color.white // Ensure white background for the webview content
                
                WebViewContainer(webView: musicService.webView)
                    .clipShape(Rectangle())
                
                if musicService.isLoading {
                    ZStack {
                        Color.white
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.gray)
                            Text("Loading Google Sign In...")
                                .font(.system(size: 13))
                                .foregroundStyle(.gray)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(width: 850, height: 650) // Slightly larger for better readability
        .preferredColorScheme(.light) // Google login is mostly light
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure webView is in this container's hierarchy
        if webView.superview != nsView {
            webView.removeFromSuperview()
            nsView.addSubview(webView)
            
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: nsView.topAnchor),
                webView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor)
            ])
        }
    }
}
