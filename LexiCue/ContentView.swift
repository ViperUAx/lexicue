import SwiftUI

struct ContentView: View {
    @State private var savedPhrases: [String] = []
    @State private var phraseProgress: [String: PhraseProgress] = [:]
    @State private var phraseDifficulties: [String: PhraseDifficulty] = [:]
    @State private var difficultyTask: Task<Void, Never>?
    @State private var showAISettings = false
    @AppStorage("backendBaseURL") private var backendBaseURL = ""

    let difficultyClassifierVersion = 5

    let defaultPhrases = [
        "laser-focused",
        "play the hand you’re dealt",
        "taking a massive gamble"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LexiCue")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Memorize your own words and phrases faster.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    summaryCards
                    actionSection
                    NavigationLink {
                        StatisticsView(
                            savedPhrases: savedPhrases,
                            phraseProgress: phraseProgress,
                            phraseDifficulties: phraseDifficulties
                        )
                    } label: {
                        actionRow(
                            title: "Statistics",
                            subtitle: "Open grouped success rates by difficulty",
                            tint: .green
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("AI") {
                        showAISettings = true
                    }
                }
            }
            .sheet(isPresented: $showAISettings) {
                AISettingsView(endpointURL: $backendBaseURL)
            }
            .onAppear {
                loadPhrases()
                loadPhraseProgress()
                loadPhraseDifficulties()
                invalidateCachedDifficultiesIfNeeded()
                classifyMissingDifficulties()
            }
            .onChange(of: savedPhrases) { _, newValue in
                savePhrases(newValue)
                removeProgressForDeletedPhrases(using: newValue)
                removeDifficultyForDeletedPhrases(using: newValue)
                classifyMissingDifficulties()
            }
            .onChange(of: phraseProgress) { _, newValue in
                savePhraseProgress(newValue)
            }
            .onChange(of: phraseDifficulties) { _, newValue in
                savePhraseDifficulties(newValue)
            }
            .onDisappear {
                difficultyTask?.cancel()
            }
        }
    }

    var summaryCards: some View {
        HStack(spacing: 12) {
            dashboardCard(title: "Saved", value: "\(savedPhrases.count)", subtitle: "phrases")
            dashboardCard(title: "Need Review", value: "\(phrasesNeedingReviewCount)", subtitle: "weaker items")
            dashboardCard(title: "Answers", value: "\(totalAttempts)", subtitle: "checked")
        }
    }

    var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                QuizView(
                    savedPhrases: savedPhrases,
                    phraseProgress: $phraseProgress,
                    practiceMode: .all
                )
            } label: {
                actionRow(
                    title: "Practice All",
                    subtitle: "Instant local cards for every saved phrase",
                    tint: .blue
                )
            }
            .disabled(savedPhrases.isEmpty)

            NavigationLink {
                QuizView(
                    savedPhrases: savedPhrases,
                    phraseProgress: $phraseProgress,
                    practiceMode: .review
                )
            } label: {
                actionRow(
                    title: "Review Weak Phrases",
                    subtitle: "Focus on items you miss more often",
                    tint: .orange
                )
            }
            .disabled(phrasesNeedingReviewCount == 0)

            NavigationLink {
                MyWordsView(
                    savedPhrases: $savedPhrases,
                    phraseProgress: $phraseProgress,
                    phraseDifficulties: $phraseDifficulties
                )
            } label: {
                actionRow(
                    title: "Manage My Phrases",
                    subtitle: "Add one by one or paste a whole list",
                    tint: .gray
                )
            }
        }
    }

    var phrasesNeedingReviewCount: Int {
        savedPhrases.reduce(into: 0) { count, phrase in
            let progress = phraseProgress[phrase.normalizedProgressKey] ?? PhraseProgress()
            if progress.needsReview {
                count += 1
            }
        }
    }

    var totalAttempts: Int {
        phraseProgress.values.reduce(0) { $0 + $1.correctCount + $1.wrongCount }
    }

    func savePhrases(_ phrases: [String]) {
        UserDefaults.standard.set(phrases, forKey: "savedPhrases")
    }

    func loadPhrases() {
        if let saved = UserDefaults.standard.stringArray(forKey: "savedPhrases") {
            savedPhrases = saved
        } else {
            savedPhrases = defaultPhrases
        }
    }

    func savePhraseProgress(_ progress: [String: PhraseProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: "phraseProgress")
    }

    func savePhraseDifficulties(_ difficulties: [String: PhraseDifficulty]) {
        guard let data = try? JSONEncoder().encode(difficulties) else { return }
        UserDefaults.standard.set(data, forKey: "phraseDifficulties")
    }

    func loadPhraseProgress() {
        guard
            let data = UserDefaults.standard.data(forKey: "phraseProgress"),
            let progress = try? JSONDecoder().decode([String: PhraseProgress].self, from: data)
        else {
            phraseProgress = [:]
            return
        }

        phraseProgress = progress
    }

    func loadPhraseDifficulties() {
        guard
            let data = UserDefaults.standard.data(forKey: "phraseDifficulties"),
            let difficulties = try? JSONDecoder().decode([String: PhraseDifficulty].self, from: data)
        else {
            phraseDifficulties = [:]
            return
        }

        phraseDifficulties = difficulties
    }

    func invalidateCachedDifficultiesIfNeeded() {
        let savedVersion = UserDefaults.standard.integer(forKey: "difficultyClassifierVersion")
        guard savedVersion != difficultyClassifierVersion else { return }

        phraseDifficulties = [:]
        UserDefaults.standard.set(difficultyClassifierVersion, forKey: "difficultyClassifierVersion")
    }

    func removeProgressForDeletedPhrases(using phrases: [String]) {
        let validKeys = Set(phrases.map(\.normalizedProgressKey))
        phraseProgress = phraseProgress.filter { validKeys.contains($0.key) }
    }

    func removeDifficultyForDeletedPhrases(using phrases: [String]) {
        let validKeys = Set(phrases.map(\.normalizedProgressKey))
        phraseDifficulties = phraseDifficulties.filter { validKeys.contains($0.key) }
    }

    func classifyMissingDifficulties() {
        difficultyTask?.cancel()

        let phrasesToClassify = savedPhrases.filter {
            let key = $0.normalizedProgressKey
            return !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phraseDifficulties[key] == nil
        }

        guard !phrasesToClassify.isEmpty else { return }

        difficultyTask = Task {
            for phrase in phrasesToClassify {
                if Task.isCancelled { return }
                let difficulty = await PhraseDifficultyAssessor.assessDifficulty(
                    for: phrase,
                    configuration: backendConfiguration
                )
                if Task.isCancelled { return }

                await MainActor.run {
                    phraseDifficulties[phrase.normalizedProgressKey] = difficulty
                }
            }
        }
    }

    var backendConfiguration: BackendConfiguration {
        BackendConfiguration(baseURLString: backendBaseURL)
    }

    func dashboardCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    func actionRow(title: String, subtitle: String, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(tint)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    func homeSuccessBadge(for progress: PhraseProgress) -> some View {
        Text(progress.totalAttempts > 0 ? "\(Int(progress.successRate * 100))%" : "-%")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(successTint(for: progress))
            .clipShape(Capsule())
            .frame(minWidth: 48, alignment: .trailing)
    }

    func successTint(for progress: PhraseProgress) -> Color {
        guard progress.totalAttempts > 0 else { return .gray.opacity(0.6) }

        let rate = progress.successRate
        if rate >= 0.85 {
            return Color(red: 0.05, green: 0.65, blue: 0.18)
        }
        if rate >= 0.65 {
            return Color(red: 0.36, green: 0.74, blue: 0.25)
        }
        if rate >= 0.45 {
            return Color(red: 0.78, green: 0.68, blue: 0.18)
        }
        if rate >= 0.25 {
            return Color(red: 0.86, green: 0.44, blue: 0.18)
        }
        return Color(red: 0.80, green: 0.18, blue: 0.18)
    }
}

