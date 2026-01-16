import Foundation

/// A snapshot of billing data for an AWS account
public struct BillingSnapshot: Codable, Sendable {
    public let accountId: String
    public let accountName: String

    /// Current month-to-date cost
    public let monthToDateCost: Double

    /// Last month's total cost
    public let lastMonthCost: Double

    /// Forecasted cost for the current month
    public let forecastedMonthCost: Double?

    /// Daily average cost this month
    public let dailyAverageCost: Double

    /// Cost breakdown by service
    public let costByService: [ServiceCost]

    /// Daily cost history for the current month
    public let dailyCosts: [DailyCost]

    /// Monthly cost history (last 6 months)
    public let monthlyCosts: [MonthlyCost]

    /// When this data was fetched
    public let updatedAt: Date

    /// Currency code (typically USD)
    public let currency: String

    public init(
        accountId: String,
        accountName: String,
        monthToDateCost: Double,
        lastMonthCost: Double,
        forecastedMonthCost: Double?,
        dailyAverageCost: Double,
        costByService: [ServiceCost],
        dailyCosts: [DailyCost],
        monthlyCosts: [MonthlyCost],
        updatedAt: Date = Date(),
        currency: String = "USD"
    ) {
        self.accountId = accountId
        self.accountName = accountName
        self.monthToDateCost = monthToDateCost
        self.lastMonthCost = lastMonthCost
        self.forecastedMonthCost = forecastedMonthCost
        self.dailyAverageCost = dailyAverageCost
        self.costByService = costByService
        self.dailyCosts = dailyCosts
        self.monthlyCosts = monthlyCosts
        self.updatedAt = updatedAt
        self.currency = currency
    }

    /// Change from last month (percentage)
    public var monthOverMonthChange: Double? {
        guard lastMonthCost > 0 else { return nil }
        return ((monthToDateCost - lastMonthCost) / lastMonthCost) * 100
    }

    /// Days remaining in the current month
    public var daysRemainingInMonth: Int {
        let calendar = Calendar.current
        let today = Date()
        guard let range = calendar.range(of: .day, in: .month, for: today),
              let dayOfMonth = calendar.dateComponents([.day], from: today).day else {
            return 0
        }
        return range.count - dayOfMonth
    }
}

/// Cost for a specific AWS service
public struct ServiceCost: Codable, Sendable, Identifiable {
    public var id: String { serviceName }
    public let serviceName: String
    public let cost: Double
    public let percentage: Double

    public init(serviceName: String, cost: Double, percentage: Double) {
        self.serviceName = serviceName
        self.cost = cost
        self.percentage = percentage
    }

    /// Shortened service name for display
    public var shortName: String {
        serviceName
            .replacingOccurrences(of: "Amazon ", with: "")
            .replacingOccurrences(of: "AWS ", with: "")
    }
}

/// Daily cost entry
public struct DailyCost: Codable, Sendable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let cost: Double

    public init(date: Date, cost: Double) {
        self.date = date
        self.cost = cost
    }
}

/// Monthly cost entry
public struct MonthlyCost: Codable, Sendable, Identifiable {
    public var id: String { month }
    public let month: String // "2024-01" format
    public let cost: Double
    public let isComplete: Bool

    public init(month: String, cost: Double, isComplete: Bool = true) {
        self.month = month
        self.cost = cost
        self.isComplete = isComplete
    }

    public var displayMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: month) else { return month }
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    public var shortMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: month) else { return month }
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}

/// Aggregated billing data across all accounts
public struct AggregatedBilling: Sendable {
    public let totalMonthToDate: Double
    public let totalLastMonth: Double
    public let totalForecast: Double?
    public let snapshots: [BillingSnapshot]
    public let updatedAt: Date

    public init(snapshots: [BillingSnapshot]) {
        self.snapshots = snapshots
        self.totalMonthToDate = snapshots.reduce(0) { $0 + $1.monthToDateCost }
        self.totalLastMonth = snapshots.reduce(0) { $0 + $1.lastMonthCost }

        let forecasts = snapshots.compactMap { $0.forecastedMonthCost }
        self.totalForecast = forecasts.isEmpty ? nil : forecasts.reduce(0, +)

        self.updatedAt = snapshots.map(\.updatedAt).max() ?? Date()
    }

    public var monthOverMonthChange: Double? {
        guard totalLastMonth > 0 else { return nil }
        return ((totalMonthToDate - totalLastMonth) / totalLastMonth) * 100
    }
}
