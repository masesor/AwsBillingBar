import Foundation

/// Represents an AWS account configuration
public struct AWSAccount: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var accountId: String
    public var profileName: String?
    public var region: String
    public var color: AccountColor
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        accountId: String,
        profileName: String? = nil,
        region: String = "us-east-1",
        color: AccountColor = .blue,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.accountId = accountId
        self.profileName = profileName
        self.region = region
        self.color = color
        self.isEnabled = isEnabled
    }
}

/// Color coding for accounts (useful for distinguishing dev/qa/prod)
public enum AccountColor: String, Codable, Sendable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case purple
    case teal

    public var displayName: String {
        rawValue.capitalized
    }
}

/// Authentication method for AWS
public enum AWSAuthMethod: String, Codable, Sendable {
    case profile        // Use AWS CLI profile
    case accessKey      // Use access key + secret
    case sso            // Use AWS SSO
}

/// Credentials for an AWS account
public struct AWSCredentials: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date?

    public init(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        expiration: Date? = nil
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    public var isExpired: Bool {
        guard let expiration else { return false }
        return Date() >= expiration
    }
}
