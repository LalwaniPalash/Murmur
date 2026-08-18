import SwiftUI

// The panel vocabulary. Every control in the app is built from these parts, because a
// stock SwiftUI control dropped into a committed faceplate reads as a missing part.

// MARK: - Engraved lettering

/// Panel lettering. Engraved legends are always caps with positive tracking — that is
/// what makes them read as cut into the finish rather than printed on top of it.
struct Legend: View {
    enum Size {
        case title, section, control, micro

        var pointSize: CGFloat {
            switch self {
            case .title: 19
            case .section: 11.5
            case .control: 11
            case .micro: 9.5
            }
        }

        var tracking: CGFloat {
            switch self {
            case .title: MurmurTheme.Tracking.title
            case .section, .control: MurmurTheme.Tracking.legend
            case .micro: MurmurTheme.Tracking.micro
            }
        }
    }

    let text: String
    var size: Size = .section
    var color: Color = MurmurTheme.Engraving.ink

    init(_ text: String, size: Size = .section, color: Color = MurmurTheme.Engraving.ink) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(MurmurFace.legend(size.pointSize, weight: size == .micro ? .medium : .semibold))
            .tracking(size.tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Scribe rules

/// A hairline scribed into the finish. Corner ticks mark a panel division the way a
/// real faceplate scores its sections.
struct ScribeRule: View {
    var strong = false
    var ticks = false

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(strong ? MurmurTheme.Engraving.scribeStrong : MurmurTheme.Engraving.scribe)
                .frame(height: MurmurTheme.Space.hairline)
            if ticks {
                HStack {
                    tick
                    Spacer(minLength: 0)
                    tick
                }
            }
        }
        .frame(height: ticks ? 5 : MurmurTheme.Space.hairline)
        .accessibilityHidden(true)
    }

    private var tick: some View {
        Rectangle()
            .fill(MurmurTheme.Engraving.scribeStrong)
            .frame(width: MurmurTheme.Space.hairline, height: 5)
    }
}

// MARK: - Plates and recesses

/// A plate raised off the panel face. Content lives on plates; plates never nest.
struct Plate<Content: View>: View {
    var padding: CGFloat = MurmurTheme.Space.large
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                    .fill(MurmurTheme.Finish.plate)
                    .shadow(color: .black.opacity(0.13), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                    .strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
            )
    }
}

// MARK: - Lamps

/// A lamp is on or off. There is no third state and no animation between them — that is
/// the whole point of putting one on this product.
struct Lamp: View {
    enum Colour { case record, verify, caution }

    let colour: Colour
    let isLit: Bool
    var diameter: CGFloat = 7

    private var litColour: Color {
        switch colour {
        case .record: MurmurTheme.Lamp.record
        case .verify: MurmurTheme.Lamp.verify
        case .caution: MurmurTheme.Lamp.caution
        }
    }

