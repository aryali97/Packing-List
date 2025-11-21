import SwiftUI

struct PackingListCard: View {
    let packingList: PackingList
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(packingList.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
            }
            
            Spacer()
            
            if let date = packingList.tripDate {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if packingList.isTemplate {
                Text("Template")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Image(systemName: "checklist")
                Text("\(packingList.rootItem.children.count) items")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(height: 120)
        .background(Color(hex: packingList.colorHex).opacity(0.1))
        .background(.background)
        .cornerRadius(12)
        .shadow(radius: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: packingList.colorHex), lineWidth: 1)
        )
    }
}

// Helper for Hex color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
