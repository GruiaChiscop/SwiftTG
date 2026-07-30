// SelectCountryView.swift

import SwiftUI

struct SelectCountryView: View {
    @Binding var showSelectCountryView: Bool
    let countryNums: [PhoneNumberInfo]
    let selectCountry: (PhoneNumberInfo) -> Void

    @State var query = ""
    
    var filteredCountries: [PhoneNumberInfo] {
        countryNums
            .filter { $0.matches(query) }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredCountries) { info in
                Button {
                    selectCountry(info)
                    showSelectCountryView.toggle()
                } label: {
                    HStack {
                        Text(info.flagEmoji)
                        Text(info.name)
                        Spacer()
                        Text("+\(info.phoneNumberPrefix)")
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(info.accessibilityLabel)
            }
            .background(.black)
            .padding(.top, -20)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showSelectCountryView.toggle()
                    }
                }
            }
        }
    }
}
