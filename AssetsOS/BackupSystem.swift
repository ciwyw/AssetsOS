import Foundation
import Observation
import SwiftData
import UserNotifications

struct BackupPreview: Codable, Equatable, Identifiable {
    let exportedAt: Date
    let accountCount: Int
    let assetCount: Int
    let fixedTermCount: Int
    let schemaVersion: Int

    var id: String {
        "\(schemaVersion)-\(exportedAt.timeIntervalSince1970)-\(accountCount)-\(assetCount)-\(fixedTermCount)"
    }
}

enum BackupState {
    case normal
    case unconfigured
    case failed(String)
    case awaitingExistingBackup(BackupPreview)

    var isAwaitingExistingBackup: Bool {
        if case .awaitingExistingBackup = self { return true }
        return false
    }
}

fileprivate struct BackupArchive: Codable {
    let schemaVersion: Int
    let exportedAt: String
    let accounts: [BackupAccount]
    let assets: [BackupAsset]
}

fileprivate struct BackupAccount: Codable {
    let id: String
    let name: String
    let categoryRaw: String
    let note: String?
    let boundBankAccountID: String?
    let shAAccountCode: String?
    let szAAccountCode: String?
    let createdAt: String
    let updatedAt: String
    let closedAt: String?
}

fileprivate struct BackupAsset: Codable {
    let id: String
    let accountID: String
    let kindRaw: String
    let balanceSideRaw: String
    let name: String
    let note: String?
    let currentAmount: String
    let cashAvailabilityRaw: String?
    let totalInvested: String
    let totalWithdrawn: String
    let lockEndDate: String?
    let principal: String
    let annualRate: String
    let startDate: String?
    let maturityDate: String?
    let fundingModeRaw: String?
    let sourceCashAssetID: String?
    let settledAmount: String?
    let settledAt: String?
    let createdAt: String
    let updatedAt: String
    let closedAt: String?
}

enum TermNotificationManager {
    private static var canUseNotificationCenter: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        guard canUseNotificationCenter else { return .notDetermined }
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func requestIfNeeded() async -> UNAuthorizationStatus {
        guard canUseNotificationCenter else { return .notDetermined }
        let status = await refreshAuthorizationStatus()
        guard status == .notDetermined else { return status }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted ? .authorized : await refreshAuthorizationStatus()
    }

    static func cancelAll() async {
        guard canUseNotificationCenter else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    static func cancel(for assetID: UUID) {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers(for: assetID)
        )
    }

    static func schedule(for asset: Asset) async {
        guard canUseNotificationCenter else { return }
        guard asset.kind == .fixedTerm, asset.lifecycle != .settled, let maturityDate = asset.maturityDate else {
            cancel(for: asset.id)
            return
        }
        let validReminders: [(index: Int, fireDate: Date, subtitle: String)] = [
            (0, DateKit.notificationDate(for: DateKit.adding(days: -3, to: maturityDate)), "还有 3 天到期"),
            (1, DateKit.notificationDate(for: maturityDate), "今天到期")
        ].filter { $0.fireDate > Date() }

        cancel(for: asset.id)
        guard !validReminders.isEmpty else { return }

        let status = await requestIfNeeded()
        guard allowsScheduling(for: status) else { return }

        let center = UNUserNotificationCenter.current()
        for reminder in validReminders {
            let components = DateKit.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let content = UNMutableNotificationContent()
            content.title = asset.name
            content.subtitle = "\(asset.account?.name ?? "") · \(reminder.subtitle)"
            content.body = "请检查是否需要结清。V1 不会自动到账。"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifiers(for: asset.id)[reminder.index],
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    static func rescheduleAll(assets: [Asset]) async {
        await cancelAll()
        for asset in assets where asset.kind == .fixedTerm && asset.lifecycle != .settled {
            await schedule(for: asset)
        }
    }

    private static func identifiers(for assetID: UUID) -> [String] {
        ["fixed-term-\(assetID.uuidString)-three-days", "fixed-term-\(assetID.uuidString)-due-day"]
    }

    private static func allowsScheduling(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            return true
#if os(iOS)
        case .ephemeral:
            return true
#endif
        default:
            return false
        }
    }
}

enum BackupCodec {
    static let schemaVersion = 2

