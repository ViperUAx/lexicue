import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

struct MyWordsView: View {
    @Binding var savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var phraseMeanings: [String: String]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]
    @AppStorage("backendBaseURL") private var backendBaseURL = ""

    @State private var pastedPhrases = ""
    @State private var importMessage = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedPhotoData: Data?
    @State private var pendingPhotoData: Data?
    @State private var photoRecognitionRule = "Phrases are on the left side and shown one per line."
    @State private var recognizedPhotoPhrases: [String] = []
    @State private var selectedRecognizedPhrases = Set<String>()
    @State private var isImportingPhoto = false
    @State private var showCamera = false
    @State private var showPhotoImportRules = false
    @State private var showRecognizedPhrasePicker = false
    @FocusState private var focusedField: Field?
    private let appFont = Font.custom("Helvetica Neue", size: 17)

    enum Field {
        case pastedList
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                importSection
                savedPhrasesSection
            }
            .padding()
        }
        .environment(\.font, appFont)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Phrases")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedPhotoItem) {
            await loadSelectedPhotoForRuleEntry()
        }
        .task(id: capturedPhotoData) {
            await loadCapturedPhotoForRuleEntry()
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView(imageData: $capturedPhotoData)
        }
        .sheet(isPresented: $showPhotoImportRules) {
            PhotoImportRuleSheet(
                imageData: pendingPhotoData,
                rule: $photoRecognitionRule,
                isImporting: isImportingPhoto,
                onCancel: {
                    pendingPhotoData = nil
                    recognizedPhotoPhrases = []
                    selectedRecognizedPhrases = []
                    showPhotoImportRules = false
                },
                onStartImport: {
                    Task {
                        await recognizePhrasesFromPendingPhoto()
                    }
                }
            )
        }
        .sheet(isPresented: $showRecognizedPhrasePicker) {
            RecognizedPhrasePickerSheet(
                phrases: recognizedPhotoPhrases,
                selectedPhrases: $selectedRecognizedPhrases,
                onCancel: {
                    recognizedPhotoPhrases = []
                    selectedRecognizedPhrases = []
                    pendingPhotoData = nil
                    showRecognizedPhrasePicker = false
                },
                onImport: {
                    importSelectedRecognizedPhrases()
                }
            )
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

            #if canImport(PhotosUI)
            VStack(alignment: .leading, spacing: 10) {
                Text("Photo recognition reads phrase-like text from a notebook or highlighted page. It works best when phrases are clearly separated by lines, shown on the left side, or visibly marked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Import From Library", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImportingPhoto)

                    #if canImport(UIKit)
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImportingPhoto || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    #endif

                    if isImportingPhoto {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning photo for phrases...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #endif
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

            if !savedPhrases.isEmpty {
                Text("Tap any phrase to open its encyclopedia with detailed success stats and phrase history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                                    savedPhrases: $savedPhrases,
                                    phraseProgress: $phraseProgress,
                                    phraseMeanings: $phraseMeanings,
                                    practiceHistory: $practiceHistory
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Text(phrase)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundStyle(.primary)

                                    CompactMasteryProgressView(progress: progress)
                                }
                            }
                            .buttonStyle(.plain)

                            ProgressView(value: compactMasteryProgressValue(for: progress))
                                .tint(compactMasteryProgressColor(for: progress))
                                .frame(width: 92)
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

    func loadSelectedPhotoForRuleEntry() async {
        guard let selectedPhotoItem else { return }

        isImportingPhoto = true
        defer {
            isImportingPhoto = false
            self.selectedPhotoItem = nil
        }

        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self) else {
                importMessage = "Could not load the selected image."
                return
            }
            pendingPhotoData = data
            photoRecognitionRule = "Phrases are on the left side and shown one per line."
            showPhotoImportRules = true
        } catch {
            importMessage = "Could not load the selected image."
        }
    }

    func loadCapturedPhotoForRuleEntry() async {
        guard let capturedPhotoData else { return }
        pendingPhotoData = capturedPhotoData
        photoRecognitionRule = "Phrases are on the left side and shown one per line."
        self.capturedPhotoData = nil
        showPhotoImportRules = true
    }

    func recognizePhrasesFromPendingPhoto() async {
        guard let pendingPhotoData else { return }

        isImportingPhoto = true
        defer { isImportingPhoto = false }

        do {
            let extracted = try await extractPhrasesForPhotoImport(from: pendingPhotoData)
            recognizedPhotoPhrases = extracted
            selectedRecognizedPhrases = Set(extracted)
            showPhotoImportRules = false
            if extracted.isEmpty {
                importMessage = "No new phrases were recognized from the photo."
                self.pendingPhotoData = nil
            } else {
                showRecognizedPhrasePicker = true
            }
        } catch {
            importMessage = "Photo import failed. Try a clearer image and adjust the recognition rule."
        }
    }

    func extractPhrasesForPhotoImport(from imageData: Data) async throws -> [String] {
        let configuration = BackendConfiguration(baseURLString: backendBaseURL)
        if configuration.isValid {
            let preparedData = preparePhotoForUpload(imageData)
            let extracted = try await BackendAIService.shared.extractPhotoPhrases(
                imageData: preparedData,
                rule: photoRecognitionRule,
                configuration: configuration
            )
            return extracted
        }

        return try await PhotoPhraseRecognizer.extractPhrases(
            from: imageData,
            rule: photoRecognitionRule
        )
    }

    func importSelectedRecognizedPhrases() {
        let selected = recognizedPhotoPhrases.filter { selectedRecognizedPhrases.contains($0) }
        let importedCount = mergeImportedPhrases(selected)
        importMessage = importedCount == 0
            ? "No new phrases were imported from the recognized list."
            : "Imported \(importedCount) phrase\(importedCount == 1 ? "" : "s") from the recognized list."
        pendingPhotoData = nil
        recognizedPhotoPhrases = []
        selectedRecognizedPhrases = []
        showRecognizedPhrasePicker = false
    }

    func mergeImportedPhrases(_ phrases: [String]) -> Int {
        var importedCount = 0
        for phrase in phrases where !containsPhrase(phrase) {
            savedPhrases.append(phrase)
            importedCount += 1
        }
        return importedCount
    }

    func deleteAllPhrases() {
        savedPhrases = []
        phraseProgress = [:]
        phraseMeanings = [:]
        practiceHistory = [:]
        importMessage = "All phrases deleted."
    }

    func containsPhrase(_ phrase: String) -> Bool {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines).normalizedProgressKey
        return savedPhrases.contains { $0.normalizedProgressKey == normalizedPhrase }
    }

    func compactMasteryProgressValue(for progress: PhraseProgress) -> Double {
        guard let range = progress.masteryLevel.pointsRange else { return 1 }
        let clampedPoints = min(max(progress.masteryPoints, range.lowerBound), range.upperBound)
        let covered = clampedPoints - range.lowerBound
        let span = max(1, range.upperBound - range.lowerBound)
        return Double(covered) / Double(span)
    }

    func compactMasteryProgressColor(for progress: PhraseProgress) -> Color {
        switch progress.masteryLevel {
        case .one: return .gray
        case .two: return .blue
        case .three: return .orange
        case .four: return .purple
        case .five: return .pink
        }
    }

    func preparePhotoForUpload(_ imageData: Data) -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else { return imageData }
        let maxDimension: CGFloat = 1600
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(longestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: 0.75) ?? imageData
        #else
        return imageData
        #endif
    }
}

