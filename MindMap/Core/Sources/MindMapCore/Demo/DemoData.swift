import Foundation

/// A curated, deterministic demo library. It exists so the map is explorable
/// before any export is imported, and it exercises every provider/color path.
/// Demo threads are flagged so they can be removed with one click.
public enum DemoData {

    public static func make(now: Date = Date()) -> ThreadLibrary {
        var rng = SplitMix64(seed: 0x4d49_4e44_4d45_4d45) // "MINDMEME"
        var threads: [ConversationThread] = []

        for (topicIndex, topic) in topics.enumerated() {
            let providers = schedule(for: topicIndex)
            for (variant, provider) in providers.enumerated() {
                let messages = makeMessages(
                    topic: topic,
                    variant: variant,
                    provider: provider,
                    rng: &rng,
                    now: now,
                    topicIndex: topicIndex
                )
                let daysAgo = Int.random(in: 3...470, using: &rng)
                let hour = Int.random(in: 8...22, using: &rng)
                let minute = Int.random(in: 0...59, using: &rng)
                let base = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                let start = Calendar.current.date(
                    bySettingHour: hour, minute: minute, second: 0, of: base
                ) ?? base

                var stamped: [ChatMessage] = []
                for (index, message) in messages.enumerated() {
                    let offset = Double(index) * Double(Int.random(in: 40...260, using: &rng))
                    stamped.append(ChatMessage(
                        id: message.id,
                        role: message.role,
                        text: message.text,
                        timestamp: start.addingTimeInterval(offset)
                    ))
                }

                let lastMessage = stamped.last?.timestamp ?? start
                let titleSuffix: String
                switch provider {
                case .chatgpt: titleSuffix = variant % 2 == 0 ? " — action plan" : " — checklist"
                case .gemini: titleSuffix = variant % 2 == 0 ? " — deep dive" : ""
                case .claude: titleSuffix = " — trade-offs"
                case .opencode: titleSuffix = " — session notes"
                case .other: titleSuffix = " — local notes"
                }

                threads.append(ConversationThread(
                    id: "demo-\(provider.rawValue)-\(topicIndex)-\(variant)",
                    provider: provider,
                    title: topic.title + titleSuffix,
                    createdAt: start,
                    updatedAt: lastMessage,
                    messages: stamped,
                    model: modelName(for: provider, variant: variant),
                    sourceFile: "demo",
                    isDemo: true
                ))
            }
        }

        threads.sort { $0.updatedAt > $1.updatedAt }
        return ThreadLibrary(threads: threads, lastImport: nil)
    }

    // MARK: - Generation

    private static func schedule(for index: Int) -> [Provider] {
        switch index % 4 {
        case 0: return [.chatgpt, .gemini, .claude]
        case 1: return [.chatgpt, .gemini]
        case 2: return [.chatgpt, .gemini, .other]
        default: return [.gemini, .claude, .chatgpt]
        }
    }

    private static func modelName(for provider: Provider, variant: Int) -> String {
        switch provider {
        case .chatgpt: return variant % 2 == 0 ? "gpt-5" : "gpt-5-mini"
        case .gemini: return variant % 2 == 0 ? "gemini-3-pro" : "gemini-2.5-flash"
        case .claude: return variant % 2 == 0 ? "claude-4.5-sonnet" : "claude-4-opus"
        case .opencode: return "deepseek-v4.1-flash"
        case .other: return "local-llama-3.3-70b"
        }
    }

