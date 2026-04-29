#!/usr/bin/env swift

import Foundation

// MARK: - Errors

enum DecodeError: LocalizedError {
    case missingOptions
    case unknownOption(String)
    case missingArgument(String)
    case invalidArgument(String, String)
    case sourceNotFound(String)
    case noSubdirectories(String)
    case tooFewStreams(String)
    case ffmpegFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .missingOptions:                return "-i and -o are required"
        case .unknownOption(let o):          return "unknown option: \(o)"
        case .missingArgument(let o):        return "\(o) requires an argument"
        case .invalidArgument(let o, let v): return "invalid value for \(o): \(v)"
        case .sourceNotFound(let p):         return "source directory not found: \(p)"
        case .noSubdirectories(let p):       return "no subdirectories found in \(p)"
        case .tooFewStreams(let d):          return "fewer than 2 stream files in \(d)"
        case .ffmpegFailed(let code, let msg):
            return "ffmpeg exited with status \(code)\(msg.isEmpty ? "" : ": \(msg)")"
        }
    }
}

// MARK: - Options

struct Options {
    let source: URL
    let output: URL
    let concurrency: Int
    let keepSource: Bool
}

func printHelp(to stream: UnsafeMutablePointer<FILE> = stdout) {
    let program = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "bilibili-decode"
    let defaultJobs = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    let text = """
    Usage: \(program) -i <source> -o <output> [-j <workers>] [-k|--keep]

    Decode and merge Bilibili offline downloads into .mp4 files.
    Iterates each subdirectory of <source>, strips the 9-byte obfuscation
    header from the two stream files, and remuxes them with ffmpeg.

    Options:
      -i <dir>      Source directory containing Bilibili download subdirs
      -o <dir>      Output directory for merged .mp4 files (created if needed)
      -j <N>        Number of videos to process in parallel (default: \(defaultJobs))
      -k, --keep    Keep source files after a successful merge (default: delete)
      -h, --help    Show this help message and exit

    """
    fputs(text, stream)
}

func parseOptions() throws -> Options {
    let args = Array(CommandLine.arguments.dropFirst())
    var source: String?
    var output: String?
    var concurrency = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    var keepSource = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "-h", "--help":
            printHelp()
            exit(0)
        case "-i":
            i += 1
            guard i < args.count else { throw DecodeError.missingArgument("-i") }
            source = args[i]
        case "-o":
            i += 1
            guard i < args.count else { throw DecodeError.missingArgument("-o") }
            output = args[i]
        case "-j":
            i += 1
            guard i < args.count else { throw DecodeError.missingArgument("-j") }
            guard let n = Int(args[i]), n > 0 else {
                throw DecodeError.invalidArgument("-j", args[i])
            }
            concurrency = n
        case "-k", "--keep":
            keepSource = true
        default:
            throw DecodeError.unknownOption(args[i])
        }
        i += 1
    }

    guard let source, let output else { throw DecodeError.missingOptions }

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source, isDirectory: &isDir), isDir.boolValue else {
        throw DecodeError.sourceNotFound(source)
    }

    return Options(
        source: URL(fileURLWithPath: source),
        output: URL(fileURLWithPath: output),
        concurrency: concurrency,
        keepSource: keepSource
    )
}

// MARK: - Helpers

