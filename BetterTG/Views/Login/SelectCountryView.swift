// SelectCountryView.swift

import SwiftUI

struct SelectCountryView: View {
    @Binding var showSelectCountryView: Bool
    @Binding var selectedCountryNum: PhoneNumberInfo
    let countryNums: [PhoneNumberInfo]

    @State var query = ""
    
    var filteredCountries: [PhoneNumberInfo] {
        countryNums
            .filter { country in
                query.isEmpty
                    || country.name.lowercased().contains(query.lowercased())
                    || country.phoneNumberPrefix.lowercased().contains(query.lowercased())
                    || country.country.lowercased().contains(query.lowercased())
            }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredCountries, id: \.self) { info in
                Button {
                    selectedCountryNum = info
                    showSelectCountryView.toggle()
                } label: {
                    HStack {
                        Text(info.name)
                        Spacer()
                        Text("+\(info.phoneNumberPrefix)")
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel("\(info.name), calling code plus \(info.phoneNumberPrefix)")
                .accessibilityHint("Selects country")
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
