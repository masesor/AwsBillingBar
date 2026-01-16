import AppKit
import SwiftUI
import AwsBillingBarCore

/// Controls the menu bar status item and its menu
@MainActor
final class StatusItemController: NSObject {
    private let store: BillingStore
    private let statusItem: NSStatusItem
    private var menu: NSMenu?
    private var hostingView: NSHostingView<AnyView>?

    init(store: BillingStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupObservation()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        // Set initial icon
        updateIcon()

        // Set up menu
        rebuildMenu()

        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupObservation() {
        // Observe store changes
        withObservationTracking {
            _ = self.store.snapshots
            _ = self.store.errors
            _ = self.store.isRefreshing
            _ = self.store.accounts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.rebuildMenu()
                self?.setupObservation()
            }
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }

        rebuildMenu()
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        // Use SF Symbol for reliability
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let icon = NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "AWS Billing")?.withSymbolConfiguration(config) {
            icon.isTemplate = true
            button.image = icon
        } else {
            // Fallback to text if symbol not available
            button.title = "$"
        }
        button.toolTip = tooltipText()
    }

    private func tooltipText() -> String {
        if store.accounts.isEmpty {
            return "AWS Billing Bar - Click to configure"
        }

        let total = store.aggregated.totalMonthToDate
        return "AWS MTD: \(formatCurrency(total))"
    }

    private func rebuildMenu() {
        let newMenu = NSMenu()

        // Header
        let headerItem = NSMenuItem()
        headerItem.view = NSHostingView(rootView: MenuHeaderView())
        newMenu.addItem(headerItem)

        newMenu.addItem(NSMenuItem.separator())

        if store.accounts.isEmpty {
            // No accounts configured
            let noAccountsItem = NSMenuItem()
            noAccountsItem.view = NSHostingView(rootView: NoAccountsView())
            newMenu.addItem(noAccountsItem)
        } else {
            // Summary card
            let summaryItem = NSMenuItem()
            let summaryView = BillingSummaryView(store: store)
            summaryItem.view = NSHostingView(rootView: summaryView)
            newMenu.addItem(summaryItem)

            newMenu.addItem(NSMenuItem.separator())

            // Individual account cards
            for account in store.accounts.filter(\.isEnabled) {
                let accountItem = NSMenuItem()
                let accountView = AccountCardView(
                    account: account,
                    snapshot: store.snapshot(for: account.id),
                    error: store.errors[account.id]
                )
                accountItem.view = NSHostingView(rootView: accountView)
                newMenu.addItem(accountItem)
            }
        }

        newMenu.addItem(NSMenuItem.separator())

        // Refresh button
        let refreshItem = NSMenuItem(
            title: store.isRefreshing ? "Refreshing..." : "Refresh Now",
            action: store.isRefreshing ? nil : #selector(refreshClicked),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        newMenu.addItem(refreshItem)

        // Last updated
        if let lastRefresh = store.lastRefresh {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let timeAgo = formatter.localizedString(for: lastRefresh, relativeTo: Date())
            let lastUpdateItem = NSMenuItem(title: "Updated \(timeAgo)", action: nil, keyEquivalent: "")
            lastUpdateItem.isEnabled = false
            newMenu.addItem(lastUpdateItem)
        }

        newMenu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        newMenu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit AWS Billing Bar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        newMenu.addItem(quitItem)

        self.menu = newMenu
    }

    @objc private func refreshClicked() {
        Task {
            await store.refresh()
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}


struct MenuHeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("AWS Billing")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 280)
    }
}


struct NoAccountsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No AWS Accounts Configured")
                .font(.headline)

            Text("Open Settings to add your AWS accounts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 280)
        .padding()
    }
}
