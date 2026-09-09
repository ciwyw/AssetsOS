import Foundation
import SwiftData

enum AccountCategory: String, CaseIterable, Codable, Identifiable {
    case bank
    case paymentPlatform
    case fundPlatform
    case securitiesPlatform
    case other
    case personalRelations

    var id: String { rawValue }

    static var v1Cases: [AccountCategory] {
        [.bank, .paymentPlatform, .fundPlatform, .securitiesPlatform, .other]
    }

    var title: String {
        switch self {
        case .bank: return "银行"
        case .paymentPlatform: return "支付平台"
        case .fundPlatform: return "基金平台"
        case .securitiesPlatform: return "证券平台"
        case .other: return "其他"
        case .personalRelations: return "个人往来"
        }
    }

    var badge: String {
        switch self {
        case .bank: return "行"
        case .paymentPlatform: return "付"
        case .fundPlatform: return "基"
        case .securitiesPlatform: return "券"
        case .other: return "他"
        case .personalRelations: return "往"
        }
    }

    var sortIndex: Int {
        switch self {
        case .bank: return 0
        case .paymentPlatform: return 1
        case .fundPlatform: return 2
        case .securitiesPlatform: return 3
        case .other: return 4
        case .personalRelations: return 5
        }
    }
}

enum AssetKind: String, CaseIterable, Codable, Identifiable {
    case cash
    case cashPlus
    case fixedTerm
    case fund
    case stock
    case bankWealth
    case loanReceivable
    case loanPayable

    var id: String { rawValue }

    static var v1Cases: [AssetKind] {
        [.cash, .cashPlus, .fixedTerm, .fund, .stock, .bankWealth]
    }

    var title: String {
        switch self {
        case .cash: return "活期"
        case .cashPlus: return "活期+"
        case .fixedTerm: return "定期"
        case .fund: return "基金"
        case .stock: return "股票"
        case .bankWealth: return "银行理财"
        case .loanReceivable: return "借出"
        case .loanPayable: return "借入"
        }
    }

    var subtitle: String {
        switch self {
        case .cash:
            return "可直接转账、支付或交易的现金余额"
        case .cashPlus:
            return "货币基金、货币钱包、现金管理产品"
        case .fixedTerm:
            return "收益率与到期日明确的产品"
        case .fund:
            return "场外公募基金"
        case .stock:
            return "股票、场内 ETF、其他交易所持仓"
        case .bankWealth:
            return "收益随净值变化的理财产品"
        case .loanReceivable:
            return "V3 预留"
        case .loanPayable:
            return "V3 预留"
        }
    }

    var sortIndex: Int {
        switch self {
        case .cash: return 0
        case .cashPlus: return 1
        case .fixedTerm: return 2
        case .fund: return 3
        case .stock: return 4
        case .bankWealth: return 5
        case .loanReceivable: return 6
        case .loanPayable: return 7
        }
    }

    var isInvestment: Bool {
        switch self {
        case .fund, .stock, .bankWealth:
            return true
        default:
            return false
        }
    }

    var isCashLike: Bool {
        self == .cash || self == .cashPlus
    }
}

enum BalanceSide: String, Codable {
    case asset
    case liability
}

enum CashAvailability: String, CaseIterable, Codable, Identifiable {
    case direct
    case redeemable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: return "直接可用"
        case .redeemable: return "可变现"
        }
    }

    var detail: String {
        switch self {
        case .direct: return "可直接支付或即时使用"
        case .redeemable: return "需要先赎回才能使用"
        }
    }
}

enum FundingMode: String, CaseIterable, Codable, Identifiable {
    case existing
    case fromCash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing: return "录入已有"
        case .fromCash: return "从现有资金创建"
        }
    }
}

enum FundingStatus: String, CaseIterable, Identifiable {
    case direct
    case redeemable
    case locked
    case receivable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: return "直接可用"
        case .redeemable: return "可变现"
        case .locked: return "锁定中"
        case .receivable: return "应收与待到账"
        }
    }

    var sortIndex: Int {
        switch self {
        case .direct: return 0
        case .redeemable: return 1
        case .locked: return 2
        case .receivable: return 3
        }
    }
}

enum FixedTermLifecycle: String {
    case active
    case due
    case settled
}

