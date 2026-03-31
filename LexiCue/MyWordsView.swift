import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MyWordsView: View {
    @Binding var savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var phraseDifficulties: [String: PhraseDifficulty]

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
        .toolbar {
            if !savedPhrases.isEmpty {
                EditButton()
            }
        }
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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phrase)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let progress = phraseProgress[phrase.normalizedProgressKey],
                                   progress.correctCount > 0 || progress.wrongCount > 0 {
                                    Text("Correct \(progress.correctCount) • Missed \(progress.wrongCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            DifficultyBadge(difficulty: phraseDifficulties[phrase.normalizedProgressKey])

                            if let index = savedPhrases.firstIndex(of: phrase) {
                                Button(role: .destructive) {
                                    phraseProgress.removeValue(forKey: phrase.normalizedProgressKey)
                                    phraseDifficulties.removeValue(forKey: phrase.normalizedProgressKey)
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
        phraseDifficulties = [:]
        importMessage = "All phrases deleted."
    }

    func containsPhrase(_ phrase: String) -> Bool {
        savedPhrases.contains {
            $0.compare(phrase, options: .caseInsensitive) == .orderedSame
        }
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
            phraseDifficulties: .constant([
                "laser-focused": .advanced,
                "play the hand you’re dealt": .expert
            ])
        )
    }
}

struct DifficultyBadge: View {
    let difficulty: PhraseDifficulty?

    var body: some View {
        Group {
            if let difficulty {
                Text(difficulty.shortLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(difficulty.tint)
                    .clipShape(Capsule())
                    .accessibilityLabel(difficulty.title)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Assigning difficulty")
            }
        }
        .frame(minWidth: 40, alignment: .trailing)
    }
}
