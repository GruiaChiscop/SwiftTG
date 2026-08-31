// PermissionOnboardingRow.swift

import SwiftUI

struct PermissionOnboardingRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let actionTitle: String
    let isEnabled: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)

            if isEnabled {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    HStack {
                        if isWorking {
                            ProgressView()
                        }
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