enum AssetsOSSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Account.self, Asset.self]
    }

    @Model
    final class Account {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var note: String?
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \Asset.account) var assets: [Asset]?

        init(
            id: UUID = UUID(),
            name: String,
            category: AccountCategory,
            note: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            closedAt: Date? = nil,
            assets: [Asset]? = nil
        ) {
            self.id = id
            self.name = name
            self.categoryRaw = category.rawValue
            self.note = note
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.closedAt = closedAt
            self.assets = assets
        }
    }

    @Model
    final class Asset {
        @Attribute(.unique) var id: UUID
        var kindRaw: String
        var balanceSideRaw: String
        var name: String
        var note: String?
        var currentAmount: Decimal
        var cashAvailabilityRaw: String?
        var totalInvested: Decimal
        var totalWithdrawn: Decimal
        var lockEndDate: Date?
        var principal: Decimal
        var annualRate: Decimal
        var startDate: Date?
        var maturityDate: Date?
        var fundingModeRaw: String?
        var sourceCashAssetID: UUID?
        var settledAmount: Decimal?
        var settledAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        var account: Account?

        init(
            id: UUID = UUID(),
            account: Account,
            kind: AssetKind,
            name: String,
            note: String? = nil,
            currentAmount: Decimal = .zero,
            cashAvailability: CashAvailability? = nil,
            totalInvested: Decimal = .zero,
            totalWithdrawn: Decimal = .zero,
            lockEndDate: Date? = nil,
            principal: Decimal = .zero,
            annualRate: Decimal = .zero,
            startDate: Date? = nil,
            maturityDate: Date? = nil,
            fundingMode: FundingMode? = nil,
            sourceCashAssetID: UUID? = nil,
            settledAmount: Decimal? = nil,
            settledAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            closedAt: Date? = nil
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.balanceSideRaw = BalanceSide.asset.rawValue
            self.name = name
            self.note = note
            self.currentAmount = currentAmount
            self.cashAvailabilityRaw = cashAvailability?.rawValue
            self.totalInvested = totalInvested
            self.totalWithdrawn = totalWithdrawn
            self.lockEndDate = lockEndDate
            self.principal = principal
            self.annualRate = annualRate
            self.startDate = startDate
            self.maturityDate = maturityDate
            self.fundingModeRaw = fundingMode?.rawValue
            self.sourceCashAssetID = sourceCashAssetID
            self.settledAmount = settledAmount
            self.settledAt = settledAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.closedAt = closedAt
            self.account = account
        }
    }
}

enum AssetsOSSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Account.self, Asset.self]
    }

    @Model
    final class Account {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var note: String?
        var boundBankAccountID: UUID?
        var shAAccountCode: String?
        var szAAccountCode: String?
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \Asset.account) var assets: [Asset]?

        init(
            id: UUID = UUID(),
            name: String,
            category: AccountCategory,
            note: String? = nil,
            boundBankAccountID: UUID? = nil,
            shAAccountCode: String? = nil,
            szAAccountCode: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            closedAt: Date? = nil,
            assets: [Asset]? = nil
        ) {
            self.id = id
            self.name = name
            self.categoryRaw = category.rawValue
            self.note = note
            self.boundBankAccountID = boundBankAccountID
            self.shAAccountCode = shAAccountCode
            self.szAAccountCode = szAAccountCode
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.closedAt = closedAt
            self.assets = assets
        }
    }

    @Model
    final class Asset {
        @Attribute(.unique) var id: UUID
        var kindRaw: String
        var balanceSideRaw: String
        var name: String
        var note: String?
        var currentAmount: Decimal
        var cashAvailabilityRaw: String?
        var totalInvested: Decimal
        var totalWithdrawn: Decimal
        var lockEndDate: Date?
        var principal: Decimal
        var annualRate: Decimal
        var startDate: Date?
        var maturityDate: Date?
        var fundingModeRaw: String?
        var sourceCashAssetID: UUID?
        var settledAmount: Decimal?
        var settledAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        var account: Account?

        init(
            id: UUID = UUID(),
            account: Account,
            kind: AssetKind,
            name: String,
            note: String? = nil,
            currentAmount: Decimal = .zero,
            cashAvailability: CashAvailability? = nil,
            totalInvested: Decimal = .zero,
            totalWithdrawn: Decimal = .zero,
            lockEndDate: Date? = nil,
            principal: Decimal = .zero,
            annualRate: Decimal = .zero,
            startDate: Date? = nil,
            maturityDate: Date? = nil,
            fundingMode: FundingMode? = nil,
            sourceCashAssetID: UUID? = nil,
            settledAmount: Decimal? = nil,
            settledAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            closedAt: Date? = nil
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.balanceSideRaw = BalanceSide.asset.rawValue
            self.name = name
            self.note = note
            self.currentAmount = currentAmount
            self.cashAvailabilityRaw = cashAvailability?.rawValue
            self.totalInvested = totalInvested
            self.totalWithdrawn = totalWithdrawn
            self.lockEndDate = lockEndDate
            self.principal = principal
            self.annualRate = annualRate
            self.startDate = startDate
            self.maturityDate = maturityDate
            self.fundingModeRaw = fundingMode?.rawValue
            self.sourceCashAssetID = sourceCashAssetID
            self.settledAmount = settledAmount
            self.settledAt = settledAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.closedAt = closedAt
            self.account = account
        }
    }
}

