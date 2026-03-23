import SwiftUI

// MARK: - Hub Settings View

struct HubSettingsView: View {
    let safeArea: EdgeInsets

    @ObservedObject private var client = HubClient.shared
    @State private var savedUrls: [String] = HubClient.savedUrls()
    @State private var activeUrl: String = UserDefaults.standard.string(forKey: HubClient.activeUrlKey) ?? ""
    @State private var newUrlText: String = ""
    @State private var discovering: Bool = false
    @State private var discoverStatus: String = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    Text("HUB SETTINGS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .tracking(4)
                    Spacer()
                    // Live connection dot
                    Circle()
                        .fill(client.isConnected ? Color.green : Color.red.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 20)
                }
                .padding(.top, safeArea.top + 16)
                .padding(.bottom, 20)

                // Add new URL
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD HUB URL")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                        .tracking(3)
                        .padding(.horizontal, 20)

                    // Auto-discover button
                    Button {
                        startDiscovery()
                    } label: {
                        HStack(spacing: 8) {
                            if discovering {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(discovering ? "Searching..." : "Find Hub on Network")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.orange.opacity(discovering ? 0.4 : 0.85))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(discovering)
                    .padding(.horizontal, 20)

                    if !discoverStatus.isEmpty {
                        Text(discoverStatus)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                    }

                    HStack(spacing: 10) {
                        TextField("http://192.168.1.x:5050", text: $newUrlText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            addUrl()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .disabled(newUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)

                // Saved URLs list
                VStack(alignment: .leading, spacing: 8) {
                    Text("SAVED URLS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                        .tracking(3)
                        .padding(.horizontal, 20)

                    if savedUrls.isEmpty {
                        Text("No URLs saved yet")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(savedUrls, id: \.self) { url in
                                    HubUrlRow(
                                        url: url,
                                        isActive: url == activeUrl,
                                        onSetActive: { setActive(url) },
                                        onDelete: { deleteUrl(url) }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, safeArea.bottom + 16)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Actions

    private func startDiscovery() {
        discovering = true
        discoverStatus = "Looking for hub..."
        Task {
            let found = await HubDiscovery.discover()
            await MainActor.run {
                discovering = false
                if let url = found {
                    discoverStatus = "Found: \(url)"
                    newUrlText = url
                    addUrl()
                    // Always activate the freshly discovered URL and connect,
                    // regardless of how many saved URLs already exist.
                    setActive(url)
                } else {
                    discoverStatus = "No hub found on this network."
                }
            }
        }
    }

    private func addUrl() {
        let trimmed = newUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HubClient.addUrl(trimmed)
        reload()
        newUrlText = ""
        // Auto-set as active if first entry
        if savedUrls.count == 1 { setActive(trimmed) }
    }

    private func setActive(_ url: String) {
        HubClient.setActiveUrl(url)
        activeUrl = url
    }

    private func deleteUrl(_ url: String) {
        HubClient.removeUrl(url)
        reload()
        if activeUrl == url {
            activeUrl = UserDefaults.standard.string(forKey: HubClient.activeUrlKey) ?? ""
        }
    }

    private func reload() {
        savedUrls = HubClient.savedUrls()
    }
}

// MARK: - URL Row

private struct HubUrlRow: View {
    let url: String
    let isActive: Bool
    let onSetActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(isActive ? Color.green : Color.white.opacity(0.15))
                .frame(width: 8, height: 8)

            Text(url)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if !isActive {
                Button("Set Active") {
                    onSetActive()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
