"""Exercise the actual Foundation models and bubble splitter without an iPhone."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
models = (root / "ios/Lumi/Models/ChatModels.swift").read_text()
viewmodel = (root / "ios/Lumi/ViewModels/ChatViewModel.swift").read_text()
models = models[:models.index("struct ChatOptionPick")]
splitter = viewmodel[viewmodel.index("    private func assistantBubbles("):viewmodel.index("    private static func htmlCardPayload(")]
thinking = viewmodel[viewmodel.index("    private func extractThinking("):viewmodel.index("    private func friendlyError(")]
checks = r'''
let url = "https://openaccess-cdn.clevelandart.org/1963.253/1963.253_web.jpg"
func trace(_ image: String = url, succeeded: Bool = true, ok: Bool = true) throws -> ChatToolCallTrace {
    let data = try JSONSerialization.data(withJSONObject: ["ok": ok, "photo": [
        "imageURL": image, "title": "The Burning of the Houses of Lords and Commons",
        "caption": "逛檐廊时想叼回来给你看。", "credit": "J. M. W. Turner",
        "sourceURL": "https://www.clevelandart.org/art/1963.253"
    ]])
    return ChatToolCallTrace(name: "lumi_engawa_share_photo", arguments: "{}", result: String(decoding: data, as: UTF8.self), succeeded: succeeded)
}
let receipt = try trace()
let original = ChatMessage(id: UUID(), role: .assistant, content: "这张想给你看。\n慢慢看。", createdAt: .now, thinking: "保存的心声", contentType: "sentinel", htmlContent: "<!doctype html><html><body>old card</body></html>", htmlTitle: "叼给你看", toolCalls: [receipt])
let harness = PhotoBubbleHarness()
let bubbles = harness.split(original)
assert(bubbles.count == 3)
assert(bubbles.filter { $0.contentType == "engawa_photos" }.count == 1)
assert(!bubbles.contains { $0.contentType == "html" || $0.htmlContent != nil })
assert(bubbles[0].content == "这张想给你看。")
assert(bubbles[0].thinking == "保存的心声")
assert(bubbles[0].toolCalls.isEmpty)
assert(bubbles[2].engawaSharedPhotos.first?.caption == "逛檐廊时想叼回来给你看。")
assert(bubbles[2].engawaSharedPhotos.first?.credit == "J. M. W. Turner")
assert(bubbles[2].engawaSharedPhotos.first?.sourceLink?.host == "www.clevelandart.org")
assert(bubbles[2].toolCalls == [receipt])
assert(harness.split(original).map(\.id) == bubbles.map(\.id))
assert(harness.split(bubbles[2]) == [bubbles[2]])
let persisted = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(bubbles[2]))
assert(persisted.engawaSharedPhotos == bubbles[2].engawaSharedPhotos)
var failed = original
failed.toolCalls = [try trace(succeeded: false), try trace(ok: false), ChatToolCallTrace(name: "other", arguments: "{}", result: receipt.result, succeeded: true)]
assert(failed.engawaSharedPhotos.isEmpty)
assert(harness.split(failed).contains { $0.contentType == "html" })
var invalid = original
invalid.toolCalls = [try trace("javascript:alert(1)"), try trace("http://example.org/a.jpg"), try trace("https://service.internal/a.jpg")]
assert(invalid.engawaSharedPhotos.isEmpty)
var multiple = original
multiple.toolCalls = [receipt, receipt] + (1...5).map { try! trace("https://example.org/photo\($0).jpg") }
assert(multiple.engawaSharedPhotos.count == 4)
let noText = ChatMessage(id: UUID(), role: .assistant, content: "", createdAt: .now, thinking: "心声", htmlContent: "<html></html>", toolCalls: [receipt])
assert(harness.split(noText).count == 1)
assert(harness.split(noText)[0].thinking == "心声")
let user = ChatMessage(id: UUID(), role: .user, content: "", createdAt: .now, toolCalls: [receipt])
assert(user.engawaSharedPhotos.isEmpty)
print("PASS: legacy card migration, native card splitting, history reload, captions, thinking, tool receipts, failure fallback, URL checks and photo limits")
'''
# The fixture is a raw string; keep ordinary Swift newline escapes and key paths.
checks = checks.replace('\\\\n', '\\n').replace('\\\\.', '\\.').replace('\\\\(', '\\(')
with tempfile.TemporaryDirectory(prefix="lumi-engawa-photo-") as folder:
    folder = Path(folder)
    source = folder / "main.swift"
    source.write_text(models + "\nfinal class PhotoBubbleHarness {\n" + splitter + thinking
                      + "\nfunc split(_ message: ChatMessage) -> [ChatMessage] { assistantBubbles(from: message) }\n}\n" + checks)
    binary = folder / "checks"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(folder / "cache"), str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
