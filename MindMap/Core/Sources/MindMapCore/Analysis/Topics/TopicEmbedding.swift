import Foundation

/// Re-embeddable representation used by the topic pipeline. Production can
/// swap in a bundled CoreML sentence encoder without touching the segmenter,
/// classifier, or graph builder.
public protocol TopicEmbeddingProvider: Sendable {
    var id: String { get }
    var dimensions: Int { get }
    func embed(_ text: String) -> [Float]
}

/// Deterministic bag-of-words feature hashing. No model file, no network:
/// identical text always produces the identical vector, which keeps the
/// pipeline testable and the map stable across launches.
public struct HashingEmbedder: TopicEmbeddingProvider {
    public let id: String
    public let dimensions: Int

    public init(dimensions: Int = 256) {
        self.dimensions = max(32, dimensions)
        self.id = "hash-\(self.dimensions)-v1"
    }

    public func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        let tokens = KeywordExtractor.tokenize(text)
        guard !tokens.isEmpty else { return vector }

        func add(_ token: String, weight: Float) {
            let hash = StableID.hash(token)
            let index = Int(hash % UInt64(dimensions))
            let sign: Float = ((hash >> 40) & 1) == 0 ? 1 : -1
            vector[index] += sign * weight
        }

        for token in tokens {
            add(token, weight: 1)
        }
        if tokens.count > 1 {
            for index in 0..<(tokens.count - 1) {
                add(tokens[index] + " " + tokens[index + 1], weight: 0.5)
            }
        }

        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for index in vector.indices {
                vector[index] /= norm
            }
        }
        return vector
    }
}

// MARK: - Vector helpers

enum TopicVector {
    static func dot(_ a: [Float], _ b: [Float]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var total: Double = 0
        for index in 0..<count {
            total += Double(a[index] * b[index])
        }
        return total
    }

    static func centroid(_ vectors: [[Float]], dimensions: Int) -> [Float] {
        guard !vectors.isEmpty else { return [Float](repeating: 0, count: dimensions) }
        var result = [Float](repeating: 0, count: dimensions)
        for vector in vectors {
            let count = min(dimensions, vector.count)
            for index in 0..<count {
                result[index] += vector[index]
            }
        }
        let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for index in result.indices {
                result[index] /= norm
            }
        }
        return result
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