struct PhraseProgress: Codable, Hashable {
    var correctCount = 0
    var wrongCount = 0

    var totalAttempts: Int {
        correctCount + wrongCount
    }

    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctCount) / Double(totalAttempts)
    }

    var reviewPriority: Int {
        wrongCount - correctCount
    }

    var needsReview: Bool {
        reviewPriority > 0
    }
}

enum PhraseDifficulty: Int, Codable, CaseIterable, Hashable {
    case beginner = 1
    case elementary = 2
    case intermediate = 3
    case advanced = 4
    case expert = 5

    var title: String {
        switch self {
        case .beginner:
            return "Beginner"
        case .elementary:
            return "Elementary"
        case .intermediate:
            return "Intermediate"
        case .advanced:
            return "Advanced"
        case .expert:
            return "Expert"
        }
    }

    var shortLabel: String {
        switch self {
        case .beginner:
            return "BEG"
        case .elementary:
            return "ELEM"
        case .intermediate:
            return "INT"
        case .advanced:
            return "ADV"
        case .expert:
            return "EXPERT"
        }
    }

    var tint: Color {
        switch self {
        case .beginner:
            return Color(red: 0.83, green: 0.92, blue: 0.83)
        case .elementary:
            return Color(red: 0.72, green: 0.90, blue: 0.72)
        case .intermediate:
            return Color(red: 0.28, green: 0.72, blue: 0.32)
        case .advanced:
            return Color(red: 0.12, green: 0.60, blue: 0.22)
        case .expert:
            return Color(red: 0.03, green: 0.46, blue: 0.12)
        }
    }
}

