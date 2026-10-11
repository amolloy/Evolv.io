//
//  main.swift
//  EvolvScorer
//
//  Scores rendered genotype images for rich structure, locally.
//  Documentation/Scorer.md has the design.
//

import Foundation

let usage = """
usage: EvolvScorer score [--json] [--no-vision] <image>...
       EvolvScorer serve [--port 4850] [--lan] [--no-vision]

score   Score image files and print one line (or one JSON object) per file.
serve   Run the HTTP service: GET /health, POST /score (image bytes as body,
        optional ?id= echoed back). Loopback only unless --lan, which also
        advertises _evolvscore._tcp over Bonjour.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(2)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
arguments.removeFirst()

var json = false, lan = false, useVision = true
var port: UInt16 = 4850
var files: [String] = []
var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--json": json = true
    case "--lan": lan = true
    case "--no-vision": useVision = false
    case "--port":
        index += 1
        guard index < arguments.count, let value = UInt16(arguments[index]) else { fail("--port needs a number") }
        port = value
    case let option where option.hasPrefix("--"):
        fail("unknown option \(option)\n\n\(usage)")
    case let file:
        files.append(file)
    }
    index += 1
}

let scorer = Scorer(useVision: useVision)

switch command {
case "score":
    guard !files.isEmpty else { fail(usage) }
    if !json {
        print("score  dud      cover  variety coher  rich   aesth  file")
    }
    for file in files {
        let url = URL(fileURLWithPath: file)
        guard let image = AnalysisImage.decode(contentsOf: url) else {
            FileHandle.standardError.write(Data("\(file): not an image ImageIO can read\n".utf8))
            continue
        }
        let result = try await scorer.score(image, id: file)
        if json {
            print(String(data: try JSONEncoder.scorer.encode(result), encoding: .utf8)!)
        } else {
            let s = result.structure
            let aesthetics = result.aesthetics.map { String(format: "%+.2f", $0.overall) } ?? "  -  "
            let dud = (result.dudReason ?? "-").padding(toLength: 7, withPad: " ", startingAt: 0)
            print(String(format: "%.3f  %@  %.2f   %.2f    %.2f   %.2f   %@  %@",
                         result.score, dud, s.coverage, s.variety, s.coherence, s.richness,
                         aesthetics, url.lastPathComponent))
        }
    }

case "serve":
    // Line-buffer stdout so a LaunchAgent's log file shows each line as it happens.
    setvbuf(stdout, nil, _IOLBF, 0)
    let server = HTTPServer(port: port, lan: lan, scorer: scorer)
    do {
        try server.start()
    } catch {
        fail("EvolvScorer: couldn't listen on port \(port): \(error)")
    }
    while true {
        try await Task.sleep(for: .seconds(3600))
    }

default:
    fail(usage)
}
