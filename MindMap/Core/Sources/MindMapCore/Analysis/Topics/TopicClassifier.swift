import Foundation

/// Hierarchical, deterministic topic scoring. Each node owns a prototype
/// built from its seed vocabulary; parents gate their children so a leaf can
/// never win outside the domain that explains it.
public struct TopicClassifier: Sendable {
    struct Prototype: Sendable {
        var node: TopicNode
        var centroid: [Float]
        var tokens: Set<String>
    }

    private let taxonomy: TopicTaxonomy
    private let embedder: any TopicEmbeddingProvider
    private let prototypes: [String: Prototype]
    private let roots: [TopicNode]
    private let leaves: [TopicNode]
    private let fallbackID: String?

    public init(taxonomy: TopicTaxonomy, embedder: any TopicEmbeddingProvider) {
        self.taxonomy = taxonomy
        self.embedder = embedder

        // A parent's prototype is its own seeds plus every descendant's, so a
        // leaf term like "kubernetes" still gives the Technology root evidence
        // instead of being gated out by a root vocabulary that never mentions it.
        let childrenByParent = Dictionary(
            grouping: taxonomy.nodes.filter { $0.parentID != nil },
            by: { $0.parentID ?? "" }
        )
        func subtreeTexts(_ node: TopicNode) -> [String] {
            var texts = node.seeds + [node.description]
            for child in childrenByParent[node.id] ?? [] {
                texts.append(contentsOf: subtreeTexts(child))
            }
            return texts
        }

        var prototypes: [String: Prototype] = [:]
        for node in taxonomy.nodes {
            let texts = subtreeTexts(node)
            let vectors = texts.map { embedder.embed($0) }
            var tokens = Set<String>()
            for text in texts {
                tokens.formUnion(KeywordExtractor.tokenize(text))
            }
            prototypes[node.id] = Prototype(
                node: node,
                centroid: TopicVector.centroid(vectors, dimensions: embedder.dimensions),
                tokens: tokens
            )
        }
        self.prototypes = prototypes
        self.roots = taxonomy.roots.filter { !$0.isFallback }
        self.leaves = taxonomy.leaves
        self.fallbackID = taxonomy.fallbackLeaf?.id
    }

    // MARK: - Distribution

    /// Soft distribution over leaf topics. Multi-label at the thread level:
    /// the pipeline sums these distributions instead of forcing one region.
    public func distribution(for text: String) -> [String: Double] {
        let tokens = Set(KeywordExtractor.tokenize(text))
        guard !tokens.isEmpty, !leaves.isEmpty else {
            return fallbackDistribution()
        }
        let embedding = embedder.embed(text)

        var rootScores: [String: Double] = [:]
        for root in roots {
            guard let prototype = prototypes[root.id] else { continue }
            rootScores[root.id] = combinedScore(embedding: embedding, tokens: tokens, prototype: prototype)
        }
        guard let strongestRoot = rootScores.values.max() else {
            return fallbackDistribution()
        }

        var leafScores: [String: Double] = [:]
        for leaf in leaves {
            guard let prototype = prototypes[leaf.id] else { continue }
            let parentScore = leaf.parentID.flatMap { rootScores[$0] } ?? strongestRoot
            let own = combinedScore(embedding: embedding, tokens: tokens, prototype: prototype)
            leafScores[leaf.id] = 0.38 * parentScore + 0.62 * own
        }

        guard let maximum = leafScores.values.max() else {
            return fallbackDistribution()
        }
        // Nothing in the text resembles the spine: keep it in Emerging rather
        // than forcing a confident wrong region. A real vocabulary hit earns
        // a lower bar than a purely geometric near-miss.
        let hasVocabulary = tokens.contains { token in
            prototypes.contains { entry in
                !entry.value.node.isFallback && entry.value.tokens.contains(token)
            }
        }
        if maximum < (hasVocabulary ? 0.10 : 0.18) {
            return fallbackDistribution()
        }

        let temperature = 0.09
        var weights: [String: Double] = [:]
        var total = 0.0
        // Sorted iteration keeps floating-point accumulation bit-stable
        // across launches (dictionary order is randomized).
        for id in leafScores.keys.sorted() {
            guard let score = leafScores[id] else { continue }
            let weight = exp((score - maximum) / temperature)
            weights[id] = weight
            total += weight
        }
        guard total > 0 else { return fallbackDistribution() }
        for id in weights.keys {
            weights[id] = (weights[id] ?? 0) / total
        }

        // Sparsify: long-tail leaves at 1–2% are scoring noise, not signal.
        // Keeping them would paint every thread with eight faint regions.
        if let best = weights.values.max() {
            let floor = best * 0.12
            let kept = weights.filter { $0.value >= floor }
            let keptTotal = kept.keys.sorted().reduce(0.0) { $0 + (kept[$1] ?? 0) }
            if keptTotal > 0 {
                weights = kept.mapValues { $0 / keptTotal }
            }
        }
        return weights
    }

    public func blended(_ text: String, with prior: [String: Double], priorWeight: Double) -> [String: Double] {
        let own = distribution(for: text)
        guard !prior.isEmpty, priorWeight > 0 else { return own }
        // A segment with no vocabulary evidence inherits the thread's title
        // prior instead of dragging a well-titled conversation into Emerging.
        if own.count == 1, let id = own.keys.first, id == fallbackID {
            return prior
        }
        let clamped = min(max(priorWeight, 0), 0.5)
        var result: [String: Double] = [:]
        for id in own.keys.sorted() {
            result[id] = (own[id] ?? 0) * (1 - clamped)
        }
        for id in prior.keys.sorted() {
            result[id, default: 0] += (prior[id] ?? 0) * clamped
        }
        return result
    }

    public func evidence(for text: String, topicID: String, limit: Int = 4) -> [String] {
        guard let prototype = prototypes[topicID] else { return [] }
        let ranked = KeywordExtractor.keywords(inText: text, idf: [:], limit: 16)
        return ranked
            .map(\.term)
            .filter { prototype.tokens.contains($0) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Scoring

    private func combinedScore(embedding: [Float], tokens: Set<String>, prototype: Prototype) -> Double {
        let cosine = max(0, TopicVector.dot(embedding, prototype.centroid))
        let overlap = tokens.intersection(prototype.tokens).count
        let lexical = overlap == 0 ? 0 : Double(overlap) / (Double(overlap) + 2.5)
        return 0.58 * cosine + 0.42 * lexical
    }

    private func fallbackDistribution() -> [String: Double] {
        guard let fallbackID else { return [:] }
        return [fallbackID: 1]
    }
}
