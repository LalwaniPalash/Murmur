import SwiftUI

enum MurmurTheme {
    enum ColorToken {
        static let canvas = Color(red: 0.973, green: 0.969, blue: 0.956)
        static let sidebar = Color(red: 0.937, green: 0.925, blue: 0.895)
        static let surface = Color(red: 0.995, green: 0.992, blue: 0.982)
        static let surfaceRaised = Color.white
        static let ink = Color(red: 0.105, green: 0.102, blue: 0.092)
        static let secondaryInk = Color(red: 0.37, green: 0.35, blue: 0.31)
        static let tertiaryInk = Color(red: 0.54, green: 0.51, blue: 0.45)
        static let line = Color.black.opacity(0.085)
        static let selected = Color.black.opacity(0.075)
        static let inverse = Color(red: 0.10, green: 0.095, blue: 0.082)
        static let success = Color(red: 0.16, green: 0.48, blue: 0.30)
        static let warning = Color(red: 0.74, green: 0.43, blue: 0.12)
        static let danger = Color(red: 0.72, green: 0.18, blue: 0.16)
    }

    enum Space {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        static let pill: CGFloat = 999
    }
}

struct MurmurPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .background(MurmurTheme.ColorToken.inverse.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous))
    }
}

struct MurmurSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MurmurTheme.ColorToken.ink)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(MurmurTheme.ColorToken.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous)
                    .stroke(MurmurTheme.ColorToken.line)
            }
            .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.small, style: .continuous))
    }
}

struct MurmurCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(MurmurTheme.Space.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MurmurTheme.ColorToken.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MurmurTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MurmurTheme.Radius.medium, style: .continuous)
                    .stroke(MurmurTheme.ColorToken.line)
            }
    }
}

struct PageHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
            }
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
        }
    }
}

struct EmptyFeatureView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(MurmurTheme.ColorToken.tertiaryInk)
                .frame(width: 48, height: 48)
                .background(MurmurTheme.ColorToken.sidebar)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MurmurTheme.ColorToken.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MurmurPrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}