    private static func makeMessages(
        topic: Topic,
        variant: Int,
        provider: Provider,
        rng: inout SplitMix64,
        now: Date,
        topicIndex: Int
    ) -> [ChatMessage] {
        let prompts = topic.prompts
        let notes = topic.notes
        let opening = prompts[variant % prompts.count]
        let term = topic.terms[variant % topic.terms.count]
        let otherTerm = topic.terms[(variant + 1) % topic.terms.count]

        let followUps = [
            "That helps. If I had to ship a first version in two weeks, what would you cut first in \(term), and what should I absolutely keep?",
            "Can you make that concrete? Walk me through one small example for \(term) and name the failure modes I should watch for.",
            "I like the direction. What changes if the constraints get tighter, especially around \(otherTerm)?",
            "One last angle: how would you explain the trade-off between \(term) and \(otherTerm) to a smart person outside the field?"
        ]
        let closings = [
            "Turn this into a short checklist I can keep next to the project and revisit at the end of the week.",
            "If I only remember three things from this conversation, what should they be?",
            "Where would you look first once this is running in the real world and the assumptions start to break?",
            "Give me a 30-day plan with the smallest useful milestones, and flag what would make you change course."
        ]

        func flavor(_ role: MessageRole) -> String? {
            guard role == .assistant else { return nil }
            switch provider {
            case .chatgpt:
                return variant % 2 == 0 ? "A practical way to frame this:" : "Here is the short version, then the details:"
            case .gemini:
                return variant % 2 == 0 ? "Let's break this into layers." : "There are a few useful angles here."
            case .claude:
                return "A few thoughts before the concrete steps, because the trade-offs matter here."
            case .opencode:
                return "Working notes from the local session:"
            case .other:
                return "Local notes, no cloud, so I'll keep this tight:"
            }
        }

        func assistantText(_ indexes: [Int]) -> String {
            let body = indexes.map { notes[$0 % notes.count] }.joined(separator: "\n\n")
            if let flavor = flavor(.assistant) {
                return flavor + "\n\n" + body
            }
            return body
        }

        let followUp = followUps[(variant + topicIndex) % followUps.count]
        let closing = closings[(variant + topicIndex) % closings.count]

        var messages: [ChatMessage] = [
            ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-1",
                role: .user,
                text: opening
            ),
            ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-2",
                role: .assistant,
                text: assistantText([variant, variant + 1, variant + 2])
            ),
            ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-3",
                role: .user,
                text: followUp
            ),
            ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-4",
                role: .assistant,
                text: assistantText([variant + 3, variant + 4])
            )
        ]

        if variant != 1 || topicIndex % 2 == 0 {
            messages.append(ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-5",
                role: .user,
                text: closing
            ))
            messages.append(ChatMessage(
                id: "demo-\(topicIndex)-\(variant)-6",
                role: .assistant,
                text: assistantText([variant + 5, variant])
            ))
        }

        return messages
    }

    // MARK: - Catalog

    private struct Topic {
        var title: String
        var terms: [String]
        var prompts: [String]
        var notes: [String]
    }

    private static let topics: [Topic] = [
        Topic(
            title: "Designing an AI agent memory architecture",
            terms: ["agent memory", "embeddings", "retrieval", "context window"],
            prompts: [
                "I'm designing an AI agent memory architecture for a research assistant. It should remember decisions across sessions without stuffing everything into the context window. How would you split short-term and long-term memory?",
                "Our agent forgets why it chose a plan two days ago. We have embeddings and a vector store, but retrieval keeps surfacing near-duplicates. Where would you start fixing the memory pipeline?",
                "I want to prototype episodic memory for a coding agent: what happened, why it mattered, and what to do next time. What schema would you use before writing any retrieval code?"
            ],
            notes: [
                "Treat agent memory as three layers: a working context assembled per turn, an episodic log of decisions with reasons, and a semantic index for things that must be recalled by meaning rather than recency.",
                "The context window is a budget, not storage. Assemble it at request time from a small set of high-salience memories, and record why each memory was included so you can debug bad answers later.",
                "Embeddings answer similarity, not relevance. Pair vector retrieval with structured filters such as project, date, owner, and confidence, otherwise near-duplicates crowd out the one memory that changes the decision.",
                "Store decisions as compact records: the choice, alternatives rejected, evidence, and an expiry date. That gives the agent something to revisit instead of replaying the entire transcript.",
                "For agent memory, retrieval quality improves when you summarize at write time. Keep the raw event, but index a short human-readable summary with explicit entities and timestamps.",
                "Instrument memory with counters: how often a retrieved item is cited, how often it is contradicted, and how often it is never used. Prune from evidence rather than guessing."
            ]
        ),
        Topic(
            title: "SwiftUI Canvas performance on large graphs",
            terms: ["SwiftUI", "Canvas", "animation", "rendering", "frame rate"],
            prompts: [
                "I have a SwiftUI Canvas rendering a few hundred nodes and glowing edges. It looks great at rest but drops frames while the layout animates. How would you profile and fix it without moving to Metal?",
                "What are the practical limits of SwiftUI Canvas for a node graph with labels, blur-style glows, and animated pulses? I'd rather keep the code small than chase every millisecond.",
                "My graph redraws on every simulation tick even when nothing moved. Is there a clean way to separate simulation updates from rendering and only publish visible changes?"
            ],
            notes: [
                "Start by measuring: a signpost around the simulation step and another around Canvas drawing. Most Canvas performance problems are state churn or per-frame text layout, not the drawing calls themselves.",
                "Avoid resolving fonts or Text views inside the draw closure. Precompute styles, cache resolved strings, and draw labels only when zoom or selection makes them legible.",
                "Glows are cheaper as two or three concentric strokes with falling opacity than as a blur filter. Real blur on hundreds of nodes is where frame rate usually disappears.",
                "Drive the simulation at a fixed timestep and publish a compact snapshot. If the view recomputes graph topology every tick, you are doing layout work at rendering frequency.",
                "When the graph settles, drop to a slower animation clock and keep only cheap ambient motion. Users read a still map as stable, and the battery will thank you.",
                "A Canvas can comfortably carry a few hundred nodes and edges at 60 fps on Apple silicon if you avoid per-node views, shadows, and text layout in the hot path."
            ]
        ),
        Topic(
            title: "Neo-brutalist design system for a fintech app",
            terms: ["design system", "typography", "color", "components", "accessibility"],
            prompts: [
                "I'm building a neo-brutalist design system for a fintech app. I want the attitude of thick borders and raw type without making money feel unsafe. How would you set the rules?",
                "Our design system has twelve shades of gray and four button variants. Can you help me compress it into a small token set that still covers dense financial tables?",
                "How do you make bold, high-contrast typography work for transaction lists without turning the screen into noise?"
            ],
            notes: [
                "Neo-brutalism is a hierarchy strategy: one heavy outline, one loud surface, and generous whitespace around the thing that matters. If everything is loud, nothing is.",
                "Build the color system from semantics first: positive, negative, pending, neutral, and destructive. Two shades per semantic role is usually enough for dense finance UI.",
                "Typography should do most of the work. Use one display face with tight tracking and one durable UI face; let size and weight carry hierarchy instead of adding more colors.",
                "Borders are expensive at scale because they consume layout. Prefer a consistent 1.5 px outline plus a larger corner radius over stacked shadows and decorative frames.",
                "Accessibility is a constraint, not a coat of paint. Check contrast on the loud accent surfaces and never encode gains or losses with color alone.",
                "A good design system shows its limits: document when to break the grid for a hero number, and keep that exception out of the component library."
            ]
        ),
        Topic(
            title: "Kubernetes vs Nomad for a side project",
            terms: ["Kubernetes", "Nomad", "deployment", "cluster", "operations"],
            prompts: [
                "I have three small services, a Postgres database, and one weekend per month for operations. Is Kubernetes or Nomad the better fit, or should I stay on a single VM?",
                "Our team already knows Kubernetes, but the cluster bill is larger than the product revenue. What would a pragmatic migration away from Kubernetes look like without a rewrite?",
                "How do you decide between Kubernetes and Nomad when the real constraint is on-call attention rather than raw scale?"
            ],
            notes: [
                "For three services and a monthly operations budget, a single VM with systemd and a reverse proxy is a legitimate architecture. Kubernetes earns its complexity when scheduling, isolation, and rollout automation are daily problems.",
                "Nomad is simpler to operate than Kubernetes, but the ecosystem around ingress, certificates, and observability is smaller. Count the integrations you would have to build yourself before choosing it.",
                "Managed Kubernetes removes control-plane toil, not the cost of designing deployments, resource limits, and upgrade paths. Budget for those even when the control plane is free.",
                "The migration decision should be driven by failure modes: what breaks at 3 a.m., who can fix it, and how quickly can you roll back. Compare both platforms against that scenario.",
                "A useful middle path is containers on a small VM with a simple orchestrator. You keep reproducible images and health checks without adopting a distributed control plane.",
                "Kubernetes is a platform, not a deployment tool. If nobody owns the platform, the team will slowly accumulate YAML that nobody understands."
            ]
        ),
        Topic(
            title: "Shipping a local-first note taking app",
            terms: ["local-first", "sync", "CRDT", "offline", "conflict"],
            prompts: [
                "I'm building a local-first note taking app with offline editing and multi-device sync. Should I start with a CRDT or an operation log with manual conflict resolution?",
                "Users edit the same note on two devices and expect merges to feel invisible. What are the honest limits of CRDT-based sync for rich text?",
                "How would you explain local-first architecture to a small team that is used to a central database and optimistic UI?"
            ],
            notes: [
                "Local-first means the device owns the data and the network is an optimization. Start by making reads and writes work with no server at all, then add sync as a background process.",
                "CRDTs are excellent for text and sets, but they complicate schema migration and rich-text semantics. If your data model is mostly blocks, an operation log with deterministic merge rules may be easier to reason about.",
                "Conflicts are a product decision before they are an algorithm. Decide what the user should see when two people edit the same paragraph, then choose the data structure that can express it.",
                "Sync should be idempotent and resumable. Give every operation a stable id, store a cursor per device, and make replaying the same batch a no-op.",
                "Encryption changes everything: if the server cannot read content, conflict resolution must happen on-device, which rules out many server-side merge strategies.",
                "Local-first apps earn trust through visible state. Show sync status, last successful backup, and what is still pending, instead of hiding uncertainty behind a spinner."
            ]
        ),
        Topic(
            title: "Ramen broth: tonkotsu vs shoyu",
            terms: ["ramen", "broth", "tonkotsu", "shoyu", "recipe"],
            prompts: [
                "I want to make ramen at home this weekend. I love tonkotsu but I have about six hours, not eighteen. What is a realistic broth plan?",
                "My shoyu ramen tastes flat even though I used good soy sauce. How do I build depth without turning it into a tonkotsu project?",
                "Can you explain the difference between tonkotsu and shoyu broth in terms of technique and the ingredients that actually matter?"
            ],
            notes: [
                "Tonkotsu is an emulsion problem: collagen and fat need sustained heat and agitation. Six hours can work if you use split trotters, keep a hard rolling boil, and accept a lighter body.",
                "Shoyu depth comes from layering, not more soy sauce. Build a tare with kombu, shiitake, and a little mirin, then season the bowl to taste instead of the whole pot.",
                "A pressure cooker collapses tonkotsu time dramatically, but the broth will be cleaner and less milky. Finish with a short hard boil and an immersion blender for body.",
                "For shoyu, use a clear chicken or vegetable stock and keep it below a simmer. Boiling makes it cloudy and mutes the aroma of the tare.",
                "Aromatics should be added late: garlic and ginger can turn bitter over long cooks, while scallion and shiitake are happier with more time.",
                "The bowl is assembled, not cooked: tare, aroma oil, hot broth, drained noodles, and toppings in that order. Taste the broth after the tare goes in, never before."
            ]
        ),
        Topic(
            title: "Training for a sub-3:30 marathon",
            terms: ["marathon", "running", "training", "pace", "recovery"],
            prompts: [
                "I ran a 1:42 half marathon and want to break 3:30 in the marathon in five months. What weekly structure would you use without burning out?",
                "My easy runs keep drifting to marathon pace. How do I rebuild discipline around easy running and still get the quality sessions in?",
                "I have a history of shin splints. How would you adjust a marathon block so volume goes up without repeating the injury?"
            ],
            notes: [
                "A sub-3:30 marathon is roughly 4:58 per kilometer. Most of the training should feel easier than that, with one threshold session and one long run carrying the specific work.",
                "Protect the easy pace. If easy runs creep toward marathon pace, the hard days lose contrast and recovery disappears; use a heart-rate cap or a conversational test.",
                "Build volume in three-week waves: two increases and one lighter week. The long run can grow to 30–32 km, but only if the rest of the week stays honest.",
                "Shin splints respond to load management and calf strength, not just rest. Reduce consecutive impact days, add slow heel raises, and keep intensity on softer surfaces where possible.",
                "Marathon pace work belongs in the long run, but in small doses: blocks of 5–8 km with easy running between them teach fueling and pacing without turning every weekend into a race.",
                "Recovery is part of the plan: sleep, protein, and one genuinely easy day after the long run. A missed easy run is cheaper than a missed month."
            ]
        ),
        Topic(
            title: "ETFs vs direct indexing for long-term investing",
            terms: ["ETF", "portfolio", "tax", "investing", "diversification"],
            prompts: [
                "I'm comparing a broad ETF portfolio with direct indexing for a long-term taxable account. At what portfolio size does direct indexing start to make sense?",
                "How do I evaluate tax-loss harvesting claims without getting lost in the marketing? I want a simple framework for a European investor.",
                "Is direct indexing worth the complexity if I mostly want global diversification and low fees?"
            ],
            notes: [
                "Direct indexing is a tax and customization product first, an investment product second. It starts to matter when harvestable losses and customization are worth more than the extra basis points and complexity.",
                "Compare total cost, not expense ratio: trading spreads, tracking difference, platform fees, and the tax drag of rebalancing all belong in the same table.",
                "Tax-loss harvesting shifts taxes rather than erasing them. The benefit depends on your future tax rate, the wash-sale rules in your jurisdiction, and how long you can defer gains.",
                "A broad global ETF is hard to beat for simplicity. Direct indexing has to earn its place with a specific goal such as excluding a sector or overweighting a factor, not with vibes.",
                "For a European investor, withholding tax, fund domicile, and reporting requirements can matter more than the harvesting story. Model those before optimizing the edges.",
                "Write the policy statement first: target allocation, rebalancing bands, and what you will not do during a drawdown. The product should follow the policy, not define it."
            ]
        ),
        Topic(
            title: "Three weeks in Japan: Tokyo, Kyoto, Kanazawa",
            terms: ["Japan", "Tokyo", "Kyoto", "Kanazawa", "travel"],
            prompts: [
                "I have three weeks in Japan in late October and want Tokyo, Kyoto, and Kanazawa without changing hotels every night. How would you split the days?",
                "Is Kanazawa worth four nights for a first trip, or should I put those days into Kyoto and Osaka? I care more about food and craft than checklist sightseeing.",
                "How do I plan rail travel in Japan so the itinerary stays flexible but I still get the good trains?"
            ],
            notes: [
                "Give Tokyo six or seven nights, Kyoto five, and Kanazawa three, with one buffer night. Late October rewards slow travel: the light is beautiful and the popular gardens are crowded by mid-morning.",
                "Kanazawa is a strong first-trip choice if you care about food and craft. The Omicho market, Higashi Chaya, and the 21st Century Museum fit comfortably into three nights without rushing.",
                "Base yourself once per city. Day trips from Kyoto are easy, but moving luggage every two days burns the best hours of the trip.",
                "For rail, reserve the long-distance legs early and keep regional trains flexible. A rail pass only pays off if the math matches your actual route, not the brochure.",
                "Book one memorable meal per city and leave the rest to neighborhood counters. In Kanazawa, seafood; in Kyoto, a counter omakase; in Tokyo, a standing soba lunch.",
                "Carry cash for small restaurants and markets. Many excellent places still do not take cards, especially outside the big hotel districts."
            ]
        ),
        Topic(
            title: "Mixing a synthwave track in Ableton",
            terms: ["synthwave", "Ableton", "mixing", "synthesizer", "reverb"],
            prompts: [
                "I'm mixing a synthwave track in Ableton and everything sounds loud but flat. How should I organize the low end and the reverb so the mix breathes?",
                "My snare disappears when the pads come in. What is the right way to carve space without making the drums sound thin?",
                "How much sidechain compression is normal for synthwave, and when does it start to sound like a genre caricature?"
            ],
            notes: [
                "Start with gain staging and a reference track. Synthwave is dense by design, so the mix needs deliberate holes more than more layers.",
                "Treat the kick and bass as one instrument: choose which owns the sub frequencies, then high-pass the other without mercy.",
                "Pads are wide and washy; the snare needs a narrow, dry center. Carve 200–400 Hz out of the pads rather than boosting the snare.",
                "Reverb should be a shared space, not eight separate rooms. Use one long plate and one short room on sends, then automate the sends instead of the plugin mix.",
                "Sidechain compression is seasoning. Two to four dB of gain reduction on the bass is usually enough; if the pumping becomes the hook, make that a deliberate arrangement choice.",
                "Check the mix in mono and at low volume. Synthwave collapses quickly when the wide chorus bass disappears on a phone speaker."
            ]
        ),
        Topic(
            title: "Understanding transformer attention from scratch",
            terms: ["transformer", "attention", "neural network", "softmax", "embedding"],
            prompts: [
                "I understand the shapes in a transformer but not why attention works. Can you explain queries, keys, and values without hand-waving the intuition?",
                "Why does multi-head attention help, and what would I lose with a single head? I want a mental model, not just the equations.",
                "How would you implement a minimal attention layer in PyTorch to make sure I really understand the data flow?"
            ],
            notes: [
                "Attention is a soft lookup. Each token asks a question (query), compares it with labels on other tokens (keys), and retrieves a weighted blend of their content (values).",
                "The softmax is where competition happens: scores become a distribution, so attending more to one token necessarily means attending less to another. That normalization is the core constraint.",
                "Multiple heads let the model run several lookups in parallel: one head may track syntax, another coreference, another position. The outputs are concatenated and projected back into one space.",
                "Shapes are the best debugging tool. Write down batch, heads, sequence length, and head dimension before writing code; most transformer bugs are a transpose in disguise.",
                "A minimal implementation is a scaled dot product, a causal mask for decoding, softmax, and a value projection. Test it on a tiny sequence where you can verify the weights by hand.",
                "Attention alone is permutation-invariant, so position must be injected explicitly through positional encodings or relative biases. That is why the same tokens in a different order can behave differently."
            ]
        ),
        Topic(
            title: "Rust ownership for TypeScript developers",
            terms: ["Rust", "ownership", "borrowing", "TypeScript", "memory"],
            prompts: [
                "I write TypeScript every day and keep bouncing off Rust's borrow checker. What mental model makes ownership click without pretending it is just garbage collection?",
                "When should I clone in Rust instead of fighting lifetimes? I want pragmatic rules, not purity.",
                "How do references, ownership, and mutation interact in a struct that holds a cache and exposes read methods?"
            ],
            notes: [
                "Ownership is a compile-time answer to who is responsible for freeing a value. TypeScript hides that question; Rust makes you answer it in the type.",
                "Borrowing is a read/write lock checked statically: any number of readers or one writer, never both. Most borrow-checker pain is really a design that wants shared mutation.",
                "Cloning is a legitimate tool at boundaries and in cold paths. Fight lifetimes in hot loops, not in configuration parsing.",
                "When a struct needs interior mutability, prefer a small, well-documented use of RefCell or a lock over sprinkling lifetimes through the public API.",
                "Design APIs around data flow: take ownership when you store, take references when you only read, and return owned values when the caller needs to outlive the borrow.",
                "The compiler is a collaborator, but it is not a performance profiler. Measure before replacing clear code with clever lifetimes."
            ]
        ),
        Topic(
            title: "A solar punk transit map for Stuttgart",
            terms: ["transit", "Stuttgart", "urbanism", "solarpunk", "map"],
            prompts: [
                "I want to design a solarpunk-inspired transit map for Stuttgart that feels optimistic without lying about the network. Where would you start?",
                "How do you make a transit diagram beautiful when the real network is radial, hilly, and full of awkward interchanges?",
                "What would a car-free Sunday in Stuttgart look like as a map, and how would you communicate temporary routes clearly?"
            ],
            notes: [
                "Start from the topology, not the geography. A transit map is a diagram of frequency and connection; the valley shape of Stuttgart belongs in the background, not in every line.",
                "Solarpunk is an aesthetic of maintenance and abundance: greenery integrated into stations, visible bike infrastructure, and honest travel times. Avoid rendering a future that only exists in the poster.",
                "Color is a functional layer. Reserve one hue family for rail, another for trams, and use texture rather than more colors for temporary routes.",
                "The hilly topography suggests funiculars and cable links as first-class lines. Treat them as connectors with clear interchange symbols instead of decorative icons.",
                "Test the map at phone size and in grayscale. If the network still reads, the design is doing its job.",
                "Include the unglamorous layer: night buses, bike parking, and barrier-free access. That is where optimism becomes credible."
            ]
        ),
        Topic(
            title: "Sleep science: fixing a late chronotype",
            terms: ["sleep", "circadian", "light", "routine", "melatonin"],
            prompts: [
                "I fall asleep around 2 a.m. and wake up exhausted at 8. What does the evidence actually say about shifting a late chronotype earlier?",
                "Is melatonin useful for delayed sleep phase, or should I focus on morning light and consistency first?",
                "How do I build an evening routine that lowers arousal without turning bedtime into another productivity project?"
            ],
            notes: [
                "Circadian timing is set mostly by light exposure and regularity. Morning outdoor light for 20–30 minutes is the strongest lever, followed by dim, warm light in the evening.",
                "Shift gradually: 15–20 minutes earlier every few days. A sudden two-hour change fights your clock and usually collapses by the weekend.",
                "Melatonin can advance sleep timing in delayed sleep phase, but dose and timing matter, and it is not a sedative. Discuss it with a clinician, especially with other medications.",
                "Protect the wake time even after a bad night. A consistent anchor is what lets the rest of the rhythm move earlier.",
                "Lower arousal before bed with a boring, repeatable sequence: lights down, screens away, shower, stretch, read. The content matters less than the predictability.",
                "Track sleep timing, not just duration. A week of data showing a stable wake time is more useful than a single perfect night."
            ]
        ),
        Topic(
            title: "Photographing neon at night with a 35mm",
            terms: ["photography", "neon", "night", "exposure", "35mm"],
            prompts: [
                "I want to shoot neon signs at night with a 35mm lens on a full-frame camera. How do I expose for glowing tubes without blowing out the colors?",
                "Should I use a tripod for neon street photography, or is handheld with high ISO the better look?",
                "How do I keep skin tones believable when the scene is lit by magenta and cyan signs?"
            ],
            notes: [
                "Expose for the brightest tube first, then let shadows fall where they may. Neon is a highlight-driven subject; recovering clipped color is much harder than lifting shadows.",
                "Highlight-weighted metering plus a stop of negative exposure compensation is a reliable starting point, then check the RGB histogram rather than the luminance one.",
                "A 35mm rewards close, layered compositions: sign, reflection, silhouette. At night, a fast prime and careful focus are worth more than a zoom.",
                "Handheld at f/1.8 and 1/60 s is often enough on modern sensors. Use a tripod only when you want motion-free reflections or a deep depth of field.",
                "Neon casts strong color on faces. Bring a small white reference or shoot a neutral frame so you can correct the cast without killing the mood.",
                "Rain is a gift: wet asphalt doubles the light and adds texture. Protect the lens, expose for the reflections, and let the highlights bloom."
            ]
        ),
        Topic(
            title: "Raising seed for a climate hardware startup",
            terms: ["startup", "climate", "seed", "hardware", "fundraising"],
            prompts: [
                "We are raising a seed round for a climate hardware startup with one pilot customer. What should the deck prove before we talk to funds?",
                "How do hardware timelines change the seed story? Investors keep asking for software-like traction and we are still iterating on the enclosure.",
                "What metrics matter for a climate hardware seed round beyond revenue?"
            ],
            notes: [
                "For climate hardware, the seed story is evidence of a repeatable deployment, not a finished product. Show one customer, one measurable outcome, and a credible path to unit economics.",
                "Investors underwrite risk reduction. Make the technical, regulatory, and supply-chain risks explicit, then show which ones the round retires.",
                "Hardware timelines are fine if they are honest. A milestone-based plan with long lead items called out builds more trust than a software-style hockey stick.",
                "Climate impact should be quantified in the customer's units: tonnes avoided, energy saved, or cost per deployment. A vague sustainability slide reads as decoration.",
                "Gross margin at scale depends on design decisions made now. Show the bill of materials trajectory and the two components that dominate it.",
                "Reference customers are currency. A pilot with a named partner and a path to a paid follow-on is worth more than ten letters of intent."
            ]
        ),
        Topic(
            title: "Growing tomatoes on a balcony in Germany",
            terms: ["tomatoes", "balcony", "gardening", "soil", "watering"],
            prompts: [
                "I have a south-facing balcony in Stuttgart and want to grow tomatoes in containers. What varieties and setup give the best chance of a real harvest?",
                "My tomato leaves are curling and the fruit is splitting. What am I likely doing wrong with watering and feeding?",
                "How do I plan a balcony garden so tomatoes, herbs, and a few flowers support each other instead of competing for space?"
            ],
            notes: [
                "In containers, consistency beats optimization. Choose a cherry or bush variety, use a 25–30 liter pot per plant, and keep the root zone evenly moist.",
                "Splitting fruit usually means uneven water. Mulch the surface, water deeply in the morning, and avoid alternating drought with a flood.",
                "Feed lightly and often once flowering starts. A high-potassium tomato feed every week is more effective than a single heavy dose.",
                "Leaf curl can be heat, wind, or overwatering. Check the soil before watering and give the plant afternoon shade if the balcony bakes.",
                "Companions help most by occupying different layers: basil and parsley at the edge, nasturtiums to pull aphids, and a few marigolds for pollinators.",
                "Prune indeterminate varieties to one or two stems and keep airflow around the fruit. A dense canopy invites blight in a wet German summer."
            ]
        ),
        Topic(
            title: "ESP32 home sensor mesh with Matter",
            terms: ["ESP32", "Matter", "sensor", "Home Assistant", "firmware"],
            prompts: [
                "I want to build a small mesh of ESP32 temperature and air-quality sensors that works with Home Assistant and ideally Matter. What architecture avoids a maintenance nightmare?",
                "Is Matter ready for battery-powered ESP32 sensors, or should I use ESP-NOW and bridge everything through one gateway?",
                "How do I handle OTA firmware updates and sensor calibration across a dozen devices in different rooms?"
            ],
            notes: [
                "Keep the radios boring and the gateway smart. ESP-NOW or Zigbee sensors with one bridge are often more reliable than giving every battery device its own IP stack.",
                "Matter improves interoperability but adds firmware surface and certification questions. Use it at the edge where you need ecosystem compatibility, not necessarily on every sensor.",
                "Calibrate in software, not in the enclosure. Store offset and scale per device, expose them as entities, and keep the raw value for debugging.",
                "OTA should be resumable and verifiable. Sign images, keep the previous slot, and never update all devices at once.",
                "Power budget is the design: wake, measure, transmit, sleep. The radio and the regulator usually dominate, not the sensor.",
                "Give every device a stable identity independent of its network address, so replacing hardware does not break automations."
            ]
        ),
        Topic(
            title: "Learning Japanese kanji efficiently",
            terms: ["Japanese", "kanji", "language", "memory", "vocabulary"],
            prompts: [
                "I can speak conversational Japanese but kanji still feel like a wall. What study system actually moves the needle for reading, not just recognition?",
                "Should I learn kanji by radical, by frequency, or through vocabulary? I keep restarting and losing momentum.",
                "How do I maintain kanji while living outside Japan with maybe 30 minutes a day?"
            ],
            notes: [
                "Learn kanji through words you already care about. A character in isolation is a shape; a character inside a familiar word becomes a memory hook.",
                "Frequency order reduces wasted effort, but only if the words are useful to your life. Combine a frequency list with the vocabulary from shows, articles, or work.",
                "Radicals are a compression system, not a study plan on their own. Learn them as they appear in characters you are already meeting.",
                "Spaced repetition works best with recall, not recognition. Type or write the answer, and keep the daily queue small enough to finish.",
                "Reading volume is the multiplier. Fifteen minutes of easy manga or news beats another flashcard deck once the basics are in place.",
                "Thirty minutes a day is enough if it is consistent: ten minutes of new cards, ten of reading, ten of review. Skip the perfect system and protect the streak."
            ]
        ),
        Topic(
            title: "A 3D printed modular camera rig",
            terms: ["3D printing", "camera", "rig", "modular", "prototype"],
            prompts: [
                "I'm designing a 3D printed modular camera rig for a small monitor and a wireless follow-focus. How do I prototype the joints so it does not flex or crack?",
                "What material and wall thickness would you use for a rig that holds a 1 kg camera outdoors?",
                "How do I add cable management and quick-release points without making the rig impossible to print?"
            ],
            notes: [
                "Print the interfaces, machine the load paths. Threaded inserts, metal pins, and printed clamps are more reliable than trusting layer adhesion in tension.",
                "For a 1 kg camera, use PETG or ASA with 4–5 perimeters and a sensible infill. Orient the part so layer lines are not perpendicular to the main load.",
                "Design joints around bolts and friction plates. A printed hinge that relies on a thin living hinge will creep under load and fail in the heat.",
                "Cable management is geometry: leave channels with generous bend radius, and add zip-tie slots every 40 mm instead of routing cables through sharp holes.",
                "Prototype with cardboard or cheap PLA first. Ergonomics is easier to feel than to model, especially the distance between grips.",
                "Keep a versioned test print for each interface. When a joint changes, you want to reprint one small part, not the whole rig."
            ]
        ),
        Topic(
            title: "Writing a detective novel set in 1970s Vienna",
            terms: ["novel", "detective", "Vienna", "writing", "atmosphere"],
            prompts: [
                "I'm writing a detective novel set in Vienna in 1975. How do I make the atmosphere specific without turning every scene into a history lecture?",
                "My detective is too competent and the middle sags. What would you change about the investigation structure?",
                "How much period detail is enough for a reader who has never been to Vienna?"
            ],
            notes: [
                "Use period detail as pressure, not decoration. A payphone that eats coins or a café that closes early should complicate the scene, not just set it.",
                "A competent detective needs a personal cost that the case keeps touching. Give them one decision they cannot make cleanly, and let the plot force it twice.",
                "The middle sags when every interview confirms the theory. Make one witness lie for a sympathetic reason and one clue point at the wrong suspect.",
                "Vienna is a city of interiors: stairwells, courtyards, coffee houses, offices with too much paper. Use those spaces to stage conversations.",
                "Research the bureaucracy. In 1975, records, telephones, and forensics all move at different speeds, which is a gift for pacing.",
                "Let the reader feel the era through what people cannot say. Restraint often reads as more authentic than a paragraph of brand names."
            ]
        ),
        Topic(
            title: "Quantum computing: is the hype justified?",
            terms: ["quantum", "qubits", "computing", "error correction", "hype"],
            prompts: [
                "Quantum computing announcements keep promising breakthroughs. Which claims are real milestones and which are marketing?",
                "How close is practical error correction, and what would have to be true for quantum computers to change chemistry or cryptography?",
                "Explain the difference between qubit count and useful quantum computation to someone who reads tech news."
            ],
            notes: [
                "Qubit count is the least interesting number in a quantum announcement. Coherence time, gate fidelity, connectivity, and error-correction overhead determine whether the machine can do useful work.",
                "Error correction is the real threshold. Below a certain physical error rate, adding more qubits makes the logical qubit worse, not better.",
                "Near-term quantum advantage claims usually compare against a narrow classical baseline. Ask what a well-optimized classical algorithm would cost on the same problem.",
                "Chemistry and materials simulation are the most credible long-term applications because the problem is naturally quantum. General-purpose speedups are much further away.",
                "Cryptography is a real concern, but the timeline is uncertain and the migration to post-quantum algorithms is already underway. Panic is not a strategy.",
                "Hardware modalities differ wildly: superconducting, trapped ion, photonic, neutral atom. Each has different error profiles, and none has won decisively."
            ]
        ),
        Topic(
            title: "Sealing a leaky balcony door",
            terms: ["balcony", "door", "seal", "insulation", "repair"],
            prompts: [
                "Rain is coming in around my balcony door frame. How do I diagnose whether it is the seal, the drainage, or the wall connection before I start buying materials?",
                "I replaced the rubber seal but water still appears inside after heavy rain. What should I check next?",
                "What is the right way to insulate and seal a balcony door without trapping moisture in the wall?"
            ],
            notes: [
                "Diagnose with a hose, not a guess. Spray low and work upward while someone watches inside; most leaks are at the threshold or the corners, not the middle of the seal.",
                "Check the drainage path first. A blocked sill or a door that sits too low will push water inward no matter how good the rubber is.",
                "Replace seals with the same profile and compression, not the thickest available. Too much compression makes the door hard to close and can distort the frame.",
                "Never seal the exterior joint with pure silicone if it needs to shed water. Use a backer rod and a vapor-open sealant appropriate for the facade.",
                "Interior moisture can be condensation, not a leak. Check for cold bridges and ventilation before adding more sealant.",
                "If the frame is moving or the threshold is rotten, stop cosmetic repairs. Water follows structure, and a bigger repair will be cheaper than repeated patches."
            ]
        ),
        Topic(
            title: "Board game design: asymmetric factions",
            terms: ["board game", "factions", "balance", "design", "playtest"],
            prompts: [
                "I'm designing a board game with four asymmetric factions. How do I balance them without flattening what makes each one interesting?",
                "Playtesters say one faction feels unfair but cannot explain why. How do I turn that feedback into a testable change?",
                "How much asymmetry is too much for a first-time player?"
            ],
            notes: [
                "Balance is not symmetry. Each faction should have a distinct rhythm and a clear weakness; the goal is comparable agency, not identical win rates.",
                "Measure time-to-first-meaningful-decision and time-to-runaway. Many perceived balance problems are actually pacing problems in the first three rounds.",
                "Change one lever at a time: resource income, action efficiency, or information. If you change all three, the next playtest tells you nothing.",
                "New players need a low-complexity entry faction. Keep one straightforward option in the box so the asymmetry is a choice, not a barrier.",
                "Write down the intended experience for each faction in one sentence. If a mechanic does not serve that sentence, it is a candidate for removal.",
                "Balance at the table, not in the spreadsheet. Win rate matters, but so does whether the losing player understood why they lost."
            ]
        ),
        Topic(
            title: "Meal prep for a high-protein week",
            terms: ["meal prep", "protein", "recipes", "nutrition", "batch cooking"],
            prompts: [
                "I want to prep five high-protein lunches on Sunday without eating the same bowl every day. What is a flexible base system?",
                "How do I hit 140 g of protein a day without relying on protein powder for every meal?",
                "What actually reheats well, and what should I assemble fresh?"
            ],
            notes: [
                "Prep components, not finished meals: a protein, a grain, a roasted vegetable, a sauce, and a crunchy element. Mix them differently through the week.",
                "Protein targets are easier with a anchor at each meal: eggs or skyr at breakfast, chicken, tofu, or legumes at lunch, fish or cottage cheese at dinner.",
                "Cook two proteins on Sunday, not five. A tray of chicken thighs and a pot of lentils cover most lunches and freeze well.",
                "Keep sauces separate and acid at the end. A lemon-tahini sauce and a chili crisp can make the same base feel like two different cuisines.",
                "Reheat grains with a splash of water and keep vegetables slightly underdone so they survive the microwave.",
                "Leave one dinner slot unplanned. A rigid week collapses on Wednesday; a flexible one survives."
            ]
        ),
        Topic(
            title: "Evaluating an e-bike for a 15 km commute",
            terms: ["e-bike", "commute", "battery", "motor", "maintenance"],
            prompts: [
                "I'm replacing a 15 km car commute with an e-bike in a hilly city. What specs actually matter, and where do cheap bikes cut corners?",
                "Mid-drive or hub motor for a commute with two steep climbs? I also want to carry panniers.",
                "What is the real maintenance cost of an e-bike over three years?"
            ],
            notes: [
                "For 15 km each way, battery capacity and service access matter more than peak motor power. A 500 Wh battery is comfortable; 400 Wh is workable if you can charge at work.",
                "A mid-drive motor uses the bike's gears and climbs better with cargo. A hub motor is simpler and cheaper, but it struggles on steep grades when loaded.",
                "Buy from a shop that services the motor and battery. A direct-to-consumer bargain becomes expensive when the controller fails and nobody will touch it.",
                "Budget for consumables: brake pads, chain, tires, and eventually a battery. The battery is the big line item, so check replacement price before buying.",
                "Test the bike on your actual route, not the parking lot. Motor cut-off behavior, brake feel, and pannier clearance only show up at speed.",
                "Security is part of the cost. A good lock, insurance, and a place to park inside at both ends can matter more than a lighter frame."
            ]
        ),
        Topic(
            title: "Building a personal knowledge graph",
            terms: ["knowledge graph", "notes", "links", "retrieval", "zettelkasten"],
            prompts: [
                "I have thousands of notes across three apps and no idea what is in them. How do I build a personal knowledge graph without spending a year organizing?",
                "How do I decide what deserves a permanent note versus a fleeting capture?",
                "What is the minimum linking habit that makes a knowledge graph useful instead of decorative?"
            ],
            notes: [
                "Start with retrieval, not taxonomy. Pick twenty questions you actually ask, then organize only enough to answer them.",
                "A note earns permanence when it changes a future decision. Everything else can stay as a capture with a date and a source.",
                "Link by tension, not topic: 'this contradicts', 'this extends', 'this is an example of'. Named relationships survive re-organization.",
                "Keep one inbox and review it weekly. A knowledge graph fails from unprocessed input, not from a missing folder hierarchy.",
                "Tags are cheap; links are expensive and valuable. Use tags for states and links for meaning.",
                "Let the graph stay messy at the edges. A small number of well-connected notes is more useful than a perfectly sorted archive."
            ]
        ),
        Topic(
            title: "Analog film stocks for portraits",
            terms: ["film", "portrait", "grain", "color", "photography"],
            prompts: [
                "I want to shoot portraits on 35mm film and I'm overwhelmed by stock choices. What are the practical differences between Portra, Gold, and Pro 400H?",
                "How do I expose for skin tones on negative film without losing the highlights?",
                "Which film stock would you pick for indoor window light and why?"
            ],
            notes: [
                "Portra 400 is the safest portrait stock: wide latitude, gentle contrast, and skin tones that stay believable under mixed light.",
                "Gold 200 is warmer and more saturated. It is forgiving and cheap, but it can push skin toward orange in tungsten light.",
                "Pro 400H has a cooler, airier palette and handles overexposure well. It is less forgiving of underexposure, so meter for the shadows.",
                "Negative film loves light. Rate Portra at 200–320 for portraits if you want cleaner shadows and softer grain.",
                "Window light is a large soft source: place the subject parallel to it, expose for the lit side, and let the background fall.",
                "Develop consistently at one lab before judging a stock. Scanning choices affect the look as much as the emulsion."
            ]
        ),
        Topic(
            title: "Small business bookkeeping in Germany",
            terms: ["bookkeeping", "tax", "invoices", "Germany", "receipts"],
            prompts: [
                "I'm freelancing in Germany and my receipts live in a shoebox. What is a realistic monthly bookkeeping routine that survives an audit?",
                "How do I handle Kleinunternehmer rules, VAT, and invoices without hiring a bookkeeper immediately?",
                "What records should I keep digitally, and what still needs paper?"
            ],
            notes: [
                "Separate business and private accounts first. Every bookkeeping system becomes simpler when there is one clean source of truth.",
                "Capture receipts weekly, not monthly. Photograph the paper, name the file with date and amount, and record the purpose in one line.",
                "Kleinunternehmer status affects whether you charge VAT, not whether you keep records. Confirm the thresholds for your year with a tax advisor.",
                "Invoices need a sequential number, dates, a description of services, and the tax treatment. Use one template and never renumber.",
                "Keep receipts for ten years where required. Digital archives are fine if they are complete, readable, and backed up.",
                "A monthly close of two hours beats a yearly panic. Reconcile the bank, file receipts, and check open invoices on the same day each month."
            ]
        ),
        Topic(
            title: "Voice interface design without a screen",
            terms: ["voice", "interface", "conversation", "accessibility", "design"],
            prompts: [
                "I'm designing a voice interface for a kitchen timer and recipe assistant. How do I make it usable without a screen?",
                "Voice menus keep growing because every stakeholder wants an option. How do I keep the interaction short?",
                "How do I design for mistakes and interruptions when there is no visual state to fall back on?"
            ],
            notes: [
                "Design the repair conversation before the happy path. Users will interrupt, mispronounce, and change their minds; the interface needs a graceful way back.",
                "Keep the first turn under ten seconds. A voice interface that explains itself before doing anything loses the room.",
                "Do not read a menu unless the user asks for one. Offer two or three likely actions and let them say 'something else'.",
                "Use earcons and consistent confirmation phrases so users can tell listening from thinking from failure without staring at a light.",
                "Recognition confidence should change the response: ask a short clarifying question when uncertain, and confirm before irreversible actions.",
                "Test with background noise and hands busy. A kitchen is the honest usability lab."
            ]
        ),
        Topic(
            title: "Kündigung und Umzug: Fristen prüfen",
            terms: ["Mietvertrag", "Kündigung", "Fristen", "Umzug", "Wohnung"],
            prompts: [
                "Ich möchte meine Wohnung in Stuttgart kündigen und im Frühjahr umziehen. Welche Fristen und Formvorschriften muss ich beachten?",
                "Mein Vermieter behauptet, die Kündigung sei zu spät. Wie prüfe ich die Frist und was sollte im Schreiben stehen?",
                "Was muss ich bei der Wohnungsübergabe dokumentieren, damit die Kaution später nicht strittig wird?"
            ],
            notes: [
                "Die gesetzliche Kündigungsfrist für Mieter beträgt in der Regel drei Monate, kann im Vertrag aber verlängert worden sein. Maßgeblich ist der Zugang, nicht das Absendedatum.",
                "Die Kündigung muss schriftlich erfolgen und alle im Vertrag genannten Mieter enthalten. Eine E-Mail oder ein Anruf reicht nicht.",
                "Prüfe zuerst den Mietvertrag auf Sonderfristen und Verlängerungsklauseln. Ein Foto der Unterschriftenseite hilft, wenn der Vertrag nicht auffindbar ist.",
                "Beim Umzug sollten Zählerstände, Schlüsselübergabe und vorhandene Schäden gemeinsam protokolliert werden. Fotos mit Datum sind kein Ersatz für ein Übergabeprotokoll, aber wichtige Ergänzung.",
                "Die Kaution darf nicht mit der letzten Miete verrechnet werden. Verlange eine schriftliche Abrechnung und bewahre alle Belege auf.",
                "Bei Streit über die Frist ist eine Beratung bei der Mietervereinigung oft günstiger als ein Anwalt und klärt die Formfragen schnell."
            ]
        ),
        Topic(
            title: "Bewerbung für ein Stipendium",
            terms: ["Stipendium", "Bewerbung", "Motivation", "Lebenslauf", "Gutachten"],
            prompts: [
                "Ich bewerbe mich für ein Stipendium für ein Masterstudium. Wie strukturiere ich ein Motivationsschreiben, das nicht nach Bewerbungsfloskel klingt?",
                "Brauche ich für ein Stipendium ein Gutachten, und wie wähle ich die richtige Person aus?",
                "Wie gehe ich mit einer Lücke im Lebenslauf um, ohne sie zu rechtfertigen?"
            ],
            notes: [
                "Ein Motivationsschreiben beantwortet drei Fragen: Warum dieses Fach, warum jetzt, und warum du. Jeder Absatz sollte eine davon bedienen.",
                "Beginne mit einem konkreten Moment oder Problem aus deiner Erfahrung, nicht mit einem Zitat über Bildung.",
                "Gutachten wirken am stärksten, wenn die Person deine Arbeit konkret beschreiben kann. Frage früh und liefere eine kurze Erinnerung an gemeinsame Projekte.",
                "Lücken sind normal. Beschreibe, was du in der Zeit gelernt oder entschieden hast, ohne dich zu rechtfertigen.",
                "Halte dich exakt an die Formalien: Seitenzahl, Schriftgröße, Anhänge. Viele gute Bewerbungen scheitern an der Formatprüfung.",
                "Lass eine Person gegenlesen, die das Fach nicht kennt. Wenn sie deine Motivation versteht, ist der Text klar."
            ]
        ),
        Topic(
            title: "Rezept für Kürbissuppe mit Röstaroma",
            terms: ["Kürbissuppe", "Rezept", "Kürbis", "Röstaroma", "Gewürze"],
            prompts: [
                "Ich möchte eine Kürbissuppe kochen, die nicht nach Babybrei schmeckt. Wie bekomme ich Röstaroma und Tiefe?",
                "Welche Kürbissorte eignet sich für eine cremige Suppe, und brauche ich wirklich Sahne?",
                "Wie würze ich Kürbissuppe, damit sie interessant bleibt, ohne scharf zu werden?"
            ],
            notes: [
                "Röste den Kürbis vor dem Kochen im Ofen mit etwas Öl und Salz. Die Maillard-Reaktion bringt Süße und Tiefe, die im Topf nicht entsteht.",
                "Hokkaido muss nicht geschält werden und liefert eine natürliche Cremigkeit. Butternut ist milder und eignet sich, wenn die Suppe feiner werden soll.",
                "Sahne ist optional. Geröstete Kürbiskerne, ein Löffel Tahin oder etwas braune Butter geben mehr Charakter als ein Schuss Sahne.",
                "Baue die Basis mit Zwiebel, Ingwer und einer Prise Muskat auf. Chili nur als Hintergrund, nicht als Hauptnote.",
                "Zum Schluss mit Apfelessig oder Zitronensaft abschmecken. Säure hebt die Süße und lässt die Gewürze klarer hervortreten.",
                "Röste die Kerne separat und gib sie erst beim Servieren dazu, damit sie knusprig bleiben."
            ]
        )
    ]
}

// MARK: - Deterministic RNG

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
