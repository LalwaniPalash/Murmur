import Foundation

@MainActor
final class RuntimeInstaller: ObservableObject {
    @Published private(set) var activeRuntime: RuntimeInstallation.Kind?
    @Published private(set) var activeWhisperModel: WhisperModelPreset?
    @Published private(set) var activeLlamaModel: LlamaModelPreset?
    @Published private(set) var runtimeProgress: TaskProgressState?
    @Published private(set) var whisperModelProgress: TaskProgressState?
    @Published private(set) var llamaModelProgress: TaskProgressState?
    private var refreshGeneration: UInt = 0
    private var runtimeInstallTask: Task<Void, Never>?
    private var whisperModelInstallTask: Task<Void, Never>?
    private var llamaModelInstallTask: Task<Void, Never>?

    func refreshRuntimeDetections(modelManager: ModelManager) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let managedPaths = Dictionary(uniqueKeysWithValues: modelManager.runtimes.compactMap { runtime in
            runtime.installPath.map { (runtime.kind, $0) }
        })

        Task.detached(priority: .utility) {
            let resolutions = Self.collectRuntimeResolutions(managedPaths: managedPaths)
            await MainActor.run {
                guard generation == self.refreshGeneration else { return }
                self.applyRuntimeResolutions(resolutions, modelManager: modelManager)
            }
        }
    }

    func install(_ kind: RuntimeInstallation.Kind, modelManager: ModelManager) {
        guard activeRuntime == nil else { return }
        activeRuntime = kind
        runtimeProgress = TaskProgressState(
            title: "Installing \(kind.rawValue)",
            detail: "Preparing build directory",
            fractionCompleted: 0.05
        )

        modelManager.updateRuntime(kind) { runtime in
            runtime.installState = .installing
            runtime.lastUpdatedAt = Date()
            runtime.notes = "Installing official \(kind.rawValue) runtime."
        }

        runtimeInstallTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try await Self.performInstall(kind) { progress in
                    await MainActor.run {
                        self.runtimeProgress = progress
                    }
                }

                await MainActor.run {
                    modelManager.updateRuntime(kind) { runtime in
                        runtime.installState = .installed
                        runtime.installPath = result.path
                        runtime.version = result.version
                        runtime.notes = result.notes
                        runtime.lastUpdatedAt = Date()
                        runtime.detectionSource = .managed
                    }
                    self.runtimeProgress = nil
                    self.activeRuntime = nil
                    self.refreshRuntimeDetections(modelManager: modelManager)
                }
            } catch is CancellationError {
                await MainActor.run {
                    modelManager.updateRuntime(kind) { runtime in
                        if runtime.installPath == nil {
                            runtime.installState = .notInstalled
                            runtime.detectionSource = .unknown
                        } else {
                            runtime.installState = .installed
                        }
                        runtime.notes = "Installation cancelled."
                        runtime.lastUpdatedAt = Date()
                    }
                    self.runtimeProgress = nil
                    self.activeRuntime = nil
                    self.runtimeInstallTask = nil
                    self.refreshRuntimeDetections(modelManager: modelManager)
                }
            } catch {
                await MainActor.run {
                    modelManager.updateRuntime(kind) { runtime in
                        runtime.installState = .failed
                        runtime.notes = error.localizedDescription
                        runtime.lastUpdatedAt = Date()
                        runtime.detectionSource = .unknown
                    }
                    self.runtimeProgress = nil
                    self.activeRuntime = nil
                    self.runtimeInstallTask = nil
                }
            }
        }
    }

    func update(_ kind: RuntimeInstallation.Kind, modelManager: ModelManager) {
        install(kind, modelManager: modelManager)
    }

    func installWhisperModel(_ preset: WhisperModelPreset, modelManager: ModelManager) {
        guard activeWhisperModel == nil else { return }
        activeWhisperModel = preset
        whisperModelProgress = TaskProgressState(
            title: "Installing \(preset.displayName)",
            detail: "Preparing whisper.cpp model download",
            fractionCompleted: 0
        )
        modelManager.markWhisperModelInstalling(preset)

        whisperModelInstallTask = Task.detached(priority: .userInitiated) {
            do {
                let modelPath = try await Self.performWhisperModelInstall(preset) { progress in
                    await MainActor.run {
                        self.whisperModelProgress = progress
                    }
                }

                await MainActor.run {
                    modelManager.markWhisperModelInstalled(preset, path: modelPath)
                    self.whisperModelProgress = nil
                    self.activeWhisperModel = nil
                    self.whisperModelInstallTask = nil
                    modelManager.refreshInstalledWhisperModels()
                }
            } catch is CancellationError {
                await MainActor.run {
                    modelManager.markWhisperModelCancelled(preset)
                    self.whisperModelProgress = nil
                    self.activeWhisperModel = nil
                    self.whisperModelInstallTask = nil
                    modelManager.refreshInstalledWhisperModels()
                }
            } catch {
                await MainActor.run {
                    modelManager.markWhisperModelFailed(preset, message: error.localizedDescription)
                    self.whisperModelProgress = nil
                    self.activeWhisperModel = nil
                    self.whisperModelInstallTask = nil
                }
            }
        }
    }

    func installLlamaModel(_ preset: LlamaModelPreset, modelManager: ModelManager) {
        guard activeLlamaModel == nil else { return }
        activeLlamaModel = preset
        llamaModelProgress = TaskProgressState(
            title: "Installing \(preset.displayName)",
            detail: "Preparing llama.cpp model download",
            fractionCompleted: 0
        )
        modelManager.markLlamaModelInstalling(preset)

        llamaModelInstallTask = Task.detached(priority: .userInitiated) {
            do {
                let modelPath = try await Self.performLlamaModelInstall(preset) { progress in
                    await MainActor.run {
                        self.llamaModelProgress = progress
                    }
                }

                await MainActor.run {
                    modelManager.markLlamaModelInstalled(preset, path: modelPath)
                    self.llamaModelProgress = nil
                    self.activeLlamaModel = nil
                    self.llamaModelInstallTask = nil
                    modelManager.refreshInstalledLlamaModels()
                }
            } catch is CancellationError {
                await MainActor.run {
                    modelManager.markLlamaModelCancelled(preset)
                    self.llamaModelProgress = nil
                    self.activeLlamaModel = nil
                    self.llamaModelInstallTask = nil
                    modelManager.refreshInstalledLlamaModels()
                }
            } catch {
                await MainActor.run {
                    modelManager.markLlamaModelFailed(preset, message: error.localizedDescription)
                    self.llamaModelProgress = nil
                    self.activeLlamaModel = nil
                    self.llamaModelInstallTask = nil
                }
            }
        }
    }

    func cancelRuntimeInstall() {
        runtimeInstallTask?.cancel()
    }

    func cancelWhisperModelInstall() {
        whisperModelInstallTask?.cancel()
    }

    func cancelLlamaModelInstall() {
        llamaModelInstallTask?.cancel()
    }

    private func applyRuntimeResolutions(
        _ resolutions: [RuntimeInstallation.Kind: RuntimeResolution],
        modelManager: ModelManager
    ) {
        for kind in RuntimeInstallation.Kind.allCases {
            guard let resolution = resolutions[kind] else { continue }
            modelManager.updateRuntime(kind) { runtime in
                runtime.installState = resolution.installState
                runtime.installPath = resolution.path
                runtime.version = resolution.version ?? (resolution.installState == .installed ? runtime.version : nil)
                runtime.notes = resolution.notes
                runtime.lastUpdatedAt = Date()
                runtime.detectionSource = resolution.source
            }
        }
    }

    private nonisolated static func performInstall(
        _ kind: RuntimeInstallation.Kind,
        progress: @escaping @Sendable (TaskProgressState) async -> Void
    ) async throws -> (path: String, version: String?, notes: String) {
        try Task.checkCancellation()

        // --- Step 1: Check PATH via `which` for any existing installation ---
        await progress(
            TaskProgressState(
                title: "Checking for \(kind.rawValue)",
                detail: "Searching PATH for existing installation…",
                fractionCompleted: 0.05
            )
        )

        for candidate in executableCandidates(for: kind) {
            try Task.checkCancellation()
            guard let found = (try? runProcess(
                "/usr/bin/which", arguments: [candidate], timeout: 5
            ))?.trimmingCharacters(in: .whitespacesAndNewlines),
            !found.isEmpty else { continue }

            if let version = try? validateRuntime(executablePath: found, kind: kind) {
                await progress(
                    TaskProgressState(
                        title: "Found \(kind.rawValue)",
                        detail: "Using existing installation at \(found)",
                        fractionCompleted: 1.0
                    )
                )
                return (path: found, version: version, notes: "Detected on PATH at \(found)")
            }
        }

        // --- Step 2: Not found or broken — proceed with source build ---
        let fileManager = FileManager.default
        let runtimesRoot = AppPaths.runtimesDirectory
        let installRoot = runtimesRoot.appendingPathComponent(kind.rawValue.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
        let repositoryURL = repositoryURL(for: kind)

        await progress(
            TaskProgressState(
                title: "Installing \(kind.rawValue)",
                detail: fileManager.fileExists(atPath: installRoot.path) ? "Updating source checkout" : "Cloning official repository",
                fractionCompleted: 0.15
            )
        )

        if fileManager.fileExists(atPath: installRoot.path) {
            try Task.checkCancellation()
            _ = try runProcess("/usr/bin/git", arguments: ["-C", installRoot.path, "pull", "--ff-only"])
        } else {
            try Task.checkCancellation()
            _ = try runProcess("/usr/bin/git", arguments: ["clone", "--depth", "1", repositoryURL, installRoot.path])
        }

        guard let cmake = toolPath(named: "cmake") else {
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 90,
                userInfo: [NSLocalizedDescriptionKey:
                    "CMake is required to build \(kind.rawValue) from source.\n\n" +
                    "Install CMake:  brew install cmake\n" +
                    "Or install \(kind.rawValue) directly:  brew install \(primaryBinaryName(for: kind))"]
            )
        }

        let buildDirectory = installRoot.appendingPathComponent("build", isDirectory: true)
        var configureArguments = [
            "-S", installRoot.path,
            "-B", buildDirectory.path,
            "-DCMAKE_BUILD_TYPE=Release",
            "-DGGML_METAL=ON",
        ]
        if kind == .llamaCPP {
            configureArguments.append("-DLLAMA_CURL=ON")
        }

        await progress(
            TaskProgressState(
                title: "Installing \(kind.rawValue)",
                detail: "Configuring native build",
                fractionCompleted: 0.4
            )
        )
        try Task.checkCancellation()
        _ = try runProcess(cmake, arguments: configureArguments)

        await progress(
            TaskProgressState(
                title: "Installing \(kind.rawValue)",
                detail: "Compiling runtime binaries",
                fractionCompleted: 0.75
            )
        )
        try Task.checkCancellation()
        _ = try runProcess(
            cmake,
            arguments: ["--build", buildDirectory.path, "--target", primaryBinaryName(for: kind), "-j"],
            outputMode: .discard
        )

        let binaryPath = buildDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(primaryBinaryName(for: kind))
            .path

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 81,
                userInfo: [NSLocalizedDescriptionKey: "\(primaryBinaryName(for: kind)) was not produced by the build."]
            )
        }

        await progress(
            TaskProgressState(
                title: "Installing \(kind.rawValue)",
                detail: "Validating runtime executable",
                fractionCompleted: 0.92
            )
        )
        try Task.checkCancellation()
        let version = try validateRuntime(executablePath: binaryPath, kind: kind)
        let notes = "Managed runtime ready at \(binaryPath)."

        await progress(
            TaskProgressState(
                title: "Installing \(kind.rawValue)",
                detail: "Finishing installation",
                fractionCompleted: 1
            )
        )

        return (binaryPath, version, notes)
    }

    private nonisolated static func performWhisperModelInstall(
        _ preset: WhisperModelPreset,
        progress: @escaping @Sendable (TaskProgressState) async -> Void
    ) async throws -> String {
        let destination = AppPaths.whisperModelsDirectory.appendingPathComponent(preset.fileName)
        let url = whisperModelDownloadURL(for: preset)
        return try await downloadFile(
            from: url,
            to: destination,
            title: "Installing \(preset.displayName)",
            subtitle: "Downloading whisper.cpp model",
            progress: progress
        )
    }

    private nonisolated static func performLlamaModelInstall(
        _ preset: LlamaModelPreset,
        progress: @escaping @Sendable (TaskProgressState) async -> Void
    ) async throws -> String {
        let destination = AppPaths.llamaModelsDirectory.appendingPathComponent(preset.fileName)
        let url = llamaModelDownloadURL(for: preset)
        return try await downloadFile(
            from: url,
            to: destination,
            title: "Installing \(preset.displayName)",
            subtitle: "Downloading llama.cpp model",
            progress: progress
        )
    }

    private nonisolated static func downloadFile(
        from url: URL,
        to destination: URL,
        title: String,
        subtitle: String,
        progress: @escaping @Sendable (TaskProgressState) async -> Void
    ) async throws -> String {
        let fileManager = FileManager.default
        try Task.checkCancellation()
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let temporaryURL = destination.deletingLastPathComponent().appendingPathComponent("\(destination.lastPathComponent).download")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try? fileManager.removeItem(at: temporaryURL)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)

        let request = URLRequest(url: url)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let expectedLength = response.expectedContentLength
        let handle = try FileHandle(forWritingTo: temporaryURL)

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        await progress(TaskProgressState(title: title, detail: subtitle, fractionCompleted: 0))

        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                received += 1

                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                if received % (256 * 1024) == 0 {
                    let fraction = expectedLength > 0 ? min(Double(received) / Double(expectedLength), 0.99) : nil
                    await progress(TaskProgressState(title: title, detail: subtitle, fractionCompleted: fraction))
                }
            }

            if buffer.isEmpty == false {
                try handle.write(contentsOf: buffer)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        try Task.checkCancellation()
        try fileManager.moveItem(at: temporaryURL, to: destination)
        try validateModelFile(at: destination)

        await progress(TaskProgressState(title: title, detail: "Finalizing local model", fractionCompleted: 1))
        return destination.path
    }

    private nonisolated static func collectRuntimeResolutions(
        managedPaths: [RuntimeInstallation.Kind: String]
    ) -> [RuntimeInstallation.Kind: RuntimeResolution] {
        Dictionary(uniqueKeysWithValues: RuntimeInstallation.Kind.allCases.map { kind in
            let bundledProbe = bundledRuntimeProbe(for: kind)
            let pathProbe = pathRuntimeProbe(for: kind)
            let managedProbe = managedPaths[kind].flatMap {
                installedRuntimeProbe(for: kind, explicitPath: $0, source: .managed)
            }

            let resolution: RuntimeResolution
            if let bundledProbe, bundledProbe.isRunnable {
                resolution = RuntimeResolution(
                    installState: .installed,
                    path: bundledProbe.path,
                    version: bundledProbe.version,
                    notes: bundledProbe.notes,
                    source: bundledProbe.source
                )
            } else if let pathProbe, pathProbe.isRunnable {
                resolution = RuntimeResolution(
                    installState: .installed,
                    path: pathProbe.path,
                    version: pathProbe.version,
                    notes: pathProbe.notes,
                    source: pathProbe.source
                )
            } else if let managedProbe, managedProbe.isRunnable {
                resolution = RuntimeResolution(
                    installState: .installed,
                    path: managedProbe.path,
                    version: managedProbe.version,
                    notes: managedProbe.notes,
                    source: managedProbe.source
                )
            } else if let bundledProbe {
                resolution = RuntimeResolution(
                    installState: .failed,
                    path: bundledProbe.path,
                    version: nil,
                    notes: bundledProbe.notes,
                    source: .bundled
                )
            } else if let pathProbe {
                resolution = RuntimeResolution(
                    installState: .failed,
                    path: pathProbe.path,
                    version: nil,
                    notes: pathProbe.notes,
                    source: .path
                )
            } else if let managedProbe {
                resolution = RuntimeResolution(
                    installState: .failed,
                    path: managedProbe.path,
                    version: nil,
                    notes: managedProbe.notes,
                    source: .managed
                )
            } else {
                resolution = RuntimeResolution(
                    installState: .notInstalled,
                    path: nil,
                    version: nil,
                    notes: "Not found on PATH. Checked with `which`.",
                    source: .unknown
                )
            }

            return (kind, resolution)
        })
    }

    private nonisolated static func bundledRuntimeProbe(for kind: RuntimeInstallation.Kind) -> RuntimeProbe? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let runtimeRoot = resourceURL.appendingPathComponent("Runtimes", isDirectory: true)
        for architecture in bundledRuntimeArchitectureCandidates() {
            let candidateURL = runtimeRoot
                .appendingPathComponent(architecture, isDirectory: true)
                .appendingPathComponent(primaryBinaryName(for: kind))
            guard FileManager.default.fileExists(atPath: candidateURL.path) else {
                continue
            }
            return installedRuntimeProbe(
                for: kind,
                explicitPath: candidateURL.path,
                source: .bundled,
                command: "\(architecture)/\(primaryBinaryName(for: kind))"
            )
        }
        return nil
    }

    private nonisolated static func pathRuntimeProbe(for kind: RuntimeInstallation.Kind) -> RuntimeProbe? {
        for candidate in executableCandidates(for: kind) {
            guard let path = which(candidate) else {
                continue
            }
            return installedRuntimeProbe(for: kind, explicitPath: path, source: .path, command: candidate)
        }
        return nil
    }

    private nonisolated static func installedRuntimeProbe(
        for kind: RuntimeInstallation.Kind,
        explicitPath: String,
        source: RuntimeInstallation.DetectionSource,
        command: String? = nil
    ) -> RuntimeProbe {
        do {
            let version = try validateRuntime(executablePath: explicitPath, kind: kind)
            let notePrefix: String
            switch source {
            case .bundled:
                notePrefix = "Bundled runtime available at \(command ?? primaryBinaryName(for: kind))."
            case .path:
                notePrefix = "Detected on PATH via `which \(command ?? primaryBinaryName(for: kind))`."
            case .managed:
                notePrefix = "Managed runtime available at \(explicitPath)."
            case .unknown:
                notePrefix = "Runtime available at \(explicitPath)."
            }
            return RuntimeProbe(
                path: explicitPath,
                version: version,
                notes: notePrefix,
                source: source,
                isRunnable: true
            )
        } catch let error as NSError {
            let notePrefix: String
            switch source {
            case .bundled:
                notePrefix = "Bundled runtime exists at \(command ?? primaryBinaryName(for: kind)), but it is not runnable."
            case .path:
                notePrefix = "Found on PATH via `which \(command ?? primaryBinaryName(for: kind))`, but it is not runnable."
            case .managed:
                notePrefix = "Managed runtime exists at \(explicitPath), but it is not runnable."
            case .unknown:
                notePrefix = "Runtime exists at \(explicitPath), but it is not runnable."
            }

            let errorMessage = error.localizedDescription
            let details: String
            if errorMessage.contains("dyld") || errorMessage.contains("Library") || errorMessage.contains("libwhisper") {
                if source == .bundled {
                    details = "Broken dependency (missing library). Rebuild the bundled runtime with app-relative library paths."
                } else {
                    details = "Broken dependency (missing library). Try reinstalling via: brew reinstall \(primaryBinaryName(for: kind))"
                }
            } else {
                details = errorMessage
            }

            return RuntimeProbe(
                path: explicitPath,
                version: nil,
                notes: "\(notePrefix) \(details)",
                source: source,
                isRunnable: false
            )
        } catch {
            let notePrefix: String
            switch source {
            case .bundled:
                notePrefix = "Bundled runtime exists at \(command ?? primaryBinaryName(for: kind)), but it is not runnable."
            case .path:
                notePrefix = "Found on PATH via `which \(command ?? primaryBinaryName(for: kind))`, but it is not runnable."
            case .managed:
                notePrefix = "Managed runtime exists at \(explicitPath), but it is not runnable."
            case .unknown:
                notePrefix = "Runtime exists at \(explicitPath), but it is not runnable."
            }
            return RuntimeProbe(
                path: explicitPath,
                version: nil,
                notes: "\(notePrefix) \(error.localizedDescription)",
                source: source,
                isRunnable: false
            )
        }
    }

    private nonisolated static func validateRuntime(executablePath: String, kind: RuntimeInstallation.Kind) throws -> String? {
        _ = try runProcess(executablePath, arguments: validationArguments(for: kind), timeout: 15)

        guard let versionOutput = try? runProcess(
            executablePath,
            arguments: versionArguments(for: kind),
            timeout: 3
        ) else {
            return nil
        }

        return versionOutput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("version:") || $0.hasPrefix("whisper.cpp") || $0.hasPrefix("main") })
    }

    private nonisolated static func validateModelFile(at url: URL) throws {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 52,
                userInfo: [NSLocalizedDescriptionKey:
                    "Model file was not saved. Please try downloading again."]
            )
        }

        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let sizeNumber = attrs[.size] as? NSNumber else {
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 53,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not read model file properties. Please try again."]
            )
        }

        let fileSize = sizeNumber.int64Value
        guard fileSize > 1_000_000 else {
            try? fileManager.removeItem(at: url)
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 50,
                userInfo: [NSLocalizedDescriptionKey:
                    "Downloaded file is too small (\(fileSize) bytes). Please try downloading again."]
            )
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            let header = handle.readData(ofLength: 4)
            try? handle.close()

            let gguf = Data([0x47, 0x47, 0x55, 0x46])      // "GGUF"
            let ggml = Data([0x67, 0x67, 0x6D, 0x6C])      // "ggml"
            let ggmlLE = Data([0x6C, 0x6D, 0x67, 0x67])    // "lmgg" (little-endian variant)

            guard header == gguf || header == ggml || header == ggmlLE else {
                try? fileManager.removeItem(at: url)
                let headerHex = header.map { String(format: "%02X", $0) }.joined(separator: " ")
                throw NSError(
                    domain: "Murmur.RuntimeInstaller",
                    code: 51,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Downloaded file has invalid header (got: \(headerHex)). It may be corrupted or the wrong file type. Please try again."]
                )
            }
        } catch {
            if (error as NSError).domain == "Murmur.RuntimeInstaller" {
                throw error
            }
            try? fileManager.removeItem(at: url)
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: 54,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not read model file: \(error.localizedDescription)"]
            )
        }
    }

    private nonisolated static func validationArguments(for kind: RuntimeInstallation.Kind) -> [String] {
        switch kind {
        case .whisperCPP:
            ["-h"]
        case .llamaCPP:
            ["-h"]
        }
    }

    private nonisolated static func versionArguments(for kind: RuntimeInstallation.Kind) -> [String] {
        switch kind {
        case .whisperCPP:
            ["-h"]
        case .llamaCPP:
            ["--version"]
        }
    }

    private nonisolated static func executableCandidates(for kind: RuntimeInstallation.Kind) -> [String] {
        switch kind {
        case .whisperCPP:
            ["whisper-cli", "whisper-server", "whisper-stream", "whisper.cpp"]
        case .llamaCPP:
            ["llama-cli", "llama-server", "llama.cpp"]
        }
    }

    private nonisolated static func primaryBinaryName(for kind: RuntimeInstallation.Kind) -> String {
        switch kind {
        case .whisperCPP:
            "whisper-cli"
        case .llamaCPP:
            "llama-cli"
        }
    }

    private nonisolated static func bundledRuntimeArchitectureCandidates() -> [String] {
#if arch(arm64)
        ["arm64", "universal"]
#elseif arch(x86_64)
        ["x86_64", "universal"]
#else
        ["universal"]
#endif
    }

    private nonisolated static func repositoryURL(for kind: RuntimeInstallation.Kind) -> String {
        switch kind {
        case .whisperCPP:
            "https://github.com/ggml-org/whisper.cpp.git"
        case .llamaCPP:
            "https://github.com/ggml-org/llama.cpp.git"
        }
    }

    private nonisolated static func whisperModelDownloadURL(for preset: WhisperModelPreset) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(preset.fileName)?download=true")!
    }

    private nonisolated static func llamaModelDownloadURL(for preset: LlamaModelPreset) -> URL {
        URL(string: "https://huggingface.co/\(preset.repoIdentifier)/resolve/main/\(preset.fileName)?download=true")!
    }

    private nonisolated static func which(_ command: String) -> String? {
        let output = try? runProcess("/usr/bin/which", arguments: [command]).trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private nonisolated static func toolPath(named tool: String) -> String? {
        which(tool)
    }

    @discardableResult
    private nonisolated static func runProcess(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 300,
        outputMode: ProcessOutputMode = .capture
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
            .merging(defaultRuntimeEnvironment(for: executable)) { _, new in new }

        var stdoutReader: Pipe?
        var stderrReader: Pipe?
        if outputMode == .capture {
            let stdout = Pipe()
            let stderr = Pipe()
            stdoutReader = stdout
            stderrReader = stderr
            process.standardOutput = stdout
            process.standardError = stderr
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let readGroup = DispatchGroup()
        let collector = ProcessOutputCollector()

        if let stdoutReader {
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collector.storeStdout(stdoutReader.fileHandleForReading.readDataToEndOfFile())
                readGroup.leave()
            }
        }

        if let stderrReader {
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collector.storeStderr(stderrReader.fileHandleForReading.readDataToEndOfFile())
                readGroup.leave()
            }
        }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if Task.isCancelled {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + 5)
                readGroup.wait()
                throw CancellationError()
            }
            if Date() >= deadline {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + 5)
                readGroup.wait()
                throw NSError(
                    domain: "Murmur.RuntimeInstaller",
                    code: 82,
                    userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executable).lastPathComponent) timed out."]
                )
            }
        }

        readGroup.wait()
        let output = collector.combinedOutput()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "Murmur.RuntimeInstaller",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.nonEmpty ?? "Runtime command failed."]
            )
        }

        return output
    }

    private nonisolated static func defaultRuntimeEnvironment(for executablePath: String) -> [String: String] {
        let executableURL = URL(fileURLWithPath: executablePath)
        let libexecURL = executableURL.deletingLastPathComponent().appendingPathComponent("libexec", isDirectory: true)
        guard let backendPath = preferredGGMLBackendPath(in: libexecURL) else {
            return [:]
        }
        return ["GGML_BACKEND_PATH": backendPath]
    }

    private nonisolated static func preferredGGMLBackendPath(in libexecURL: URL) -> String? {
        [
            "libggml-metal.so",
            "libggml-cpu-apple_m4.so",
            "libggml-cpu-apple_m2_m3.so",
            "libggml-cpu-apple_m1.so",
            "libggml-blas.so",
        ]
            .map { libexecURL.appendingPathComponent($0).path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}

private struct RuntimeProbe {
    var path: String
    var version: String?
    var notes: String
    var source: RuntimeInstallation.DetectionSource
    var isRunnable: Bool
}

private struct RuntimeResolution {
    var installState: RuntimeInstallation.InstallState
    var path: String?
    var version: String?
    var notes: String
    var source: RuntimeInstallation.DetectionSource
}

private enum ProcessOutputMode {
    case capture
    case discard
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
