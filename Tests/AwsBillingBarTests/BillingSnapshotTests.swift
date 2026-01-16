import Testing
@testable import AwsBillingBarCore
import Foundation

@Suite("BillingSnapshot Tests")
struct BillingSnapshotTests {

    @Test("Calculate month over month change")
    func monthOverMonthChange() {
        let snapshot = BillingSnapshot(
            accountId: "123456789012",
            accountName: "Test Account",
            monthToDateCost: 150.0,
            lastMonthCost: 100.0,
            forecastedMonthCost: 200.0,
            dailyAverageCost: 10.0,
            costByService: [],
            dailyCosts: [],
            monthlyCosts: []
        )

        #expect(snapshot.monthOverMonthChange == 50.0)
    }

    @Test("Month over month change with zero last month")
    func monthOverMonthChangeZero() {
        let snapshot = BillingSnapshot(
            accountId: "123456789012",
            accountName: "Test Account",
            monthToDateCost: 150.0,
            lastMonthCost: 0.0,
            forecastedMonthCost: nil,
            dailyAverageCost: 10.0,
            costByService: [],
            dailyCosts: [],
            monthlyCosts: []
        )

        #expect(snapshot.monthOverMonthChange == nil)
    }

    @Test("Service cost short name")
    func serviceCostShortName() {
        let service = ServiceCost(
            serviceName: "Amazon Elastic Compute Cloud - Compute",
            cost: 50.0,
            percentage: 25.0
        )

        #expect(service.shortName == "Elastic Compute Cloud - Compute")
    }

    @Test("Monthly cost display month")
    func monthlyCostDisplayMonth() {
        let monthly = MonthlyCost(month: "2024-03", cost: 100.0)

        #expect(monthly.shortMonth == "Mar")
    }
}

@Suite("AWSAccount Tests")
struct AWSAccountTests {

    @Test("Account creation with defaults")
    func accountDefaults() {
        let account = AWSAccount(
            name: "Production",
            accountId: "123456789012"
        )

        #expect(account.name == "Production")
        #expect(account.accountId == "123456789012")
        #expect(account.region == "us-east-1")
        #expect(account.isEnabled == true)
        #expect(account.profileName == nil)
    }

    @Test("Account color display name")
    func colorDisplayName() {
        #expect(AccountColor.blue.displayName == "Blue")
        #expect(AccountColor.orange.displayName == "Orange")
    }
}

@Suite("AggregatedBilling Tests")
struct AggregatedBillingTests {

    @Test("Aggregate multiple snapshots")
    func aggregateSnapshots() {
        let snapshots = [
            BillingSnapshot(
                accountId: "111111111111",
                accountName: "Dev",
                monthToDateCost: 100.0,
                lastMonthCost: 80.0,
                forecastedMonthCost: 120.0,
                dailyAverageCost: 5.0,
                costByService: [],
                dailyCosts: [],
                monthlyCosts: []
            ),
            BillingSnapshot(
                accountId: "222222222222",
                accountName: "Prod",
                monthToDateCost: 500.0,
                lastMonthCost: 450.0,
                forecastedMonthCost: 600.0,
                dailyAverageCost: 25.0,
                costByService: [],
                dailyCosts: [],
                monthlyCosts: []
            )
        ]

        let aggregated = AggregatedBilling(snapshots: snapshots)

        #expect(aggregated.totalMonthToDate == 600.0)
        #expect(aggregated.totalLastMonth == 530.0)
        #expect(aggregated.totalForecast == 720.0)
        #expect(aggregated.snapshots.count == 2)
    }

    @Test("Aggregate empty snapshots")
    func aggregateEmpty() {
        let aggregated = AggregatedBilling(snapshots: [])

        #expect(aggregated.totalMonthToDate == 0.0)
        #expect(aggregated.totalLastMonth == 0.0)
        #expect(aggregated.totalForecast == nil)
    }
}
