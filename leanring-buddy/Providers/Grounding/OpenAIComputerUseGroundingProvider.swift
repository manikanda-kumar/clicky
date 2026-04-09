//
//  OpenAIComputerUseGroundingProvider.swift
//  leanring-buddy
//
//  Vision-based grounding fallback using OpenAI computer use.
//  This does not execute actions; it only reads the suggested target coordinate.
//

import AppKit
import Foundation

final class OpenAIComputerUseGroundingProvider: ClickyGroundingProvider {
    private let apiKey = AppBundleConfiguration.stringValue(forKey: "OpenAIAPIKey")
    private let modelName = AppBundleConfiguration.stringValue(forKey: "OpenAIComputerUseModel")
        ?? "computer-use-preview"
    private let apiURL = URL(string: "https://api.openai.com/v1/responses")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    func ground(request: ClickyGroundingRequest) async -> ClickyGroundingResult? {
        guard let apiKey, let screenCaptureSelection = preferredScreenCapture(from: request.screenCaptures) else {
            return nil
        }

        let prompt = makePrompt(
            userTranscript: request.userTranscript,
            assistantResponseText: request.assistantResponseText,
            screenCaptureSelection: screenCaptureSelection,
            screenCount: request.screenCaptures.count
        )

        guard let responseData = await sendComputerUseRequest(
            apiKey: apiKey,
            prompt: prompt,
            screenCaptureSelection: screenCaptureSelection
        ) else {
            return nil
        }

        guard let computerCall = parseComputerCall(from: responseData) else {
            return nil
        }

        guard let x = computerCall.x, let y = computerCall.y else {
            return nil
        }

        let screenshotCoordinate = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let spokenText = stripPointTag(from: request.assistantResponseText)

        return ClickyGroundingResult(
            spokenText: spokenText,
            coordinate: screenshotCoordinate,
            elementLabel: computerCall.label ?? "computer-use target",
            screenNumber: screenCaptureSelection.screenNumber,
            source: "openai-computer-use"
        )
    }

    private struct ComputerCallCandidate {
        let x: Double?
        let y: Double?
        let label: String?
    }

    private struct ScreenCaptureSelection {
        let capture: CompanionScreenCapture
        let screenNumber: Int
    }

    private func preferredScreenCapture(from screenCaptures: [CompanionScreenCapture]) -> ScreenCaptureSelection? {
        if let cursorScreenIndex = screenCaptures.firstIndex(where: { $0.isCursorScreen }) {
            return ScreenCaptureSelection(
                capture: screenCaptures[cursorScreenIndex],
                screenNumber: cursorScreenIndex + 1
            )
        }

        guard let firstCapture = screenCaptures.first else { return nil }
        return ScreenCaptureSelection(capture: firstCapture, screenNumber: 1)
    }

    private func makePrompt(
        userTranscript: String,
        assistantResponseText: String,
        screenCaptureSelection: ScreenCaptureSelection,
        screenCount: Int
    ) -> String {
        let screenSummary = screenCount > 1
            ? "The cursor is on screen \(screenCaptureSelection.screenNumber) of \(screenCount)."
            : "There is one screen."

        return """
        You are helping a macOS assistant point at the most relevant visible UI element.

        User transcript: "\(userTranscript)"
        Assistant text: "\(assistantResponseText)"

        \(screenSummary)
        The screenshot dimensions are \(screenCaptureSelection.capture.screenshotWidthInPixels)x\(screenCaptureSelection.capture.screenshotHeightInPixels) pixels.

        Return one click on the most relevant element, or no action if there is no specific element to point at.
        Do not execute anything. Only suggest the coordinate.
        """
    }

    private func sendComputerUseRequest(
        apiKey: String,
        prompt: String,
        screenCaptureSelection: ScreenCaptureSelection
    ) async -> Data? {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "tools": [
                [
                    "type": "computer_use_preview",
                    "display_width": screenCaptureSelection.capture.screenshotWidthInPixels,
                    "display_height": screenCaptureSelection.capture.screenshotHeightInPixels,
                    "environment": "browser"
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ],
                        [
                            "type": "input_image",
                            "image_url": "data:image/jpeg;base64,\(screenCaptureSelection.capture.imageData.base64EncodedString())"
                        ]
                    ]
                ]
            ],
            "reasoning": [
                "summary": "concise"
            ],
            "truncation": "auto"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }

    private func parseComputerCall(from responseData: Data) -> ComputerCallCandidate? {
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let output = json["output"] as? [[String: Any]] else {
            return nil
        }

        for item in output {
            guard let itemType = item["type"] as? String,
                  itemType == "computer_call",
                  let action = item["action"] as? [String: Any] else {
                continue
            }

            let actionType = action["type"] as? String
            guard actionType == "click" || actionType == "double_click" || actionType == "move" else {
                continue
            }

            let x = (action["x"] as? NSNumber)?.doubleValue
            let y = (action["y"] as? NSNumber)?.doubleValue
            let label = extractLabel(from: item)

            return ComputerCallCandidate(
                x: x,
                y: y,
                label: label
            )
        }

        return nil
    }

    private func extractLabel(from item: [String: Any]) -> String? {
        guard let summary = item["summary"] as? [String: Any],
              let text = summary["text"] as? String else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
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
