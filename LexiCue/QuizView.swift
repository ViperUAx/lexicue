import SwiftUI

struct QuizView: View {
    let savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]
    let practiceMode: PracticeMode
    let phraseScope: PracticePhraseScope
    let selectedPhraseKeys: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var practiceCards: [PracticeCard] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var generationStatus = "Building practice cards."
    @State private var loadingProgress = 0.0
    @State private var generationTask: Task<Void, Never>?
    @State private var userAnswer = ""
    @State private var resultMessage = ""
    @State private var hasCheckedAnswer = false
    @State private var meaningHint: String?
    @State private var isLoadingMeaningHint = false
    @State private var recordedWrongAttempt = false
    @State private var completionLogged = false
    @State private var sessionCorrectCount = 0
    @State private var sessionWrongCount = 0
    @State private var showSessionSummary = false
    @State private var generationSource: PracticeGenerationSource = .ai
    @State private var isRefreshingCurrentCard = false
    @State private var revealedPromptCharacterCount = 0
    @State private var promptRevealTask: Task<Void, Never>?
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @FocusState private var answerFieldFocused: Bool
    private let appFont = Font.custom("Helvetica Neue", size: 17)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    loadingView
                } else if showSessionSummary {
                    sessionSummaryView
                } else if practiceCards.isEmpty {
                    ContentUnavailableView(
                        practiceMode.emptyTitle,
                        systemImage: "text.badge.plus",
                        description: Text(practiceMode.emptyMessage)
                    )
                } else {
                    let currentCard = practiceCards[currentIndex]

                    VStack(spacing: 12) {
                        Text("Card \(currentIndex + 1) of \(practiceCards.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ProgressView(value: progressValue)

                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(practiceMode.cardTitle)
                            .font(.title2)
                            .fontWeight(.bold)

                        promptView(for: currentCard)
                            .font(.system(size: 22, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        TextField(practiceMode.answerPlaceholder, text: $userAnswer)
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
                    }

                    HStack(spacing: 12) {
                        Button(meaningHint == nil ? "Hint" : "Hide Hint") {
                            if meaningHint == nil {
                                loadMeaningHint(for: currentCard)
                            } else {
                                meaningHint = nil
                            }
                        }
                        .buttonStyle(.bordered)

                        if hasCheckedAnswer && !isAnswerCorrect(for: currentCard) {
                            Button("Next Card") {
                                showNextCard()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Refresh") {
                            refreshCurrentCard()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading || isRefreshingCurrentCard)
                    }
                }
            }
            .padding()
        }
        .environment(\.font, appFont)
        .navigationTitle(practiceMode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshPracticeCardsIfNeeded()
        }
        .onDisappear {
            generationTask?.cancel()
            promptRevealTask?.cancel()
        }
    }

    var progressValue: Double {
        guard !practiceCards.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(practiceCards.count)
    }

    var loadingView: some View {
        VStack(spacing: 18) {
            Text("Preparing Practice")
                .font(.title2)
                .fontWeight(.semibold)

            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.12), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: max(0.02, loadingProgress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)

                Text("\(Int((loadingProgress * 100).rounded()))%")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            Text(generationStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    var savedPhraseCount: Int {
        activePhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var activePhrases: [String] {
        let scopedPhrases: [String]
        switch phraseScope {
        case .all:
            scopedPhrases = savedPhrases
        case .selected:
            let selectedKeys = Set(selectedPhraseKeys)
            scopedPhrases = savedPhrases.filter { selectedKeys.contains($0.normalizedProgressKey) }
        }

        switch practiceMode {
        case .random, .search:
            return scopedPhrases
        case .weakest:
            return scopedPhrases.filter {
                let progress = phraseProgress[$0.normalizedProgressKey] ?? PhraseProgress()
                return progress.totalAttempts > 0 && progress.successRate > 0 && progress.successRate <= 0.5
            }
        }
    }

    var currentProgress: PhraseProgress? {
        guard !practiceCards.isEmpty else { return nil }
        return phraseProgress[practiceCards[currentIndex].phrase.normalizedProgressKey]
    }

    var sessionTotalCount: Int {
        sessionCorrectCount + sessionWrongCount
    }

    var sessionSuccessRate: Double {
        guard sessionTotalCount > 0 else { return 0 }
        return Double(sessionCorrectCount) / Double(sessionTotalCount)
    }

    func refreshPracticeCardsIfNeeded() {
        guard practiceCards.isEmpty, !isLoading, !showSessionSummary else { return }
        refreshPracticeCards(using: .ai)
    }

    func refreshPracticeCards(using source: PracticeGenerationSource = .ai) {
        generationTask?.cancel()
        generationSource = source
        showSessionSummary = false
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
                practiceMode: practiceMode,
                phraseScope: phraseScope,
                source: PracticeGenerationSource.ai,
                configuration: backendConfiguration,
                practiceHistory: practiceHistory,
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
                startPromptRevealIfNeeded()
            }
        }
    }

    func showNextCard() {
        guard !practiceCards.isEmpty else { return }

        let currentCard = practiceCards[currentIndex]
        let shouldCountAsCorrect = hasCheckedAnswer && isAnswerCorrect(for: currentCard)
        let shouldCountAsWrong = !shouldCountAsCorrect && (recordedWrongAttempt || hasCheckedAnswer)
        if shouldCountAsWrong {
            completeCardIfNeeded(currentCard, wasCorrect: false)
        }

        if currentIndex + 1 >= practiceCards.count {
            showSessionSummary = true
            return
        }

        currentIndex = (currentIndex + 1) % practiceCards.count
        resetCardState()
        startPromptRevealIfNeeded()
    }

    @MainActor
    func generatePracticeCards() async {
        isLoading = true
        loadingProgress = 0
        currentIndex = 0
        sessionCorrectCount = 0
        sessionWrongCount = 0
        resetCardState()
        generationStatus = "Opening the AI session."
        await Task.yield()
        loadingProgress = 0.05
        generationStatus = "Choosing phrases for this round."

        let result = await PracticeCardFactory.makeCards(
            for: activePhrases,
            phraseProgress: phraseProgress,
            practiceMode: practiceMode,
            phraseScope: phraseScope,
            source: generationSource,
            configuration: backendConfiguration,
            practiceHistory: practiceHistory,
            progress: { completed, total, status in
                await MainActor.run {
                    loadingProgress = total > 0 ? Double(completed) / Double(total) : 0
                    generationStatus = status
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
        startPromptRevealIfNeeded()
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

            completeCardIfNeeded(card, wasCorrect: true)

            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    showNextCard()
                }
            }
        } else {
            answerFieldFocused = true
            resultMessage = "Not quite. Try again, or use the hint."

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
        meaningHint = nil
        isLoadingMeaningHint = false
        recordedWrongAttempt = false
        completionLogged = false
        answerFieldFocused = !practiceCards.isEmpty
    }

    func completeCardIfNeeded(_ card: PracticeCard, wasCorrect: Bool) {
        guard !completionLogged else { return }

        completionLogged = true
        if wasCorrect {
            sessionCorrectCount += 1
        } else {
            sessionWrongCount += 1
        }
    }

    func completedSentence(for card: PracticeCard) -> String {
        card.completedSentence
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

    func startNextSession() {
        practiceCards = []
        refreshPracticeCards(using: .ai)
    }

    func startPromptRevealIfNeeded() {
        promptRevealTask?.cancel()
        revealedPromptCharacterCount = 0

        guard !practiceCards.isEmpty else { return }
        let promptLength = practiceCards[currentIndex].prompt.count
        guard promptLength > 0 else { return }

        promptRevealTask = Task {
            for nextCount in 1...promptLength {
                if Task.isCancelled { return }
                await MainActor.run {
                    revealedPromptCharacterCount = nextCount
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    var sessionSummaryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Session Complete")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Success performance")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(Int((sessionSuccessRate * 100).rounded()))%")
                    .font(.system(size: 48, weight: .bold))

                Text("Correct \(sessionCorrectCount) • Missed \(sessionWrongCount)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Button("Next Session") {
                startNextSession()
            }
            .buttonStyle(.borderedProminent)

            Button("Main Menu") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
        logPracticeAttempt(for: card, wasCorrect: wasCorrect)
    }

    func logPracticeAttempt(for card: PracticeCard, wasCorrect: Bool) {
        let key = card.phrase.normalizedProgressKey
        var entries = practiceHistory[key] ?? []
        entries.insert(
            PracticeLogEntry(
                sentence: completedSentence(for: card),
                wasCorrect: wasCorrect
            ),
            at: 0
        )
        practiceHistory[key] = Array(entries.prefix(20))
    }

    func normalized(_ text: String) -> String {
        expandedContractions(in: text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    func expandedContractions(in text: String) -> String {
        var expanded = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")

        let replacements: [(String, String)] = [
            ("i'm", "i am"),
            ("you're", "you are"),
            ("we're", "we are"),
            ("they're", "they are"),
            ("he's", "he is"),
            ("she's", "she is"),
            ("it's", "it is"),
            ("that's", "that is"),
            ("there's", "there is"),
            ("here's", "here is"),
            ("what's", "what is"),
            ("who's", "who is"),
            ("can't", "cannot"),
            ("won't", "will not"),
            ("don't", "do not"),
            ("doesn't", "does not"),
            ("didn't", "did not"),
            ("isn't", "is not"),
            ("aren't", "are not"),
            ("wasn't", "was not"),
            ("weren't", "were not"),
            ("haven't", "have not"),
            ("hasn't", "has not"),
            ("hadn't", "had not"),
            ("wouldn't", "would not"),
            ("shouldn't", "should not"),
            ("couldn't", "could not"),
            ("mustn't", "must not"),
            ("let's", "let us"),
            ("i've", "i have"),
            ("you've", "you have"),
            ("we've", "we have"),
            ("they've", "they have"),
            ("i'll", "i will"),
            ("you'll", "you will"),
            ("he'll", "he will"),
            ("she'll", "she will"),
            ("we'll", "we will"),
            ("they'll", "they will"),
            ("i'd", "i would"),
            ("you'd", "you would"),
            ("he'd", "he would"),
            ("she'd", "she would"),
            ("we'd", "we would"),
            ("they'd", "they would"),
            ("isnt", "is not"),
            ("arent", "are not"),
            ("dont", "do not"),
            ("doesnt", "does not"),
            ("didnt", "did not"),
            ("cant", "cannot"),
            ("wont", "will not"),
            ("im", "i am"),
            ("ive", "i have"),
            ("ill", "i will"),
            ("id", "i would")
        ]

        for (source, target) in replacements {
            expanded = expanded.replacingOccurrences(of: source, with: target)
        }

        return expanded
    }

    var backendConfiguration: BackendConfiguration {
        BackendConfiguration(baseURLString: backendBaseURL)
    }

    @ViewBuilder
    func promptView(for card: PracticeCard) -> some View {
        if practiceMode == .search {
            Text(formattedSearchPrompt(for: card, visibleCharacterCount: revealedPromptCharacterCount))
        } else {
            Text(String(card.prompt.prefix(revealedPromptCharacterCount)))
        }
    }

    func formattedSearchPrompt(for card: PracticeCard, visibleCharacterCount: Int) -> AttributedString {
        let visiblePrompt = String(card.prompt.prefix(visibleCharacterCount))
        var attributed = AttributedString(visiblePrompt)
        let highlightedText = card.highlightedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !highlightedText.isEmpty,
            let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: highlightedText), options: [.caseInsensitive]),
            let match = regex.firstMatch(in: visiblePrompt, range: NSRange(visiblePrompt.startIndex..., in: visiblePrompt)),
            let range = Range(match.range, in: visiblePrompt),
            let attributedRange = Range(range, in: attributed)
        else {
            return attributed
        }

        attributed[attributedRange].font = .body.italic()
        return attributed
    }
}

struct PracticeCard: Identifiable, Hashable {
    let id = UUID()
    let phrase: String
    let prompt: String
    let completedSentence: String
    let highlightedText: String
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

            return PracticeCard(
                phrase: cleanedPhrase,
                prompt: prompt,
                completedSentence: sentence,
                highlightedText: ""
            )
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
        phraseScope: PracticePhraseScope,
        source: PracticeGenerationSource,
        configuration: BackendConfiguration,
        practiceHistory: [String: [PracticeLogEntry]],
        progress: (@Sendable (_ completed: Int, _ total: Int, _ status: String) async -> Void)?
    ) async -> PracticeCardResult {
        let cleanedPhrases = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedPhrases.isEmpty else {
            return PracticeCardResult(cards: [], status: "Add a phrase to begin.")
        }

        let targetPhraseCount = min(
            10,
            PracticeCycleManager.candidatePhrases(
                for: practiceMode,
                phraseScope: phraseScope,
                phrases: cleanedPhrases,
                phraseProgress: phraseProgress
            ).count
        )

        guard targetPhraseCount > 0 else {
            return PracticeCardResult(cards: [], status: practiceMode.emptyMessage)
        }

        if source == .ai {
            if configuration.isValid {
                do {
                    var acceptedPhraseCards: [String: [PracticeCard]] = [:]
                    var attemptedPhrases = Set<String>()
                    var attemptedCount = 0
                    let progressTotal = max(targetPhraseCount + 3, 1)
                    if let progress {
                        await progress(1, progressTotal, "Selecting \(targetPhraseCount) phrases for this session.")
                    }

                    while acceptedPhraseCards.count < targetPhraseCount {
                        let needed = targetPhraseCount - acceptedPhraseCards.count
                        let nextPhrases = PracticeCycleManager.nextSessionPhrases(
                            for: practiceMode,
                            phraseScope: phraseScope,
                            phrases: cleanedPhrases,
                            phraseProgress: phraseProgress,
                            count: needed,
                            excluding: attemptedPhrases
                        )

                        guard !nextPhrases.isEmpty else { break }
                        attemptedPhrases.formUnion(nextPhrases)

                        let completedBeforeBatch = attemptedCount
                        let generatedCards = try await BackendSentenceProvider().cards(
                            for: nextPhrases,
                            practiceMode: practiceMode,
                            practiceHistory: practiceHistory,
                            configuration: configuration,
                            progress: { completed, _ in
                                let totalCompleted = min(targetPhraseCount, completedBeforeBatch + completed)
                                if let progress {
                                    await progress(
                                        min(progressTotal - 2, totalCompleted + 1),
                                        progressTotal,
                                        "Generating phrases \(min(targetPhraseCount, totalCompleted)) of \(targetPhraseCount)."
                                    )
                                }
                            }
                        )
                        attemptedCount += nextPhrases.count

                        let groupedCards = Dictionary(grouping: generatedCards, by: \.phrase)
                        for phrase in nextPhrases {
                            guard acceptedPhraseCards[phrase] == nil else { continue }
                            guard let phraseCards = groupedCards[phrase], phraseCards.count >= 2 else { continue }
                            acceptedPhraseCards[phrase] = Array(phraseCards.prefix(2))
                        }
                    }

                    let generatedCards = acceptedPhraseCards.values.flatMap { $0 }
                    if acceptedPhraseCards.count == targetPhraseCount, !generatedCards.isEmpty {
                        if let progress {
                            await progress(progressTotal - 1, progressTotal, "Arranging two different rounds for this session.")
                        }
                        return PracticeCardResult(
                            cards: finalizedCards(from: generatedCards),
                            status: "AI-generated session ready."
                        )
                    }

                    return PracticeCardResult(
                        cards: [],
                        status: "AI could not complete a full \(targetPhraseCount * 2)-card session right now."
                    )
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    return PracticeCardResult(cards: [], status: "AI failed: \(message)")
                }
            }

            return PracticeCardResult(cards: [], status: "AI backend is not configured.")
        }

        return PracticeCardResult(cards: [], status: "AI is required for this practice mode.")
    }

    private static func finalizedCards(from cards: [PracticeCard]) -> [PracticeCard] {
        repeatedRoundCards(from: cards, repeatsPerPhrase: 2)
    }

    private static func repeatedRoundCards(from cards: [PracticeCard], repeatsPerPhrase: Int) -> [PracticeCard] {
        let groupedCards = Dictionary(grouping: cards, by: \.phrase)
        let firstRoundOrder = Array(groupedCards.keys).shuffled()
        let secondRoundOrder = alternateOrder(from: firstRoundOrder)
        var arranged: [PracticeCard] = []

        for roundIndex in 0..<repeatsPerPhrase {
            let roundOrder = roundIndex == 0 ? firstRoundOrder : secondRoundOrder
            for phrase in roundOrder {
                guard let phraseCards = groupedCards[phrase], !phraseCards.isEmpty else { continue }
                let sourceIndex = min(roundIndex, phraseCards.count - 1)
                arranged.append(phraseCards[sourceIndex])
            }
        }

        return spacedCards(from: arranged)
    }

    private static func alternateOrder(from firstRoundOrder: [String]) -> [String] {
        guard firstRoundOrder.count > 1 else { return firstRoundOrder }

        var alternate = Array(firstRoundOrder.dropFirst()) + [firstRoundOrder[0]]
        if alternate == firstRoundOrder {
            alternate = firstRoundOrder.reversed()
        }
        return Array(alternate)
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
}

enum PracticeMode {
    case random
    case weakest
    case search

    var navigationTitle: String {
        switch self {
        case .random:
            return "Random"
        case .weakest:
            return "Weakest"
        case .search:
            return "Search"
        }
    }

    var emptyTitle: String {
        switch self {
        case .random:
            return "No Phrases Yet"
        case .weakest:
            return "No Weakest Phrases"
        case .search:
            return "No Phrases Yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .random:
            return "Add a few phrases first, then come back here to practise them."
        case .weakest:
            return "You need phrases with a success rate between 1% and 50% for this mode."
        case .search:
            return "Add a few phrases first, then use search mode to infer them from synonyms."
        }
    }

    var cardTitle: String {
        switch self {
        case .random, .weakest:
            return "Fill in the missing phrase"
        case .search:
            return "Guess the original phrase"
        }
    }

    var answerPlaceholder: String {
        switch self {
        case .random, .weakest:
            return "Type the missing phrase"
        case .search:
            return "Type the original phrase"
        }
    }

    var backendMode: String {
        switch self {
        case .random:
            return "random"
        case .weakest:
            return "weakest"
        case .search:
            return "search"
        }
    }

    func cycleStorageKey(for phraseScope: PracticePhraseScope) -> String {
        "practiceCycleState.\(backendMode).\(phraseScope.cycleKeySuffix)"
    }
}

enum PracticeGenerationSource {
    case ai
}

struct BackendSentenceProvider {
    func cards(
        for phrases: [String],
        practiceMode: PracticeMode,
        practiceHistory: [String: [PracticeLogEntry]],
        configuration: BackendConfiguration,
        progress: (@Sendable (_ completed: Int, _ total: Int) async -> Void)?
    ) async throws -> [PracticeCard] {
        await withTaskGroup(of: [PracticeCard].self) { group in
            for phrase in phrases {
                group.addTask {
                    do {
                        let previousSentences = practiceHistory[normalizedPhraseKey(phrase)]?.map(\.sentence) ?? []
                        let generated = try await BackendAIService.shared.generatePracticeCards(
                            for: phrase,
                            mode: practiceMode,
                            previousSentences: previousSentences,
                            configuration: configuration
                        )
                        let phraseCards: [PracticeCard] = generated.compactMap { generatedCard in
                            switch practiceMode {
                            case .random, .weakest:
                                guard let prompt = SentenceGenerator.blankedSentence(from: generatedCard.sentence, phrase: phrase) else {
                                    return nil
                                }
                                return PracticeCard(
                                    phrase: phrase,
                                    prompt: prompt,
                                    completedSentence: generatedCard.sentence,
                                    highlightedText: ""
                                )
                            case .search:
                                return PracticeCard(
                                    phrase: phrase,
                                    prompt: generatedCard.sentence,
                                    completedSentence: generatedCard.sentence,
                                    highlightedText: generatedCard.highlightedText
                                )
                            }
                        }

                        if phraseCards.isEmpty {
                            return []
                        }

                        return phraseCards
                    } catch {
                        return []
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

nonisolated func normalizedPhraseKey(_ phrase: String) -> String {
    phrase
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "’", with: "'")
}

struct PracticeCycleState: Codable {
    var pool: [String]
    var order: [String]
    var nextIndex: Int
}

enum PracticeCycleManager {
    static func nextSessionPhrases(
        for mode: PracticeMode,
        phraseScope: PracticePhraseScope,
        phrases: [String],
        phraseProgress: [String: PhraseProgress],
        count: Int,
        excluding excludedPhrases: Set<String> = []
    ) -> [String] {
        let candidates = candidatePhrases(for: mode, phraseScope: phraseScope, phrases: phrases, phraseProgress: phraseProgress)
        guard !candidates.isEmpty else { return [] }

        var state = loadState(for: mode, phraseScope: phraseScope, candidates: candidates)
        var selected: [String] = []
        let targetCount = max(1, count)
        var inspectedCount = 0

        while selected.count < targetCount, inspectedCount < max(state.order.count * 2, 1) {
            if state.order.isEmpty || state.nextIndex >= state.order.count {
                state.order = state.pool.shuffled()
                state.nextIndex = 0
            }

            let phrase = state.order[state.nextIndex]
            state.nextIndex += 1
            inspectedCount += 1

            guard !excludedPhrases.contains(phrase), !selected.contains(phrase) else {
                continue
            }

            selected.append(phrase)
        }

        saveState(state, for: mode, phraseScope: phraseScope)
        return selected
    }

    static func candidatePhrases(
        for mode: PracticeMode,
        phraseScope: PracticePhraseScope,
        phrases: [String],
        phraseProgress: [String: PhraseProgress]
    ) -> [String] {
        switch mode {
        case .random, .search:
            return phrases
        case .weakest:
            return phrases.filter {
                let progress = phraseProgress[$0.normalizedProgressKey] ?? PhraseProgress()
                return progress.totalAttempts > 0 && progress.successRate > 0 && progress.successRate <= 0.5
            }
        }
    }

    private static func loadState(for mode: PracticeMode, phraseScope: PracticePhraseScope, candidates: [String]) -> PracticeCycleState {
        let key = mode.cycleStorageKey(for: phraseScope)
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let state = try? JSONDecoder().decode(PracticeCycleState.self, from: data),
            !state.pool.isEmpty,
            Set(state.order) == Set(state.pool),
            state.order.count == state.pool.count,
            state.nextIndex >= 0,
            state.nextIndex <= state.order.count
        else {
            let newPool = freezePool(for: mode, candidates: candidates)
            return PracticeCycleState(pool: newPool, order: newPool.shuffled(), nextIndex: 0)
        }

        let candidateSet = Set(candidates)
        let poolSet = Set(state.pool)

        switch mode {
        case .random, .search:
            if poolSet == candidateSet, state.pool.count == candidates.count {
                return state
            }
        case .weakest:
            if !poolSet.subtracting(candidateSet).isEmpty {
                let newPool = freezePool(for: mode, candidates: candidates)
                return PracticeCycleState(pool: newPool, order: newPool.shuffled(), nextIndex: 0)
            }
        }

        return state
    }

    private static func saveState(_ state: PracticeCycleState, for mode: PracticeMode, phraseScope: PracticePhraseScope) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: mode.cycleStorageKey(for: phraseScope))
    }

    private static func freezePool(for mode: PracticeMode, candidates: [String]) -> [String] {
        switch mode {
        case .random, .search, .weakest:
            return candidates
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
            practiceHistory: .constant([:]),
            practiceMode: .random,
            phraseScope: .all,
            selectedPhraseKeys: []
        )
    }
}
