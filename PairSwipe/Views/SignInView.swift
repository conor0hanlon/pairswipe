import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let charcoal = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let slate = Color(red: 0.42, green: 0.47, blue: 0.52)
    static let navy = charcoal
    static let blue = Color(red: 0.16, green: 0.29, blue: 0.48)
    static let teal = Color(red: 0.04, green: 0.49, blue: 0.50)
    static let coral = Color(red: 0.82, green: 0.12, blue: 0.18)
    static let red = coral
    static let orange = Color(red: 0.94, green: 0.62, blue: 0.18)
    static let cyan = teal
    static let paper = Color(red: 0.12, green: 0.15, blue: 0.19)
    static let warmPaper = paper
    static let panel = paper
    static let panelStrong = Color(red: 0.16, green: 0.19, blue: 0.23)
    static let screen = Color(red: 0.10, green: 0.13, blue: 0.17)
    static let secondaryText = Color(red: 0.76, green: 0.79, blue: 0.82)
    static let mutedText = Color(red: 0.60, green: 0.65, blue: 0.70)
    static let line = Color.white.opacity(0.16)
    static let glassStroke = line
    static let glassShadow = Color.black.opacity(0.18)
    static let surfaceShadow = glassShadow
    static let divider = Color.white.opacity(0.13)
    static let amber = orange
    static let mint = teal
    static let green = teal
}

struct AppGradientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.13),
                    Color(red: 0.19, green: 0.18, blue: 0.15),
                    Color(red: 0.08, green: 0.12, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.red)
                    .frame(height: 5)
                Rectangle()
                    .fill(AppTheme.amber)
                    .frame(height: 2)
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let material: Material

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: min(cornerRadius, 8), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: min(cornerRadius, 8), style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: AppTheme.glassShadow, radius: 16, x: 0, y: 10)
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 8,
        padding: CGFloat = 16,
        material: Material = .regularMaterial
    ) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, padding: padding, material: material))
    }
}

struct GlassButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color
    let emphasized: Bool

    init(tint: Color = AppTheme.navy, foreground: Color = .white, emphasized: Bool = true) {
        self.tint = tint
        self.foreground = foreground
        self.emphasized = emphasized
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(emphasized ? foreground : Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(emphasized ? tint.opacity(configuration.isPressed ? 0.78 : 1) : AppTheme.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(emphasized ? Color.white.opacity(0.18) : tint.opacity(0.28), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(label)
    }
}

struct GlassTag: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color = AppTheme.navy) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

struct SectionEyebrow: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(AppTheme.orange)
    }
}

struct PairSwipeLogoView: View {
    let size: CGFloat

    init(size: CGFloat = 92) {
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(AppTheme.coral)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: max(size * 0.035, 2))
                .padding(size * 0.16)

            Rectangle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.72, height: max(size * 0.08, 4))
                .offset(y: -size * 0.24)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.25, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.ink.opacity(0.22), radius: 18, x: 0, y: 10)
    }
}

struct SignInView: View {
    @State private var isSigningIn = false
    @State private var signInError: String?

    var body: some View {
        ZStack {
            AppGradientBackground()

            VStack(spacing: 24) {
                Spacer()

                PairSwipeLogoView(size: 96)

                VStack(spacing: 10) {
                    Text("PAIRSWIPE")
                        .font(.caption.weight(.black))
                        .tracking(2)
                        .foregroundStyle(AppTheme.orange)

                    Text("Decide tonight's watch")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Two private yes/no passes. One shared shortlist.")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Label("Same list", systemImage: "rectangle.stack.fill")
                        Label("Stream-ready", systemImage: "play.tv.fill")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)

                    Text("Sign in privately, pair with your partner, and keep only titles you both chose. Ratings and watch options are pulled in when you need details.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    if let signInError {
                        Text(signInError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.orange)
                            .multilineTextAlignment(.leading)
                    }

                    Button(action: signIn) {
                        HStack(spacing: 10) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSigningIn ? "Setting things up..." : "Continue")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.navy))
                    .disabled(isSigningIn)
                }
                .glassSurface(cornerRadius: 8, padding: 20, material: .regularMaterial)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    // Signs in privately and displays a useful retry message if the network fails.
    private func signIn() {
        isSigningIn = true
        signInError = nil
        AuthService.shared.signInAnonymously { error in
            isSigningIn = false
            if error != nil {
                signInError = "PairSwipe could not connect. Check your internet connection and try again."
            }
        }
    }
}
