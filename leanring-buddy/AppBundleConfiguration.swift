//
//  AppBundleConfiguration.swift
//  leanring-buddy
//
//  Shared helper for reading runtime configuration from the built app bundle.
//

import Foundation

enum AppBundleConfiguration {
    static func stringValue(forKey key: String) -> String? {
        if let environmentValue = environmentValue(forKey: key) {
            return environmentValue
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        guard let resourceInfoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let resourceInfo = NSDictionary(contentsOfFile: resourceInfoPath),
              let value = resourceInfo[key] as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func environmentValue(forKey key: String) -> String? {
        let environmentVariables = ProcessInfo.processInfo.environment

        for candidateKey in environmentKeys(forKey: key) {
            guard let value = environmentVariables[candidateKey] else { continue }

            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        return nil
    }

    private static func environmentKeys(forKey key: String) -> [String] {
        switch key {
        case "OpenAIAPIKey":
            return [key, "OPENAI_API_KEY"]
        case "OpenAIChatModel":
            return [key, "OPENAI_CHAT_MODEL"]
        case "OpenAITranscriptionModel":
            return [key, "OPENAI_TRANSCRIPTION_MODEL"]
        case "OpenAIComputerUseModel":
            return [key, "OPENAI_COMPUTER_USE_MODEL"]
        case "VoiceTranscriptionProvider":
            return [key, "CLICKY_VOICE_TRANSCRIPTION_PROVIDER"]
        case "WorkerBaseURL":
            return [key, "CLICKY_WORKER_BASE_URL"]
        case "AssemblyAITokenProxyURL":
            return [key, "ASSEMBLYAI_TOKEN_PROXY_URL"]
        default:
            return [key]
        }
    }
}