    fileprivate static func archive(from context: ModelContext) throws -> BackupArchive {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let assets = try context.fetch(FetchDescriptor<Asset>())

        return BackupArchive(
            schemaVersion: schemaVersion,
            exportedAt: DateKit.timestampString(Date()),
            accounts: accounts.map { account in
                BackupAccount(
                    id: account.id.uuidString,
                    name: account.name,
                    categoryRaw: account.categoryRaw,
                    note: account.note,
                    boundBankAccountID: account.boundBankAccountID?.uuidString,
                    shAAccountCode: account.shAAccountCode,
                    szAAccountCode: account.szAAccountCode,
                    createdAt: DateKit.timestampString(account.createdAt),
                    updatedAt: DateKit.timestampString(account.updatedAt),
                    closedAt: account.closedAt.map(DateKit.timestampString)
                )
            },
            assets: assets.map { asset in
                BackupAsset(
                    id: asset.id.uuidString,
                    accountID: asset.account?.id.uuidString ?? "",
                    kindRaw: asset.kindRaw,
                    balanceSideRaw: asset.balanceSideRaw,
                    name: asset.name,
                    note: asset.note,
                    currentAmount: Money.plainString(asset.currentAmount),
                    cashAvailabilityRaw: asset.cashAvailabilityRaw,
                    totalInvested: Money.plainString(asset.totalInvested),
                    totalWithdrawn: Money.plainString(asset.totalWithdrawn),
                    lockEndDate: asset.lockEndDate.map(DateKit.dateOnlyString),
                    principal: Money.plainString(asset.principal),
                    annualRate: Money.plainString(asset.annualRate, fractionDigits: 6),
                    startDate: asset.startDate.map(DateKit.dateOnlyString),
                    maturityDate: asset.maturityDate.map(DateKit.dateOnlyString),
                    fundingModeRaw: asset.fundingModeRaw,
                    sourceCashAssetID: asset.sourceCashAssetID?.uuidString,
                    settledAmount: asset.settledAmount.map { Money.plainString($0) },
                    settledAt: asset.settledAt.map(DateKit.timestampString),
                    createdAt: DateKit.timestampString(asset.createdAt),
                    updatedAt: DateKit.timestampString(asset.updatedAt),
                    closedAt: asset.closedAt.map(DateKit.timestampString)
                )
            }
        )
    }

    fileprivate static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    fileprivate static func decode(_ data: Data) throws -> BackupArchive {
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        try validate(archive)
        return archive
    }

    fileprivate static func preview(_ archive: BackupArchive) throws -> BackupPreview {
        let exportedAt = DateKit.parseTimestamp(archive.exportedAt) ?? Date()
        return BackupPreview(
            exportedAt: exportedAt,
            accountCount: archive.accounts.count,
            assetCount: archive.assets.count,
            fixedTermCount: archive.assets.filter { $0.kindRaw == AssetKind.fixedTerm.rawValue }.count,
            schemaVersion: archive.schemaVersion
        )
    }

