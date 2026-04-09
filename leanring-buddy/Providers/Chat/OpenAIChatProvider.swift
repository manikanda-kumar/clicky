//
//  OpenAIChatProvider.swift
//  leanring-buddy
//
//  Direct OpenAI chat provider for local testing without the worker proxy.
//

import Foundation

final class OpenAIChatProvider: ClickyChatProvider {
    static let defaultModelName = "gpt-4.1-mini"

    var model: String {
        didSet {
            openAIAPI = OpenAIAPI(apiKey: apiKey, model: Self.sanitizedModelName(from: model))
        }
    }

    private let apiKey: String
    private var openAIAPI: OpenAIAPI

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = Self.sanitizedModelName(from: model)
        self.openAIAPI = OpenAIAPI(apiKey: apiKey, model: Self.sanitizedModelName(from: model))
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let response = try await openAIAPI.analyzeImage(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt
        )

        onTextChunk(response.text)
        return response
    }

    private static func sanitizedModelName(from requestedModelName: String) -> String {
        let trimmedModelName = requestedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else { return defaultModelName }

        if trimmedModelName.hasPrefix("claude-") {
            return defaultModelName
        }

        return trimmedModelName
    }
}