struct PhraseEncyclopediaView: View {
    let phrase: String
    @Binding var savedPhrases: [String]
    @Binding var phraseProgress: [String: PhraseProgress]
    @Binding var phraseMeanings: [String: String]
    @Binding var practiceHistory: [String: [PracticeLogEntry]]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @State private var isLoadingMeaning = false
    private let appFont = Font.custom("Helvetica Neue", size: 17)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(phrase)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mastery Grade")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        MasteryLevelBadge(level: currentProgress.masteryLevel)

                        VStack(spacing: 4) {
                            Text(currentProgress.masteryLevel.title)
                                .font(.headline)
                            Text("\(currentProgress.masteryPoints) mastery points")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: masteryProgressValue)
                                .tint(masteryProgressColor)

                            HStack {
                                Text(masteryProgressLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(masteryProgressTrailingLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Success Stats")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        AttemptCountBadge(value: currentProgress.correctCount, tint: .green)
                        Text("Correct")
                            .foregroundStyle(.secondary)

                        AttemptCountBadge(value: currentProgress.wrongCount, tint: .red)
                        Text("Missed")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("Success rate")
                            .foregroundStyle(.secondary)
                        Text(successRateText)
                            .fontWeight(.semibold)
                            .foregroundStyle(successRateColor)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

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
                    Text("Last 3 played cards")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if recentHistory.isEmpty {
                        Text("No played cards yet.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recentHistory) { entry in
                                Text(highlightedSentence(entry.sentence))
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
        .environment(\.font, appFont)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Encyclopedia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    deletePhrase()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task {
            await loadMeaningIfNeeded()
        }
    }

    var storedMeaning: String {
        phraseMeanings[phrase.normalizedProgressKey] ?? "Meaning not loaded yet."
    }

    var currentProgress: PhraseProgress {
        phraseProgress[phrase.normalizedProgressKey] ?? PhraseProgress()
    }

    var successRateText: String {
        guard currentProgress.totalAttempts > 0 else { return "—" }
        return "\(Int((currentProgress.successRate * 100).rounded()))%"
    }

    var successRateColor: Color {
        guard currentProgress.totalAttempts > 0 else { return .secondary }
        return currentProgress.successRate >= 0.5 ? .green : .red
    }

    var recentHistory: [PracticeLogEntry] {
        let entries = practiceHistory[phrase.normalizedProgressKey] ?? []
        return Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

    var masteryProgressValue: Double {
        guard let range = currentProgress.masteryLevel.pointsRange else { return 1 }
        let clampedPoints = min(max(currentProgress.masteryPoints, range.lowerBound), range.upperBound)
        let covered = clampedPoints - range.lowerBound
        let span = max(1, range.upperBound - range.lowerBound)
        return Double(covered) / Double(span)
    }

    var masteryProgressLabel: String {
        guard let nextLevel = currentProgress.masteryLevel.nextLevel else {
            return "Maximum mastery reached"
        }
        return "Progress to \(nextLevel.title)"
    }

    var masteryProgressTrailingLabel: String {
        guard let nextLevel = currentProgress.masteryLevel.nextLevel,
              let nextThreshold = nextLevel.minimumPoints else {
            return "Complete"
        }
        let remaining = max(0, nextThreshold - currentProgress.masteryPoints)
        return "\(remaining) pts left"
    }

    var masteryProgressColor: Color {
        switch currentProgress.masteryLevel {
        case .one: return .gray
        case .two: return .blue
        case .three: return .orange
        case .four: return .purple
        case .five: return .pink
        }
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

    func highlightedSentence(_ sentence: String) -> AttributedString {
        var attributed = AttributedString(sentence)
        let escapedPhrase = NSRegularExpression.escapedPattern(for: phrase)

        guard
            let regex = try? NSRegularExpression(pattern: escapedPhrase, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
            let range = Range(match.range, in: sentence),
            let attributedRange = Range(range, in: attributed)
        else {
            return attributed
        }

        attributed[attributedRange].font = .body.bold()
        return attributed
    }

    func deletePhrase() {
        let key = phrase.normalizedProgressKey
        savedPhrases.removeAll { $0.normalizedProgressKey == key }
        phraseProgress.removeValue(forKey: key)
        phraseMeanings.removeValue(forKey: key)
        practiceHistory.removeValue(forKey: key)
        dismiss()
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

struct MasteryLevelBadge: View {
    let level: MasteryLevel

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(named: assetName)?.removingWhiteBackground() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            }
            #else
            Image(assetName)
                .resizable()
                .scaledToFit()
            #endif
        }
        .frame(width: 104, height: 104)
    }

    var assetName: String {
        switch level {
        case .one:
            return "mastery_I_cropped"
        case .two:
            return "mastery_II_cropped"
        case .three:
            return "mastery_III_cropped"
        case .four:
            return "mastery_IV_cropped"
        case .five:
            return "mastery_V_cropped"
        }
    }
}

struct CompactMasteryProgressView: View {
    let progress: PhraseProgress

    var body: some View {
        VStack(spacing: 0) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
        }
        .frame(width: 60)
    }

    var assetName: String {
        switch progress.masteryLevel {
        case .one:
            return "mastery_I_cropped"
        case .two:
            return "mastery_II_cropped"
        case .three:
            return "mastery_III_cropped"
        case .four:
            return "mastery_IV_cropped"
        case .five:
            return "mastery_V_cropped"
        }
    }
}

#if canImport(UIKit)
private extension UIImage {
    func removingWhiteBackground(threshold: UInt8 = 235) -> UIImage? {
        guard let cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isNearWhite(_ pixelIndex: Int) -> Bool {
            let red = pixels[pixelIndex]
            let green = pixels[pixelIndex + 1]
            let blue = pixels[pixelIndex + 2]
            return red >= threshold && green >= threshold && blue >= threshold
        }

        var queue: [Int] = []
        var visited = Set<Int>()

        func enqueueIfNeeded(x: Int, y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let pixelNumber = y * width + x
            guard !visited.contains(pixelNumber) else { return }
            let pixelIndex = pixelNumber * bytesPerPixel
            guard isNearWhite(pixelIndex) else { return }
            visited.insert(pixelNumber)
            queue.append(pixelNumber)
        }

        for x in 0..<width {
            enqueueIfNeeded(x: x, y: 0)
            enqueueIfNeeded(x: x, y: height - 1)
        }

        for y in 0..<height {
            enqueueIfNeeded(x: 0, y: y)
            enqueueIfNeeded(x: width - 1, y: y)
        }

        while !queue.isEmpty {
            let pixelNumber = queue.removeFirst()
            let x = pixelNumber % width
            let y = pixelNumber / width
            let pixelIndex = pixelNumber * bytesPerPixel
            pixels[pixelIndex + 3] = 0

            enqueueIfNeeded(x: x - 1, y: y)
            enqueueIfNeeded(x: x + 1, y: y)
            enqueueIfNeeded(x: x, y: y - 1)
            enqueueIfNeeded(x: x, y: y + 1)
        }

        guard let outputCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCGImage, scale: scale, orientation: imageOrientation)
    }
}
#endif

#if canImport(Vision) && canImport(UIKit)
enum PhotoPhraseRecognizer {
    static func extractPhrases(from imageData: Data, rule: String) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
                throw PhotoImportError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = (request.results ?? []).compactMap { observation -> RecognizedPhraseCandidate? in
                guard let top = observation.topCandidates(1).first else { return nil }
                let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isLikelyPhrase(text) else { return nil }
                return RecognizedPhraseCandidate(
                    text: text,
                    minX: observation.boundingBox.minX,
                    maxX: observation.boundingBox.maxX,
                    minY: observation.boundingBox.minY,
                    maxY: observation.boundingBox.maxY
                )
            }

            let filtered = applyRecognitionRule(rule, to: observations)

            let sorted = filtered.sorted {
                if abs($0.maxY - $1.maxY) > 0.03 {
                    return $0.maxY > $1.maxY
                }
                if abs($0.minX - $1.minX) > 0.03 {
                    return $0.minX < $1.minX
                }
                return $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending
            }

            var seen = Set<String>()
            var phrases: [String] = []
            for candidate in sorted {
                let normalized = candidate.text.normalizedProgressKey
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                phrases.append(candidate.text)
            }

            return phrases
        }.value
    }

    fileprivate nonisolated static func applyRecognitionRule(_ rule: String, to candidates: [RecognizedPhraseCandidate]) -> [RecognizedPhraseCandidate] {
        let normalizedRule = rule.lowercased()
        var filtered = candidates

        if normalizedRule.contains("left") {
            let leftHalf = filtered.filter { $0.maxX <= 0.6 || $0.minX <= 0.4 }
            if !leftHalf.isEmpty { filtered = leftHalf }
        }

        if normalizedRule.contains("right") {
            let rightHalf = filtered.filter { $0.minX >= 0.4 }
            if !rightHalf.isEmpty { filtered = rightHalf }
        }

        if normalizedRule.contains("top") {
            let topHalf = filtered.filter { $0.minY >= 0.35 }
            if !topHalf.isEmpty { filtered = topHalf }
        }

        if normalizedRule.contains("bottom") {
            let bottomHalf = filtered.filter { $0.maxY <= 0.65 }
            if !bottomHalf.isEmpty { filtered = bottomHalf }
        }

        return filtered
    }

    nonisolated static func isLikelyPhrase(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...8).contains(words.count) else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        let punctuationOnly = CharacterSet(charactersIn: ".,:;!?-_()[]{}\"'")
        return trimmed.unicodeScalars.contains { !punctuationOnly.contains($0) && CharacterSet.letters.contains($0) }
    }
}

private struct RecognizedPhraseCandidate {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
}

enum PhotoImportError: Error {
    case invalidImage
}
#endif

#if canImport(UIKit)
struct PhotoImportRuleSheet: View {
    let imageData: Data?
    @Binding var rule: String
    let isImporting: Bool
    let onCancel: () -> Void
    let onStartImport: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recognition rule")
                            .font(.headline)
                        Text("Describe how your phrases appear in the photo. Example: phrases are on the left side, one phrase per line, or highlighted in the text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $rule)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isImporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Recognizing phrases using your rule...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Recognize", action: onStartImport)
                        .disabled(isImporting || rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct RecognizedPhrasePickerSheet: View {
    let phrases: [String]
    @Binding var selectedPhrases: Set<String>
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the recognized phrases you really want to add. Uncheck anything that was identified incorrectly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(phrases, id: \.self) { phrase in
                        Button {
                            toggleSelection(for: phrase)
                        } label: {
                            HStack {
                                Image(systemName: selectedPhrases.contains(phrase) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedPhrases.contains(phrase) ? .blue : .secondary)
                                Text(phrase)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Recognized Phrases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", action: onImport)
                        .disabled(selectedPhrases.isEmpty)
                }
            }
        }
    }

    private func toggleSelection(for phrase: String) {
        if selectedPhrases.contains(phrase) {
            selectedPhrases.remove(phrase)
        } else {
            selectedPhrases.insert(phrase)
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var imageData: Data?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(imageData: $imageData, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var imageData: Data?
        private let dismiss: DismissAction

        init(imageData: Binding<Data?>, dismiss: DismissAction) {
            _imageData = imageData
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                imageData = image.jpegData(compressionQuality: 0.9)
            }
            dismiss()
        }
    }
}
#endif

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
