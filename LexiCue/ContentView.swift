import SwiftUI

struct ContentView: View {
    @State private var savedPhrases: [String] = []
    @State private var phraseProgress: [String: PhraseProgress] = [:]
    @State private var phraseMeanings: [String: String] = [:]
    @State private var practiceHistory: [String: [PracticeLogEntry]] = [:]
    @State private var showAISettings = false
    @State private var isBootstrapping = true
    @State private var bootstrapStatus = "Loading saved phrases."
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    private let appFont = Font.custom("Helvetica Neue", size: 17)

    let defaultPhrases = [
        "laser-focused",
        "play the hand you’re dealt",
        "taking a massive gamble"
    ]

    var body: some View {
        NavigationStack {
            mainContentView
            .environment(\.font, appFont)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    aiToolbarButton
                }
            }
            .sheet(isPresented: $showAISettings) {
                AISettingsView(endpointURL: $backendBaseURL)
            }
            .task {
                await bootstrapIfNeeded()
            }
            .onChange(of: savedPhrases) { _, newValue in
                let deduplicated = deduplicatedPhrases(newValue)
                if deduplicated != newValue {
                    savedPhrases = deduplicated
                    return
                }

                savePhrases(deduplicated)
                removeProgressForDeletedPhrases(using: deduplicated)
                removeMeaningForDeletedPhrases(using: deduplicated)
                removePracticeHistoryForDeletedPhrases(using: deduplicated)
            }
            .onChange(of: phraseProgress) { _, newValue in
                savePhraseProgress(newValue)
            }
            .onChange(of: phraseMeanings) { _, newValue in
                savePhraseMeanings(newValue)
            }
            .onChange(of: practiceHistory) { _, newValue in
                savePracticeHistory(newValue)
            }
        }
    }

    @ViewBuilder
    var mainContentView: some View {
        if isBootstrapping {
            startupLoadingView
        } else {
            dashboardView
        }
    }

    @ViewBuilder
    var aiToolbarButton: some View {
        if !isBootstrapping {
            Button("AI") {
                showAISettings = true
            }
        }
    }

    var startupLoadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            Text("Opening LexiCue")
                .font(.title2)
                .fontWeight(.semibold)

            Text(bootstrapStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    var dashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                summaryCards
                actionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LexiCue")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Memorize your own words and phrases faster.")
                .font(.title3)
                .foregroundStyle(.secondary)
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
            practiceAllLink
            manageWordsLink
        }
    }

    var practiceAllLink: some View {
        NavigationLink {
            PracticeModesView(
                savedPhrases: savedPhrases,
                phraseProgress: $phraseProgress,
                practiceHistory: $practiceHistory
            )
        } label: {
            actionRow(
                title: "Practice All",
                subtitle: "Choose random, weakest, or search mode",
                tint: .blue
            )
        }
        .disabled(savedPhrases.isEmpty)
    }

    var manageWordsLink: some View {
        NavigationLink {
            MyWordsView(
                savedPhrases: $savedPhrases,
                phraseProgress: $phraseProgress,
                phraseMeanings: $phraseMeanings,
                practiceHistory: $practiceHistory
            )
        } label: {
            actionRow(
                title: "Manage My Phrases",
                subtitle: "Open the list and encyclopedia",
                tint: .gray
            )
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

    @MainActor
    func bootstrapIfNeeded() async {
        guard isBootstrapping else { return }

        bootstrapStatus = "Loading saved phrases."
        let phrases = await loadSavedPhrases()

        bootstrapStatus = "Loading progress."
        let progress = await loadStoredPhraseProgress()

        bootstrapStatus = "Loading meanings."
        let meanings = await loadStoredPhraseMeanings()

        bootstrapStatus = "Loading practice history."
        let history = await loadStoredPracticeHistory()

        savedPhrases = phrases
        phraseProgress = progress
        phraseMeanings = meanings
        practiceHistory = history
        isBootstrapping = false
    }

    func savePhrases(_ phrases: [String]) {
        UserDefaults.standard.set(phrases, forKey: "savedPhrases")
    }

    func loadPhrases() {
        if let saved = UserDefaults.standard.stringArray(forKey: "savedPhrases") {
            savedPhrases = deduplicatedPhrases(saved)
        } else {
            savedPhrases = defaultPhrases
        }
    }

    func savePhraseProgress(_ progress: [String: PhraseProgress]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: "phraseProgress")
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

    func loadPhraseMeanings() {
        guard
            let data = UserDefaults.standard.data(forKey: "phraseMeanings"),
            let meanings = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            phraseMeanings = [:]
            return
        }

        phraseMeanings = meanings
    }

    func loadPracticeHistory() {
        guard
            let data = UserDefaults.standard.data(forKey: "practiceHistory"),
            let history = try? JSONDecoder().decode([String: [PracticeLogEntry]].self, from: data)
        else {
            practiceHistory = [:]
            return
        }

        practiceHistory = history
    }

    func loadSavedPhrases() async -> [String] {
        await Task.detached(priority: .userInitiated) {
            if let saved = UserDefaults.standard.stringArray(forKey: "savedPhrases") {
                return deduplicatedPhrases(saved)
            }
            return defaultPhrases
        }.value
    }

    nonisolated func deduplicatedPhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.normalizedProgressKey
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }

        return result
    }

    func loadStoredPhraseProgress() async -> [String: PhraseProgress] {
        await Task.detached(priority: .userInitiated) {
            guard
                let data = UserDefaults.standard.data(forKey: "phraseProgress"),
                let progress = try? JSONDecoder().decode([String: PhraseProgress].self, from: data)
            else {
                return [:]
            }

            return progress
        }.value
    }

    func loadStoredPhraseMeanings() async -> [String: String] {
        await Task.detached(priority: .userInitiated) {
            guard
                let data = UserDefaults.standard.data(forKey: "phraseMeanings"),
                let meanings = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return [:]
            }

            return meanings
        }.value
    }

    func loadStoredPracticeHistory() async -> [String: [PracticeLogEntry]] {
        await Task.detached(priority: .userInitiated) {
            guard
                let data = UserDefaults.standard.data(forKey: "practiceHistory"),
                let history = try? JSONDecoder().decode([String: [PracticeLogEntry]].self, from: data)
            else {
                return [:]
            }

            return history
        }.value
    }

    func savePhraseMeanings(_ meanings: [String: String]) {
        guard let data = try? JSONEncoder().encode(meanings) else { return }
        UserDefaults.standard.set(data, forKey: "phraseMeanings")
    }

    func savePracticeHistory(_ history: [String: [PracticeLogEntry]]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: "practiceHistory")
    }

    func removeProgressForDeletedPhrases(using phrases: [String]) {
        let validKeys = Set(phrases.map(\.normalizedProgressKey))
        phraseProgress = phraseProgress.filter { validKeys.contains($0.key) }
    }

    func removeMeaningForDeletedPhrases(using phrases: [String]) {
        let validKeys = Set(phrases.map(\.normalizedProgressKey))
        phraseMeanings = phraseMeanings.filter { validKeys.contains($0.key) }
    }

    func removePracticeHistoryForDeletedPhrases(using phrases: [String]) {
        let validKeys = Set(phrases.map(\.normalizedProgressKey))
        practiceHistory = practiceHistory.filter { validKeys.contains($0.key) }
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

}

