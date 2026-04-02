import Foundation

struct BackendConfiguration {
    let baseURLString: String

    var trimmedBaseURL: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var baseURL: URL? {
        guard !trimmedBaseURL.isEmpty else { return nil }
        return URL(string: trimmedBaseURL)
    }

    var isValid: Bool {
        baseURL != nil
    }
}

enum BackendAIServiceError: Error {
    case missingConfiguration
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
}

final class BackendAIService {
    static let shared = BackendAIService()

    func generatePracticeCards(
        for phrase: String,
        mode: PracticeMode,
        previousSentences: [String],
        configuration: BackendConfiguration
    ) async throws -> [GeneratedSentenceCard] {
        guard configuration.isValid else { throw BackendAIServiceError.missingConfiguration }

        let payload = try await performRequest(
            path: "generate-sentence",
            configuration: configuration,
            requestBody: PracticeGenerationRequest(
                phrase: phrase,
                mode: mode.backendMode,
                previousSentences: Array(previousSentences.prefix(20))
            )
        )

        let response = try JSONDecoder().decode(GeneratedSentenceBundle.self, from: payload)
        return response.cards
    }

    func assessDifficulty(for phrase: String, configuration: BackendConfiguration) async throws -> Int {
        guard configuration.isValid else { throw BackendAIServiceError.missingConfiguration }

        let payload = try await performRequest(
            path: "classify-difficulty",
            configuration: configuration,
            requestBody: PhraseRequest(phrase: phrase)
        )

        let response = try JSONDecoder().decode(DifficultyBundle.self, from: payload)
        return response.level
    }

    func meaningHint(for phrase: String, configuration: BackendConfiguration) async throws -> String {
        guard configuration.isValid else { throw BackendAIServiceError.missingConfiguration }

        let payload = try await performRequest(
            path: "explain-phrase",
            configuration: configuration,
            requestBody: PhraseRequest(phrase: phrase)
        )

        let response = try JSONDecoder().decode(HintBundle.self, from: payload)
        return response.hint
    }

    func fullMeaning(for phrase: String, configuration: BackendConfiguration) async throws -> String {
        guard configuration.isValid else { throw BackendAIServiceError.missingConfiguration }

        let payload = try await performRequest(
            path: "define-phrase",
            configuration: configuration,
            requestBody: PhraseRequest(phrase: phrase)
        )

        let response = try JSONDecoder().decode(MeaningBundle.self, from: payload)
        return response.meaning
    }

    private func performRequest<RequestBody: Encodable>(
        path: String,
        configuration: BackendConfiguration,
        requestBody: RequestBody
    ) async throws -> Data {
        guard
            let baseURL = configuration.baseURL,
            let requestURL = URL(string: path, relativeTo: baseURL)?.absoluteURL
        else {
            throw BackendAIServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw BackendAIServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }
}

private struct PhraseRequest: Encodable {
    let phrase: String
}

private struct PracticeGenerationRequest: Encodable {
    let phrase: String
    let mode: String
    let previousSentences: [String]
}

struct GeneratedSentenceCard: Decodable {
    let sentence: String
    let highlightedText: String
}

private struct GeneratedSentenceBundle: Decodable {
    let cards: [GeneratedSentenceCard]
}

private struct DifficultyBundle: Decodable {
    let level: Int
}

private struct HintBundle: Decodable {
    let hint: String
}

private struct MeaningBundle: Decodable {
    let meaning: String
}

extension BackendAIServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "AI backend is not configured."
        case .invalidURL:
            return "The backend URL is invalid."
        case .invalidResponse:
            return "The backend returned an unreadable response."
        case let .httpError(statusCode, message):
            let shortened = message.replacingOccurrences(of: "\n", with: " ")
            return "Backend error \(statusCode): \(shortened)"
        }
    }
}
