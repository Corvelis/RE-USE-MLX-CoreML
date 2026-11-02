import XCTest
@testable import ReuseModelAssets

final class ReuseModelAssetsTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("reuse-assets-" + UUID().uuidString)
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fixture(_ values: [(String, Data)] = [("weights.bin", Data(repeating: 7, count: 4096)), ("nested/model.json", Data("{}".utf8))]) throws -> (ReuseModelCatalog, URL) {
        let input = root.appendingPathComponent("source")
        let files = try values.map { name, data in
            let target = input.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
            return ReuseModelCatalog.File(path: name, bytes: Int64(data.count), sha256: ReuseModelCatalog.digest(data))
        }
        return (try ReuseModelCatalog(name: "fixture", files: files), input)
    }
    private func store(_ catalog: ReuseModelCatalog) throws -> ReuseModelStore {
        try ReuseModelStore(catalog: catalog, applicationSupportDirectory: root.appendingPathComponent("support"),
            cachesDirectory: root.appendingPathComponent("cache"))
    }

    func testCatalogRejectsTraversalDuplicatesAndFileDirectoryCollision() throws {
        let hash = ReuseModelCatalog.digest(Data([1]))
        for path in ["../escape", "/absolute", "dir/../escape", "dir//bad", "dir\\bad", "", ".transfers/x"] {
            XCTAssertThrowsError(try ReuseModelCatalog(name: "bad", files: [.init(path: path, bytes: 1, sha256: hash)]))
        }
        for names in [["a", "a"], ["a", "a/b"]] {
            XCTAssertThrowsError(try ReuseModelCatalog(name: "bad", files: names.map { .init(path: $0, bytes: 1, sha256: hash) }))
        }
        let decoded = try JSONDecoder().decode(ReuseModelCatalog.self, from: Data("""
        {"version":1,"name":"bad","files":[{"path":"../escape","bytes":1,"sha256":"\(hash)"}]}
        """.utf8))
        XCTAssertThrowsError(try store(decoded))
    }

    func testLocalInstallDetectsCorruptionAndDeletePreservesOtherFiles() async throws {
        let (catalog, input) = try fixture(), model = try store(catalog)
        try await model.importLocalPack(from: input)
        var state = try await model.inspect()
        XCTAssertTrue(state.isInstalled)
        let weight = model.installedModelDirectory.appendingPathComponent("weights.bin")
        try Data(repeating: 2, count: 4096).write(to: weight)
        state = try await model.inspect(); XCTAssertFalse(state.isInstalled)
        try await model.importLocalPack(from: input)
        state = try await model.inspect(); XCTAssertTrue(state.isInstalled)
        try FileManager.default.createDirectory(at: model.compilationCacheDirectory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: model.compilationCacheDirectory.appendingPathComponent("compiled-model"))
        let recording = root.appendingPathComponent("support/Recordings.wav")
        try Data([4, 5, 6]).write(to: recording)
        try await model.remove()
        state = try await model.inspect()
        XCTAssertFalse(state.isInstalled); XCTAssertEqual(state.totalBytes, 0)
        XCTAssertEqual(try Data(contentsOf: recording), Data([4, 5, 6]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testFailedInstallIsNotPublishedAndRetryReusesVerifiedFiles() async throws {
        let (catalog, input) = try fixture(), model = try store(catalog)
        let second = input.appendingPathComponent("nested/model.json")
        try Data("xx".utf8).write(to: second)
        do { try await model.importLocalPack(from: input); XCTFail("Expected hash failure") } catch {}
        var state = try await model.inspect()
        XCTAssertFalse(state.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.installedModelDirectory.path))
        XCTAssertGreaterThan(state.storedBytes, 0)
        // The completed first file is reused; its source is no longer available.
        try FileManager.default.removeItem(at: input.appendingPathComponent("weights.bin"))
        try Data("{}".utf8).write(to: second)
        try await model.importLocalPack(from: input)
        state = try await model.inspect(); XCTAssertTrue(state.isInstalled)
    }

    func testHuggingFaceURLPinsRepositoryRevisionAndEncodesPaths() throws {
        let source = try ReuseModelSource(huggingFaceRepository: "example/reuse-apple", revision: "v0.1.0")
        XCTAssertEqual(source.url(for: "nested/a b.bin").absoluteString,
            "https://huggingface.co/example/reuse-apple/resolve/v0.1.0/nested/a%20b.bin")
        for repo in ["../bad", "https://huggingface.co/user/repo", "user/repo/extra"] {
            XCTAssertThrowsError(try ReuseModelSource(huggingFaceRepository: repo, revision: "main"))
        }
        XCTAssertThrowsError(try ReuseModelSource(huggingFaceRepository: "user/repo", revision: "../bad"))
    }

    func testAccessTokenUsesAuthorizationHeaderAndRejectsHeaderInjection() throws {
        let source = try ReuseModelSource(huggingFaceRepository: "example/private", revision: "main", accessToken: " hf_fixture ")
        let request = source.request(for: "weights.bin")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hf_fixture")
        XCTAssertFalse(request.url!.absoluteString.contains("hf_fixture"))
        let anonymous = try ReuseModelSource(huggingFaceRepository: "example/private", revision: "main", accessToken: " ")
        XCTAssertNil(anonymous.request(for: "weights.bin").value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try ReuseModelSource(huggingFaceRepository: "example/private", revision: "main",
            accessToken: "hf_fixture\r\nInjected: value"))
    }

    func testRedirectOnlyForwardsCredentialsToOriginalOriginAndRejectsDowngrade() throws {
        let source = try ReuseModelSource(huggingFaceRepository: "example/private", revision: "main", accessToken: "hf_fixture")
        let original = source.request(for: "weights.bin")
        for (url, authorized) in [("https://huggingface.co:443/new-path", true),
                                  ("https://cdn.example/weights.bin", false),
                                  ("https://huggingface.co:444/weights.bin", false)] {
            var proposed = URLRequest(url: URL(string: url)!)
            proposed.setValue("Bearer should_be_removed", forHTTPHeaderField: "Authorization")
            let result = try XCTUnwrap(ReuseDownloadRedirect.request(proposed, original: original))
            XCTAssertEqual(result.value(forHTTPHeaderField: "Authorization"), authorized ? "Bearer hf_fixture" : nil)
        }
        XCTAssertNil(ReuseDownloadRedirect.request(URLRequest(url: URL(string: "http://huggingface.co/weights.bin")!), original: original))
    }

    #if os(macOS)
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ReuseModelTransferProgress] = []
        func append(_ item: ReuseModelTransferProgress) { lock.lock(); items.append(item); lock.unlock() }
        var values: [ReuseModelTransferProgress] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func server(for directory: URL) throws -> (Process, ReuseModelSource) {
        let script = root.appendingPathComponent("server.py"), port = root.appendingPathComponent("port")
        try Data(#"""
        import http.server, pathlib, sys, time, urllib.parse
        base=pathlib.Path(sys.argv[1])
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path=='/private.bin' and self.headers.get('Authorization')!='Bearer hf_fixture':
                    self.send_error(401); return
                if self.path=='/foreign.bin' and self.headers.get('Authorization') is not None:
                    self.send_error(403); return
                if self.path in ['/private-redirect.bin','/foreign-redirect.bin']:
                    target='/private.bin' if self.path=='/private-redirect.bin' else f'http://localhost:{self.server.server_port}/foreign.bin'
                    self.send_response(302); self.send_header('Location',target); self.end_headers(); return
                if self.path=='/redirect.bin':
                    self.send_response(302); self.send_header('Location','/weights.bin'); self.end_headers(); return
                path=base/urllib.parse.unquote(self.path.split('?')[0]).lstrip('/')
                if not path.is_file(): self.send_error(404); return
                data=path.read_bytes()
                self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers()
                try:
                    for i in range(0,len(data),16384):
                        self.wfile.write(data[i:i+16384]); self.wfile.flush()
                        if path.name=='slow.bin': time.sleep(.01)
                except (BrokenPipeError,ConnectionResetError): pass
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        pathlib.Path(sys.argv[2]).write_text(str(server.server_address[1]))
        server.serve_forever()
        """#.utf8).write(to: script)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, directory.path, port.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<300 {
            if let value = try? String(contentsOf: port, encoding: .utf8), let number = Int(value) {
                return (process, ReuseModelSource(baseURL: URL(string: "http://127.0.0.1:\(number)")!))
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.terminate(); throw ReuseAssetError.invalid("Local server did not start")
    }

    func testHTTPDownloadVerifiesFilesAndReportsCompletion() async throws {
        let (catalog, input) = try fixture(), model = try store(catalog)
        let (process, source) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        let progress = ProgressLog()
        try await model.download(from: source) { progress.append($0) }
        let status = try await model.inspect()
        XCTAssertTrue(status.isInstalled)
        XCTAssertEqual(progress.values.last?.fraction, 1)
        XCTAssertEqual(progress.values.last?.completedFiles, catalog.files.count)
        XCTAssertEqual(try Data(contentsOf: model.installedModelDirectory.appendingPathComponent("weights.bin")), Data(repeating: 7, count: 4096))
    }

    func testHTTP404DoesNotBecomeInstalled() async throws {
        let (catalog, input) = try fixture(), model = try store(catalog)
        try FileManager.default.removeItem(at: input.appendingPathComponent("weights.bin"))
        let (process, source) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        do { try await model.download(from: source); XCTFail("Expected HTTP failure") } catch {}
        let status = try await model.inspect(); XCTAssertFalse(status.isInstalled)
    }

    func testPrivateHTTPDownloadRequiresValidToken() async throws {
        let (catalog, input) = try fixture([("private.bin", Data([1,2,3]))])
        let model = try store(catalog), (process, base) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        for token in [nil, "hf_wrong"] as [String?] {
            let source = ReuseModelSource(baseURL: base.baseURL, accessToken: token)
            do { try await model.download(from: source); XCTFail("Expected authentication failure") }
            catch { XCTAssertTrue(error.localizedDescription.contains("HTTP 401")) }
            let state = try await model.inspect(); XCTAssertFalse(state.isInstalled)
        }
        try await model.download(from: ReuseModelSource(baseURL: base.baseURL, accessToken: "hf_fixture"))
        let state = try await model.inspect(); XCTAssertTrue(state.isInstalled)
    }

    func testAuthenticatedRedirectsKeepSameOriginTokenAndStripForeignToken() async throws {
        let (_, input) = try fixture([("private.bin", Data([1,2,3])), ("foreign.bin", Data([1,2,3]))])
        let (process, base) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        let catalog = try ReuseModelCatalog(name: "authenticated-redirects", files:
            ["private-redirect.bin", "foreign-redirect.bin"].map {
                .init(path: $0, bytes: 3, sha256: ReuseModelCatalog.digest(Data([1,2,3])))
            })
        let model = try store(catalog)
        try await model.download(from: ReuseModelSource(baseURL: base.baseURL, accessToken: "hf_fixture"))
        let state = try await model.inspect(); XCTAssertTrue(state.isInstalled)
    }

    func testRedirectedDownloadVerifiesFinalContent() async throws {
        let (_, input) = try fixture()
        let data = Data(repeating: 7, count: 4096)
        let catalog = try ReuseModelCatalog(name: "redirect", files: [
            .init(path: "redirect.bin", bytes: Int64(data.count), sha256: ReuseModelCatalog.digest(data))])
        let model = try store(catalog), (process, source) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        try await model.download(from: source)
        let status = try await model.inspect(); XCTAssertTrue(status.isInstalled)
    }

    func testCancellationDoesNotPublishPartialModelAndAllowsRemoval() async throws {
        let (catalog, input) = try fixture([("slow.bin", Data(repeating: 1, count: 4 * 1024 * 1024))])
        let model = try store(catalog), progress = ProgressLog()
        let (process, source) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        let task = Task { try await model.download(from: source) { progress.append($0) } }
        for _ in 0..<200 {
            if progress.values.contains(where: { $0.completedBytes > 0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(progress.values.contains { $0.completedBytes > 0 })
        let during = try await model.inspect(); XCTAssertFalse(during.isInstalled)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await model.remove()
        let after = try await model.inspect(); XCTAssertEqual(after.totalBytes, 0)
    }

    func testOversizedHTTPResponseIsRejected() async throws {
        let (catalog, input) = try fixture([("wrong.bin", Data([1]))]), model = try store(catalog)
        try Data(repeating: 1, count: 128 * 1024).write(to: input.appendingPathComponent("wrong.bin"))
        let (process, source) = try server(for: input)
        defer { if process.isRunning { process.terminate() } }
        do { try await model.download(from: source); XCTFail("Expected size failure") } catch {}
        let status = try await model.inspect(); XCTAssertFalse(status.isInstalled)
    }
    #endif
}
