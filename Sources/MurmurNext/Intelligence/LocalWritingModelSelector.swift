import Foundation

struct LocalWritingModelSelection: Equatable, Sendable {
    let identifier: String
    let reason: String
    let retryIdentifier: String?
}

struct LocalWritingModelSelector: Sendable {
    let manifests: [LocalWritingModelManifest]

    init(manifests: [LocalWritingModelManifest] = LocalWritingModelManifest.supported) {
        self.manifests = manifests
    }

    func select(
        mode: LocalWritingModelSelectionMode,
        preferredIdentifier: String,
        operation: WritingTransformationOperation,
        installedIdentifiers: Set<String>
    ) -> LocalWritingModelSelection? {
        let eligible = manifests.filter {
            installedIdentifiers.contains($0.id) && $0.supportedOperations.contains(operation)
        }
        guard eligible.isEmpty == false else { return nil }

        if mode != .automatic,
           let preferred = eligible.first(where: { $0.id == preferredIdentifier }) {
            let retry = mode == .fixed ? nil : strongerModel(than: preferred, in: eligible)?.id
            return .init(identifier: preferred.id, reason: mode == .fixed ? "fixed" : "preferred", retryIdentifier: retry)
        }
        if mode == .fixed { return nil }

        let order: [LocalWritingModelTier] = operation == .semanticCommand
            ? [.highestQuality, .balanced, .fastest]
            : [.balanced, .highestQuality, .fastest]
        for tier in order {
            if let match = eligible.first(where: { $0.tier == tier }) {
                return .init(
                    identifier: match.id,
                    reason: "automatic-\(tier.rawValue)",
                    retryIdentifier: strongerModel(than: match, in: eligible)?.id
                )
            }
        }
        return nil
    }

    private func strongerModel(
        than selected: LocalWritingModelManifest,
        in eligible: [LocalWritingModelManifest]
    ) -> LocalWritingModelManifest? {
        let strength: [LocalWritingModelTier: Int] = [.fastest: 0, .balanced: 1, .highestQuality: 2]
        return eligible
            .filter { strength[$0.tier, default: 0] > strength[selected.tier, default: 0] }
            .max { strength[$0.tier, default: 0] < strength[$1.tier, default: 0] }
    }
}
