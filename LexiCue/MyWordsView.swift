import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MyWordsView: View {
    @Binding var savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var phraseMeanings: [String: String]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]

    @State private var newPhrase = ""
    @State private var pastedPhrases = ""
    @State private var importMessage = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case singlePhrase
        case pastedList
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                addSinglePhraseSection
                importSection
                savedPhrasesSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Phrases")
        .navigationBarTitleDisplayMode(.inline)
    }

    var addSinglePhraseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add one word or phrase")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("Enter a phrase", text: $newPhrase)
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .singlePhrase)
                .submitLabel(.done)
                .onSubmit {
                    addPhrase()
                }

            Button("Add Phrase") {
                addPhrase()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from pasted list")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Paste one word or phrase per line, then import the whole list.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $pastedPhrases)
                .frame(minHeight: 180)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .pastedList)

            if !importMessage.isEmpty {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Paste Clipboard") {
                    pasteFromClipboard()
                }
                .buttonStyle(.bordered)

                Button("Import Lines") {
                    importPhrases()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedPhrases.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    var savedPhrasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved phrases (\(savedPhrases.count))")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if !savedPhrases.isEmpty {
                    Button("Delete All") {
                        deleteAllPhrases()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }

            if savedPhrases.isEmpty {
                Text("No phrases yet. Add one manually or paste a list above.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(savedPhrases, id: \.self) { phrase in
                        let progress = phraseProgress[phrase.normalizedProgressKey] ?? PhraseProgress()

                        HStack(spacing: 12) {
                            NavigationLink {
                                PhraseEncyclopediaView(
                                    phrase: phrase,
                                    phraseMeanings: $phraseMeanings,
                                    practiceHistory: $practiceHistory
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(phrase)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .foregroundStyle(.primary)

                                        HStack(spacing: 8) {
                                            AttemptCountBadge(value: progress.correctCount, tint: .green)
                                            AttemptCountBadge(value: progress.wrongCount, tint: .red)
                                        }
                                    }

                                    SuccessRateBadge(progress: progress)
                                }
                            }
                            .buttonStyle(.plain)

                            if let index = savedPhrases.firstIndex(of: phrase) {
                                Button(role: .destructive) {
                                    phraseProgress.removeValue(forKey: phrase.normalizedProgressKey)
                                    phraseMeanings.removeValue(forKey: phrase.normalizedProgressKey)
                                    practiceHistory.removeValue(forKey: phrase.normalizedProgressKey)
                                    savedPhrases.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if phrase != savedPhrases.last {
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

    func addPhrase() {
        let cleaned = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if !containsPhrase(cleaned) {
            savedPhrases.append(cleaned)
            importMessage = "Added 1 phrase."
        } else {
            importMessage = "That phrase is already saved."
        }

        newPhrase = ""
        focusedField = .singlePhrase
    }

    func importPhrases() {
        let lines = pastedPhrases
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var importedCount = 0
        for line in lines {
            if !containsPhrase(line) {
                savedPhrases.append(line)
                importedCount += 1
            }
        }

        importMessage = importedCount == 0
            ? "No new phrases were imported."
            : "Imported \(importedCount) phrase\(importedCount == 1 ? "" : "s")."
        pastedPhrases = ""
        focusedField = nil
    }

    func pasteFromClipboard() {
        #if canImport(UIKit)
        pastedPhrases = UIPasteboard.general.string ?? ""
        importMessage = pastedPhrases.isEmpty ? "Clipboard is empty." : "Clipboard pasted. Tap Import Lines."
        focusedField = .pastedList
        #endif
    }

    func deleteAllPhrases() {
        savedPhrases = []
        phraseProgress = [:]
        phraseMeanings = [:]
        practiceHistory = [:]
        importMessage = "All phrases deleted."
    }

    func containsPhrase(_ phrase: String) -> Bool {
        savedPhrases.contains {
            $0.compare(phrase, options: .caseInsensitive) == .orderedSame
        }
    }
}

struct PhraseEncyclopediaView: View {
    let phrase: String
    @Binding var phraseMeanings: [String: String]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]

    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var isLoadingMeaning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(phrase)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Meaning")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if isLoadingMeaning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading full meaning...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(storedMeaning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 20 completed sentences")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if recentHistory.isEmpty {
                        Text("No completed practice cards yet.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recentHistory) { entry in
                                Text(entry.sentence)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(entry.wasCorrect ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Encyclopedia")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMeaningIfNeeded()
        }
    }

    var storedMeaning: String {
        phraseMeanings[phrase.normalizedProgressKey] ?? "Meaning not loaded yet."
    }

    var recentHistory: [PracticeLogEntry] {
        let entries = practiceHistory[phrase.normalizedProgressKey] ?? []
        return Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(20))
    }

    func loadMeaningIfNeeded() async {
        let key = phrase.normalizedProgressKey
        guard phraseMeanings[key] == nil else { return }

        let configuration = BackendConfiguration(baseURLString: backendBaseURL)
        guard configuration.isValid else { return }

        isLoadingMeaning = true
        defer { isLoadingMeaning = false }

        if let meaning = try? await BackendAIService.shared.fullMeaning(for: phrase, configuration: configuration) {
            phraseMeanings[key] = meaning
        }
    }
}

struct AttemptCountBadge: View {
    let value: Int
    let tint: Color

    var body: some View {
        Text("\(value)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tint)
            .clipShape(Circle())
    }
}

struct SuccessRateBadge: View {
    let progress: PhraseProgress

    var body: some View {
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

#Preview {
    NavigationStack {
        MyWordsView(
            savedPhrases: .constant([
                "laser-focused",
                "play the hand you’re dealt",
                "taking a massive gamble"
            ]),
            phraseProgress: .constant([
                "laser-focused": PhraseProgress(correctCount: 3, wrongCount: 1)
            ]),
            phraseMeanings: .constant([
                "laser-focused": "Extremely concentrated on a single task or goal."
            ]),
            practiceHistory: .constant([
                "laser-focused": [
                    PracticeLogEntry(sentence: "She stayed laser-focused during the pitch.", wasCorrect: true)
                ]
            ])
        )
    }
}
