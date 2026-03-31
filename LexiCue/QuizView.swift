import SwiftUI

struct QuizView: View {
    let savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    let practiceMode: PracticeMode

    @State private var practiceCards: [PracticeCard] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var generationStatus = "Building practice cards."
    @State private var loadingProgress = 0.0
    @State private var generationTask: Task<Void, Never>?
    @State private var userAnswer = ""
    @State private var resultMessage = ""
    @State private var hasCheckedAnswer = false
    @State private var revealAnswer = false
    @State private var meaningHint: String?
    @State private var isLoadingMeaningHint = false
    @State private var showLetterHint = false
    @State private var recordedWrongAttempt = false
    @State private var generationSource: PracticeGenerationSource = .ai
    @State private var isRefreshingCurrentCard = false
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @FocusState private var answerFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    VStack(spacing: 16) {
                        Text("Preparing Practice")
                            .font(.title2)
                            .fontWeight(.semibold)

                        ProgressView(value: loadingProgress, total: 1)
                            .tint(.blue)

                        Text("\(Int((loadingProgress * 100).rounded()))%")
                            .font(.headline)

                        Text(generationStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if practiceCards.isEmpty {
                    ContentUnavailableView(
                        practiceMode.emptyTitle,
                        systemImage: "text.badge.plus",
                        description: Text(practiceMode.emptyMessage)
                    )
                } else {
                    let currentCard = practiceCards[currentIndex]

                    VStack(spacing: 12) {
                        Text(practiceMode.headerTitle(phraseCount: activePhrases.count))
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Card \(currentIndex + 1) of \(practiceCards.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ProgressView(value: progressValue)

                        Text(generationStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let currentProgress {
                            Text("Correct \(currentProgress.correctCount) • Missed \(currentProgress.wrongCount)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Fill in the missing phrase")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(currentCard.prompt)
                            .font(.system(size: 32, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("Type the missing phrase", text: $userAnswer)
                            .textFieldStyle(.roundedBorder)
                            .focused($answerFieldFocused)
                            .submitLabel(.done)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                checkAnswer(for: currentCard)
                            }

                        if hasCheckedAnswer {
                            Text(resultMessage)
                                .font(.headline)
                                .foregroundStyle(isAnswerCorrect(for: currentCard) ? .green : .red)
                        }

                        if isLoadingMeaningHint {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading meaning hint...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let meaningHint {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Meaning hint")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(meaningHint)
                                    .font(.subheadline)
                            }
                        }

                        if showLetterHint {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("First and last letters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(edgeLetterHint(for: currentCard.phrase))
                                    .font(.headline)
                            }
                        }

                        if revealAnswer {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Correct phrase")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(currentCard.phrase)
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    HStack(spacing: 12) {
                        Button("Check Answer") {
                            checkAnswer(for: currentCard)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(revealAnswer ? "Hide Answer" : "Show Answer") {
                            revealAnswer.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    if hasCheckedAnswer && !isAnswerCorrect(for: currentCard) {
                        HStack(spacing: 12) {
                            Button(showLetterHint ? "Hide First & Last Letters" : "Show First & Last Letters") {
                                showLetterHint.toggle()
                            }
                            .buttonStyle(.bordered)

                            Button("Next Card") {
                                showNextCard()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Fresh AI") {
                            refreshCurrentCard()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading || isRefreshingCurrentCard)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(practiceMode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshPracticeCardsIfNeeded()
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }

    var progressValue: Double {
        guard !practiceCards.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(practiceCards.count)
    }

    var savedPhraseCount: Int {
        activePhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var activePhrases: [String] {
        switch practiceMode {
        case .all:
            return savedPhrases
        case .review:
            let weaker = savedPhrases.filter { phraseProgress[$0.normalizedProgressKey]?.needsReview == true }
            return weaker.isEmpty ? savedPhrases : weaker
        }
    }

    var currentProgress: PhraseProgress? {
        guard !practiceCards.isEmpty else { return nil }
        return phraseProgress[practiceCards[currentIndex].phrase.normalizedProgressKey]
    }

    func refreshPracticeCardsIfNeeded() {
        guard practiceCards.isEmpty, !isLoading else { return }
        refreshPracticeCards(using: .ai)
    }

    func refreshPracticeCards(using source: PracticeGenerationSource = .ai) {
        generationTask?.cancel()
        generationSource = source
        generationTask = Task {
            await generatePracticeCards()
        }
    }

    func refreshCurrentCard() {
        guard !practiceCards.isEmpty else { return }

        let phrase = practiceCards[currentIndex].phrase
        let currentPrompt = practiceCards[currentIndex].prompt
        isRefreshingCurrentCard = true
        generationStatus = "Refreshing this phrase with AI."

        generationTask?.cancel()
        generationTask = Task {
            let result = await PracticeCardFactory.makeCards(
                for: [phrase],
                phraseProgress: [:],
                practiceMode: .all,
                source: PracticeGenerationSource.ai,
                configuration: backendConfiguration,
                progress: nil
            )

            if Task.isCancelled { return }

            await MainActor.run {
                let replacement = result.cards.first { $0.prompt != currentPrompt } ?? result.cards.first
                if let replacement {
                    practiceCards[currentIndex] = replacement
                    generationStatus = result.status
                } else {
                    generationStatus = "Could not refresh this phrase right now."
                }

                isRefreshingCurrentCard = false
                resetCardState()
            }
        }
    }

    func showNextCard() {
        guard !practiceCards.isEmpty else { return }

        currentIndex = (currentIndex + 1) % practiceCards.count
        resetCardState()
    }

    @MainActor
    func generatePracticeCards() async {
        isLoading = true
        loadingProgress = 0
        currentIndex = 0
        resetCardState()
        generationStatus = "Choosing phrases for this round."

        let result = await PracticeCardFactory.makeCards(
            for: activePhrases,
            phraseProgress: phraseProgress,
            practiceMode: practiceMode,
            source: generationSource,
            configuration: backendConfiguration,
            progress: { completed, total in
                await MainActor.run {
                    loadingProgress = total > 0 ? Double(completed) / Double(total) : 0
                    generationStatus = "Generating phrases \(completed) of \(total)."
                }
            }
        )
        if Task.isCancelled { return }

        practiceCards = result.cards
        generationStatus = result.status
        isLoading = false
        loadingProgress = 1
        isRefreshingCurrentCard = false
        answerFieldFocused = !practiceCards.isEmpty
    }

    func checkAnswer(for card: PracticeCard) {
        guard !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let answerWasCorrect = isAnswerCorrect(for: card)
        hasCheckedAnswer = true

        if answerWasCorrect {
            answerFieldFocused = false
            resultMessage = "Correct"

            if !recordedWrongAttempt {
                recordResult(for: card, wasCorrect: true)
            }

            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    showNextCard()
                }
            }
        } else {
            answerFieldFocused = true
            resultMessage = "Not quite. Try again, use the hint, or reveal the answer."

            if !recordedWrongAttempt {
                recordedWrongAttempt = true
                recordResult(for: card, wasCorrect: false)
            }

            if meaningHint == nil && !isLoadingMeaningHint {
                loadMeaningHint(for: card)
            }
        }
    }

    func isAnswerCorrect(for card: PracticeCard) -> Bool {
        normalized(userAnswer) == normalized(card.phrase)
    }

    func resetCardState() {
        userAnswer = ""
        resultMessage = ""
        hasCheckedAnswer = false
        revealAnswer = false
        meaningHint = nil
        isLoadingMeaningHint = false
        showLetterHint = false
        recordedWrongAttempt = false
        answerFieldFocused = !practiceCards.isEmpty
    }

    func loadMeaningHint(for card: PracticeCard) {
        guard backendConfiguration.isValid else { return }

        isLoadingMeaningHint = true
        Task {
            let hint = try? await BackendAIService.shared.meaningHint(for: card.phrase, configuration: backendConfiguration)
            await MainActor.run {
                meaningHint = hint
                isLoadingMeaningHint = false
            }
        }
    }

    func edgeLetterHint(for phrase: String) -> String {
        phrase
            .split(separator: " ")
            .map { token in
                let characters = Array(token)
                guard let first = characters.first else { return "" }
                guard characters.count > 1, let last = characters.last else { return String(first) }
                return "\(first)…\(last)"
            }
            .joined(separator: " ")
    }

    func recordResult(for card: PracticeCard, wasCorrect: Bool) {
        let key = card.phrase.normalizedProgressKey
        var progress = phraseProgress[key] ?? PhraseProgress()
        if wasCorrect {
            progress.correctCount += 1
        } else {
            progress.wrongCount += 1
        }
        phraseProgress[key] = progress
    }

    func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    var backendConfiguration: BackendConfiguration {
        BackendConfiguration(baseURLString: backendBaseURL)
    }
}

struct PracticeCard: Identifiable, Hashable {
    let id = UUID()
    let phrase: String
    let prompt: String
}

enum SentenceGenerator {
    nonisolated static func cards(for phrase: String) -> [PracticeCard] {
        let cleanedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPhrase.isEmpty else { return [] }

        let templates = templates(for: cleanedPhrase)

        return templates.shuffled().prefix(4).compactMap { template in
            let sentence = template(cleanedPhrase)
            guard let prompt = blankedSentence(from: sentence, phrase: cleanedPhrase) else {
                return nil
            }

            return PracticeCard(phrase: cleanedPhrase, prompt: prompt)
        }
    }

    nonisolated static func blankedSentence(from sentence: String, phrase: String) -> String? {
        guard let range = sentence.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        return sentence.replacingCharacters(in: range, with: "______")
    }

    nonisolated private static func templates(for phrase: String) -> [(String) -> String] {
        switch guessKind(for: phrase) {
        case .adverb:
            return [
                { phrase in "\(phrase), the team found a simpler way to finish the task." },
                { phrase in "She realized \(phrase) that the email had been sent to the wrong person." },
                { phrase in "The problem disappeared \(phrase), after a few small fixes." },
                { phrase in "He answered \(phrase), after thinking about the question for a moment." }
            ]
        case .adjective:
            return [
                { phrase in "Even under pressure, she stayed \(phrase) during the meeting." },
                { phrase in "By the final round, the whole group seemed \(phrase) and ready." },
                { phrase in "His tone sounded \(phrase) from the moment the discussion started." },
                { phrase in "After a short break, I felt more \(phrase) and ready to work." }
            ]
        case .gerundPhrase:
            return [
                { phrase in "For the small company, the decision felt like \(phrase)." },
                { phrase in "Without more data, investing that much money seemed like \(phrase)." },
                { phrase in "Accepting the offer would be \(phrase), but she wanted the opportunity." },
                { phrase in "At that stage, changing the plan looked like \(phrase)." }
            ]
        case .verbPhrase:
            return [
                { phrase in "In difficult situations, you sometimes have to \(phrase)." },
                { phrase in "His advice was simple: \(phrase) and keep moving forward." },
                { phrase in "When the odds are not in your favor, the best option is to \(phrase)." },
                { phrase in "She reminded herself to \(phrase) instead of complaining." }
            ]
        case .phrasalVerb:
            return [
                { phrase in "The two-word verb in this example is \(phrase)." },
                { phrase in "A useful phrasal verb that fits here is \(phrase)." },
                { phrase in "The missing verb phrase in this line is \(phrase)." },
                { phrase in "The vocabulary item used as a phrasal verb here is \(phrase)." }
            ]
        case .nounWord:
            return [
                { phrase in "The key noun in this example is \(phrase)." },
                { phrase in "A more formal noun that fits here is \(phrase)." },
                { phrase in "The vocabulary item used as a noun here is \(phrase)." },
                { phrase in "The missing noun in this line is \(phrase)." }
            ]
        case .verbWord:
            return [
                { phrase in "The key verb in this example is \(phrase)." },
                { phrase in "A more formal verb that fits here is \(phrase)." },
                { phrase in "The missing action word in this line is \(phrase)." },
                { phrase in "The vocabulary item used as a verb here is \(phrase)." }
            ]
        case .pastVerbWord:
            return [
                { phrase in "The speaker \(phrase) the main idea very clearly." },
                { phrase in "In the report, the witness \(phrase) what had happened." },
                { phrase in "During the discussion, she \(phrase) her concerns directly." },
                { phrase in "The article \(phrase) how the system really worked." }
            ]
        case .nounPhrase:
            return [
                { phrase in "Her first reaction was \(phrase), even though she tried to stay calm." },
                { phrase in "For many people, the change brought a sense of \(phrase)." },
                { phrase in "What he felt most in that moment was \(phrase)." },
                { phrase in "The whole situation created an atmosphere of \(phrase)." }
            ]
        case .clausePhrase:
            return [
                { phrase in "The missing full phrase in this example is \(phrase)." },
                { phrase in "A complete phrase that fits here is \(phrase)." },
                { phrase in "The vocabulary line used in this example is \(phrase)." },
                { phrase in "The missing expression in this prompt is \(phrase)." }
            ]
        case .genericPhrase:
            return [
                { phrase in "The missing phrase in this example is \(phrase)." },
                { phrase in "A natural phrase that fits here is \(phrase)." },
                { phrase in "The vocabulary item used in this prompt is \(phrase)." },
                { phrase in "The missing expression in this line is \(phrase)." }
            ]
        }
    }

    nonisolated private static func guessKind(for phrase: String) -> PhraseKind {
        let lowercased = phrase.lowercased()
        let words = lowercased.split(separator: " ")
        let adjectiveSuffixes = ["ful", "ous", "ive", "al", "ic", "able", "ible", "less", "ent", "ant", "ary", "ory"]
        let nounSuffixes = ["tion", "sion", "ment", "ness", "ity", "ship", "ism", "age", "ery", "ance", "ence"]
        let verbSuffixes = ["ate", "ize", "ise", "ify", "en"]
        let particles: Set<String> = ["with", "up", "down", "on", "off", "out", "in", "over", "away", "back", "through", "around", "into", "for"]
        let clauseStarters: Set<String> = ["might", "would", "could", "should", "will", "can", "do", "does", "did", "is", "are", "was", "were", "have", "has", "had", "if", "when", "why", "how", "what"]
        let nounPhraseStarters: Set<String> = ["a", "an", "the", "my", "your", "his", "her", "our", "their", "this", "that", "some", "any", "no"]

        if words.count == 1, lowercased.hasSuffix("ly") {
            return .adverb
        }

        if lowercased.contains("-") {
            return .adjective
        }

        if words.count == 1 {
            if adjectiveSuffixes.contains(where: lowercased.hasSuffix) {
                return .adjective
            }

            if nounSuffixes.contains(where: lowercased.hasSuffix) {
                return .nounWord
            }

            if lowercased.hasSuffix("ed") {
                return .pastVerbWord
            }

            if verbSuffixes.contains(where: lowercased.hasSuffix) {
                return .verbWord
            }

            return .genericPhrase
        }

        if lowercased.hasPrefix("to ") {
            return .verbPhrase
        }

        if let firstWord = words.first, firstWord.hasSuffix("ing") {
            return .gerundPhrase
        }

        if words.count == 2,
           let firstWord = words.first,
           let lastWord = words.last,
           particles.contains(String(lastWord)),
           firstWord.hasSuffix("ed") || firstWord.hasSuffix("ing") {
            return .phrasalVerb
        }

        if let firstWord = words.first, clauseStarters.contains(String(firstWord)) {
            return .clausePhrase
        }

        let verbStarters: Set<String> = [
            "play", "take", "make", "keep", "get", "go", "come", "look", "work", "put",
            "turn", "bring", "hold", "set", "run", "move", "stay", "let", "leave"
        ]

        if let firstWord = words.first, verbStarters.contains(String(firstWord)) {
            return .verbPhrase
        }

        if let firstWord = words.first, nounPhraseStarters.contains(String(firstWord)) {
            return .nounPhrase
        }

        return .genericPhrase
    }
}

enum PhraseKind {
    case adverb
    case adjective
    case gerundPhrase
    case verbPhrase
    case phrasalVerb
    case nounWord
    case verbWord
    case pastVerbWord
    case nounPhrase
    case clausePhrase
    case genericPhrase
}

struct PracticeCardResult {
    let cards: [PracticeCard]
    let status: String
}

enum PracticeCardFactory {
    static func makeCards(
        for phrases: [String],
        phraseProgress: [String: PhraseProgress],
        practiceMode: PracticeMode,
        source: PracticeGenerationSource,
        configuration: BackendConfiguration,
        progress: (@Sendable (_ completed: Int, _ total: Int) async -> Void)?
    ) async -> PracticeCardResult {
        let cleanedPhrases = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedPhrases.isEmpty else {
            return PracticeCardResult(cards: [], status: "Add a phrase to begin.")
        }

        let sessionPhrases = selectedSessionPhrases(
            from: cleanedPhrases,
            phraseProgress: phraseProgress,
            practiceMode: practiceMode,
            source: source
        )

        if source == .ai {
            if configuration.isValid {
                do {
                    let generatedCards = try await BackendSentenceProvider().cards(
                        for: sessionPhrases,
                        configuration: configuration,
                        progress: progress
                    )
                    if !generatedCards.isEmpty {
                        return PracticeCardResult(
                            cards: finalizedCards(
                                from: generatedCards,
                                phraseProgress: phraseProgress,
                                practiceMode: practiceMode
                            ),
                            status: statusText(
                                for: phraseProgress,
                                aiEnabled: true,
                                base: aiSessionStatus(loadedPhraseCount: sessionPhrases.count, totalPhraseCount: cleanedPhrases.count)
                            )
                        )
                    }
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    return fallbackResult(
                        phrases: sessionPhrases,
                        phraseProgress: phraseProgress,
                        practiceMode: practiceMode,
                        status: "AI failed (\(message)), using built-in sentence prompts instead."
                    )
                }
            }

            return fallbackResult(
                phrases: sessionPhrases,
                phraseProgress: phraseProgress,
                practiceMode: practiceMode,
                status: "AI backend is not configured, using built-in sentence prompts."
            )
        }

        return fallbackResult(
            phrases: sessionPhrases,
            phraseProgress: phraseProgress,
            practiceMode: practiceMode,
            status: "Using built-in sentence prompts because AI is unavailable."
        )
    }

    private static func fallbackResult(
        phrases: [String],
        phraseProgress: [String: PhraseProgress],
        practiceMode: PracticeMode,
        status: String
    ) -> PracticeCardResult {
        let cards = phrases
            .flatMap { phrase in
                SentenceGenerator.cards(for: phrase)
            }

        return PracticeCardResult(
            cards: finalizedCards(from: cards, phraseProgress: phraseProgress, practiceMode: practiceMode),
            status: statusText(for: phraseProgress, aiEnabled: false, base: status)
        )
    }

    private static func finalizedCards(from cards: [PracticeCard], phraseProgress: [String: PhraseProgress], practiceMode: PracticeMode) -> [PracticeCard] {
        switch practiceMode {
        case .all:
            return repeatedRoundCards(from: cards, repeatsPerPhrase: 3)
        case .review:
            return weightedCards(from: cards, phraseProgress: phraseProgress)
        }
    }

    private static func weightedCards(from cards: [PracticeCard], phraseProgress: [String: PhraseProgress]) -> [PracticeCard] {
        var weighted: [PracticeCard] = []

        for card in cards {
            let progress = phraseProgress[card.phrase.normalizedProgressKey] ?? PhraseProgress()
            let extraRepeats = min(2, max(0, progress.wrongCount - progress.correctCount))
            weighted.append(card)
            for _ in 0..<extraRepeats {
                weighted.append(card)
            }
        }

        return spacedCards(from: weighted.shuffled())
    }

    private static func repeatedRoundCards(from cards: [PracticeCard], repeatsPerPhrase: Int) -> [PracticeCard] {
        let groupedCards = Dictionary(grouping: cards, by: \.phrase)
        let phrases = Array(groupedCards.keys).shuffled()
        var arranged: [PracticeCard] = []

        for roundIndex in 0..<repeatsPerPhrase {
            for phrase in phrases {
                guard let phraseCards = groupedCards[phrase], !phraseCards.isEmpty else { continue }
                let sourceIndex = min(roundIndex, phraseCards.count - 1)
                arranged.append(phraseCards.shuffled()[sourceIndex])
            }
        }

        return spacedCards(from: arranged)
    }

    private static func spacedCards(from cards: [PracticeCard]) -> [PracticeCard] {
        guard cards.count > 1 else { return cards }

        var remaining = cards
        var arranged: [PracticeCard] = []

        while !remaining.isEmpty {
            let previousPhrase = arranged.last?.phrase
            let nextIndex = remaining.firstIndex { $0.phrase != previousPhrase } ?? 0
            arranged.append(remaining.remove(at: nextIndex))
        }

        return arranged
    }

    private static func selectedSessionPhrases(
        from phrases: [String],
        phraseProgress: [String: PhraseProgress],
        practiceMode: PracticeMode,
        source: PracticeGenerationSource
    ) -> [String] {
        if practiceMode == .all {
            return Array(phrases.shuffled().prefix(min(10, phrases.count)))
        }

        let maxPhrases = source == .ai ? 12 : 20
        guard phrases.count > maxPhrases else { return phrases }

        let reviewPhrases = phrases.filter {
            phraseProgress[$0.normalizedProgressKey]?.needsReview == true
        }
        let untouchedPhrases = phrases.filter {
            (phraseProgress[$0.normalizedProgressKey]?.totalAttempts ?? 0) == 0
        }
        let remainingPhrases = phrases.filter { phrase in
            !reviewPhrases.contains(phrase) && !untouchedPhrases.contains(phrase)
        }

        let orderedPhrases = reviewPhrases + untouchedPhrases + remainingPhrases
        return Array(orderedPhrases.prefix(maxPhrases))
    }

    private static func aiSessionStatus(loadedPhraseCount: Int, totalPhraseCount: Int) -> String {
        guard totalPhraseCount > loadedPhraseCount else {
            return "Using AI-generated sentence prompts."
        }

        return "Using AI-generated sentence prompts for \(loadedPhraseCount) of \(totalPhraseCount) phrases in this round."
    }

    private static func statusText(for phraseProgress: [String: PhraseProgress], aiEnabled: Bool, base: String? = nil) -> String {
        let needsReviewCount = phraseProgress.values.filter { $0.wrongCount > $0.correctCount }.count
        let sourceText = base ?? (aiEnabled ? "Using AI-generated sentence prompts." : "Using built-in sentence prompts.")

        if needsReviewCount == 0 {
            return sourceText
        }

        return "\(sourceText) Prioritising \(needsReviewCount) weaker phrase\(needsReviewCount == 1 ? "" : "s")."
    }
}

enum PracticeMode {
    case all
    case review

    var navigationTitle: String {
        switch self {
        case .all:
            return "Practice"
        case .review:
            return "Review"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "No Phrases Yet"
        case .review:
            return "No Weak Phrases"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "Add a few phrases first, then come back here to practise them."
        case .review:
            return "Miss a few phrases first, then this screen will focus on them."
        }
    }

    func headerTitle(phraseCount: Int) -> String {
        switch self {
        case .all:
            return "Practising \(phraseCount) saved phrase\(phraseCount == 1 ? "" : "s")"
        case .review:
            return "Reviewing \(phraseCount) weaker phrase\(phraseCount == 1 ? "" : "s")"
        }
    }
}

enum PracticeGenerationSource {
    case local
    case ai
}

struct BackendSentenceProvider {
    func cards(
        for phrases: [String],
        configuration: BackendConfiguration,
        progress: (@Sendable (_ completed: Int, _ total: Int) async -> Void)?
    ) async throws -> [PracticeCard] {
        await withTaskGroup(of: [PracticeCard].self) { group in
            for phrase in phrases {
                group.addTask {
                    do {
                        let sentences = try await BackendAIService.shared.generateSentences(for: phrase, configuration: configuration)
                        let phraseCards: [PracticeCard] = sentences.compactMap { sentence in
                            guard let prompt = SentenceGenerator.blankedSentence(from: sentence, phrase: phrase) else {
                                return nil
                            }

                            return PracticeCard(phrase: phrase, prompt: prompt)
                        }

                        if phraseCards.isEmpty {
                            return SentenceGenerator.cards(for: phrase)
                        }

                        return phraseCards
                    } catch {
                        return SentenceGenerator.cards(for: phrase)
                    }
                }
            }

            var cards: [PracticeCard] = []
            var completed = 0
            for await phraseCards in group {
                cards.append(contentsOf: phraseCards)
                completed += 1
                if let progress {
                    await progress(completed, phrases.count)
                }
            }

            return cards
        }
    }
}

#Preview {
    NavigationStack {
        QuizView(
            savedPhrases: [
                "laser-focused",
                "play the hand you’re dealt",
                "taking a massive gamble"
            ],
            phraseProgress: .constant([
                "laser-focused": PhraseProgress(correctCount: 2, wrongCount: 4)
            ]),
            practiceMode: .all
        )
    }
}
