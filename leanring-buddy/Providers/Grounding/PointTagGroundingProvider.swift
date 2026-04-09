//
//  PointTagGroundingProvider.swift
//  leanring-buddy
//
//  Parses the existing [POINT:...] tag format emitted by the assistant.
//

import Foundation
import CoreGraphics

final class PointTagGroundingProvider: ClickyGroundingProvider {
    func ground(request: ClickyGroundingRequest) async -> ClickyGroundingResult? {
        let responseText = request.assistantResponseText

        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            return ClickyGroundingResult(
                spokenText: responseText,
                coordinate: nil,
                elementLabel: nil,
                screenNumber: nil,
                source: "point-tag"
            )
        }

        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return ClickyGroundingResult(
                spokenText: spokenText,
                coordinate: nil,
                elementLabel: "none",
                screenNumber: nil,
                source: "point-tag"
            )
        }

        var elementLabel: String?
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int?
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return ClickyGroundingResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber,
            source: "point-tag"
        )
    }
}
