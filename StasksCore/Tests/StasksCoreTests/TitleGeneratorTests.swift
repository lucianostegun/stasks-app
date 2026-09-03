import XCTest
@testable import StasksCore

final class TitleGeneratorTests: XCTestCase {
    func client() -> AnthropicClient { AnthropicClient(apiKey: "sk-test", session: MockURLProtocol.session()) }

    func testRequestShapeAndParsing() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.handler = MockURLProtocol.respond(json: #"{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"\"Revisar PR 42 da Ana.\""}],"stop_reason":"end_turn"}"#)
        let title = await TitleGenerator(client: client()).title(channel: "eng", author: "Ana", text: "review pls", thread: [])
        XCTAssertEqual(title, "Revisar PR 42 da Ana")
        let req = MockURLProtocol.requests.first!
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? bodyData(req)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 60)
        XCTAssertNotNil(body["system"])
    }

    func testHTTPErrorYieldsNil() async {
        MockURLProtocol.handler = MockURLProtocol.respond(401, json: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        let title = await TitleGenerator(client: client()).title(channel: "c", author: "a", text: "t", thread: [])
        XCTAssertNil(title)
    }

    func testEmptyTextYieldsNil() async {
        MockURLProtocol.handler = MockURLProtocol.respond(json: #"{"content":[{"type":"text","text":"   "}]}"#)
        let title = await TitleGenerator(client: client()).title(channel: "c", author: "a", text: "t", thread: [])
        XCTAssertNil(title)
    }

    /// URLProtocol receives the body as a stream, not `httpBody`. Read it.
    func bodyData(_ req: URLRequest) -> Data {
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n > 0 { data.append(buf, count: n) } else { break } }
        return data
    }
}
