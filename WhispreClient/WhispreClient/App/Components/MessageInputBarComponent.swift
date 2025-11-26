import SwiftUI

struct MessageInputBarComponent: View {
    @Binding var message: String
    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 36

    var onSend: (String) -> Void
    
    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 120
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: {
            }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray)
            }
            
            // 📝 Текстовое поле
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("Сообщение…")
                        .foregroundStyle(.gray)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                
                TextEditor(text: $message)
                    .focused($isFocused)
                    .frame(height: textHeight)
                    .padding(6)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onChange(of: message) { _ in
                        recalcTextHeight()
                    }
            }
            
            Button(action: {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
                withAnimation {
                    message = ""
                    recalcTextHeight()
                }
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20, weight: .medium))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(
                        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .gray
                        : .accentColor
                    )
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .ignoresSafeArea(edges: [.bottom])
        .onAppear {
            recalcTextHeight()
        }
        .animation(.easeInOut(duration: 0.15), value: textHeight)
    }
    
    private func recalcTextHeight() {
        let uiFont = UIFont.preferredFont(forTextStyle: .body)
        let width = UIScreen.main.bounds.width - 100

        let boundingRect = message.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: uiFont],
            context: nil
        )
        
        let newHeight = max(minHeight, min(boundingRect.height + 24, maxHeight))
        if abs(newHeight - textHeight) > 1 {
            textHeight = newHeight
        }
    }
}

//#Preview {
//    VStack {
//        Spacer()
//        MessageInputBarComponent { text in
//            print("Send:", text)
//        }
//    }
//    .background(Color(.systemGroupedBackground))
//}
