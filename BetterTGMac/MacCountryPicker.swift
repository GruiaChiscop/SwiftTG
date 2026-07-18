// MacCountryPicker.swift

import SwiftUI

// MARK: - MacCountryPicker

struct MacCountryPicker: View {
    // MARK: Internal

    let selectedCountry: PhoneNumberInfo?
    let countries: [PhoneNumberInfo]
    let selectCountry: (PhoneNumberInfo) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Country")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("Search countries", text: $query)
                .textFieldStyle(.roundedBorder)

            if countries.isEmpty {
                Spacer()
                ProgressView("Loading countries…")
                Spacer()
            } else if filteredCountries.isEmpty {
                Spacer()
                ContentUnavailableView.search(text: query)
                Spacer()
            } else {
                List(filteredCountries) { country in
                    Button {
                        selectCountry(country)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text(country.flagEmoji)
                                .font(.title2)
                                .accessibilityHidden(true)
                            Text(country.name)
                            Spacer()
                            Text("+\(country.phoneNumberPrefix)")
                                .foregroundStyle(.secondary)
                            if country == selectedCountry {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(country.accessibilityLabel)
                    .accessibilityHint("Selects country")
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 520)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredCountries: [PhoneNumberInfo] {
        countries.filter { $0.matches(query) }
    }
}
