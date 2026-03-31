import SwiftUI

struct ContentView: View {
    @State private var savedPhrases: [String] = []
    @State private var phraseProgress: [String: PhraseProgress] = [:]
    @State private var phraseMeanings: [String: String] = [:]
    @State private var practiceHistory: [String: [PracticeLogEntry]] = [:]
    @State private var showAISettings = false
    @AppStorage("backendBaseURL") private var backendBaseURL = ""

    let defaultPhrases = [
        "laser-focused",
        "play the hand you’re dealt",
        "taking a massive gamble"
    ]

    var body: some View {
        NavigationStack {
            dashboardView
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
                loadPhraseMeanings()
                loadPracticeHistory()
            }
            .onChange(of: savedPhrases) { _, newValue in
                savePhrases(newValue)
                removeProgressForDeletedPhrases(using: newValue)
                removeMeaningForDeletedPhrases(using: newValue)
                removePracticeHistoryForDeletedPhrases(using: newValue)
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
            reviewLink
            manageWordsLink
        }
    }

    var practiceAllLink: some View {
        NavigationLink {
            QuizView(
                savedPhrases: savedPhrases,
                phraseProgress: $phraseProgress,
                practiceHistory: $practiceHistory,
                practiceMode: .all
            )
        } label: {
            actionRow(
                title: "Practice All",
                subtitle: "AI sessions from your saved phrase list",
                tint: .blue
            )
        }
        .disabled(savedPhrases.isEmpty)
    }

    var reviewLink: some View {
        NavigationLink {
            QuizView(
                savedPhrases: savedPhrases,
                phraseProgress: $phraseProgress,
                practiceHistory: $practiceHistory,
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