struct PhraseProgress: Codable, Hashable {
    var correctCount = 0
    var wrongCount = 0
    var masteryPoints = 0
    var highestMasteryLevelRaw = MasteryLevel.one.rawValue

    nonisolated init(
        correctCount: Int = 0,
        wrongCount: Int = 0,
        masteryPoints: Int = 0,
        highestMasteryLevelRaw: Int = MasteryLevel.one.rawValue
    ) {
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.masteryPoints = masteryPoints
        self.highestMasteryLevelRaw = highestMasteryLevelRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correctCount = try container.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        wrongCount = try container.decodeIfPresent(Int.self, forKey: .wrongCount) ?? 0
        masteryPoints = try container.decodeIfPresent(Int.self, forKey: .masteryPoints) ?? 0
        highestMasteryLevelRaw = try container.decodeIfPresent(Int.self, forKey: .highestMasteryLevelRaw) ?? MasteryLevel(points: masteryPoints).rawValue
    }

    nonisolated var totalAttempts: Int {
        correctCount + wrongCount
    }

    nonisolated var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctCount) / Double(totalAttempts)
    }

    nonisolated var reviewPriority: Int {
        wrongCount - correctCount
    }

    nonisolated var needsReview: Bool {
        reviewPriority > 0
    }

    nonisolated var masteryLevel: MasteryLevel {
        MasteryLevel(points: masteryPoints)
    }

    nonisolated var highestMasteryLevel: MasteryLevel {
        MasteryLevel(rawValue: highestMasteryLevelRaw) ?? .one
    }

    nonisolated var masteryFloor: Int {
        highestMasteryLevel.minimumPoints ?? 0
    }

    mutating func applyMasteryDelta(_ delta: Int) {
        let updatedPoints = max(masteryFloor, masteryPoints + delta)
        masteryPoints = max(0, updatedPoints)
        highestMasteryLevelRaw = max(highestMasteryLevelRaw, MasteryLevel(points: masteryPoints).rawValue)
    }
}

