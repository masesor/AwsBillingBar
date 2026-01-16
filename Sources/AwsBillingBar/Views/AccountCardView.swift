import SwiftUI
import Charts
import AwsBillingBarCore

/// Card view for an individual AWS account
struct AccountCardView: View {
    let account: AWSAccount
    let snapshot: BillingSnapshot?
    let error: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            accountHeader

            if let error {
                errorView(error)
            } else if let snapshot {
                costSummary(snapshot)

                if isExpanded {
                    Divider()
                        .padding(.vertical, 8)

                    expandedContent(snapshot)
                }
            } else {
                loadingView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(account.color.swiftUIColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }


    private var accountHeader: some View {
        HStack {
            Circle()
                .fill(account.color.swiftUIColor)
                .frame(width: 10, height: 10)

            Text(account.name)
                .font(.subheadline.weight(.medium))

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private func costSummary(_ snapshot: BillingSnapshot) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MTD")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(formatCurrency(snapshot.monthToDateCost))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Daily Avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(formatCurrency(snapshot.dailyAverageCost))
                    .font(.caption.monospacedDigit())
            }

            if let change = snapshot.monthOverMonthChange {
                ChangeIndicator(change: change)
            }
        }
    }

    private func expandedContent(_ snapshot: BillingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Monthly trend chart
            MonthlyTrendChart(monthlyCosts: snapshot.monthlyCosts)
                .frame(height: 80)

            // Top services
            if !snapshot.costByService.isEmpty {
                TopServicesView(services: Array(snapshot.costByService.prefix(5)))
            }

            // Forecast
            if let forecast = snapshot.forecastedMonthCost {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Forecast:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatCurrency(forecast))
                        .font(.caption.weight(.medium).monospacedDigit())

                    Spacer()

                    Text("\(snapshot.daysRemainingInMonth) days left")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}


struct MonthlyTrendChart: View {
    let monthlyCosts: [MonthlyCost]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("6 Month Trend")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if monthlyCosts.isEmpty {
                Text("No historical data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(monthlyCosts) { item in
                    BarMark(
                        x: .value("Month", item.shortMonth),
                        y: .value("Cost", item.cost)
                    )
                    .foregroundStyle(item.isComplete ? .orange : .orange.opacity(0.5))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(formatShortCurrency(cost))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatShortCurrency(_ amount: Double) -> String {
        if amount >= 1000 {
            return "$\(Int(amount / 1000))k"
        }
        return "$\(Int(amount))"
    }
}


struct TopServicesView: View {
    let services: [ServiceCost]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Services")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(services) { service in
                ServiceRow(service: service)
            }
        }
    }
}

struct ServiceRow: View {
    let service: ServiceCost

    var body: some View {
        HStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))

                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * min(service.percentage / 100, 1))
                }
            }
            .frame(width: 40, height: 4)
            .clipShape(Capsule())

            Text(service.shortName)
                .font(.caption2)
                .lineLimit(1)

            Spacer()

            Text(formatCurrency(service.cost))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
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
