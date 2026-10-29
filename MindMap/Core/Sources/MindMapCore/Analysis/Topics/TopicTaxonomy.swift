import Foundation

// MARK: - Taxonomy node

/// One node of the topic spine. Roots are broad domains ("technology",
/// "legal"); children are the stable sub-regions shown inside a domain.
public struct TopicNode: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var description: String
    public var seeds: [String]
    public var parentID: String?
    /// Fallback nodes collect low-confidence material and are never scored
    /// against the other prototypes.
    public var isFallback: Bool

    public init(
        id: String,
        label: String,
        description: String = "",
        seeds: [String] = [],
        parentID: String? = nil,
        isFallback: Bool = false
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.seeds = seeds
        self.parentID = parentID
        self.isFallback = isFallback
    }
}

// MARK: - Taxonomy

/// A flat, user-editable tree of topic nodes. The taxonomy is the stable
/// spine of the map: emergent clusters may propose children, but a region
/// keeps its name and colour until the user renames or merges it.
public struct TopicTaxonomy: Codable, Hashable, Sendable {
    public var version: Int
    public var nodes: [TopicNode]

    public init(version: Int = 1, nodes: [TopicNode]) {
        self.version = version
        self.nodes = nodes
    }

    public func node(id: String?) -> TopicNode? {
        guard let id else { return nil }
        return nodes.first { $0.id == id }
    }

    public var roots: [TopicNode] {
        nodes.filter { $0.parentID == nil }
    }

    public func children(of id: String) -> [TopicNode] {
        nodes.filter { $0.parentID == id }
    }

    public var leaves: [TopicNode] {
        nodes.filter { !$0.isFallback && children(of: $0.id).isEmpty }
    }

    public var fallbackLeaf: TopicNode? {
        nodes.first { $0.isFallback }
    }

    public func label(for id: String) -> String {
        node(id: id)?.label ?? id
    }

    public func path(to id: String) -> [TopicNode] {
        var chain: [TopicNode] = []
        var current = node(id: id)
        while let item = current {
            chain.insert(item, at: 0)
            current = node(id: item.parentID)
        }
        return chain
    }
}

// MARK: - Default spine

public extension TopicTaxonomy {

