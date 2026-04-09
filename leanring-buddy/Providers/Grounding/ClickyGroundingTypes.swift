//
//  ClickyGroundingTypes.swift
//  leanring-buddy
//
//  Shared types for grounding assistant responses to screen coordinates.
//

import Foundation
import CoreGraphics
import ScreenCaptureKit

struct ClickyGroundingRequest {
    let userTranscript: String
    let assistantResponseText: String
    let screenCaptures: [CompanionScreenCapture]

    var combinedInteractionText: String {
        "\(userTranscript) \(assistantResponseText)"
    }
}

struct ClickyGroundingResult {
    let spokenText: String
    let coordinate: CGPoint?
    let elementLabel: String?
    let screenNumber: Int?
    let source: String
}

protocol ClickyGroundingProvider: AnyObject {
    func ground(
        request: ClickyGroundingRequest
    ) async -> ClickyGroundingResult?
}
