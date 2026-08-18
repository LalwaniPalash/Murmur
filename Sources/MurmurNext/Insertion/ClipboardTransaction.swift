import AppKit
import Foundation

enum ClipboardTransactionPolicy {
    static func shouldRestore(injectedChangeCount: Int, currentChangeCount: Int) -> Bool {
        injectedChangeCount == currentChangeCount
    }
}

/// Markers clipboard managers honour. Without them every dictated phrase ends up in the
/// user's clipboard history, which for a local-only dictation app is a privacy leak by
/// accident rather than by design.
enum PasteboardConvention {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

/// Borrows the clipboard for a paste and gives it back.
///
/// The give-back is deliberately detached from the caller: the transcript is already in the
/// user's document by then, so waiting for the restore would add its delay straight onto
/// perceived dictation latency. It is also deliberately generous — Electron, JetBrains and
/// remote-desktop clients read the pasteboard well after the keystroke lands, and restoring
/// too early makes them paste the *previous* clipboard contents.
@MainActor
final class ClipboardTransaction {
    private let pasteboard: NSPasteboard
    private var archive: PasteboardArchive?
    private var pendingRestore: Task<Void, Never>?
    private var injectedChangeCount = 0

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Puts `text` on the clipboard, remembering what the user had there.
    @discardableResult
    func write(_ text: String) -> Bool {
        pendingRestore?.cancel()
        pendingRestore = nil
        let preserved = archiveToPreserve()
        archive = preserved

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: PasteboardConvention.transient)
        guard pasteboard.writeObjects([item]) else {
            preserved.restore(to: pasteboard)
            archive = nil
            return false
        }
        injectedChangeCount = pasteboard.changeCount
        return true
    }

    /// What a second dictation, starting before the first one's restore has fired, should
    /// hand back when it finishes.
    ///
    /// While Murmur's own text is still on the clipboard the answer is the archive from the
    /// first transaction — re-archiving there would capture Murmur's injected text and give
    /// it back to the user as their own clipboard. But if the clipboard moved on, the user
    /// copied something in between, and *that* is what they expect to get back.
    private func archiveToPreserve() -> PasteboardArchive {
        guard let archive, ClipboardTransactionPolicy.shouldRestore(
            injectedChangeCount: injectedChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) else { return PasteboardArchive(pasteboard: pasteboard) }
        return archive
    }

    func scheduleRestore(after delay: Duration) {
        guard archive != nil else { return }
        pendingRestore = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            self?.restoreIfUntouched()
        }
    }

    /// Hands the clipboard back, unless the user copied something else in the meantime.
    func restoreIfUntouched() {
        guard let archive else { return }
        self.archive = nil
        guard ClipboardTransactionPolicy.shouldRestore(
            injectedChangeCount: injectedChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) else { return }
        archive.restore(to: pasteboard)
    }

    /// Leaves the transcript on the clipboard, so an insertion Murmur could not complete is
    /// still recoverable with a manual ⌘V instead of being lost outright.
    func abandon() {
        pendingRestore?.cancel()
        pendingRestore = nil
        archive = nil
    }
}

@MainActor
struct PasteboardArchive {
    private struct Item {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    private let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { archived -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in archived.values {
                item.setData(data, forType: type)
            }
            return item
        }
        if restoredItems.isEmpty == false {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
