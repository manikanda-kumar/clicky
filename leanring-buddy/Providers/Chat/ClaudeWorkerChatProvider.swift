//
//  ClaudeWorkerChatProvider.swift
//  leanring-buddy
//
//  Current Claude-backed chat implementation routed through the Cloudflare Worker.
//

import Foundation

final class ClaudeWorkerChatProvider: ClickyChatProvider {
    var model: String {
        didSet {
            claudeAPI.model = model
        }
    }

    private let claudeAPI: ClaudeAPI

    init(proxyURL: String, model: String) {
        self.model = model
        self.claudeAPI = ClaudeAPI(proxyURL: proxyURL, model: model)
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        try await claudeAPI.analyzeImageStreaming(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            onTextChunk: onTextChunk
        )
    }
}
