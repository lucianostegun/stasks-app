import XCTest
@testable import StasksCore

final class OpenAICompatibleClientTests: XCTestCase {
    func client(base: String = "https://api.openai.com/v1/", key: String = "sk-x") -> OpenAICompatibleClient {
        OpenAICompatibleClient(baseURL: base, apiKey: key, model: "gpt-5-mini", session: MockURLProtocol.session())
    }

    func testRequestShapeAndParsing() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.handler = MockURLProtocol.respond(json: #"{"choices":[{"message":{"role":"assistant","content":"Review PR 42"}}]}"#)
        let text = try await client().complete(system: "sys", user: "usr", maxTokens: 60)
        XCTAssertEqual(text, "Review PR 42")
        let req = MockURLProtocol.requests.first!
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-x")
        let body = try JSONSerialization.jsonObject(with: bodyData(req)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-5-mini")
        // Floor leaves room for hidden reasoning tokens; a cap of 60 would come back empty on gpt-5 models.
        XCTAssertEqual(body["max_completion_tokens"] as? Int, OpenAICompatibleClient.minCompletionTokens)
        XCTAssertNil(body["temperature"])
        let messages = body["messages"] as! [[String: String]]
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
    }

    func testNoAuthHeaderWithoutKeyForLocalServers() async throws {
        MockURLProtocol.requests = []
        MockURLProtocol.handler = MockURLProtocol.respond(json: #"{"choices":[{"message":{"content":"ok"}}]}"#)
        _ = try await client(base: "http://localhost:11434/v1", key: "").complete(system: "s", user: "u", maxTokens: 10)
        let req = MockURLProtocol.requests.first!
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testHTTPErrorAndEmptyContent() async {
        MockURLProtocol.handler = MockURLProtocol.respond(401, json: #"{"error":{"message":"bad key"}}"#)
        do { _ = try await client().complete(system: "s", user: "u", maxTokens: 10); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? LLMError, .http(401, #"{"error":{"message":"bad key"}}"#)) }

        MockURLProtocol.handler = MockURLProtocol.respond(json: #"{"choices":[{"message":{"content":"  "}}]}"#)
        do { _ = try await client().complete(system: "s", user: "u", maxTokens: 10); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? LLMError, .emptyResponse) }
    }

    func bodyData(_ req: URLRequest) -> Data {
        if let b = req.httpBody { return b }
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n > 0 { data.append(buf, count: n) } else { break } }
        return data
    }
}
