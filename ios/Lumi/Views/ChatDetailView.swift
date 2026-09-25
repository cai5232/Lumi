import SwiftUI

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel

    init(model: ChatViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ChatViewModel())
    }

    var body: some View {
        ZStack {
            Color(red: 0.984, green: 0.961, blue: 0.961).ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if model.isSending { thinkingBubble }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 86)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: [.top, .bottom])
                .onChange(of: model.messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { composer }
        .task { await model.load() }
        .alert("Lumi", isPresented: .constant(model.errorMessage != nil)) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var topBar: some View {
        HStack {
            glassCircleButton("line.3.horizontal")
            Spacer()
            glassCircleButton("phone")
            HStack(spacing: 0) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 42)
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 24)
                Image(systemName: "checkmark.square")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 42)
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 24)
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 42)
            }
            .foregroundStyle(.black.opacity(0.58))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().fill(Color(red: 0.984, green: 0.961, blue: 0.961).opacity(0.48)))
            .overlay(Capsule().stroke(Color.white.opacity(0.82), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 8)
        .padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("回复沉小岑", text: $model.draft)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                    .background(Color.white.opacity(0.18), in: Circle())
                Text("Lumi")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.2), in: Capsule())
                Spacer()
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                    .background(Color.white.opacity(0.18), in: Circle())
                Button { Task { await model.send() } } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 36)
                        .background(.black.opacity(0.8), in: Circle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 30).fill(Color(red: 0.984, green: 0.961, blue: 0.961).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.82), lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 8)
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 7)
    }

    private func glassCircleButton(_ systemName: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().fill(Color(red: 0.984, green: 0.961, blue: 0.961).opacity(0.48)))
                .overlay(Circle().stroke(Color.white.opacity(0.82), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        }
    }

    @ViewBuilder private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.content)
                .foregroundStyle(.black)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color(red: 0.961, green: 0.925, blue: 0.925) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 21))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 4) {
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
                Text("正在想")
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white)
            .clipShape(Capsule())
            Spacer()
        }
    }
}
