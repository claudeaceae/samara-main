import Foundation

enum ClaudeTestStub {
    static func makeScript(body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("samara-claude-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let scriptURL = dir.appendingPathComponent("claude")
        let contents = "#!/bin/sh\n\(body)\n"
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    static func makeJSONResponseScript(result: String, sessionId: String = "session") throws -> URL {
        let jsonData = try JSONSerialization.data(withJSONObject: ["result": result, "session_id": sessionId], options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let body = """
        cat <<'EOF'
        \(jsonString)
        EOF
        """
        return try makeScript(body: body)
    }

    static func cleanup(_ scriptURL: URL) {
        let dir = scriptURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }
}
