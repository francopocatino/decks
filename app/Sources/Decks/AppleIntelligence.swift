import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// On-device LLM backend (Apple Intelligence). Compiled out on SDKs older
// than macOS 26 and reported unavailable on systems without the model.
enum AppleIntelligence {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Apple Intelligence is not available on this Mac." }
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *) else { return false }
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        #else
            return false
        #endif
    }

    static func reply(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *), isAvailable else { throw Unavailable() }
            let session = LanguageModelSession(instructions: system)
            let response = try await session.respond(to: user)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
            throw Unavailable()
        #endif
    }
}
