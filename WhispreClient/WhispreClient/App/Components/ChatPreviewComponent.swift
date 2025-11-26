//
//  ChatPreviewComponent.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 08.11.2025.
//

import SwiftUI

struct ChatPreviewComponent: View {
    var username: String = "test2"
    var last_message: String = "Hi, test!"
    var last_message_time: String = "11:30"
    var last_message_count: Int = 1
    
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
        HStack {
            Image("avatar")
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(username)
                    .font(Font.custom("Inter", size: 15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                Text(last_message)
                    .font(Font.custom("Inter", size: 13))
                    .fontWeight(.regular)
                    .foregroundStyle(Color("ColorTextGray"))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(formatTime(from: last_message_time))
                    .font(Font.custom("Inter", size: 13))
                    .fontWeight(.medium)
                    .foregroundStyle(Color("ColorTextGray"))
                    .multilineTextAlignment(.center)
                if (last_message_count > 0) {
                    ZStack {
                        Circle()
                            .fill(.accentBlue)
                            .frame(width: 24, height: 24)
                        
                        Text("\(last_message_count)")
                            .font(Font.custom("Inter", size: 13))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                }

            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

//#Preview {
//    ChatPreviewComponent()
//}
