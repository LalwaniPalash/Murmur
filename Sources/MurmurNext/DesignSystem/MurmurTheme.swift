import AppKit
import SwiftUI

// ENGRAVED PANEL — direction contract (seed 7acc830d, assigned index 6)
//
// THESIS: Murmur is equipment, not an app. It refuses the floating-pill-and-bouncing-
//   waveform arrangement every local dictation tool ships.
// OWN-WORLD: An anodised faceplate in two finishes — natural silver in light, black
//   anodize in dark. Legends are engraved caps in Archivo Condensed, not labels.
//   Rectilinear plates with a 3pt machined edge break, hairline scribe rules with
//   corner ticks, and exactly two lamps: record red and verify green.
// STORY: The user is writing in another app. Murmur reports its state the way a field
//   recorder does — a lamp that is on or off, a meter against a printed scale — and
//   never asks to be looked at.
// FIRST VIEWPORT: Engraved legend column at left cut from the chassis finish; the panel
//   proper at right, divided by scribe rules; the shortcut legend engraved at the foot
//   of the column where a real device puts it.
// FORM: Instrument faceplate, candidate 6 of the grounded list, seed key 7acc830d.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish
//   review, the verdict, and DESIGN.md.

// MARK: - Faces

/// The engraved legend voice. Archivo Condensed ships with the app under the OFL;
/// the system condensed width is the fallback when the resource bundle is missing.
enum MurmurFace {
    /// SwiftPM's generated `Bundle.module` for an *executable* target searches only the
    /// `.app` root and the absolute build directory. A packaged app carries the bundle in
    /// `Contents/Resources` instead, and `Bundle.module` traps rather than returning nil,
    /// so the system-face fallback below could never run. Resolve the bundle ourselves.
    private static let resourceBundle: Bundle? = {
        let name = "Murmur_MurmurNext.bundle"
        return [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0?.appendingPathComponent(name) }
            .lazy
            .compactMap { Bundle(url: $0) }
            .first
    }()

    private static let isRegistered: Bool = {
        guard let bundle = resourceBundle else { return false }
        var registeredAny = false
        for name in ["ArchivoCondensed-Medium", "ArchivoCondensed-SemiBold"] {
            let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? bundle.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
                registeredAny = true
            }
        }
        return registeredAny
    }()

    /// Engraved panel lettering. Always set in caps with positive tracking.
    static func legend(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        _ = isRegistered
        let postScriptName = weight == .medium ? "ArchivoCondensed-Medium" : "ArchivoCondensed-SemiBold"
        if let engraved = NSFont(name: postScriptName, size: size) {
            return Font(engraved)
        }
        let systemWeight: NSFont.Weight = weight == .medium ? .medium : .semibold
        return Font(NSFont.systemFont(ofSize: size, weight: systemWeight, width: .condensed))
    }

    /// Body and transcript text. The native face, deliberately — it is not the display voice.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Measured values only: decibels, durations, byte counts, rates. Never a costume.
    static func readout(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Finish

private func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: 1
    )
}

private func isDarkAnodize(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

/// One panel, two anodizings. The finish changes; the engraving does not.
private func anodized(natural: UInt32, black: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        isDarkAnodize(appearance) ? srgb(black) : srgb(natural)
    })
}

/// A scribed line is an absence of finish, so it is expressed as opacity, not pigment.
private func scribed(natural: Double, black: Double) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let dark = isDarkAnodize(appearance)
        return (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? black : natural)
    })
}

enum MurmurTheme {
    enum Finish {
        /// The panel face content sits on. Held a step darker than the plates so a
        /// raised plate actually reads as raised in both finishes.
        static let panel = anodized(natural: 0xD8D9D5, black: 0x151614)
        /// The heavier chassis the legend column is cut from.
        static let chassis = anodized(natural: 0xC6C8C2, black: 0x0F100E)
        /// A plate raised off the panel — where a group of controls or content lives.
        static let plate = anodized(natural: 0xF0F1EE, black: 0x262723)
        /// A milled recess — fields, wells, anything you type or read into.
        static let recess = anodized(natural: 0xD3D5D0, black: 0x121311)
        /// The selected legend's milled seat in the column.
        static let seat = anodized(natural: 0xDCDED8, black: 0x2B2C27)
    }

    enum Engraving {
        /// Primary legend fill: graphite in the natural finish, bone in the black.
        static let ink = anodized(natural: 0x1E201D, black: 0xE9EAE5)
        static let secondary = anodized(natural: 0x4B4F48, black: 0xACAFA5)
        /// Micro-legends. Held at ≥4.5:1 against `plate` in both finishes.
        static let tertiary = anodized(natural: 0x5F635B, black: 0x8D9187)
        /// Hairline scribe rule.
        static let scribe = scribed(natural: 0.16, black: 0.16)
        /// Scribe rule at a panel division.
        static let scribeStrong = scribed(natural: 0.30, black: 0.28)
    }

    /// Two lamps and one caution. Nothing else on the panel is coloured.
    enum Lamp {
        /// Lit only while audio is genuinely being captured.
        static let record = anodized(natural: 0xB83227, black: 0xE24A34)
        /// Lit only when a transcript was grounded and inserted.
        static let verify = anodized(natural: 0x2F6B41, black: 0x53A468)
        static let caution = anodized(natural: 0x8F5D12, black: 0xD69A3C)
        /// An unlit lamp is a dark bezel, never an absent element.
        static let unlit = scribed(natural: 0.16, black: 0.24)
    }

    enum Space {
        static let hairline: CGFloat = 1
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 18
        static let xLarge: CGFloat = 28
        static let xxLarge: CGFloat = 44
    }

    /// Machined edge breaks, not app rounding. A panel is rectilinear.
    enum Edge {
        static let plate: CGFloat = 3
        static let control: CGFloat = 2.5
        static let flowBar: CGFloat = 5
    }

    /// Tracking for engraved caps, by optical size.
    enum Tracking {
        static let title: CGFloat = 1.8
        static let legend: CGFloat = 1.35
        static let micro: CGFloat = 1.1
    }
}