    fileprivate static func restore(_ archive: BackupArchive, into context: ModelContext) throws {
        let existingAssets = try context.fetch(FetchDescriptor<Asset>())
        for asset in existingAssets { context.delete(asset) }
        try context.save()

        let existingAccounts = try context.fetch(FetchDescriptor<Account>())
        for account in existingAccounts { context.delete(account) }
        try context.save()

        var accountMap: [UUID: Account] = [:]
        for dto in archive.accounts {
            let id = try parseUUID(dto.id, label: "账户 ID")
            let createdAt = try parseTimestamp(dto.createdAt, label: "账户创建时间")
            let updatedAt = try parseTimestamp(dto.updatedAt, label: "账户更新时间")
            let closedAt = try dto.closedAt.map { try parseTimestamp($0, label: "账户关闭时间") }
            let account = Account(
                id: id,
                name: dto.name,
                category: AccountCategory(rawValue: dto.categoryRaw) ?? .other,
                note: dto.note,
                boundBankAccountID: try dto.boundBankAccountID.map { try parseUUID($0, label: "绑定银行账户 ID") },
                shAAccountCode: dto.shAAccountCode,
                szAAccountCode: dto.szAAccountCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                closedAt: closedAt
            )
            context.insert(account)
            accountMap[id] = account
        }

        for dto in archive.assets {
            let id = try parseUUID(dto.id, label: "资产 ID")
            let accountID = try parseUUID(dto.accountID, label: "所属账户 ID")
            guard let account = accountMap[accountID] else {
                throw BusinessError(message: "备份中的资产引用了不存在的账户。")
            }

            let asset = Asset(
                id: id,
                account: account,
                kind: AssetKind(rawValue: dto.kindRaw) ?? .cash,
                name: dto.name,
                note: dto.note,
                currentAmount: try parseDecimal(dto.currentAmount, label: "当前金额"),
                cashAvailability: dto.cashAvailabilityRaw.flatMap(CashAvailability.init(rawValue:)),
                totalInvested: try parseDecimal(dto.totalInvested, label: "累计投入"),
                totalWithdrawn: try parseDecimal(dto.totalWithdrawn, label: "累计取回"),
                lockEndDate: try dto.lockEndDate.map { try parseDateOnly($0, label: "锁定结束日") },
                principal: try parseDecimal(dto.principal, label: "本金"),
                annualRate: try parseDecimal(dto.annualRate, label: "年化收益率"),
                startDate: try dto.startDate.map { try parseDateOnly($0, label: "起息日") },
                maturityDate: try dto.maturityDate.map { try parseDateOnly($0, label: "到期日") },
                fundingMode: dto.fundingModeRaw.flatMap(FundingMode.init(rawValue:)),
                sourceCashAssetID: try dto.sourceCashAssetID.map { try parseUUID($0, label: "来源现金资产 ID") },
                settledAmount: try dto.settledAmount.map { try parseDecimal($0, label: "结清金额") },
                settledAt: try dto.settledAt.map { try parseTimestamp($0, label: "结清时间") },
                createdAt: try parseTimestamp(dto.createdAt, label: "资产创建时间"),
                updatedAt: try parseTimestamp(dto.updatedAt, label: "资产更新时间"),
                closedAt: try dto.closedAt.map { try parseTimestamp($0, label: "资产关闭时间") }
            )
            asset.balanceSideRaw = dto.balanceSideRaw
            context.insert(asset)
        }

        try context.save()
    }

    fileprivate static func validate(_ archive: BackupArchive) throws {
        guard archive.schemaVersion == 1 || archive.schemaVersion == schemaVersion else {
            throw BusinessError(message: "只支持 schemaVersion = 1 或 2 的备份。")
        }
        _ = try preview(archive)

        let accountIDs = try Set(archive.accounts.map { try parseUUID($0.id, label: "账户 ID") })
        guard accountIDs.count == archive.accounts.count else {
            throw BusinessError(message: "备份中存在重复的账户 ID。")
        }

        let categoryByAccountID = Dictionary(uniqueKeysWithValues: try archive.accounts.map {
            (try parseUUID($0.id, label: "账户 ID"), AccountCategory(rawValue: $0.categoryRaw) ?? .other)
        })

        for account in archive.accounts where account.boundBankAccountID != nil {
            let boundBankID = try parseUUID(account.boundBankAccountID ?? "", label: "绑定银行账户 ID")
            guard let category = categoryByAccountID[boundBankID], category == .bank else {
                throw BusinessError(message: "boundBankAccount 只能引用同一备份中的银行账户。")
            }
        }

        var assetIDs = Set<UUID>()
        for asset in archive.assets {
            let id = try parseUUID(asset.id, label: "资产 ID")
            guard assetIDs.insert(id).inserted else {
                throw BusinessError(message: "备份中存在重复的资产 ID。")
            }
            let accountID = try parseUUID(asset.accountID, label: "所属账户 ID")
            guard accountIDs.contains(accountID) else {
                throw BusinessError(message: "备份中的资产引用了不存在的账户。")
            }
            _ = try parseDecimal(asset.currentAmount, label: "当前金额")
            _ = try parseDecimal(asset.totalInvested, label: "累计投入")
            _ = try parseDecimal(asset.totalWithdrawn, label: "累计取回")
            _ = try parseDecimal(asset.principal, label: "本金")
            _ = try parseDecimal(asset.annualRate, label: "年化收益率")
            _ = try parseTimestamp(asset.createdAt, label: "资产创建时间")
            _ = try parseTimestamp(asset.updatedAt, label: "资产更新时间")
            if let lockEndDate = asset.lockEndDate { _ = try parseDateOnly(lockEndDate, label: "锁定结束日") }
            if let startDate = asset.startDate { _ = try parseDateOnly(startDate, label: "起息日") }
            if let maturityDate = asset.maturityDate { _ = try parseDateOnly(maturityDate, label: "到期日") }
            if let settledAt = asset.settledAt { _ = try parseTimestamp(settledAt, label: "结清时间") }
            if let settledAmount = asset.settledAmount { _ = try parseDecimal(settledAmount, label: "结清金额") }
        }

        let cashLikeAssetIDs = Set(
            archive.assets
                .filter { $0.kindRaw == AssetKind.cash.rawValue || $0.kindRaw == AssetKind.cashPlus.rawValue }
                .compactMap { try? parseUUID($0.id, label: "来源资产 ID") }
        )
        for asset in archive.assets where asset.sourceCashAssetID != nil {
            let sourceID = try parseUUID(asset.sourceCashAssetID ?? "", label: "来源资产 ID")
            guard cashLikeAssetIDs.contains(sourceID) else {
                throw BusinessError(message: "sourceCashAsset 只能引用同一备份中的活期或活期+。")
            }
        }
    }

