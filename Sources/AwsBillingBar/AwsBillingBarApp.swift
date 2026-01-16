import SwiftUI
import AppKit
import AwsBillingBarCore

@main
struct AwsBillingBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("AWS Billing", systemImage: "dollarsign.circle") {
            MenuContentView(settingsController: appDelegate.settingsController)
                .environment(appDelegate.billingStore)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContentView: View {
    @Environment(BillingStore.self) private var store
    let settingsController: SettingsWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeaderView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    if store.accounts.isEmpty {
                        NoAccountsView()
                            .frame(maxWidth: .infinity)
                    } else {
                        BillingSummaryView(store: store)
                            .frame(maxWidth: .infinity)

                        ForEach(store.accounts.filter(\.isEnabled)) { account in
                            AccountCardView(
                                account: account,
                                snapshot: store.snapshot(for: account.id),
                                error: store.errors[account.id]
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 400)

            Divider()

            VStack(spacing: 4) {
                Button {
                    Task {
                        await store.refresh()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(store.isRefreshing ? "Refreshing..." : "Refresh Now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("r")
                .disabled(store.isRefreshing)

                if let lastRefresh = store.lastRefresh {
                    let formatter = RelativeDateTimeFormatter()
                    Text("Updated \(formatter.localizedString(for: lastRefresh, relativeTo: Date()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 8) {
                Button {
                    settingsController.showSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(",")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let billingStore = BillingStore()
    lazy var settingsController = SettingsWindowController(store: billingStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        billingStore.startTimer()

        Task {
            await billingStore.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        billingStore.stopTimer()
    }
}
