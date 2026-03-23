import SwiftUI

// MARK: - Gesture Settings View

struct GestureSettingsView: View {
    let safeArea: EdgeInsets
    let onBack: () -> Void

    @ObservedObject private var settings = GestureSettings.shared
    @State private var editingTrigger: GestureTrigger? = nil
    @State private var showResetConfirm = false

    // Groups in the order we want to show them
    private let groupOrder = [
        "Single-Finger Swipe",
        "Edge Swipe",
        "Long Press + Swipe",
        "Tap Combos",
        "Two-Finger",
        "Three-Finger",
        "Pinch & Rotate",
        "Device Gestures",
    ]

    private var triggersByGroup: [(String, [GestureTrigger])] {
        groupOrder.compactMap { group in
            let triggers = GestureTrigger.allCases.filter { $0.group == group }
            return triggers.isEmpty ? nil : (group, triggers)
        }
    }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                header

                // ── Calibration ───────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 2) {
                        calibrationSection
                            .padding(.top, 8)

                        // ── Gesture list ──────────────────────────────────
                        ForEach(triggersByGroup, id: \.0) { (group, triggers) in
                            gestureGroup(title: group, triggers: triggers)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeArea.bottom + 24)
                }
            }
        }
        // ── Action picker sheet ───────────────────────────────────────────
        .sheet(item: $editingTrigger) { trigger in
            ActionPickerView(trigger: trigger, settings: settings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Reset all gesture assignments to defaults?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset All", role: .destructive) { settings.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("GESTURE SETTINGS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(3)

            Spacer()

            Button(action: { showResetConfirm = true }) {
                Text("Reset")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeArea.top + 12)
        .padding(.bottom, 12)
    }

    // MARK: - Calibration Section

    private var calibrationSection: some View {
        VStack(spacing: 2) {
            sectionHeader("CALIBRATION")

            VStack(spacing: 12) {
                thresholdRow(
                    label: "Swipe Threshold",
                    detail: "Minimum drag to trigger a plain swipe",
                    value: $settings.swipeThreshold,
                    range: 10...120,
                    unit: "pt"
                )
                Divider().opacity(0.1)
                thresholdRow(
                    label: "Long Press + Swipe Threshold",
                    detail: "Min drag after long press",
                    value: $settings.lpSwipeThreshold,
                    range: 5...60,
                    unit: "pt"
                )
                Divider().opacity(0.1)
                thresholdRow(
                    label: "Long Press Duration",
                    detail: "How long to hold before activating",
                    value: $settings.longPressDuration,
                    range: 0.05...1.0,
                    unit: "s"
                )
                Divider().opacity(0.1)
                thresholdRow(
                    label: "Edge Zone Width",
                    detail: "Distance from edge for edge swipes",
                    value: $settings.edgeZoneWidth,
                    range: 20...100,
                    unit: "pt"
                )
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 14)
        }
    }

    // MARK: - Gesture Group

    private func gestureGroup(title: String, triggers: [GestureTrigger]) -> some View {
        VStack(spacing: 2) {
            sectionHeader(title)

            VStack(spacing: 0) {
                ForEach(Array(triggers.enumerated()), id: \.element.id) { idx, trigger in
                    if idx > 0 { Divider().opacity(0.1).padding(.leading, 46) }
                    gestureRow(trigger)
                }
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 14)
        }
    }

    private func gestureRow(_ trigger: GestureTrigger) -> some View {
        Button { editingTrigger = trigger } label: {
            HStack(spacing: 12) {
                Image(systemName: trigger.systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(trigger.isImplemented ? .white.opacity(0.7) : .white.opacity(0.3))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(trigger.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(trigger.isImplemented ? .white.opacity(0.88) : .white.opacity(0.4))
                        if !trigger.isImplemented {
                            Text("SOON")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.6))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(settings.action(for: trigger).rawValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(
                            settings.action(for: trigger) == .none
                                ? .white.opacity(0.2)
                                : .blue.opacity(0.9)
                        )
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.18))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .tracking(3)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func thresholdRow(
        label: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(unit == "s"
                     ? String(format: "%.2f%@", value.wrappedValue, unit)
                     : String(format: "%.0f%@", value.wrappedValue, unit))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.9))
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Text(detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            Slider(value: value, in: range)
                .tint(.blue.opacity(0.7))
        }
    }
}

// MARK: - Action Picker Sheet

private struct ActionPickerView: View {
    let trigger: GestureTrigger
    @ObservedObject var settings: GestureSettings
    @Environment(\.dismiss) private var dismiss

    private let groupOrder = [
        "Disabled", "Open Panel", "Toggle Panel",
        "Switch Panel", "Close", "Right Panel Pages", "Utility"
    ]

    private var actionsByGroup: [(String, [GestureAction])] {
        groupOrder.compactMap { group in
            let actions = GestureAction.allCases.filter { $0.group == group }
            return actions.isEmpty ? nil : (group, actions)
        }
    }

    var body: some View {
        ZStack {
            Color(white: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Sheet handle + title ───────────────────────────────────
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: trigger.systemImage)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                        Text(trigger.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue.opacity(0.9))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    if !trigger.isImplemented {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text("This gesture is not yet implemented — assignment saved for future use.")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.orange.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                    }
                }
                .padding(.bottom, 10)

                Divider().opacity(0.15)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(actionsByGroup, id: \.0) { (group, actions) in
                            VStack(spacing: 0) {
                                HStack {
                                    Text(group.uppercased())
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                        .tracking(2)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                                .padding(.bottom, 6)

                                VStack(spacing: 0) {
                                    ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                                        if idx > 0 { Divider().opacity(0.1).padding(.leading, 20) }
                                        actionRow(action)
                                    }
                                }
                                .background(Color.white.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func actionRow(_ action: GestureAction) -> some View {
        let isSelected = settings.action(for: trigger) == action
        return Button {
            settings.setAction(action, for: trigger)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            HStack {
                Text(action.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .blue : .white.opacity(0.75))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
