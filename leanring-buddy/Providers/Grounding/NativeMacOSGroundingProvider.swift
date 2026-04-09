//
//  NativeMacOSGroundingProvider.swift
//  leanring-buddy
//
//  Heuristic grounding based on native macOS accessibility inspection.
//

import AppKit
import CoreGraphics
import Foundation

final class NativeMacOSGroundingProvider: ClickyGroundingProvider {
    private let automationProvider: any ClickyAutomationProvider

    init(automationProvider: any ClickyAutomationProvider = NativeMacOSAutomationProvider()) {
        self.automationProvider = automationProvider
    }

    func ground(request: ClickyGroundingRequest) async -> ClickyGroundingResult? {
        guard let automationContext = await automationProvider.inspectCurrentContext() else {
            return nil
        }

        let interactionText = normalizeText(request.combinedInteractionText)
        guard !interactionText.isEmpty else { return nil }

        let candidates = makeCandidates(from: automationContext)
        guard let bestCandidate = bestMatchingCandidate(
            among: candidates,
            interactionText: interactionText
        ) else {
            return nil
        }

        guard let screenMatch = matchingScreenCapture(
            for: bestCandidate.frame,
            in: request.screenCaptures
        ) else {
            return nil
        }

        guard let screenshotCoordinate = convertGlobalFrameToScreenshotCoordinate(
            bestCandidate.frame,
            in: screenMatch.capture
        ) else {
            return nil
        }

        return ClickyGroundingResult(
            spokenText: stripPointTag(from: request.assistantResponseText),
            coordinate: screenshotCoordinate,
            elementLabel: bestCandidate.label,
            screenNumber: screenMatch.screenNumber,
            source: "native-macos"
        )
    }

    private struct Candidate {
        let label: String
        let frame: CGRect
        let kind: String

        var kindPriority: Int {
            switch kind {
            case "focused-element":
                return 3
            case "menu-bar":
                return 2
            case "main-menu":
                return 1
            default:
                return 0
            }
        }
    }

    private func makeCandidates(from automationContext: ClickyAutomationContextSnapshot) -> [Candidate] {
        var candidates: [Candidate] = []

        if let focusedElement = automationContext.focusedElement,
           let frame = focusedElement.frame {
            let label = candidateLabel(for: focusedElement) ?? automationContext.frontmostApplication.localizedName
            candidates.append(Candidate(label: label, frame: frame, kind: "focused-element"))
        }

        for menuItem in automationContext.menuBarItems {
            guard let frame = menuItem.frame else { continue }
            let label = candidateLabel(for: menuItem) ?? automationContext.frontmostApplication.localizedName
            candidates.append(Candidate(label: label, frame: frame, kind: "menu-bar"))
        }

        for menuItem in automationContext.mainMenuItems {
            guard let frame = menuItem.frame else { continue }
            let label = candidateLabel(for: menuItem) ?? automationContext.frontmostApplication.localizedName
            candidates.append(Candidate(label: label, frame: frame, kind: "main-menu"))
        }

        return candidates
    }

    private func candidateLabel(for snapshot: ClickyAutomationElementSnapshot) -> String? {
        [snapshot.title, snapshot.value, snapshot.help, snapshot.identifier, snapshot.role]
            .compactMap { $0 }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func bestMatchingCandidate(
        among candidates: [Candidate],
        interactionText: String
    ) -> Candidate? {
        let scoredCandidates = candidates.compactMap { candidate -> (Candidate, Int)? in
            let normalizedLabel = normalizeText(candidate.label)
            guard !normalizedLabel.isEmpty else { return nil }

            let score = matchScore(label: normalizedLabel, in: interactionText, kind: candidate.kind)
            guard score > 0 else { return nil }
            return (candidate, score)
        }

        return scoredCandidates.max { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.kindPriority < rhs.0.kindPriority
            }
            return lhs.1 < rhs.1
        }?.0
    }

    private func matchScore(label: String, in interactionText: String, kind: String) -> Int {
        var score = 0

        if interactionText == label {
            score += 100
        }

        if interactionText.contains(label) {
            score += 70
        }

        if label.contains(interactionText) {
            score += 40
        }

        let labelTokens = Set(label.split(separator: " ").map(String.init))
        let interactionTokens = Set(interactionText.split(separator: " ").map(String.init))
        let overlapCount = labelTokens.intersection(interactionTokens).count
        score += overlapCount * 10

        if labelTokens.contains("menu") || kind.contains("menu") {
            score += 5
        }

        if labelTokens.contains("button") {
            score += 5
        }

        return score
    }

    private struct ScreenCaptureMatch {
        let capture: CompanionScreenCapture
        let screenNumber: Int
    }

    private func matchingScreenCapture(
        for frame: CGRect,
        in screenCaptures: [CompanionScreenCapture]
    ) -> ScreenCaptureMatch? {
        let candidateCenter = CGPoint(x: frame.midX, y: frame.midY)
        for (index, capture) in screenCaptures.enumerated() {
            if capture.displayFrame.contains(candidateCenter) {
                return ScreenCaptureMatch(capture: capture, screenNumber: index + 1)
            }
        }
        return nil
    }

    private func convertGlobalFrameToScreenshotCoordinate(
        _ frame: CGRect,
        in screenCapture: CompanionScreenCapture
    ) -> CGPoint? {
        let candidateCenter = CGPoint(x: frame.midX, y: frame.midY)
        let localX = candidateCenter.x - screenCapture.displayFrame.origin.x
        let localY = candidateCenter.y - screenCapture.displayFrame.origin.y

        guard screenCapture.displayWidthInPoints > 0,
              screenCapture.displayHeightInPoints > 0,
              screenCapture.screenshotWidthInPixels > 0,
              screenCapture.screenshotHeightInPixels > 0 else {
            return nil
        }

        let xRatio = CGFloat(screenCapture.screenshotWidthInPixels) / CGFloat(screenCapture.displayWidthInPoints)
        let yRatio = CGFloat(screenCapture.screenshotHeightInPixels) / CGFloat(screenCapture.displayHeightInPoints)

        let screenshotX = localX * xRatio
        let screenshotYTopLeftOrigin = (CGFloat(screenCapture.displayHeightInPoints) - localY) * yRatio

        return CGPoint(x: screenshotX, y: screenshotYTopLeftOrigin)
    }

    private func normalizeText(_ text: String) -> String {
        let lowercaseText = text.lowercased()
        let allowedCharacters = lowercaseText.map { character -> Character in
            if character.isLetter || character.isNumber || character.isWhitespace {
                return character
            }
            return " "
        }
        return String(allowedCharacters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripPointTag(from responseText: String) -> String {
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tagRange = Range(match.range, in: responseText)!
        return String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