typealias Account = AssetsOSSchemaV2.Account
typealias Asset = AssetsOSSchemaV2.Asset

enum AssetsOSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AssetsOSSchemaV1.self, AssetsOSSchemaV2.self] }

    static var stages: [MigrationStage] {
        [migrateV1ToV2]
    }

    static let migrateV1ToV2 = MigrationStage.lightweight(
        fromVersion: AssetsOSSchemaV1.self,
        toVersion: AssetsOSSchemaV2.self
    )
}

enum PersistenceController {
    static let schema = Schema(versionedSchema: AssetsOSSchemaV2.self)

    static func makeSharedContainer() -> ModelContainer {
        do {
            let configuration = ModelConfiguration("AssetsOSStore", schema: schema)
            return try ModelContainer(
                for: schema,
                migrationPlan: AssetsOSMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            assertionFailure("SwiftData 容器创建失败，已回退到内存库：\(error)")
            return makePreviewContainer()
        }
    }

    static func makePreviewContainer() -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                "AssetsOSPreview",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: AssetsOSMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            fatalError("无法创建预览容器：\(error)")
        }
    }
}

extension Account {
    var category: AccountCategory {
        get { AccountCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var assetList: [Asset] { assets ?? [] }

    func touch() {
        updatedAt = Date()
    }
}

extension Account: Identifiable {}

extension Asset {
    var kind: AssetKind {
        get { AssetKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    var balanceSide: BalanceSide {
        get { BalanceSide(rawValue: balanceSideRaw) ?? .asset }
        set { balanceSideRaw = newValue.rawValue }
    }

    var cashAvailability: CashAvailability? {
        get { cashAvailabilityRaw.flatMap(CashAvailability.init(rawValue:)) }
        set { cashAvailabilityRaw = newValue?.rawValue }
    }

    var fundingMode: FundingMode? {
        get { fundingModeRaw.flatMap(FundingMode.init(rawValue:)) }
        set { fundingModeRaw = newValue?.rawValue }
    }

    var isCashLike: Bool { kind.isCashLike }
    var isInvestment: Bool { kind.isInvestment }
    var isFixedTerm: Bool { kind == .fixedTerm }

    var lifecycle: FixedTermLifecycle? {
        guard isFixedTerm else { return nil }
        if settledAt != nil { return .settled }
        guard let maturityDate else { return .active }
        return DateKit.startOfDay(Date()) >= DateKit.startOfDay(maturityDate) ? .due : .active
    }

    var currentPortfolioAmount: Decimal {
        switch kind {
        case .fixedTerm:
            return lifecycle == .settled ? .zero : principal
        default:
            return currentAmount
        }
    }

    var fundingStatus: FundingStatus {
        switch kind {
        case .cash:
            return .direct
        case .cashPlus:
            return cashAvailability == .redeemable ? .redeemable : .direct
        case .fund:
            if let lockEndDate, DateKit.startOfDay(lockEndDate) > DateKit.startOfDay(Date()) {
                return .locked
            }
            return .redeemable
        case .stock:
            return .redeemable
        case .bankWealth:
            if let lockEndDate, DateKit.startOfDay(lockEndDate) > DateKit.startOfDay(Date()) {
                return .locked
            }
            return .redeemable
        case .fixedTerm:
            return lifecycle == .due ? .receivable : .locked
        case .loanReceivable:
            return .receivable
        case .loanPayable:
            return .locked
        }
    }

    var estimatedYield: Decimal {
        guard kind == .fixedTerm, let startDate, let maturityDate else { return .zero }
        let days = max(DateKit.dayCount(startDate, maturityDate), 0)
        return Money.rounded(principal * annualRate * Decimal(days) / 365)
    }

    var investmentProfitLoss: Decimal {
        switch kind {
        case .fund, .stock, .bankWealth:
            return Money.rounded(currentAmount + totalWithdrawn - totalInvested)
        case .fixedTerm:
            if let settledAmount { return Money.rounded(settledAmount - principal) }
            return .zero
        default:
            return .zero
        }
    }

    var canEditOnlyNote: Bool {
        kind == .fixedTerm && lifecycle == .settled
    }

    func touch() {
        updatedAt = Date()
    }
}

extension Asset: Identifiable {}
