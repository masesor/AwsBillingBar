import SwiftUI
import AwsBillingBarCore

/// Main settings view
struct SettingsView: View {
    @Environment(BillingStore.self) private var store

    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem {
                    Label("Accounts", systemImage: "person.2.circle")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}


struct AccountsSettingsView: View {
    @Environment(BillingStore.self) private var store
    @State private var showingAddAccount = false
    @State private var editingAccount: AWSAccount?
    @State private var availableProfiles: [String] = []

    // Add account form fields
    @State private var newName = ""
    @State private var newAccountId = ""
    @State private var newProfile: String?
    @State private var newRegion = "us-east-1"
    @State private var newColor: AccountColor = .blue

    private let regions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-central-1",
        "ap-northeast-1", "ap-southeast-1", "ap-southeast-2"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if showingAddAccount {
                // Inline add account form
                addAccountForm
            } else {
                // Account list
                List {
                    if store.accounts.isEmpty {
                        ContentUnavailableView {
                            Label("No Accounts", systemImage: "cloud")
                        } description: {
                            Text("Add an AWS account to start tracking costs")
                        } actions: {
                            Button("Add Account") {
                                showingAddAccount = true
                            }
                        }
                    } else {
                        ForEach(store.accounts) { account in
                            AccountRow(
                                account: account,
                                onEdit: { editingAccount = account },
                                onDelete: { store.removeAccount(account) },
                                onToggle: { enabled in
                                    var updated = account
                                    updated.isEnabled = enabled
                                    store.updateAccount(updated)
                                }
                            )
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                // Bottom toolbar
                HStack {
                    Button(action: { showingAddAccount = true }) {
                        Label("Add Account", systemImage: "plus")
                    }

                    Spacer()

                    Button("Refresh All") {
                        Task {
                            await store.refresh()
                        }
                    }
                    .disabled(store.isRefreshing)
                }
                .padding()
            }
        }
        .task {
            availableProfiles = await store.availableProfiles()
        }
    }

    private var addAccountForm: some View {
        Form {
            Section("New AWS Account") {
                TextField("Display Name (e.g., Production)", text: $newName)
                TextField("Account ID (12 digits)", text: $newAccountId)

                Picker("AWS Profile", selection: $newProfile) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableProfiles, id: \.self) { profile in
                        Text(profile).tag(profile as String?)
                    }
                }

                Picker("Region", selection: $newRegion) {
                    ForEach(regions, id: \.self) { region in
                        Text(region).tag(region)
                    }
                }

                Picker("Color", selection: $newColor) {
                    ForEach(AccountColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                        .tag(color)
                    }
                }
            }

            Section {
                HStack {
                    Button("Cancel") {
                        resetForm()
                        showingAddAccount = false
                    }

                    Spacer()

                    Button("Add Account") {
                        let account = AWSAccount(
                            name: newName.isEmpty ? "AWS Account" : newName,
                            accountId: newAccountId,
                            profileName: newProfile,
                            region: newRegion,
                            color: newColor
                        )
                        store.addAccount(account)
                        resetForm()
                        showingAddAccount = false

                        Task {
                            await store.refresh()
                        }
                    }
                    .disabled(newAccountId.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetForm() {
        newName = ""
        newAccountId = ""
        newProfile = nil
        newRegion = "us-east-1"
        newColor = .blue
    }
}


struct AccountRow: View {
    let account: AWSAccount
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void

    @State private var isEnabled: Bool

    init(account: AWSAccount, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.account = account
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: account.isEnabled)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(account.color.swiftUIColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(account.accountId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let profile = account.profileName {
                        Text("Profile: \(profile)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    onToggle(newValue)
                }

            Menu {
                Button("Edit...", action: onEdit)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 4)
    }
}


struct AddAccountSheet: View {
    @Environment(BillingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let availableProfiles: [String]

    @State private var name = ""
    @State private var accountId = ""
    @State private var selectedProfile: String?
    @State private var region = "us-east-1"
    @State private var color: AccountColor = .blue
    @FocusState private var isNameFieldFocused: Bool

    private let regions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-central-1",
        "ap-northeast-1", "ap-southeast-1", "ap-southeast-2"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Add AWS Account")
                .font(.headline)
                .padding()

            Form {
                TextField("Display Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)

                TextField("Account ID", text: $accountId)
                    .textFieldStyle(.roundedBorder)

                Picker("AWS Profile", selection: $selectedProfile) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableProfiles, id: \.self) { profile in
                        Text(profile).tag(profile as String?)
                    }
                }

                Picker("Region", selection: $region) {
                    ForEach(regions, id: \.self) { region in
                        Text(region).tag(region)
                    }
                }

                Picker("Color", selection: $color) {
                    ForEach(AccountColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                        .tag(color)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Account") {
                    let account = AWSAccount(
                        name: name.isEmpty ? "AWS Account" : name,
                        accountId: accountId,
                        profileName: selectedProfile,
                        region: region,
                        color: color
                    )
                    store.addAccount(account)
                    dismiss()

                    Task {
                        await store.refresh()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountId.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            // Ensure the window becomes key and accepts keyboard input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow {
                    window.makeKey()
                }
                isNameFieldFocused = true
            }
        }
    }
}


struct EditAccountSheet: View {
    @Environment(BillingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let account: AWSAccount
    let availableProfiles: [String]

    @State private var name: String
    @State private var accountId: String
    @State private var selectedProfile: String?
    @State private var region: String
    @State private var color: AccountColor
    @FocusState private var isNameFieldFocused: Bool

    private let regions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-central-1",
        "ap-northeast-1", "ap-southeast-1", "ap-southeast-2"
    ]

    init(account: AWSAccount, availableProfiles: [String]) {
        self.account = account
        self.availableProfiles = availableProfiles
        self._name = State(initialValue: account.name)
        self._accountId = State(initialValue: account.accountId)
        self._selectedProfile = State(initialValue: account.profileName)
        self._region = State(initialValue: account.region)
        self._color = State(initialValue: account.color)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit AWS Account")
                .font(.headline)
                .padding()

            Form {
                TextField("Display Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)

                TextField("Account ID", text: $accountId)
                    .textFieldStyle(.roundedBorder)

                Picker("AWS Profile", selection: $selectedProfile) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableProfiles, id: \.self) { profile in
                        Text(profile).tag(profile as String?)
                    }
                }

                Picker("Region", selection: $region) {
                    ForEach(regions, id: \.self) { region in
                        Text(region).tag(region)
                    }
                }

                Picker("Color", selection: $color) {
                    ForEach(AccountColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                        .tag(color)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    var updated = account
                    updated.name = name
                    updated.accountId = accountId
                    updated.profileName = selectedProfile
                    updated.region = region
                    updated.color = color
                    store.updateAccount(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountId.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow {
                    window.makeKey()
                }
                isNameFieldFocused = true
            }
        }
    }
}


struct GeneralSettingsView: View {
    @Environment(BillingStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Form {
            Section("Refresh") {
                Picker("Auto-refresh", selection: $store.refreshFrequency) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Text("AWS billing data typically updates every few hours. Frequent refreshes won't show new data faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: .constant(false))
                    .disabled(true)

                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}


struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("AWS Billing Bar")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Monitor your AWS costs from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