    private static func parseUUID(_ text: String, label: String) throws -> UUID {
        guard let value = UUID(uuidString: text) else {
            throw BusinessError(message: "\(label) 格式无效。")
        }
        return value
    }

    private static func parseDecimal(_ text: String, label: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw BusinessError(message: "\(label) 不是有效的十进制字符串。")
        }
        return value
    }

    private static func parseDateOnly(_ text: String, label: String) throws -> Date {
        guard let value = DateKit.parseDateOnly(text) else {
            throw BusinessError(message: "\(label) 不是有效的 yyyy-MM-dd 日期。")
        }
        return value
    }

    private static func parseTimestamp(_ text: String, label: String) throws -> Date {
        guard let value = DateKit.parseTimestamp(text) else {
            throw BusinessError(message: "\(label) 不是有效的 ISO 时间。")
        }
        return value
    }
}

@MainActor
@Observable
final class BackupManager {
    private enum Key {
        static let folderBookmark = "backup.folder.bookmark"
        static let folderName = "backup.folder.name"
        static let lastSuccess = "backup.last.success"
        static let lastError = "backup.last.error"
        static let pendingPreview = "backup.pending.preview"
        static let pauseWrites = "backup.pause.writes"
    }

    static let latestFileName = "AssetsOS.json"
    static let historyLimit = 3
    static let minimumInterval: TimeInterval = 5 * 60

    var folderName: String?
    var lastSuccessAt: Date?
    var lastErrorText: String?
    var pendingExistingBackup: BackupPreview?
    var isPausedForPendingBackup: Bool
    var isRunning = false

    private var pendingTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var observedContext: ModelContext?

    init() {
        let defaults = UserDefaults.standard
        folderName = defaults.string(forKey: Key.folderName)
        let stamp = defaults.double(forKey: Key.lastSuccess)
        lastSuccessAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        lastErrorText = defaults.string(forKey: Key.lastError)
        if let data = defaults.data(forKey: Key.pendingPreview) {
            pendingExistingBackup = try? JSONDecoder().decode(BackupPreview.self, from: data)
        }
        isPausedForPendingBackup = defaults.bool(forKey: Key.pauseWrites)
    }

    var state: BackupState {
        if let pendingExistingBackup { return .awaitingExistingBackup(pendingExistingBackup) }
        if let lastErrorText, !lastErrorText.isEmpty { return .failed(lastErrorText) }
        if folderName == nil { return .unconfigured }
        return .normal
    }

    var isConfigured: Bool { folderName != nil }

