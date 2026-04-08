import SwiftUI

struct ContentView: View {
    @State private var savedPhrases: [String] = []
    @State private var phraseProgress: [String: PhraseProgress] = [:]
    @State private var phraseMeanings: [String: String] = [:]
    @State private var practiceHistory: [String: [PracticeLogEntry]] = [:]
    @State private var showAISettings = false
    @State private var isBootstrapping = true
    @State private var bootstrapStatus = "Loading saved phrases."
    @State private var xpGainToasts: [XPGainToast] = []
    @AppStorage("backendBaseURL") private var backendBaseURL = ""
    @AppStorage("playerXP") private var playerXP = 0
    @AppStorage("highestPlayerLevelRaw") private var highestPlayerLevelRaw = PlayerLevel.one.rawValue
    private let appFont = Font.custom("Helvetica Neue", size: 17)

    let defaultPhrases = [
        "laser-focused",
        "play the hand you’re dealt",
        "taking a massive gamble"
    ]

    var body: some View {
        NavigationStack {
            rootNavigationContent
        }
    }

    var rootNavigationContent: some View {
        RootContentContainer(
            mainContent: mainContentView,
            overlayContent: AnyView(xpGainOverlay)
        )
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
        .task {
            await listenForXPGains()
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

    var mainContentView: AnyView {
        if isBootstrapping {
            return AnyView(startupLoadingView)
        } else {
            return AnyView(dashboardView)
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

    var xpGainOverlay: some View {
        ZStack {
            ForEach(xpGainToasts.indices, id: \.self) { index in
                XPGainToastView(toast: xpGainToasts[index], stackIndex: index)
            }
        }
        .padding(.top, 12)
        .animation(.easeOut(duration: 2), value: xpGainToasts)
        .allowsHitTesting(false)
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
                playerLevelSection
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

    var playerLevelSection: some View {
        let level = PlayerLevel(xp: playerXP)
        let range = level.range

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(level.rawValue)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\(playerXP) XP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let nextLevel = level.nextLevel {
                    Text("\(max(0, nextLevel.range.lowerBound - playerXP)) XP to Level \(nextLevel.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Max level reached")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: playerLevelProgressValue)
                .tint(.blue)

            HStack {
                Text("\(range.lowerBound) XP")
                Spacer()
                Text("\(range.upperBound) XP")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

    var playerLevelProgressValue: Double {
        let range = PlayerLevel(xp: playerXP).range
        let covered = min(max(playerXP, range.lowerBound), range.upperBound) - range.lowerBound
        let span = max(1, range.upperBound - range.lowerBound)
        return Double(covered) / Double(span)
    }

    @MainActor
    func bootstrapIfNeeded() async {
        guard isBootstrapping else { return }

        await showBootstrapStep("Waking up your study space.")
        let phrases = await loadSavedPhrases()

        await showBootstrapStep("Bringing your phrase list into place.")
        let progress = await loadStoredPhraseProgress()

        await showBootstrapStep("Restoring your mastery progress.")
        let meanings = await loadStoredPhraseMeanings()

        await showBootstrapStep("Preparing meanings and notes.")
        let history = await loadStoredPracticeHistory()

        await showBootstrapStep("Collecting your recent practice moments.")
        await showBootstrapStep("Getting the first screen ready.")

        savedPhrases = phrases
        phraseProgress = progress
        phraseMeanings = meanings
        practiceHistory = history
        highestPlayerLevelRaw = max(highestPlayerLevelRaw, PlayerLevel(xp: playerXP).rawValue)
        isBootstrapping = false
    }

    @MainActor
    func showBootstrapStep(_ message: String) async {
        bootstrapStatus = message
        try? await Task.sleep(for: .milliseconds(220))
    }

    @MainActor
    func listenForXPGains() async {
        for await notification in NotificationCenter.default.notifications(named: .didGainXP) {
            guard let amount = notification.object as? Int, amount > 0 else { continue }
            showXPGainToast(amount: amount)
        }
    }

    @MainActor
    func showXPGainToast(amount: Int) {
        let toast = XPGainToast(amount: amount)
        xpGainToasts.append(toast)

        Task { @MainActor in
            guard let index = xpGainToasts.firstIndex(where: { $0.id == toast.id }) else { return }
            xpGainToasts[index].isAnimating = true

            try? await Task.sleep(for: .seconds(2))
            xpGainToasts.removeAll { $0.id == toast.id }
        }
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

struct XPGainToast: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
    var isAnimating = false
}

struct XPGainToastView: View {
    let toast: XPGainToast
    let stackIndex: Int

    var body: some View {
        Text("+\(toast.amount) XP")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(y: toast.isAnimating ? animatedOffset : initialOffset)
            .opacity(toast.isAnimating ? 0 : 1)
    }

    private var initialOffset: CGFloat {
        CGFloat(-10 - (stackIndex * 12))
    }

    private var animatedOffset: CGFloat {
        CGFloat(-60 - (stackIndex * 12))
    }
}

struct RootContentContainer: View {
    let mainContent: AnyView
    let overlayContent: AnyView

    var body: some View {
        ZStack(alignment: .top) {
            mainContent
            overlayContent
        }
    }
}

enum PlayerLevel: Int, CaseIterable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case eleven = 11
    case twelve = 12
    case thirteen = 13
    case fourteen = 14
    case fifteen = 15
    case sixteen = 16
    case seventeen = 17
    case eighteen = 18
    case nineteen = 19
    case twenty = 20
    case twentyOne = 21
    case twentyTwo = 22
    case twentyThree = 23
    case twentyFour = 24
    case twentyFive = 25
    case twentySix = 26
    case twentySeven = 27
    case twentyEight = 28
    case twentyNine = 29
    case thirty = 30
    case thirtyOne = 31
    case thirtyTwo = 32
    case thirtyThree = 33
    case thirtyFour = 34
    case thirtyFive = 35
    case thirtySix = 36
    case thirtySeven = 37
    case thirtyEight = 38
    case thirtyNine = 39
    case forty = 40

    init(xp: Int) {
        self = Self.allCases.first(where: { xp <= $0.range.upperBound }) ?? .forty
    }

    var range: ClosedRange<Int> {
        switch self {
        case .one: return 0...100
        case .two: return 101...235
        case .three: return 236...436
        case .four: return 437...704
        case .five: return 705...1039
        case .six: return 1040...1440
        case .seven: return 1441...1908
        case .eight: return 1909...2443
        case .nine: return 2444...3044
        case .ten: return 3045...3712
        case .eleven: return 3713...4447
        case .twelve: return 4448...5248
        case .thirteen: return 5249...6116
        case .fourteen: return 6117...7051
        case .fifteen: return 7052...8052
        case .sixteen: return 8053...9120
        case .seventeen: return 9121...10255
        case .eighteen: return 10256...11456
        case .nineteen: return 11457...12724
        case .twenty: return 12725...14059
        case .twentyOne: return 14060...15460
        case .twentyTwo: return 15461...16928
        case .twentyThree: return 16929...18463
        case .twentyFour: return 18464...20064
        case .twentyFive: return 20065...21732
        case .twentySix: return 21733...23467
        case .twentySeven: return 23468...25268
        case .twentyEight: return 25269...27136
        case .twentyNine: return 27137...29071
        case .thirty: return 29072...31072
        case .thirtyOne: return 31073...33140
        case .thirtyTwo: return 33141...35275
        case .thirtyThree: return 35276...37476
        case .thirtyFour: return 37477...39744
        case .thirtyFive: return 39745...42079
        case .thirtySix: return 42080...44480
        case .thirtySeven: return 44481...46948
        case .thirtyEight: return 46949...49483
        case .thirtyNine: return 49484...52084
        case .forty: return 52085...54752
        }
    }

    var nextLevel: PlayerLevel? {
        PlayerLevel(rawValue: rawValue + 1)
    }
}

enum PlayerXPManager {
    static let xpKey = "playerXP"
    static let highestLevelKey = "highestPlayerLevelRaw"
    static let additionGainDateKey = "dailyAdditionXPDate"
    static let additionGainAmountKey = "dailyAdditionXPGained"

    static func currentXP() -> Int {
        UserDefaults.standard.integer(forKey: xpKey)
    }

    static func currentLevel() -> PlayerLevel {
        PlayerLevel(xp: currentXP())
    }

    static func highestReachedLevelRaw() -> Int {
        max(
            UserDefaults.standard.integer(forKey: highestLevelKey),
            PlayerLevel(xp: currentXP()).rawValue
        )
    }

    static func applySessionXPReward(masteryPoints: Int, successRate: Double) -> Int {
        let effectiveMasteryPoints = max(0, masteryPoints)
        guard effectiveMasteryPoints > 0, successRate > 0 else { return 0 }

        let reward = Int(ceil((Double(effectiveMasteryPoints) * (successRate * 100)) / 200))
        guard reward > 0 else { return 0 }
        applyXPGain(reward)
        return reward
    }

    static func applyPhraseAdditionXP(for phrase: String) -> Int {
        resetDailyAdditionIfNeeded()

        let level = currentLevel()
        let dailyLimit = 50 + (level.rawValue * 10)
        let gainedToday = UserDefaults.standard.integer(forKey: additionGainAmountKey)
        let remaining = max(0, dailyLimit - gainedToday)
        guard remaining > 0 else { return 0 }

        let reward = min(remaining, phraseXPValue(for: phrase))
        guard reward > 0 else { return 0 }

        applyXPGain(reward)
        UserDefaults.standard.set(gainedToday + reward, forKey: additionGainAmountKey)
        UserDefaults.standard.set(currentDayStamp(), forKey: additionGainDateKey)
        return reward
    }

    static func applyPhraseDeletionXPRemoval(for phrase: String) -> Int {
        let removal = phraseXPValue(for: phrase)
        guard removal > 0 else { return 0 }

        let currentXP = currentXP()
        let highestLevel = PlayerLevel(rawValue: highestReachedLevelRaw()) ?? .one
        let floorXP = highestLevel.range.lowerBound
        let updatedXP = max(floorXP, currentXP - removal)
        UserDefaults.standard.set(updatedXP, forKey: xpKey)
        UserDefaults.standard.set(highestReachedLevelRaw(), forKey: highestLevelKey)
        return currentXP - updatedXP
    }

    static func phraseXPValue(for phrase: String) -> Int {
        let wordCount = phrase.split(whereSeparator: \.isWhitespace).count
        return max(0, wordCount * 2)
    }

    private static func applyXPGain(_ gain: Int) {
        let currentXP = currentXP()
        let updatedXP = currentXP + gain
        UserDefaults.standard.set(updatedXP, forKey: xpKey)
        let highestRaw = max(highestReachedLevelRaw(), PlayerLevel(xp: updatedXP).rawValue)
        UserDefaults.standard.set(highestRaw, forKey: highestLevelKey)
        NotificationCenter.default.post(name: .didGainXP, object: gain)
    }

    private static func resetDailyAdditionIfNeeded() {
        let today = currentDayStamp()
        let storedDay = UserDefaults.standard.string(forKey: additionGainDateKey)
        if storedDay != today {
            UserDefaults.standard.set(today, forKey: additionGainDateKey)
            UserDefaults.standard.set(0, forKey: additionGainAmountKey)
        }
    }

    private static func currentDayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

extension Notification.Name {
    static let didGainXP = Notification.Name("didGainXP")
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
    phrases
        .filter {
            let progress = phraseProgress[$0.normalizedProgressKey] ?? PhraseProgress()
            return progress.totalAttempts > 2
        }
        .sorted { lhs, rhs in
        let left = phraseProgress[lhs.normalizedProgressKey] ?? PhraseProgress()
        let right = phraseProgress[rhs.normalizedProgressKey] ?? PhraseProgress()

        if left.successRate != right.successRate {
            return left.successRate < right.successRate
        }

        if left.totalAttempts != right.totalAttempts {
            return left.totalAttempts < right.totalAttempts
        }

        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