    /// Curated English + German seed vocabulary. Seeds are not training data
    /// in the ML sense: they define the vocabulary each region stands for and
    /// are matched by the deterministic classifier.
    static let `default`: TopicTaxonomy = {
        var nodes: [TopicNode] = []

        func add(
            _ id: String,
            _ label: String,
            _ description: String,
            _ seeds: [String],
            parent: String? = nil,
            fallback: Bool = false
        ) {
            nodes.append(TopicNode(
                id: id,
                label: label,
                description: description,
                seeds: seeds,
                parentID: parent,
                isFallback: fallback
            ))
        }

        // PRODUCT ----------------------------------------------------------
        add(
            "product", "Product",
            "product strategy, customers, roadmap, pricing, growth",
            ["product strategy roadmap customers market pricing launch scope",
             "produkt strategie kunden markt preis planung"]
        )
        add(
            "product/strategy", "Strategy",
            "roadmap prioritization scope milestones features",
            ["roadmap prioritization prioritize scope mvp milestone backlog feature shipping ship local-first note-taking startup",
             "fahrplan priorisierung umfang funktion meilenstein lieferung"]
        , parent: "product")
        add(
            "product/discovery", "Discovery",
            "customer research interviews personas market feedback",
            ["customer persona interview discovery market audience survey feedback segment",
             "kundenbefragung zielgruppe marktforschung feedback"]
        , parent: "product")
        add(
            "product/pricing", "Pricing",
            "pricing packaging tiers subscription plans",
            ["pricing packaging tier subscription upsell billing monetization revenue",
             "preisgestaltung preis paket abonnement tarif"]
        , parent: "product")
        add(
            "product/growth", "Growth",
            "acquisition retention funnels conversion campaigns",
            ["growth acquisition retention funnel conversion campaign onboarding activation",
             "wachstum neukunden bindung trichter kampagne"]
        , parent: "product")

        // TECHNOLOGY -------------------------------------------------------
        add(
            "technology", "Technology",
            "software, architecture, infrastructure, AI systems",
            ["technology software engineering code architecture infrastructure",
             "technik technologie entwicklung software architektur"]
        )
        add(
            "technology/software", "Software",
            "implementation, debugging, refactoring, tests, APIs",
            ["swift swiftui kotlin python javascript typescript rust api bug debug refactor compile function endpoint backend frontend test build xcode performance rendering render frame graph node knowledge sync crdt offline esp32 sensor firmware",
             "programmieren fehler beheben schnittstelle funktion testen leistung"]
        , parent: "technology")
        add(
            "technology/architecture", "Architecture",
            "system design, databases, deployment, scaling",
            ["architecture database schema migration server infrastructure deployment docker kubernetes nomad cluster postgres container cache queue scaling latency distributed microservice",
             "architektur datenbank schema migration server bereitstellung skalierung"]
        , parent: "technology")
        add(
            "technology/ai", "AI",
            "models, prompts, agents, embeddings, inference",
            ["llm prompt agent embedding neural transformer attention inference token finetuning rag vector openai claude gemini memory retrieval context semantic",
             "kuenstliche intelligenz modell eingabe aufforderung vektor gedaechtnis"]
        , parent: "technology")

        // DESIGN -----------------------------------------------------------
        add(
            "design", "Design",
            "interface, interaction, visual language, brand",
            ["design interface interaction visual experience brand",
             "design gestaltung oberflaeche erfahrung marke"]
        )
        add(
            "design/interface", "Interface",
            "layout, typography, components, motion, accessibility",
            ["interface layout typography component wireframe prototype figma interaction animation accessibility responsive visual hud canvas brutalist neobrutalist contrast spacing grid screen voice transit",
             "oberflaeche layout schrift komponente entwurf barrierefrei kontrast raster"]
        , parent: "design")
        add(
            "design/brand", "Brand",
            "identity, logo, palette, voice, aesthetics",
            ["brand identity logo palette colour color typeface style aesthetic tone voice",
             "marke identitaet logo farbe stil"]
        , parent: "design")

        // LEGAL ------------------------------------------------------------
        add(
            "legal", "Legal",
            "contracts, privacy, compliance, intellectual property",
            ["legal law contract privacy compliance licence license regulation",
             "recht vertrag datenschutz gesetz compliance lizenz"]
        )
        add(
            "legal/contracts", "Contracts",
            "agreements, clauses, liability, termination, jurisdiction",
            ["contract agreement clause liability nda terms signature indemnity termination jurisdiction breach kündigung kuendigung frist mietrecht mietvertrag",
             "vertrag vereinbarung klausel haftung kuendigung gericht frist mietrecht"]
        , parent: "legal")
        add(
            "legal/privacy", "Privacy",
            "GDPR, consent, retention, data protection policy",
            ["privacy gdpr consent policy compliance regulation data protection cookie retention dpa dsgvo datenschutz",
             "datenschutz einwilligung richtlinie aufbewahrung"]
        , parent: "legal")
        add(
            "legal/ip", "IP",
            "copyright, trademark, patent, licensing, attribution",
            ["copyright trademark patent license licensing intellectual property attribution open source infringement urheberrecht marke",
             "urheberrecht marke patent lizenz quellenangabe"]
        , parent: "legal")

        // FINANCE ----------------------------------------------------------
        add(
            "finance", "Finance",
            "budgets, fundraising, accounting, business numbers",
            ["finance money budget fundraising accounting revenue tax",
             "finanzen geld budget steuer buchhaltung umsatz"]
        )
        add(
            "finance/planning", "Planning",
            "budgets, forecasts, runway, costs, margins",
            ["budget forecast runway cost expense cash margin projection burn investing investment etf index indexing portfolio stock fund return savings",
             "budget prognose kosten ausgaben gewinnspanne anlage portfolio"]
        , parent: "finance")
        add(
            "finance/fundraising", "Fundraising",
            "investors, pitches, valuation, rounds, equity",
            ["fundraising investor pitch valuation round seed startup climate hardware equity cap table",
             "investor finanzierung bewertung kapital gruendung"]
        , parent: "finance")
        add(
            "finance/accounting", "Accounting",
            "invoices, tax, bookkeeping, receipts",
            ["invoice tax accounting bookkeeping receipt vat steuer rechnung buchhaltung",
             "rechnung steuer buchhaltung beleg"]
        , parent: "finance")

        // RESEARCH ---------------------------------------------------------
        add(
            "research", "Research",
            "papers, experiments, methods, learning",
            ["research paper study experiment methodology learning",
             "forschung studie experiment methode lernen"]
        )
        add(
            "research/literature", "Literature",
            "papers, citations, journals, related work",
            ["paper study citation journal literature abstract preprint survey related work quantum computing theory hype",
             "studie quelle zeitschrift literatur zusammenfassung quanten"]
        , parent: "research")
        add(
            "research/experiment", "Experiment",
            "hypotheses, datasets, benchmarks, evaluation",
            ["experiment hypothesis dataset methodology results baseline benchmark evaluation metric sample",
             "experiment hypothese datensatz ergebnis auswertung"]
        , parent: "research")
        add(
            "research/learning", "Learning",
            "tutorials, courses, explanations, practice",
            ["learn tutorial course explain understand lesson practice curriculum exercise kanji japanese language vocabulary",
             "lernen tutorial kurs erklaeren uebung sprache vokabel"]
        , parent: "research")

        // OPERATIONS -------------------------------------------------------
        add(
            "operations", "Operations",
            "delivery process, team, vendors, project management",
            ["operations process delivery team vendor project management",
             "betrieb ablauf lieferung team projekt leitung"]
        )
        add(
            "operations/delivery", "Delivery",
            "sprints, timelines, milestones, workflow",
            ["sprint timeline milestone backlog workflow process delivery kanban dependency planning",
             "sprint zeitplan meilenstein ablauf planung"]
        , parent: "operations")
        add(
            "operations/team", "Team",
            "hiring, roles, onboarding, performance",
            ["hiring interview onboarding role candidate team manager performance review recruiting bewerbung stipendium scholarship application resume motivation essay deadline",
             "einstellung bewerbung rolle team personal stipendium motivierung"]
        , parent: "operations")
        add(
            "operations/vendors", "Vendors",
            "suppliers, procurement, agencies, negotiations",
            ["vendor supplier procurement purchase contractor agency negotiation",
             "lieferant einkauf agentur verhandlung"]
        , parent: "operations")

        // PERSONAL ---------------------------------------------------------
        add(
            "personal", "Personal",
            "health, home, leisure, everyday life",
            ["personal health home leisure life",
             "persoenlich gesundheit wohnen freizeit leben"]
        )
        add(
            "personal/health", "Health",
            "fitness, sleep, nutrition, medical",
            ["workout sleep diet nutrition doctor exercise health stress meditation running marathon training chronotype protein meal fitness bike cycling commute",
             "training schlaf ernaehrung arzt gesundheit sport fahrrad pendeln"]
        , parent: "personal")
        add(
            "personal/home", "Home",
            "housing, moves, furniture, rent",
            ["apartment move moving furniture rent house kitchen lease landlord renovation balcony door leak seal tomato plant garden umzug",
             "wohnung umzug moebel miete haus kuche vermieter renovierung balkon pflanze garten"]
        , parent: "personal")
        add(
            "personal/leisure", "Leisure",
            "travel, hobbies, media, food",
            ["travel trip holiday game hobby music book movie restaurant recipe ramen broth tonkotsu shoyu cooking cook soup pumpkin kürbis kürbissuppe röstaroma japan tokyo kyoto kanazawa synthwave ableton track mixing photography photograph camera lens film portrait analog neon novel writing board boardgame player faction playtest mechanic asymmetry printed print rig modular detective",
             "reise urlaub spiel hobby musik buch restaurant rezept kochen fotografie kamera film roman brettspiel"]
        , parent: "personal")

        // PHILOSOPHY -------------------------------------------------------
        // Formal/analytic philosophy. Scope is deliberately the formal core:
        // logic, mathematics, language, mind, epistemology, metaphysics, and
        // philosophy of science. Ethics and political philosophy are not
        // seeded here, so those conversations stay in their existing regions.
        add(
            "philosophy", "Philosophy",
            "formal philosophy, analytic philosophy, ontology, epistemology, logic",
            ["philosophy philosophical philosopher metaphysics epistemology ontology logic logical analytic kant plato aristotle hegel wittgenstein heidegger hume descartes leibniz spinoza phenomenology dialectic rationalism empiricism skepticism consciousness qualia",
             "philosophie philosophisch erkenntnistheorie ontologie metaphysik logik bewusstsein philosoph"]
        )
        add(
            "philosophy/logic", "Logic",
            "validity, inference, modality, paradoxes, formal systems",
            ["logic logical syllogism propositional predicate quantifier modal inference deduction induction paradox tautology consistency soundness completeness validity formalization countermodel deontic",
             "logik schlussfolgerung ableitung widerspruch beweis"]
        , parent: "philosophy")
        add(
            "philosophy/mathematics", "Mathematics",
            "axioms, set theory, infinity, platonism, formalism, incompleteness",
            ["mathematics mathematical axiom axiomatic set cardinality ordinal infinity continuum platonism formalism intuitionism logicism incompleteness godel gödel hilbert frege russell peano",
             "mathematik axiomatisch mengenlehre unendlichkeit beweis"]
        , parent: "philosophy")
        add(
            "philosophy/language", "Language",
            "meaning, reference, semantics, pragmatics, speech acts",
            ["meaning semantics reference sense analytic synthetic priori posteriori speech pragmatics grice kripke frege russell descriptivism rigid designation proposition",
             "bedeutung semantik referenz sprechakt"]
        , parent: "philosophy")
        add(
            "philosophy/mind", "Mind",
            "consciousness, qualia, intentionality, mental causation, personal identity",
            ["mind consciousness qualia intentionality phenomenal mental causation dualism physicalism functionalism behaviorism chalmers nagel zombie hard problem personal identity emergence",
             "bewusstsein geist intentionalitaet dualismus phaenomenologie"]
        , parent: "philosophy")
        add(
            "philosophy/epistemology", "Epistemology",
            "knowledge, justification, belief, skepticism, rationality",
            ["epistemology epistemic knowledge justification belief skeptic skepticism certainty evidence gettier coherentism foundationalism reliabilism rationalism empiricism priori posteriori testimony",
             "erkenntnistheorie wissen rechtfertigung ueberzeugung skeptizismus gewissheit"]
        , parent: "philosophy")
        add(
            "philosophy/metaphysics", "Metaphysics",
            "existence, causation, modality, identity, time, free will",
            ["metaphysics ontology ontological existence causation causality substance property identity modality possible worlds necessity contingency determinism compatibilism universals particulars mereology endurance perdurance",
             "metaphysik ontologie existenz kausalitaet identitaet determinismus wille"]
        , parent: "philosophy")
        add(
            "philosophy/science", "Science",
            "explanation, realism, falsification, paradigms, demarcation",
            ["scientific falsification paradigm kuhn popper lakatos realism instrumentalism reductionism emergence laden observation demarcation underdetermination",
             "wissenschaftstheorie erklaerung falsifikation paradigma"]
        , parent: "philosophy")

        // EMERGING ---------------------------------------------------------
        add(
            "emerging", "Emerging",
            "low-confidence material that does not fit an existing region yet",
            ["emerging miscellaneous unclear"],
            fallback: true
        )
        add(
            "emerging/misc", "Miscellaneous",
            "unclassified or mixed topics waiting to be adopted",
            ["miscellaneous various other general unclear random",
             "sonstiges unklar allgemein"]
        , parent: "emerging", fallback: true)

        return TopicTaxonomy(version: 5, nodes: nodes)
    }()
}
