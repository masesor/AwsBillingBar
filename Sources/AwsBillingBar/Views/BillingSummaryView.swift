import SwiftUI
import Charts
import AwsBillingBarCore

/// Summary view showing aggregated billing across all accounts
struct BillingSummaryView: View {
    let store: BillingStore

    private var aggregated: AggregatedBilling {
        store.aggregated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Total cost header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Month to Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatCurrency(aggregated.totalMonthToDate))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Change indicator
                if let change = aggregated.monthOverMonthChange {
                    ChangeIndicator(change: change)
                }
            }

            // Comparison row
            HStack(spacing: 16) {
                MetricPill(
                    title: "Last Month",
                    value: formatCurrency(aggregated.totalLastMonth),
                    icon: "calendar.badge.clock"
                )

                if let forecast = aggregated.totalForecast {
                    MetricPill(
                        title: "Forecast",
                        value: formatCurrency(forecast),
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
            }

            // Mini chart if we have data
            if !aggregated.snapshots.isEmpty {
                MiniCostChart(snapshots: aggregated.snapshots)
                    .frame(height: 60)
            }

            // Account breakdown
            if aggregated.snapshots.count > 1 {
                Divider()

                AccountBreakdownView(snapshots: aggregated.snapshots, accounts: store.accounts)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}


struct ChangeIndicator: View {
    let change: Double

    private var isPositive: Bool { change > 0 }
    private var color: Color {
        if abs(change) < 5 { return .secondary }
        return isPositive ? .red : .green
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)
            Text("\(abs(change), specifier: "%.1f")%")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}


struct MetricPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.monospacedDigit().bold())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}


struct MiniCostChart: View {
    let snapshots: [BillingSnapshot]

    private var dailyCosts: [DailyCost] {
        // Combine daily costs from all snapshots
        var combined: [Date: Double] = [:]
        for snapshot in snapshots {
            for daily in snapshot.dailyCosts {
                let key = Calendar.current.startOfDay(for: daily.date)
                combined[key, default: 0] += daily.cost
            }
        }
        return combined.map { DailyCost(date: $0.key, cost: $0.value) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        if dailyCosts.isEmpty {
            Text("No data available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(dailyCosts) { item in
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Cost", item.cost)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0.6), .orange.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Cost", item.cost)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}


struct AccountBreakdownView: View {
    let snapshots: [BillingSnapshot]
    let accounts: [AWSAccount]

    private var total: Double {
        snapshots.reduce(0) { $0 + $1.monthToDateCost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Account")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(snapshots, id: \.accountId) { snapshot in
                let account = accounts.first { $0.accountId == snapshot.accountId }
                AccountBreakdownRow(
                    name: snapshot.accountName,
                    cost: snapshot.monthToDateCost,
                    percentage: total > 0 ? (snapshot.monthToDateCost / total) * 100 : 0,
                    color: account?.color ?? .blue
                )
            }
        }
    }
}

struct AccountBreakdownRow: View {
    let name: String
    let cost: Double
    let percentage: Double
    let color: AccountColor

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(formatCurrency(cost))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text("\(percentage, specifier: "%.0f")%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}


extension AccountColor {
    var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .teal: return .teal
        }
    }
}