enum MasteryLevel: Int, CaseIterable, Codable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    nonisolated init(points: Int) {
        switch points {
        case ..<50:
            self = .one
        case ..<125:
            self = .two
        case ..<250:
            self = .three
        case ..<400:
            self = .four
        default:
            self = .five
        }
    }

    var title: String {
        switch self {
        case .one: return "Grade I"
        case .two: return "Grade II"
        case .three: return "Grade III"
        case .four: return "Grade IV"
        case .five: return "Grade V"
        }
    }

    var symbol: String {
        switch self {
        case .one: return "I"
        case .two: return "II"
        case .three: return "III"
        case .four: return "IV"
        case .five: return "V"
        }
    }

    var pointsRange: ClosedRange<Int>? {
        switch self {
        case .one: return 0...49
        case .two: return 50...124
        case .three: return 125...249
        case .four: return 250...399
        case .five: return 400...700
        }
    }

    var nextLevel: MasteryLevel? {
        switch self {
        case .one: return .two
        case .two: return .three
        case .three: return .four
        case .four: return .five
        case .five: return nil
        }
    }

    nonisolated var minimumPoints: Int? {
        switch self {
        case .one: return 0
        case .two: return 50
        case .three: return 125
        case .four: return 250
        case .five: return 400
        }
    }
}

