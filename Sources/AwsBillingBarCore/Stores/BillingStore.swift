import Foundation
import Logging

/// Main store for billing data across all accounts
@MainActor @Observable
public final class BillingStore {
    private let logger = Logger(label: "AwsBillingBar.BillingStore")

    /// Current billing snapshots by account ID
    public private(set) var snapshots: [String: BillingSnapshot] = [:]

    /// Errors by account ID
    public private(set) var errors: [String: String] = [:]

    /// Whether a refresh is in progress
    public private(set) var isRefreshing: Bool = false

    /// Last successful refresh time
    public private(set) var lastRefresh: Date?

    /// Configured accounts
    public var accounts: [AWSAccount] = [] {
        didSet {
            saveAccounts()
        }
    }

    /// Refresh frequency
    public var refreshFrequency: RefreshFrequency = .fiveMinutes {
        didSet {
            restartTimer()
        }
    }

    private let credentialsManager: AWSCredentialsManager
    private let costExplorerClient: AWSCostExplorerClient
    private var timerTask: Task<Void, Never>?
    private let accountsFileURL: URL

    public init() {
        self.credentialsManager = AWSCredentialsManager()
        self.costExplorerClient = AWSCostExplorerClient(credentialsManager: credentialsManager)

        // Set up accounts file path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AwsBillingBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.accountsFileURL = appDir.appendingPathComponent("accounts.json")

        loadAccounts()
    }


    /// Refresh billing data for all enabled accounts
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        defer { isRefreshing = false }

        let enabledAccounts = accounts.filter(\.isEnabled)

        await withTaskGroup(of: (String, Result<BillingSnapshot, Error>).self) { group in
            for account in enabledAccounts {
                group.addTask { [costExplorerClient] in
                    do {
                        let snapshot = try await costExplorerClient.fetchBilling(for: account)
                        return (account.id, .success(snapshot))
                    } catch {
                        return (account.id, .failure(error))
                    }
                }
            }

            for await (accountId, result) in group {
                switch result {
                case .success(let snapshot):
                    snapshots[accountId] = snapshot
                    errors.removeValue(forKey: accountId)
                case .failure(let error):
                    errors[accountId] = error.localizedDescription
                    logger.error("Failed to fetch billing for \(accountId): \(error)")
                }
            }
        }

        lastRefresh = Date()
    }

    /// Start the auto-refresh timer
    public func startTimer() {
        restartTimer()
    }

    /// Stop the auto-refresh timer
    public func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Get aggregated billing data
    public var aggregated: AggregatedBilling {
        AggregatedBilling(snapshots: Array(snapshots.values))
    }

    /// Get snapshot for a specific account
    public func snapshot(for accountId: String) -> BillingSnapshot? {
        snapshots[accountId]
    }

    /// Add a new account
    public func addAccount(_ account: AWSAccount) {
        accounts.append(account)
    }

    /// Remove an account
    public func removeAccount(_ account: AWSAccount) {
        accounts.removeAll { $0.id == account.id }
        snapshots.removeValue(forKey: account.id)
        errors.removeValue(forKey: account.id)
    }

    /// Update an existing account
    public func updateAccount(_ account: AWSAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        }
    }

    /// Clear all cached credentials
    public func clearCredentials() async {
        await credentialsManager.clearCache()
    }

    /// Get available AWS profiles
    public func availableProfiles() async -> [String] {
        await credentialsManager.listProfiles()
    }


    private func restartTimer() {
        timerTask?.cancel()

        guard let interval = refreshFrequency.seconds else {
            return
        }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.refresh()
            }
        }
    }

    private func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: accountsFileURL)
        } catch {
            logger.error("Failed to save accounts: \(error)")
        }
    }

    private func loadAccounts() {
        do {
            let data = try Data(contentsOf: accountsFileURL)
            accounts = try JSONDecoder().decode([AWSAccount].self, from: data)
        } catch {
            // No existing accounts file, use defaults
            accounts = []
        }

        // Uncomment to enable demo account with mock data
        // addMockAccountIfNeeded()
    }

    // MARK: - Demo Account (uncomment to enable)

    /*
    private func addMockAccountIfNeeded() {
        let mockAccountId = "demo-account-123456789012"

        // Check if mock account already exists
        guard !accounts.contains(where: { $0.id == mockAccountId }) else {
            // Ensure mock data is loaded
            if snapshots[mockAccountId] == nil {
                snapshots[mockAccountId] = Self.createMockSnapshot()
            }
            return
        }

        // Add mock account
        let mockAccount = AWSAccount(
            id: mockAccountId,
            name: "Demo Account",
            accountId: "123456789012",
            profileName: nil,
            region: "us-east-1",
            color: .purple,
            isEnabled: true
        )
        accounts.append(mockAccount)

        // Add mock billing data
        snapshots[mockAccountId] = Self.createMockSnapshot()
    }

    private static func createMockSnapshot() -> BillingSnapshot {
        let calendar = Calendar.current
        let today = Date()

        // Generate daily costs for the current month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let dayOfMonth = calendar.component(.day, from: today)

        var dailyCosts: [DailyCost] = []
        for day in 1..<dayOfMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                let baseCost = Double.random(in: 45...85)
                dailyCosts.append(DailyCost(date: date, cost: baseCost))
            }
        }

        // Generate monthly costs for last 6 months
        var monthlyCosts: [MonthlyCost] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"

        for monthsAgo in (0...5).reversed() {
            if let date = calendar.date(byAdding: .month, value: -monthsAgo, to: today) {
                let monthStr = dateFormatter.string(from: date)
                let baseCost = Double.random(in: 1200...2200)
                let isComplete = monthsAgo > 0
                monthlyCosts.append(MonthlyCost(month: monthStr, cost: baseCost, isComplete: isComplete))
            }
        }

        let monthToDate = dailyCosts.reduce(0) { $0 + $1.cost }
        let lastMonth = monthlyCosts.dropLast().last?.cost ?? 1500

        return BillingSnapshot(
            accountId: "123456789012",
            accountName: "Demo Account",
            monthToDateCost: monthToDate,
            lastMonthCost: lastMonth,
            forecastedMonthCost: monthToDate * 1.4,
            dailyAverageCost: monthToDate / Double(max(dayOfMonth - 1, 1)),
            costByService: [
                ServiceCost(serviceName: "Amazon EC2", cost: monthToDate * 0.35, percentage: 35),
                ServiceCost(serviceName: "Amazon RDS", cost: monthToDate * 0.25, percentage: 25),
                ServiceCost(serviceName: "Amazon S3", cost: monthToDate * 0.15, percentage: 15),
                ServiceCost(serviceName: "AWS Lambda", cost: monthToDate * 0.12, percentage: 12),
                ServiceCost(serviceName: "Amazon CloudFront", cost: monthToDate * 0.08, percentage: 8),
                ServiceCost(serviceName: "Other", cost: monthToDate * 0.05, percentage: 5)
            ],
            dailyCosts: dailyCosts,
            monthlyCosts: monthlyCosts,
            updatedAt: Date(),
            currency: "USD"
        )
    }
    */
}

/// Refresh frequency options
public enum RefreshFrequency: String, CaseIterable, Sendable {
    case manual = "manual"
    case oneMinute = "1min"
    case twoMinutes = "2min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case oneHour = "1hour"

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        }
    }

    public var seconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        }
    }
}
