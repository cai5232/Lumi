import SwiftUI

struct ChatDetailView: View {
    @State private var model: ChatViewModel

    init(model: ChatViewModel = ChatViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.961, green: 0.925, blue: 0.925).ignoresSafeArea()

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
                    .padding(.top, 8)
                    .padding(.bottom, 78)
                }
                .scrollIndicators(.hidden)
                .mask(LinearGradient(colors: [.clear, .black.opacity(0.96), .black], startPoint: .top, endPoint: .center))
                .onChange(of: model.messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            VStack(spacing: 0) {
                topBar
                composer
            }
        }
        .task { await model.load() }
        .alert("Lumi", isPresented: .constant(model.errorMessage != nil)) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var topBar: some View {
        HStack {
            Button(action: {}) { Image(systemName: "folder").font(.title3) }
                .buttonStyle(.bordered)
                .clipShape(Circle())
            Spacer()
            Text("沉小岑")
                .font(.system(size: 15, weight: .medium))
                .blur(radius: 1.8)
                .opacity(0.5)
            Spacer()
            HStack(spacing: 2) {
                Button(action: {}) { Image(systemName: "phone") }
                Button(action: {}) { Image(systemName: "heart") }
                Button(action: {}) { Image(systemName: "ellipsis") }
            }
            .buttonStyle(.bordered)
            .clipShape(Capsule())
        }
        .foregroundStyle(Color(red: 0.83, green: 0.56, blue: 0.53))
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var composer: some View {
        HStack(spacing: 7) {
            Button(action: {}) { Image(systemName: "link") }
            Button(action: {}) { Image(systemName: "mic") }
            HStack(spacing: 2) {
                TextField("说点什么…", text: $model.draft)
                    .submitLabel(.send)
                    .onSubmit { Task { await model.send() } }
                Button(action: {}) { Image(systemName: "face.smiling") }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.white)
            .clipShape(Capsule())
            Button { Task { await model.send() } } label: { Image(systemName: "arrow.up") }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.content)
                .foregroundStyle(.black)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color(red: 0.88, green: 0.82, blue: 0.81) : .white)
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
