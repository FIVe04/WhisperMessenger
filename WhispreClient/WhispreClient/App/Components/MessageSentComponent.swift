//
//  MessageSentComponent.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 09.11.2025.
//

import SwiftUI

struct MessageSentComponent: View {
    @State var messageText: String = "Hello! How are you?"
    @State var timeText: String = "10:43"
    @State var formattedTime: String = ""
    
    func formatTime(from isoString: String) -> String {
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "HH:mm"
        
        let isoFormatterWithFrac = ISO8601DateFormatter()
        isoFormatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatterWithFrac.date(from: isoString) {
            return outputFormatter.string(from: date)
        }
        
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]
        if let date = isoFormatterNoFrac.date(from: isoString) {
            return outputFormatter.string(from: date)
        }
        
        let altFormatter = DateFormatter()
        altFormatter.locale = Locale(identifier: "en_US_POSIX")
        altFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        if let date = altFormatter.date(from: isoString) {
            return outputFormatter.string(from: date)
        }
        
        return ""
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(messageText)
                .font(Font.custom("Inter", size: 13))
                .fontWeight(.regular)
                .foregroundColor(.white)
                .padding(12)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 0
                    )
                    .fill(.accentBlue)
                )

            
            Text(formattedTime)
                .font(Font.custom("Inter", size: 11))
                .fontWeight(.regular)
                .foregroundColor(.colorTextGray)
                .padding(.leading, 8)
        }
        .onAppear {
            formattedTime = formatTime(from: timeText)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
    }
}

#Preview {
    MessageSentComponent()
}
