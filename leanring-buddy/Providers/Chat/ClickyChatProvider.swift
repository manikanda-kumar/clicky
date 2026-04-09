//
//  ClickyChatProvider.swift
//  leanring-buddy
//
//  Shared chat provider interface for Clicky's assistant response pipeline.
//

import Foundation

protocol ClickyChatProvider: AnyObject {
    var model: String { get set }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval)
}
