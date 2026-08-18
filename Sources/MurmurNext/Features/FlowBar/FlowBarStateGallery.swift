import SwiftUI

/// A gallery of every Flow Bar state on one surface.
///
/// The Flow Bar is the surface users see most and the hardest one to review: it only
/// exists during a dictation, and its fault state needs a genuine failure to provoke.
/// Rather than breaking a model file or revoking a permission to see one frame, this
/// renders `FlowBarFace` from plain values.
///
/// Opened with `MURMUR_UI_GALLERY=1` in the environment; it is not reachable from the
/// shipping UI and adds no code to the dictation path.
struct FlowBarStateGallery: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MURMUR_UI_GALLERY"] == "1"
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let legend: String
        let phase: DictationPhase
        var decibels: Double = -96
        var whisperLikelihood: Double = 0
        var message: String = ""
        var recovery: String?
        var width: CGFloat = 246
    }

    private let entries: [Entry] = [
        Entry(legend: "Tuning", phase: .calibrating, decibels: -48),
        Entry(legend: "Listening — quiet", phase: .listening, decibels: -42),
        Entry(legend: "Listening — normal", phase: .listening, decibels: -18),
        Entry(legend: "Listening — hot", phase: .listening, decibels: -4),
        Entry(legend: "Whisper detected", phase: .listening, decibels: -38, whisperLikelihood: 0.8),
        Entry(legend: "Correcting", phase: .finalizing),
        Entry(legend: "Writing", phase: .inserting),
        Entry(legend: "Inserted", phase: .completed),
        Entry(legend: "Cancelled", phase: .cancelled),
        Entry(
            legend: "Fault — focus lost, transcript parked",
            phase: .failed,
            message: "On clipboard",
            recovery: "⌘V to paste"
        ),
        Entry(legend: "Fault — secure input", phase: .failed, message: "On clipboard", recovery: "⌘V to paste"),
        Entry(legend: "Fault — no recovery", phase: .failed, message: "Write failed"),
        Entry(legend: "Fault — unlabelled", phase: .failed)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MurmurTheme.Space.large) {
                Legend("Flow Bar states", size: .title)
                    .padding(.bottom, MurmurTheme.Space.small)
                    .overlay(alignment: .bottom) { ScribeRule(strong: true, ticks: true) }

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: MurmurTheme.Space.small) {
                        Legend(entry.legend, size: .micro, color: MurmurTheme.Engraving.tertiary)
                        FlowBarFace(
                            phase: entry.phase,
                            decibels: entry.decibels,
                            whisperLikelihood: entry.whisperLikelihood,
                            message: entry.message,
                            recovery: entry.recovery
                        )
                        .frame(width: entry.width, height: 42)
                    }
                }
            }
            .padding(MurmurTheme.Space.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MurmurTheme.Finish.panel)
    }
}
