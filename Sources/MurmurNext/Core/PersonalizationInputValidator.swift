import Foundation

enum PersonalizationValidationError: Error, Equatable, LocalizedError {
    case emptyField(String)
    case fieldTooLong(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .emptyField(let field): "\(field) cannot be empty."
        case .fieldTooLong(let field): "\(field) is too long."
        case .duplicate(let item): "A matching \(item) already exists."
        }
    }
}

struct PersonalizationInputValidator: Sendable {
    func validateDictionary(
        spokenForm: String,
        writtenForm: String,
        context: WritingContext?,
        existing: [DictionaryItem]
    ) throws {
        try validate(spokenForm, name: "Spoken form", maximumBytes: 500)
        try validate(writtenForm, name: "Written form", maximumBytes: 500)
        let spokenKey = normalize(spokenForm)
        let writtenKey = normalize(writtenForm)
        guard existing.contains(where: {
            normalize($0.spokenForm) == spokenKey
                && normalize($0.writtenForm) == writtenKey
                && $0.context == context
        }) == false else {
            throw PersonalizationValidationError.duplicate("dictionary entry")
        }
    }

    func validateSnippet(
        trigger: String,
        expansion: String,
        existing: [SnippetItem]
    ) throws {
        try validate(trigger, name: "Snippet trigger", maximumBytes: 500)
        try validate(expansion, name: "Snippet expansion", maximumBytes: 1_000_000)
        let key = normalize(trigger)
        guard existing.contains(where: { normalize($0.trigger) == key }) == false else {
            throw PersonalizationValidationError.duplicate("snippet trigger")
        }
    }

    private func validate(_ value: String, name: String, maximumBytes: Int) throws {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw PersonalizationValidationError.emptyField(name)
        }
        guard value.utf8.count <= maximumBytes else {
            throw PersonalizationValidationError.fieldTooLong(name)
        }
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
