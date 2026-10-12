import Foundation

enum CalendarSecrets {
    static let baseURL = "https://lumi-tokyo-api.zeabur.app/v1/calendar"
    static var token: String { LumiKeychain.read(account: "push-api-token") }
}