struct VideoInfo: Decodable { let title: String }

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    var isRegularFile: Bool {
        (try? resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}

let forbiddenCharacters = CharacterSet(charactersIn: #"<>:"/\|?*"#)

func sanitize(_ title: String) -> String {
    let cleaned = title
        .components(separatedBy: forbiddenCharacters).joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "untitled" : cleaned
}

let metadataNames: Set<String> = ["view", ".playurl", ".videoInfo"]
let metadataExtensions: Set<String> = ["jpg", "png", "json"]

func isMetadata(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    return metadataNames.contains(name)
        || metadataExtensions.contains(url.pathExtension)
        || name.hasPrefix("dm")
}

func subfileURL(_ url: URL, skip: Int) -> String {
    "subfile,,start,\(skip),end,0,,:file:\(url.path)"
}

func merge(stream1: URL, stream2: URL, into output: URL) throws {
    let errLog = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("bili-ffmpeg-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: errLog.path, contents: nil)
    let errFile = try FileHandle(forWritingTo: errLog)
    defer {
        try? errFile.close()
        try? FileManager.default.removeItem(at: errLog)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "ffmpeg", "-nostdin", "-y", "-loglevel", "error",
        "-i", subfileURL(stream1, skip: 9),
        "-i", subfileURL(stream2, skip: 9),
        "-c", "copy", "file:\(output.path)",
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errFile

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errData = (try? Data(contentsOf: errLog)) ?? Data()
        let msg = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        throw DecodeError.ffmpegFailed(process.terminationStatus, msg)
    }
}

// MARK: - Per-video processing

func processVideo(_ dir: URL, into outputDir: URL, keepSource: Bool) throws -> String {
    let fm = FileManager.default

    let info = try JSONDecoder().decode(
        VideoInfo.self,
        from: Data(contentsOf: dir.appendingPathComponent("videoInfo.json"))
    )
    let name = sanitize(info.title)

    var streams: [URL] = []
    var allFiles: [URL] = []
    for entry in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        where entry.isRegularFile {
        allFiles.append(entry)
        if !isMetadata(entry) {
            streams.append(entry)
        }
    }
    streams.sort { $0.lastPathComponent < $1.lastPathComponent }

    guard streams.count >= 2 else {
        throw DecodeError.tooFewStreams(dir.lastPathComponent)
    }

    try merge(
        stream1: streams[0],
        stream2: streams[1],
        into: outputDir.appendingPathComponent("\(name).mp4")
    )

    if !keepSource {
        for file in allFiles {
            try? fm.removeItem(at: file)
        }
    }
    return name
}

// MARK: - Orchestration

func run() async throws {
    let options = try parseOptions()
    let fm = FileManager.default

    try fm.createDirectory(at: options.output, withIntermediateDirectories: true)

    let subdirs = try fm.contentsOfDirectory(
        at: options.source,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    )
    .filter(\.isDirectory)
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !subdirs.isEmpty else {
        throw DecodeError.noSubdirectories(options.source.path)
    }

    let total = subdirs.count
    print("Found \(total) videos. Processing with \(options.concurrency) workers.")

    var failures: [(dir: String, error: Error)] = []
    var completed = 0

    await withTaskGroup(of: (URL, Result<String, Error>).self) { group in
        var iterator = subdirs.makeIterator()
        let outputDir = options.output
        let keepSource = options.keepSource

        for _ in 0..<options.concurrency {
            guard let next = iterator.next() else { break }
            group.addTask(priority: .userInitiated) {
                (next, Result { try processVideo(next, into: outputDir, keepSource: keepSource) })
            }
        }

        while let (dir, result) = await group.next() {
            completed += 1
            switch result {
            case .success(let name):
                print("[\(completed)/\(total)] ✓ \(name)")
            case .failure(let err):
                print("[\(completed)/\(total)] ✗ \(dir.lastPathComponent): \(err.localizedDescription)")
                failures.append((dir.lastPathComponent, err))
            }
            if let next = iterator.next() {
                group.addTask(priority: .userInitiated) {
                    (next, Result { try processVideo(next, into: outputDir, keepSource: keepSource) })
                }
            }
        }
    }

    if !failures.isEmpty {
        fputs("\n\(failures.count) failed:\n", stderr)
        for (dir, err) in failures {
            fputs("  - \(dir): \(err.localizedDescription)\n", stderr)
        }
        exit(1)
    }
}

// MARK: - Entry

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        try await run()
    } catch {
        fputs("Error: \(error.localizedDescription)\n\n", stderr)
        printHelp(to: stderr)
        exit(1)
    }
    sem.signal()
}
sem.wait()
