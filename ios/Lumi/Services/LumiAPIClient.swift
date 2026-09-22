import Foundation

enum LumiAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的内容"
        case .server(let message): return message
        }
    }
}

final class LumiAPIClient {
    // 真机调试时替换成开发机的局域网 IP。
    var baseURL = URL(string: "http://127.0.0.1:8787")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchThread(id: String) async throws -> ChatThread {
        try await request(path: "/v1/chats/\(id)")
    }

    func sendMessage(_ content: String, to id: String) async throws -> SendMessageResponse {
        var request = URLRequest(url: baseURL.appending(path: "/v1/chats/\(id)/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.api.encode(SendMessageRequest(content: content))
        return try await perform(request)
    }

    private func request<T: Decodable>(path: String) async throws -> T {
        try await perform(URLRequest(url: baseURL.appending(path: path)))
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LumiAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "请求失败"
            throw LumiAPIError.server(message)
        }
        return try JSONDecoder.api.decode(T.self, from: data)
    }
}

private extension JSONEncoder {
    static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