enum PhraseDifficultyAssessor {
    static func assessDifficulty(for phrase: String, configuration: BackendConfiguration) async -> PhraseDifficulty {
        if configuration.isValid {
            do {
                let level = try await BackendAIService.shared.assessDifficulty(for: phrase, configuration: configuration)
                if let difficulty = PhraseDifficulty(rawValue: max(1, min(5, level))) {
                    return difficulty
                }
            } catch {
                return heuristicDifficulty(for: phrase)
            }
        }

        return heuristicDifficulty(for: phrase)
    }

    private static func heuristicDifficulty(for phrase: String) -> PhraseDifficulty {
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = cleaned.split(separator: " ")
        let singleWord = words.count == 1
        let advancedSuffixes = [
            "ate", "ize", "ise", "ify", "tion", "sion", "ment", "ence", "ance", "ious", "ible", "able"
        ]
        let advancedWords: Set<String> = [
            "exonerate", "scrutinize", "meticulous", "coherent", "ambiguous", "inevitable",
            "subtle", "notwithstanding", "plausible", "allocate", "legitimate", "reluctantly"
        ]

        if singleWord && advancedWords.contains(cleaned) {
            return .advanced
        }

        if singleWord && cleaned.count <= 4 {
            return .beginner
        }

        if singleWord && cleaned.count <= 6 {
            return .elementary
        }

        if singleWord && cleaned.count <= 8 {
            return .intermediate
        }

        if singleWord && (cleaned.count >= 10 || advancedSuffixes.contains(where: cleaned.hasSuffix)) {
            return .advanced
        }

        if singleWord && cleaned.count == 9 {
            return .advanced
        }

        if cleaned.contains("’") || cleaned.contains("'") || cleaned.contains("-") {
            return .advanced
        }

        if words.count >= 4 {
            return .expert
        }

        if words.count == 3 {
            return .advanced
        }

        if words.count == 2 {
            return .intermediate
        }

        return .intermediate
    }
}

struct StatisticsView: View {
    let savedPhrases: [String]
    let phraseProgress: [String: PhraseProgress]
    let phraseDifficulties: [String: PhraseDifficulty]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if groupedStatistics.isEmpty {
                    Text("No statistics yet.")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(groupedStatistics, id: \.difficulty.rawValue) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.difficulty.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(group.difficulty.tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(group.difficulty.tint.opacity(0.14))
                                .clipShape(Capsule())

                            VStack(spacing: 0) {
                                ForEach(group.phrases, id: \.self) { phrase in
                                    let progress = phraseProgress[phrase.normalizedProgressKey] ?? PhraseProgress()

                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(phrase)
                                            Text("Correct \(progress.correctCount) • Missed \(progress.wrongCount)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        SuccessRateValue(progress: progress)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)

                                    if phrase != group.phrases.last {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    var groupedStatistics: [(difficulty: PhraseDifficulty, phrases: [String])] {
        PhraseDifficulty.allCases
            .sorted { $0.rawValue > $1.rawValue }
            .compactMap { difficulty in
                let phrases = savedPhrases.filter {
                    phraseDifficulties[$0.normalizedProgressKey] == difficulty
                }

                guard !phrases.isEmpty else { return nil }
                return (difficulty, phrases)
            }
    }
}

struct SuccessRateValue: View {
    let progress: PhraseProgress

    var body: some View {
        Text(progress.totalAttempts > 0 ? "\(Int(progress.successRate * 100))%" : "-%")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(successTint)
            .clipShape(Capsule())
            .frame(minWidth: 48, alignment: .trailing)
    }

    var successTint: Color {
        guard progress.totalAttempts > 0 else { return .gray.opacity(0.6) }

        let rate = progress.successRate
        if rate >= 0.85 {
            return Color(red: 0.05, green: 0.65, blue: 0.18)
        }
        if rate >= 0.65 {
            return Color(red: 0.36, green: 0.74, blue: 0.25)
        }
        if rate >= 0.45 {
            return Color(red: 0.78, green: 0.68, blue: 0.18)
        }
        if rate >= 0.25 {
            return Color(red: 0.86, green: 0.44, blue: 0.18)
        }
        return Color(red: 0.80, green: 0.18, blue: 0.18)
    }
}

struct AISettingsView: View {
    @Binding var endpointURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("https://your-server.com", text: $endpointURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                }

                Section {
                    Text("LexiCue should call only your own backend. Your server should hold the OpenAI key, generate sentences, classify difficulty, and return only the safe result to the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Expected Endpoints") {
                    Text("POST /generate-sentence")
                    Text("POST /classify-difficulty")
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension String {
    var normalizedProgressKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }
}

#Preview {
    ContentView()
}