    var body: some View {
        Circle()
            .fill(isLit ? litColour : MurmurTheme.Lamp.unlit)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle().strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Readouts

/// A measured value against its legend. Figures are tabular so a changing value never
/// shifts the layout underneath it.
struct Readout: View {
    let legend: String
    let value: String
    var unit: String?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(MurmurFace.readout(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(MurmurTheme.Engraving.ink)
                if let unit {
                    Legend(unit, size: .micro, color: MurmurTheme.Engraving.tertiary)
                }
            }
            Legend(legend, size: .micro, color: MurmurTheme.Engraving.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(legend): \(value) \(unit ?? "")")
    }
}

// MARK: - Level meter

/// A fixed-scale segment ladder against an engraved dB scale — the instrument answer to
/// four bouncing capsules. The scale never rescales and the width never changes, so a
/// loud passage cannot move anything on screen.
struct LevelMeter: View {
    /// Input level in dBFS.
    let decibels: Double
    /// Segments above this fraction of the ladder read as caution.
    var segments: Int = 22
    var segmentHeight: CGFloat = 11
    var onDevice = false

    private var floorDecibels: Double { -60 }

    private var litCount: Int {
        guard decibels > floorDecibels else { return 0 }
        let fraction = (decibels - floorDecibels) / -floorDecibels
        return Int((min(max(fraction, 0), 1) * Double(segments)).rounded())
    }

    private var cautionThreshold: Int { Int(Double(segments) * 0.82) }

    private var unlitColour: Color {
        onDevice ? Color.white.opacity(0.14) : MurmurTheme.Lamp.unlit
    }

    private func litColour(_ index: Int) -> Color {
        if index >= cautionThreshold {
            return onDevice ? Color(red: 0.84, green: 0.60, blue: 0.24) : MurmurTheme.Lamp.caution
        }
        return onDevice ? Color.white.opacity(0.90) : MurmurTheme.Engraving.ink
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < litCount ? litColour(index) : unlitColour)
                    .frame(width: 2.5, height: segmentHeight)
            }
        }
        .animation(.easeOut(duration: 0.09), value: litCount)
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// The panel's primary action: an engraved plate you press.
struct PanelButtonStyle: ButtonStyle {
    enum Rank { case primary, secondary, destructive }

    var rank: Rank = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(MurmurFace.legend(11, weight: .semibold))
            .tracking(MurmurTheme.Tracking.legend)
            .textCase(.uppercase)
            .foregroundStyle(foreground(pressed: pressed))
            .padding(.horizontal, MurmurTheme.Space.medium)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .fill(background(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .strokeBorder(border, lineWidth: MurmurTheme.Space.hairline)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }

    private func foreground(pressed: Bool) -> Color {
        switch rank {
        case .primary: MurmurTheme.Finish.plate
        case .secondary: MurmurTheme.Engraving.ink
        case .destructive: MurmurTheme.Lamp.record
        }
    }

    private func background(pressed: Bool) -> Color {
        switch rank {
        case .primary: MurmurTheme.Engraving.ink.opacity(pressed ? 0.78 : 1)
        case .secondary, .destructive: pressed ? MurmurTheme.Finish.seat : MurmurTheme.Finish.plate
        }
    }

    private var border: Color {
        rank == .primary ? .clear : MurmurTheme.Engraving.scribeStrong
    }
}

/// A machined slide switch. The stock SwiftUI toggle is the single most conspicuous
/// giveaway in a committed faceplate: it introduces a system blue that exists nowhere
/// else here, and it reads as a control borrowed from another product.
struct PanelToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let trackWidth: CGFloat = 30
    private let trackHeight: CGFloat = 16
    private let knobInset: CGFloat = 1.5

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .fill(
                        isOn
                            ? AnyShapeStyle(MurmurTheme.Engraving.ink)
                            : AnyShapeStyle(
                                MurmurTheme.Finish.recess
                                    .shadow(.inner(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1))
                            )
                    )
                    .frame(width: trackWidth, height: trackHeight)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(MurmurTheme.Finish.plate)
                    .frame(width: trackHeight - knobInset * 2, height: trackHeight - knobInset * 2)
                    .padding(.horizontal, knobInset)
                    .shadow(color: .black.opacity(0.24), radius: 1, x: 0, y: 0.5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .strokeBorder(MurmurTheme.Engraving.scribeStrong, lineWidth: MurmurTheme.Space.hairline)
                    .frame(width: trackWidth, height: trackHeight)
            )
            .frame(width: trackWidth, height: trackHeight)
            .animation(.easeOut(duration: 0.12), value: isOn)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A panel switch: legend at left, detail beneath, switch at right. The detail line is
/// optional and omitted whenever the legend already says it.
struct PanelSwitch: View {
    let legend: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MurmurTheme.Space.large) {
            VStack(alignment: .leading, spacing: 3) {
                Legend(legend, size: .control)
                if let detail {
                    Text(detail)
                        .font(MurmurFace.body(11.5))
                        .foregroundStyle(MurmurTheme.Engraving.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(PanelToggleStyle())
                .accessibilityLabel(legend)
        }
        .padding(.vertical, MurmurTheme.Space.small)
    }
}

/// A read-only specification line: engraved legend at left, measured value at right.
struct SpecLine: View {
    let legend: String
    let value: String
    var lamp: Lamp.Colour?
    var isLit = false

    var body: some View {
        HStack(spacing: MurmurTheme.Space.medium) {
            Legend(legend, size: .control, color: MurmurTheme.Engraving.secondary)
            Spacer(minLength: MurmurTheme.Space.medium)
            if let lamp {
                Lamp(colour: lamp, isLit: isLit)
            }
            Text(value)
                .font(MurmurFace.readout(11.5))
                .monospacedDigit()
                .foregroundStyle(MurmurTheme.Engraving.ink)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(legend): \(value)")
    }
}

// MARK: - Page scaffold

/// Every hub destination is one panel: an engraved title cut into the head, a scribe
/// rule under it, then sections.
struct PanelPage<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = nil
        self.content = content()
    }

    init<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.xLarge) {
                HStack(alignment: .center) {
                    Legend(title, size: .title)
                    Spacer(minLength: MurmurTheme.Space.large)
                    if let trailing { trailing }
                }
                .padding(.bottom, MurmurTheme.Space.medium)
                .overlay(alignment: .bottom) { ScribeRule(strong: true, ticks: true) }

                content
            }
            .padding(.horizontal, MurmurTheme.Space.xxLarge)
            .padding(.vertical, MurmurTheme.Space.xLarge)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A named division of the panel.
struct PanelSection<Content: View>: View {
    let legend: String
    var note: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(legend: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.legend = legend
        self.note = note
        self.trailing = nil
        self.content = content()
    }

    init<Trailing: View>(
        legend: String,
        note: String? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.legend = legend
        self.note = note
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.medium) {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.xSmall) {
                HStack(alignment: .center, spacing: MurmurTheme.Space.medium) {
                    Legend(legend, size: .section, color: MurmurTheme.Engraving.secondary)
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
                ScribeRule()
            }
            if let note {
                Text(note)
                    .font(MurmurFace.body(12))
                    .foregroundStyle(MurmurTheme.Engraving.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

/// An empty state engraved into the panel rather than illustrated on it.
struct BlankPlate: View {
    let legend: String
    var action: (title: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: MurmurTheme.Space.medium) {
            Legend(legend, size: .control, color: MurmurTheme.Engraving.tertiary)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PanelButtonStyle(rank: .secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MurmurTheme.Space.xxLarge)
        .background(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .fill(MurmurTheme.Finish.recess.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MurmurTheme.Edge.plate, style: .continuous)
                .strokeBorder(
                    MurmurTheme.Engraving.scribe,
                    style: StrokeStyle(lineWidth: MurmurTheme.Space.hairline, dash: [3, 3])
                )
        )
    }
}

/// A one-line outcome against a lamp. Success and fault share a shape so a result never
/// arrives as a differently-sized surprise.
struct StatusLine: View {
    let text: String
    let lamp: Lamp.Colour

    var body: some View {
        HStack(alignment: .top, spacing: MurmurTheme.Space.small) {
            Lamp(colour: lamp, isLit: true)
                .padding(.top, 3)
            Text(text)
                .font(MurmurFace.body(11.5))
                .foregroundStyle(MurmurTheme.Engraving.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Mark

/// Five bars at the levels of a spoken phrase. The mark, not a live meter — it never
/// animates, because a logo that reacts to audio is the thing this design refuses.
struct MurmurMark: View {
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .center, spacing: 1.5 * scale) {
            ForEach([6.0, 12.0, 17.0, 10.0, 5.0], id: \.self) { height in
                Rectangle()
                    .fill(MurmurTheme.Engraving.ink)
                    .frame(width: 2 * scale, height: height * scale)
            }
        }
        .frame(width: 22 * scale, height: 20 * scale)
        .accessibilityHidden(true)
    }
}

// MARK: - Fields

/// A recessed field. The stock rounded text field is the one control that most gives a
/// faceplate away, so it is rebuilt rather than restyled.
struct PanelField: View {
    let legend: String
    @Binding var text: String
    var prompt: String?
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
            Legend(legend, size: .micro, color: MurmurTheme.Engraving.tertiary)
            Group {
                if axis == .vertical, let lineLimit {
                    TextField(prompt ?? "", text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(prompt ?? "", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(MurmurFace.body(13))
            .foregroundStyle(MurmurTheme.Engraving.ink)
            .padding(.horizontal, MurmurTheme.Space.small)
            .padding(.vertical, MurmurTheme.Space.small)
            .background(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .fill(
                        MurmurTheme.Finish.recess
                            .shadow(.inner(color: .black.opacity(0.18), radius: 2, x: 0, y: 1))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: MurmurTheme.Edge.control, style: .continuous)
                    .strokeBorder(MurmurTheme.Engraving.scribe, lineWidth: MurmurTheme.Space.hairline)
            )
            .accessibilityLabel(legend)
        }
    }
}
