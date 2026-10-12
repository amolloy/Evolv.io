//
//  Scorer.swift
//  EvolvScorer
//
//  Combines the structure metrics with Apple's on-device aesthetics score
//  into the single 0...1 number clients sort on.
//

import CoreGraphics
import Foundation
import Vision

struct AestheticsScores: Codable {
    /// Vision's overall score, -1...1.
    var overall: Double
    /// Vision's guess that the image is a screenshot, receipt or similar.
    var isUtility: Bool
}

struct ScoreResult: Codable {
    var id: String?
    var score: Double
    var dud: Bool
    var dudReason: String?
    var structure: StructureMetrics
    var aesthetics: AestheticsScores?
    /// Vision's image feature print, when asked for. Clients compare these
    /// (Euclidean distance) to tell near-copies from new looks.
    var featurePrint: [Float]?
    var elapsedMs: Double
}

enum ScorerError: Error, CustomStringConvertible {
    case undecodable

    var description: String {
        switch self {
        case .undecodable: return "not an image ImageIO can read"
        }
    }
}

struct Scorer {
    /// Share of the final score that comes from Vision's aesthetics score.
    /// Light until it shows it agrees with Andy's picks; it was trained on photos.
    static let aestheticsWeight = 0.2

    var useVision = true

    func score(_ data: Data, id: String? = nil, featurePrint: Bool = false) async throws -> ScoreResult {
        guard let image = AnalysisImage.decode(data) else { throw ScorerError.undecodable }
        return try await score(image, id: id, featurePrint: featurePrint)
    }

    func score(_ image: CGImage, id: String? = nil, featurePrint wantsFeaturePrint: Bool = false) async throws -> ScoreResult {
        let start = Date()
        guard let analysis = AnalysisImage(image) else { throw ScorerError.undecodable }
        let structure = StructureAnalyzer.analyze(analysis)
        let aesthetics = useVision ? await Self.aesthetics(image) : nil
        let featurePrint = wantsFeaturePrint ? await Self.featurePrint(image) : nil

        var score = structure.score
        if let aesthetics {
            let mapped = min(max((aesthetics.overall + 1) / 2, 0), 1)
            score = (1 - Self.aestheticsWeight) * structure.score + Self.aestheticsWeight * mapped
        }
        if structure.dudReason != nil { score = 0 }

        return ScoreResult(
            id: id, score: score, dud: structure.dudReason != nil,
            dudReason: structure.dudReason, structure: structure,
            aesthetics: aesthetics, featurePrint: featurePrint, elapsedMs: Date().timeIntervalSince(start) * 1000)
    }

    static func featurePrint(_ image: CGImage) async -> [Float]? {
        do {
            let observation = try await GenerateImageFeaturePrintRequest().perform(on: image)
            switch observation.elementType {
            case .float:
                return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            case .double:
                return observation.data.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
            default:
                return nil
            }
        } catch {
            FileHandle.standardError.write(Data("EvolvScorer: Vision feature print failed: \(error)\n".utf8))
            return nil
        }
    }

    static func aesthetics(_ image: CGImage) async -> AestheticsScores? {
        let request = CalculateImageAestheticsScoresRequest()
        do {
            let observation = try await request.perform(on: image)
            return AestheticsScores(overall: Double(observation.overallScore), isUtility: observation.isUtility)
        } catch {
            FileHandle.standardError.write(Data("EvolvScorer: Vision aesthetics failed: \(error)\n".utf8))
            return nil
        }
    }
}
