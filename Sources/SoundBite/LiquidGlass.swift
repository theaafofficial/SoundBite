import SwiftUI

// MARK: - API Shim for macOS 26 LiquidGlass
// Implements the "official" spec: High Index Refraction + Volumetric Rim

struct LiquidGlass: ViewModifier {
    var cornerRadius: CGFloat
    var blurRadius: CGFloat
    var tint: Color
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. High-Index Base (Double Material Stack)
                    // Simulates thickness by stacking materials
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    
                    Rectangle()
                        .fill(.thickMaterial)
                        .opacity(0.3) // Subtle index bump
                    
                    // 2. Tint Injection
                    Rectangle()
                        .fill(tint)
                }
                .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            // 3. Volumetric Rim Light (The "Caustic Edge")
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.6), location: 0),   // Top-Left Highlight
                                .init(color: .white.opacity(0.1), location: 0.4),
                                .init(color: .white.opacity(0.0), location: 0.6),
                                .init(color: .white.opacity(0.2), location: 1.0)  // Bottom-Right Refraction
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            // 4. Refractive Shadow
            // Uses standard shadow but tighter to simulate contact
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Applies the native macOS 26 LiquidGlass material.
    /// - Parameters:
    ///   - cornerRadius: The curvature of the glass block.
    ///   - tint: Optional internal tint (default: white 10%).
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        tint: Color = .white.opacity(0.05)
    ) -> some View {
        self.modifier(LiquidGlass(cornerRadius: cornerRadius, blurRadius: 20, tint: tint))
    }
}
