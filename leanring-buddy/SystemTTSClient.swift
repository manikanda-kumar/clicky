//
//  SystemTTSClient.swift
//  leanring-buddy
//
//  Local macOS speech synthesis fallback for development without ElevenLabs.
//

import AppKit
import Foundation

@MainActor
final class SystemTTSClient {
    private let speechSynthesizer = NSSpeechSynthesizer()

    func speakText(_ text: String) async throws {
        stopPlayback()

        let startedSpeaking = speechSynthesizer.startSpeaking(text)
        if !startedSpeaking {
            throw NSError(
                domain: "SystemTTSClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "System speech synthesis failed to start."]
            )
        }
    }

    var isPlaying: Bool {
        speechSynthesizer.isSpeaking
    }

    func stopPlayback() {
        speechSynthesizer.stopSpeaking()
    }
}