struct PracticeLogEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let sentence: String
    let wasCorrect: Bool
    let createdAt: Date

    init(id: UUID = UUID(), sentence: String, wasCorrect: Bool, createdAt: Date = .now) {
        self.id = id
        self.sentence = sentence
        self.wasCorrect = wasCorrect
        self.createdAt = createdAt
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
                    Text("LexiCue should call only your own backend. Your server should hold the OpenAI key, generate sentences, meanings, and hints, and return only the safe result to the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Expected Endpoints") {
                    Text("POST /generate-sentence")
                    Text("POST /explain-phrase")
                    Text("POST /define-phrase")
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

struct PracticeModesView: View {
    let savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                modeLink(
                    title: "Random Mode",
                    subtitle: "5 phrases, 2 cards each",
                    practiceMode: .random,
                    tint: .blue
                )

                modeLink(
                    title: "Search Mode",
                    subtitle: "Guess the original phrase from an italic synonym",
                    practiceMode: .search,
                    tint: .purple
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Practice Modes")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    func modeLink(title: String, subtitle: String, practiceMode: PracticeMode, tint: Color) -> some View {
        NavigationLink {
            PracticeScopePickerView(
                savedPhrases: savedPhrases,
                phraseProgress: $phraseProgress,
                practiceHistory: $practiceHistory,
                practiceMode: practiceMode
            )
        } label: {
            modeRow(title: title, subtitle: subtitle, tint: tint)
        }
        .disabled(isDisabled(practiceMode))
    }

    func modeRow(title: String, subtitle: String, tint: Color) -> some View {
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

    func isDisabled(_ mode: PracticeMode) -> Bool {
        switch mode {
        case .random, .search:
            return savedPhrases.isEmpty
        case .weakest:
            return true
        }
    }

    var weakestCandidates: [String] {
        weakestPhraseCandidates(from: savedPhrases, phraseProgress: phraseProgress)
    }
}

enum PracticePhraseScope: String, Hashable, Codable {
    case all
    case selected
    case lessPlayed
    case weakest

    var title: String {
        switch self {
        case .all:
            return "All Phrases"
        case .selected:
            return "Selected Phrases"
        case .lessPlayed:
            return "Less Played"
        case .weakest:
            return "Weakest"
        }
    }

    var cycleKeySuffix: String {
        rawValue
    }
}

struct PracticeScopePickerView: View {
    let savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]
    let practiceMode: PracticeMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    QuizView(
                        savedPhrases: savedPhrases,
                        phraseProgress: $phraseProgress,
                        practiceHistory: $practiceHistory,
                        practiceMode: practiceMode,
                        phraseScope: .all,
                        selectedPhraseKeys: []
                    )
                } label: {
                    scopeRow(
                        title: "All Phrases",
                        subtitle: "Use the full phrase collection in this mode.",
                        tint: practiceMode == .random ? .blue : .purple
                    )
                }

                NavigationLink {
                    PracticePhraseSelectionView(
                        savedPhrases: savedPhrases,
                        phraseProgress: $phraseProgress,
                        practiceHistory: $practiceHistory,
                        practiceMode: practiceMode
                    )
                } label: {
                    scopeRow(
                        title: "Selected Phrases",
                        subtitle: "Quickly flag the phrases you want to practise.",
                        tint: practiceMode == .random ? .blue : .purple
                    )
                }

                NavigationLink {
                    QuizView(
                        savedPhrases: savedPhrases,
                        phraseProgress: $phraseProgress,
                        practiceHistory: $practiceHistory,
                        practiceMode: practiceMode,
                        phraseScope: .lessPlayed,
                        selectedPhraseKeys: []
                    )
                } label: {
                    scopeRow(
                        title: "Less Played",
                        subtitle: "Prioritize phrases with fewer total attempts.",
                        tint: practiceMode == .random ? .blue : .purple
                    )
                }
                .disabled(savedPhrases.isEmpty)

                NavigationLink {
                    QuizView(
                        savedPhrases: savedPhrases,
                        phraseProgress: $phraseProgress,
                        practiceHistory: $practiceHistory,
                        practiceMode: practiceMode,
                        phraseScope: .weakest,
                        selectedPhraseKeys: []
                    )
                } label: {
                    scopeRow(
                        title: "Weakest Phrases",
                        subtitle: "Use the 5 weakest phrases, with never-played phrases first.",
                        tint: practiceMode == .random ? .blue : .purple
                    )
                }
                .disabled(weakestCandidates.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(practiceMode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    var weakestCandidates: [String] {
        weakestPhraseCandidates(from: savedPhrases, phraseProgress: phraseProgress)
    }

    func scopeRow(title: String, subtitle: String, tint: Color) -> some View {
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
}

struct PracticePhraseSelectionView: View {
    let savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]
    let practiceMode: PracticeMode

    @State private var selectedKeys: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(selectedKeys.count) selected")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Select All") {
                        selectedKeys = Set(savedPhrases.map(\.normalizedProgressKey))
                    }
                    .font(.subheadline)

                    Button("Clear") {
                        selectedKeys = []
                    }
                    .font(.subheadline)
                }

                VStack(spacing: 0) {
                    ForEach(savedPhrases, id: \.self) { phrase in
                        Button {
                            toggle(phrase)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedKeys.contains(phrase.normalizedProgressKey) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedKeys.contains(phrase.normalizedProgressKey) ? .blue : .secondary)

                                Text(phrase)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if phrase != savedPhrases.last {
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                NavigationLink {
                    QuizView(
                        savedPhrases: savedPhrases,
                        phraseProgress: $phraseProgress,
                        practiceHistory: $practiceHistory,
                        practiceMode: practiceMode,
                        phraseScope: .selected,
                        selectedPhraseKeys: Array(selectedKeys)
                    )
                } label: {
                    Text("Start Practice")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedKeys.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select Phrases")
        .navigationBarTitleDisplayMode(.inline)
    }

    func toggle(_ phrase: String) {
        let key = phrase.normalizedProgressKey
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }
}

extension String {
    nonisolated var normalizedProgressKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }
}

#Preview {
    ContentView()
}

nonisolated func weakestPhraseCandidates(from phrases: [String], phraseProgress: [String: PhraseProgress]) -> [String] {
    phrases.sorted { lhs, rhs in
        let left = phraseProgress[lhs.normalizedProgressKey] ?? PhraseProgress()
        let right = phraseProgress[rhs.normalizedProgressKey] ?? PhraseProgress()

        let leftNeverPlayed = left.totalAttempts == 0
        let rightNeverPlayed = right.totalAttempts == 0
        if leftNeverPlayed != rightNeverPlayed {
            return leftNeverPlayed
        }

        if left.successRate != right.successRate {
            return left.successRate < right.successRate
        }

        if left.totalAttempts != right.totalAttempts {
            return left.totalAttempts < right.totalAttempts
        }

        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
