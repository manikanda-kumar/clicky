//
//  GroundingCoordinator.swift
//  leanring-buddy
//
//  Coordinates the set of grounding providers and returns the first usable result.
//

import Foundation

final class GroundingCoordinator {
    private let providers: [any ClickyGroundingProvider]

    init(providers: [any ClickyGroundingProvider] = [
        NativeMacOSGroundingProvider(),
        OpenAIComputerUseGroundingProvider(),
        PointTagGroundingProvider()
    ]) {
        self.providers = providers
    }

    func ground(request: ClickyGroundingRequest) async -> ClickyGroundingResult {
        for provider in providers {
            if let groundedResult = await provider.ground(request: request) {
                return groundedResult
            }
        }

        return ClickyGroundingResult(
            spokenText: request.assistantResponseText,
            coordinate: nil,
            elementLabel: nil,
            screenNumber: nil,
            source: "fallback"
        )
    }
}
