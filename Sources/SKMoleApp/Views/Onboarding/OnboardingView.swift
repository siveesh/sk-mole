import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Setup Step", selection: $page) {
                Text("Welcome").tag(0)
                Text("Access").tag(1)
                Text("Defaults").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            TabView(selection: $page) {
                WelcomeStep()
                    .tag(0)
                AccessStep(model: model)
                    .tag(1)
                FinishStep(model: model)
                    .tag(2)
            }

            footer
                .padding(24)
                .background(.ultraThinMaterial)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(AppPalette.canvas)
        .task {
            model.refreshFullDiskAccessStatus()
            await model.refreshPrivilegedHelperState()
            model.refreshMenuBarCompanionState()
        }
    }

    private var footer: some View {
        HStack {
            if page > 0 {
                Button("Back") {
                    page -= 1
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Skip for Now") {
                model.dismissOnboardingForNow()
            }
            .buttonStyle(.bordered)

            Button(primaryActionTitle) {
                if page == 2 {
                    model.completeOnboarding()
                } else {
                    page += 1
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var primaryActionTitle: String {
        page == 2 ? "Finish Setup" : "Continue"
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to SK Mole")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("A safety-first Mac toolkit that cleans, uninstalls, inspects storage, watches system health, and gives you clearer control over maintenance work.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                FeatureCard(symbol: "sparkles.rectangle.stack", title: "Cleanup", subtitle: "Review reclaimable files before action.")
                FeatureCard(symbol: "xmark.app", title: "Uninstall", subtitle: "Preview remnants and reset app data deliberately.")
                FeatureCard(symbol: "internaldrive", title: "Storage", subtitle: "Drill into volumes, large files, and hidden pressure.")
                FeatureCard(symbol: "gauge.with.dots.needle.50percent", title: "Monitoring", subtitle: "See history, system pressure, and quick actions.")
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct AccessStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Permission Center")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("SK Mole works without forcing broad access, but giving it a few approvals up front makes deeper scans smoother and easier to explain.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                PermissionRow(
                    title: "Full Disk Access",
                    subtitle: model.fullDiskAccessStatus.detail,
                    pillTitle: model.fullDiskAccessStatus.title,
                    tint: model.fullDiskAccessStatus.needsAttention ? AppPalette.amber : AppPalette.accent,
                    primaryActionTitle: "Open Privacy & Security",
                    secondaryActionTitle: "Re-check",
                    onPrimaryAction: model.openFullDiskAccessSettings,
                    onSecondaryAction: model.refreshFullDiskAccessStatus
                )

                PermissionRow(
                    title: "Privileged Helper",
                    subtitle: model.privilegedHelperState.detail,
                    pillTitle: model.privilegedHelperState.summary,
                    tint: model.privilegedHelperState.isEnabled ? AppPalette.accent : AppPalette.amber,
                    primaryActionTitle: "Open Optimize",
                    secondaryActionTitle: "Refresh Status",
                    onPrimaryAction: {
                        model.open(section: .optimize)
                    },
                    onSecondaryAction: {
                        Task { await model.refreshPrivilegedHelperState() }
                    }
                )

                PermissionRow(
                    title: "Menu Bar Companion",
                    subtitle: model.menuBarCompanionState.detail,
                    pillTitle: model.menuBarCompanionState.summary,
                    tint: model.menuBarCompanionState.isRunning ? AppPalette.accent : AppPalette.sky,
                    primaryActionTitle: "Launch Companion",
                    secondaryActionTitle: "Refresh Status",
                    onPrimaryAction: {
                        model.menuBarCompanionEnabled = true
                        model.launchMenuBarCompanionNow()
                    },
                    onSecondaryAction: model.refreshMenuBarCompanionState
                )
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct FinishStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Shape the Daily Flow")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("A few defaults make SK Mole feel much more native once the first-run setup is out of the way.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            SectionCard(
                title: "Launch Behavior",
                subtitle: "Set the first window target and optionally keep the menu bar companion around for quick reopen and quit flows.",
                symbol: "sparkles.tv"
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(
                        "Main window startup",
                        selection: Binding(
                            get: { model.startupPreference },
                            set: { model.startupPreference = $0 }
                        )
                    ) {
                        ForEach(StartupPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }

                    Toggle(
                        "Enable the menu bar companion",
                        isOn: Binding(
                            get: { model.menuBarCompanionEnabled },
                            set: { model.menuBarCompanionEnabled = $0 }
                        )
                    )

                    Toggle(
                        "Show Full Disk Access reminders",
                        isOn: Binding(
                            get: { model.showFullDiskAccessReminders },
                            set: { model.showFullDiskAccessReminders = $0 }
                        )
                    )
                }
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let pillTitle: String
    let tint: Color
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        SectionCard(title: title, subtitle: subtitle, symbol: "lock.shield") {
            HStack(alignment: .center, spacing: 14) {
                Pill(title: pillTitle, tint: tint)
                Spacer()
                Button(primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(.borderedProminent)
                Button(secondaryActionTitle, action: onSecondaryAction)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppPalette.accent)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.78))
        )
    }
}
