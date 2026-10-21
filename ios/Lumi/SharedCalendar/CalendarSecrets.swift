import Foundation

enum CalendarSecrets {
    static let baseURL = "https://lumi-api.yanvn.top/v1/calendar"
    static var token: String { LumiKeychain.read(account: "push-api-token") }
}