    func startObserving(_ context: ModelContext) {
        observedContext = context
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let observedContext = self.observedContext else { return }
                self.scheduleBackup(from: observedContext)
            }
        }
    }

    func scheduleBackup(from context: ModelContext) {
        guard isConfigured, !isPausedForPendingBackup, pendingExistingBackup == nil, pendingTask == nil else { return }
        let idle = lastSuccessAt.map { Date().timeIntervalSince($0) } ?? Self.minimumInterval
        let wait = max(0, Self.minimumInterval - idle)
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            await self.backupNow(from: context)
            self.pendingTask = nil
        }
    }

    func backupNow(from context: ModelContext) async {
        pendingTask?.cancel()
        pendingTask = nil
        guard isConfigured, !isPausedForPendingBackup, pendingExistingBackup == nil, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let archive = try BackupCodec.archive(from: context)
            try write(archive: archive, toConfiguredFolder: true)
            lastSuccessAt = Date()
            lastErrorText = nil
            persistState()
        } catch {
            lastErrorText = error.localizedDescription
            persistState()
        }
    }

    func flushWhenEnteringBackground(context: ModelContext) async {
        guard pendingTask != nil else { return }
        await backupNow(from: context)
    }

    func configureInitialDirectory(_ url: URL, context: ModelContext) async {
        do {
            let currentCounts = try storeCounts(from: context)
            let bookmark = try makeBookmark(for: url)
            let folderName = url.lastPathComponent
            let existingPreview = try inspectLatestPreview(in: url)

            saveFolder(bookmark: bookmark, folderName: folderName)
            lastErrorText = nil
            if currentCounts.accountCount == 0 && currentCounts.assetCount == 0, let existingPreview {
                pendingExistingBackup = existingPreview
                isPausedForPendingBackup = true
                persistState()
                return
            }

            pendingExistingBackup = nil
            isPausedForPendingBackup = false
            persistState()
            await backupNow(from: context)
        } catch {
            lastErrorText = error.localizedDescription
            persistState()
        }
    }

    func changeDirectory(_ url: URL, context: ModelContext) async {
        do {
            let archive = try BackupCodec.archive(from: context)
            try write(archive: archive, to: url)
            let bookmark = try makeBookmark(for: url)
            saveFolder(bookmark: bookmark, folderName: url.lastPathComponent)
            pendingExistingBackup = nil
            isPausedForPendingBackup = false
            lastErrorText = nil
            lastSuccessAt = Date()
            persistState()
        } catch {
            lastErrorText = error.localizedDescription
            persistState()
        }
    }

    func overwritePendingBackup(from context: ModelContext) async {
        pendingExistingBackup = nil
        isPausedForPendingBackup = false
        persistState()
        await backupNow(from: context)
    }

    func previewPendingBackup() throws -> BackupPreview {
        guard let pendingExistingBackup else {
            throw BusinessError(message: "当前没有待处理的旧备份。")
        }
        return pendingExistingBackup
    }

    func restorePendingBackup(into context: ModelContext) async throws {
        let data = try readLatestConfiguredData()
        try await restore(fromData: data, into: context, sourceFolderURL: configuredFolderURL())
        pendingExistingBackup = nil
        isPausedForPendingBackup = false
        lastErrorText = nil
        persistState()
    }

    func previewRestore(fileAt url: URL) throws -> BackupPreview {
        let data = try read(fileAt: url)
        let archive = try BackupCodec.decode(data)
        return try BackupCodec.preview(archive)
    }

    func restore(fileAt url: URL, into context: ModelContext) async throws {
        let data = try read(fileAt: url)
        try await restore(fromData: data, into: context, sourceFolderURL: url.deletingLastPathComponent())
        lastErrorText = nil
        pendingExistingBackup = nil
        isPausedForPendingBackup = false
        persistState()
    }

    private func restore(fromData data: Data, into context: ModelContext, sourceFolderURL: URL?) async throws {
        let archive = try BackupCodec.decode(data)
        let currentArchive = try BackupCodec.archive(from: context)
        try writeSafetyBackupIfPossible(currentArchive, sourceFolderURL: sourceFolderURL)
        await TermNotificationManager.cancelAll()
        try BackupCodec.restore(archive, into: context)
        let restoredAssets = try context.fetch(FetchDescriptor<Asset>())
        await TermNotificationManager.rescheduleAll(assets: restoredAssets)
    }

    private func storeCounts(from context: ModelContext) throws -> (accountCount: Int, assetCount: Int) {
        let accountCount = try context.fetchCount(FetchDescriptor<Account>())
        let assetCount = try context.fetchCount(FetchDescriptor<Asset>())
        return (accountCount, assetCount)
    }

    private func saveFolder(bookmark: Data, folderName: String) {
        let defaults = UserDefaults.standard
        defaults.set(bookmark, forKey: Key.folderBookmark)
        defaults.set(folderName, forKey: Key.folderName)
        self.folderName = folderName
    }

    private func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(folderName, forKey: Key.folderName)
        defaults.set(lastSuccessAt?.timeIntervalSince1970 ?? 0, forKey: Key.lastSuccess)
        defaults.set(lastErrorText, forKey: Key.lastError)
        defaults.set(isPausedForPendingBackup, forKey: Key.pauseWrites)
        if let pendingExistingBackup {
            defaults.set(try? JSONEncoder().encode(pendingExistingBackup), forKey: Key.pendingPreview)
        } else {
            defaults.removeObject(forKey: Key.pendingPreview)
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData()
    }

    private func configuredFolderURL() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: Key.folderBookmark) else {
            throw BusinessError(message: "尚未配置备份目录。")
        }
        var isStale = false
        let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
        if isStale, let refreshed = try? folder.bookmarkData() {
            UserDefaults.standard.set(refreshed, forKey: Key.folderBookmark)
        }
        return folder
    }

    private func write(archive: BackupArchive, toConfiguredFolder: Bool) throws {
        let folder = try configuredFolderURL()
        try write(archive: archive, to: folder)
    }

    private func write(archive: BackupArchive, to folderURL: URL) throws {
        let data = try BackupCodec.encode(archive)
        try withSecurityScopedFolder(folderURL) { folder in
            let latest = folder.appendingPathComponent(Self.latestFileName)
            try writeCoordinated(data, to: latest)

            let historyURL = folder.appendingPathComponent(historyFileName(for: Date()))
            try? writeCoordinated(data, to: historyURL)
            try? pruneHistory(in: folder)
        }
    }

    private func writeSafetyBackupIfPossible(_ archive: BackupArchive, sourceFolderURL: URL?) throws {
        let data = try BackupCodec.encode(archive)
        if let folderURL = try? configuredFolderURL() {
            try? withSecurityScopedFolder(folderURL) { folder in
                let safety = folder.appendingPathComponent(safetyFileName(for: Date()))
                try writeCoordinated(data, to: safety)
            }
            return
        }

        if let sourceFolderURL {
            try? withSecurityScopedFolder(sourceFolderURL) { folder in
                let safety = folder.appendingPathComponent(safetyFileName(for: Date()))
                try writeCoordinated(data, to: safety)
            }
            return
        }

        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(safetyFileName(for: Date()))
        try? data.write(to: temporary, options: .atomic)
    }

    private func inspectLatestPreview(in folderURL: URL) throws -> BackupPreview? {
        try withSecurityScopedFolder(folderURL) { folder in
            let latest = folder.appendingPathComponent(Self.latestFileName)
            guard FileManager.default.fileExists(atPath: latest.path) else { return nil }
            let data = try readCoordinated(from: latest)
            let archive = try BackupCodec.decode(data)
            return try BackupCodec.preview(archive)
        }
    }

    private func readLatestConfiguredData() throws -> Data {
        let folder = try configuredFolderURL()
        return try withSecurityScopedFolder(folder) { folder in
            let latest = folder.appendingPathComponent(Self.latestFileName)
            guard FileManager.default.fileExists(atPath: latest.path) else {
                throw BusinessError(message: "当前目录中没有找到最新备份文件。")
            }
            return try readCoordinated(from: latest)
        }
    }

    private func read(fileAt url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try readCoordinated(from: url)
    }

    private func withSecurityScopedFolder<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    private func writeCoordinated(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var capturedError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { target in
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                capturedError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let capturedError { throw capturedError }
    }

    private func readCoordinated(from url: URL) throws -> Data {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordinatorError: NSError?
        var result: Data?
        var capturedError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { target in
            do {
                result = try Data(contentsOf: target)
            } catch {
                capturedError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let capturedError { throw capturedError }
        guard let result else { throw BusinessError(message: "未能读取备份文件。") }
        return result
    }

    private func historyFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "AssetsOS-\(formatter.string(from: date)).json"
    }

    private func safetyFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "AssetsOS-pre-restore-\(formatter.string(from: date)).json"
    }

    private func pruneHistory(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let history = names
            .filter { $0.hasPrefix("AssetsOS-") && $0.hasSuffix(".json") && !$0.contains("pre-restore") }
            .sorted(by: >)
        for stale in history.dropFirst(Self.historyLimit) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
        }
    }
}
