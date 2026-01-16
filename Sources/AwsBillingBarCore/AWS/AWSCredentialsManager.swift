import Foundation
import Logging

/// Manages AWS credentials from various sources
public actor AWSCredentialsManager {
    private let logger = Logger(label: "AwsBillingBar.CredentialsManager")
    private var cachedCredentials: [String: CachedCredentials] = [:]

    public init() {}

    /// Get credentials for a profile, with caching
    public func getCredentials(for profile: String?) async throws -> AWSCredentials {
        let profileKey = profile ?? "default"

        // Check cache
        if let cached = cachedCredentials[profileKey], !cached.isExpired {
            return cached.credentials
        }

        // Load fresh credentials
        let credentials = try await loadCredentials(profile: profile)

        // Cache them
        cachedCredentials[profileKey] = CachedCredentials(
            credentials: credentials,
            loadedAt: Date()
        )

        return credentials
    }

    /// Load credentials from AWS CLI configuration
    private func loadCredentials(profile: String?) async throws -> AWSCredentials {
        // Try to get credentials from AWS CLI
        let profileArg = profile.map { "--profile \($0)" } ?? ""

        // First try to get credentials from environment or credential process
        let result = try await runAWSCLI(
            "configure export-credentials \(profileArg) --format env"
        )

        return try parseCredentialsFromEnv(result)
    }

    /// Parse credentials from AWS CLI export-credentials output
    private func parseCredentialsFromEnv(_ output: String) throws -> AWSCredentials {
        var accessKeyId: String?
        var secretAccessKey: String?
        var sessionToken: String?

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            switch key {
            case "AWS_ACCESS_KEY_ID", "export AWS_ACCESS_KEY_ID":
                accessKeyId = value
            case "AWS_SECRET_ACCESS_KEY", "export AWS_SECRET_ACCESS_KEY":
                secretAccessKey = value
            case "AWS_SESSION_TOKEN", "export AWS_SESSION_TOKEN":
                sessionToken = value.isEmpty ? nil : value
            default:
                break
            }
        }

        guard let accessKey = accessKeyId, let secretKey = secretAccessKey else {
            throw AWSError.credentialsNotFound
        }

        return AWSCredentials(
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            sessionToken: sessionToken,
            expiration: sessionToken != nil ? Date().addingTimeInterval(3600) : nil
        )
    }

    /// Run AWS CLI command and return output
    private func runAWSCLI(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", "aws \(command)"]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: AWSError.cliError(output))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// List available AWS profiles
    public func listProfiles() async -> [String] {
        do {
            let result = try await runAWSCLI("configure list-profiles")
            return result.split(separator: "\n").map(String.init)
        } catch {
            logger.error("Failed to list profiles: \(error)")
            return []
        }
    }

    /// Clear cached credentials
    public func clearCache() {
        cachedCredentials.removeAll()
    }

    /// Clear cached credentials for a specific profile
    public func clearCache(for profile: String?) {
        cachedCredentials.removeValue(forKey: profile ?? "default")
    }
}

/// Cached credentials with expiration tracking
private struct CachedCredentials {
    let credentials: AWSCredentials
    let loadedAt: Date

    var isExpired: Bool {
        // Refresh cache every 50 minutes for session tokens, or if credentials expired
        if credentials.isExpired {
            return true
        }
        if credentials.sessionToken != nil {
            return Date().timeIntervalSince(loadedAt) > 50 * 60
        }
        // For permanent credentials, cache for 24 hours
        return Date().timeIntervalSince(loadedAt) > 24 * 60 * 60
    }
}

/// AWS-related errors
public enum AWSError: Error, LocalizedError {
    case credentialsNotFound
    case cliError(String)
    case apiError(String)
    case invalidResponse
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "AWS credentials not found. Please configure AWS CLI."
        case .cliError(let message):
            return "AWS CLI error: \(message)"
        case .apiError(let message):
            return "AWS API error: \(message)"
        case .invalidResponse:
            return "Invalid response from AWS"
        case .notConfigured:
            return "AWS account not configured"
        }
    }
}
