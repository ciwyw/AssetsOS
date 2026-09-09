import Foundation
import Observation
import SwiftData

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case accounts
    case fixedTerms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .accounts: return "账户"
        case .fixedTerms: return "定期"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .accounts: return "rectangle.grid.1x2"
        case .fixedTerms: return "calendar"
        }
    }
}

@MainActor
@Observable
final class AppCoordinator {
    var selectedTab: AppTab = .overview
    var focusedCategory: AccountCategory?
    var shouldPresentAddAccount = false
    var accountsTabRetapCount = 0

    func handleTabSelection(_ tab: AppTab) {
        if selectedTab == tab {
            if tab == .accounts {
                accountsTabRetapCount += 1
            }
            return
        }
        selectedTab = tab
    }

    func openAddAccount() {
        selectedTab = .accounts
        shouldPresentAddAccount = true
    }

    func routeToAccounts(category: AccountCategory? = nil) {
        selectedTab = .accounts
        focusedCategory = category
    }

    func routeToFixedTerms() {
        selectedTab = .fixedTerms
    }
}

struct CategoryBreakdown: Identifiable {
    let category: AccountCategory
    let amount: Decimal
    let accounts: [Account]
    var id: String { category.rawValue }
}

struct FundingStatusBreakdown: Identifiable {
    let status: FundingStatus
    let amount: Decimal
    let assets: [Asset]
    var id: String { status.rawValue }
}

struct InvestmentPnLRow: Identifiable {
    let id: String
    let title: String
    let amount: Decimal
}

struct ProcessingItem: Identifiable {
    enum Kind {
        case due
        case upcoming

        var title: String {
            switch self {
            case .due: return "待结清"
            case .upcoming: return "即将到期"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let asset: Asset
    let subtitle: String
}

struct FixedTermSummary {
    let activeCount: Int
    let activePrincipal: Decimal
    let activeEstimatedYield: Decimal
    let dueCount: Int
    let duePrincipal: Decimal
    let nearestMaturityDate: Date?
}

struct DeleteImpactPreview {
    let title: String
    let subtitle: String
    let totalAssetChange: Decimal
    let investmentPnLChange: Decimal
    let cashImpactText: String
    let footnote: String
    let confirmTitle: String
}

struct AccountDeleteBlocker {
    let account: Account
    let records: [Asset]
    let bindingAccounts: [Account]
}

enum CashTransferDirection {
    case inbound
    case outbound

    var title: String {
        switch self {
        case .inbound: return "转入"
        case .outbound: return "转出"
        }
    }
}

enum TransferCounterparty {
    case external
    case internalAsset(Asset)
}

struct BusinessError: LocalizedError, Identifiable {
    let id = UUID()
    let message: String

    var errorDescription: String? { message }
}

enum PortfolioEngine {
    static func accountAssets(_ account: Account, in allAssets: [Asset]) -> [Asset] {
        allAssets.filter { $0.account?.id == account.id }
    }

    static func currentAssets(_ account: Account, in allAssets: [Asset]) -> [Asset] {
        accountAssets(account, in: allAssets)
            .filter { !($0.kind == .fixedTerm && $0.lifecycle == .settled) }
            .sorted(by: assetSort)
    }

    static func settledFixedTerms(_ account: Account, in allAssets: [Asset]) -> [Asset] {
        accountAssets(account, in: allAssets)
            .filter { $0.kind == .fixedTerm && $0.lifecycle == .settled }
            .sorted(by: assetSort)
    }

    static func allCurrentAssets(in allAssets: [Asset]) -> [Asset] {
        allAssets.filter { !($0.kind == .fixedTerm && $0.lifecycle == .settled) }
    }

    static func accountAmount(_ account: Account, in allAssets: [Asset]) -> Decimal {
        Money.rounded(
            currentAssets(account, in: allAssets)
                .reduce(.zero) { $0 + $1.currentPortfolioAmount }
        )
    }

    static func totalAssets(in allAssets: [Asset]) -> Decimal {
        Money.rounded(allCurrentAssets(in: allAssets).reduce(.zero) { $0 + $1.currentPortfolioAmount })
    }

    static func categoryBreakdown(accounts: [Account], assets: [Asset]) -> [CategoryBreakdown] {
        AccountCategory.v1Cases.compactMap { category in
            let categoryAccounts = accounts
                .filter { $0.category == category }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            let amount = Money.rounded(categoryAccounts.reduce(.zero) { partial, account in
                partial + accountAmount(account, in: assets)
            })
            guard amount != .zero else { return nil }
            return CategoryBreakdown(category: category, amount: amount, accounts: categoryAccounts)
        }
    }

    static func fundingBreakdown(assets: [Asset]) -> [FundingStatusBreakdown] {
        let current = allCurrentAssets(in: assets)
        return FundingStatus.allCases.map { status in
            let scoped = current.filter { $0.fundingStatus == status }
                .sorted { lhs, rhs in
                    if lhs.currentPortfolioAmount != rhs.currentPortfolioAmount {
                        return lhs.currentPortfolioAmount > rhs.currentPortfolioAmount
                    }
                    if (lhs.account?.name ?? "") != (rhs.account?.name ?? "") {
                        return (lhs.account?.name ?? "") < (rhs.account?.name ?? "")
                    }
                    return lhs.name < rhs.name
                }
            let amount = Money.rounded(scoped.reduce(.zero) { $0 + $1.currentPortfolioAmount })
            return FundingStatusBreakdown(status: status, amount: amount, assets: scoped)
        }
    }

    static func investmentBreakdown(assets: [Asset]) -> [InvestmentPnLRow] {
        let funds = Money.rounded(assets.filter { $0.kind == .fund }.reduce(.zero) { $0 + $1.investmentProfitLoss })
        let stocks = Money.rounded(assets.filter { $0.kind == .stock }.reduce(.zero) { $0 + $1.investmentProfitLoss })
        let bankWealth = Money.rounded(assets.filter { $0.kind == .bankWealth }.reduce(.zero) { $0 + $1.investmentProfitLoss })
        let settledTerms = Money.rounded(assets.filter { $0.kind == .fixedTerm && $0.lifecycle == .settled }.reduce(.zero) { $0 + $1.investmentProfitLoss })
        return [
            InvestmentPnLRow(id: "fund", title: "基金", amount: funds),
            InvestmentPnLRow(id: "stock", title: "股票", amount: stocks),
            InvestmentPnLRow(id: "bankWealth", title: "银行理财", amount: bankWealth),
            InvestmentPnLRow(id: "settledTerm", title: "已结清定期", amount: settledTerms),
        ]
    }

    static func totalInvestmentPnL(assets: [Asset]) -> Decimal {
        Money.rounded(investmentBreakdown(assets: assets).reduce(.zero) { $0 + $1.amount })
    }

    static func processingItems(assets: [Asset], now: Date = Date()) -> [ProcessingItem] {
        let today = DateKit.today(now)
        return assets.filter { $0.kind == .fixedTerm && $0.lifecycle != .settled }
            .compactMap { asset in
                guard let maturityDate = asset.maturityDate else { return nil }
                let diff = DateKit.dayCount(today, maturityDate)
                if diff <= 0 {
                    let subtitle = "\(asset.account?.name ?? "") · \(asset.name)，已到期"
                    return ProcessingItem(id: asset.id, kind: .due, asset: asset, subtitle: subtitle)
                }
                guard diff <= 3 else { return nil }
                let subtitle = "\(asset.account?.name ?? "") · \(asset.name)，\(DateKit.shortDateText(maturityDate)) 到期"
                return ProcessingItem(id: asset.id, kind: .upcoming, asset: asset, subtitle: subtitle)
            }
            .sorted { lhs, rhs in
                if lhs.kind.title != rhs.kind.title {
                    return lhs.kind == .due
                }
                return (lhs.asset.maturityDate ?? .distantFuture) < (rhs.asset.maturityDate ?? .distantFuture)
            }
    }

    static func fixedTerms(status: FixedTermLifecycle, assets: [Asset]) -> [Asset] {
        assets.filter { $0.kind == .fixedTerm && $0.lifecycle == status }
            .sorted(by: fixedTermSort)
    }

    static func fixedTermSummary(assets: [Asset]) -> FixedTermSummary {
        let active = fixedTerms(status: .active, assets: assets)
        let due = fixedTerms(status: .due, assets: assets)
        let allOpen = active + due
        return FixedTermSummary(
            activeCount: active.count,
            activePrincipal: Money.rounded(active.reduce(.zero) { $0 + $1.principal }),
            activeEstimatedYield: Money.rounded(active.reduce(.zero) { $0 + $1.estimatedYield }),
            dueCount: due.count,
            duePrincipal: Money.rounded(due.reduce(.zero) { $0 + $1.principal }),
            nearestMaturityDate: allOpen.compactMap(\.maturityDate).min()
        )
    }

    static func accountSections(accounts: [Account]) -> [(category: AccountCategory, accounts: [Account])] {
        AccountCategory.v1Cases.compactMap { category in
            let scoped = accounts
                .filter { $0.category == category }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            return scoped.isEmpty ? nil : (category, scoped)
        }
    }

    static func bankAccounts(accounts: [Account], excluding accountID: UUID? = nil) -> [Account] {
        accounts
            .filter { $0.category == .bank && $0.id != accountID }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func boundBankAccount(for securitiesAccount: Account, accounts: [Account]) -> Account? {
        guard securitiesAccount.category == .securitiesPlatform,
              let boundBankAccountID = securitiesAccount.boundBankAccountID else {
            return nil
        }
        return accounts.first { $0.id == boundBankAccountID && $0.category == .bank }
    }

    static func securitiesAccounts(boundTo bankAccount: Account, accounts: [Account], excluding accountID: UUID? = nil) -> [Account] {
        accounts
            .filter {
                $0.id != accountID
                    && $0.category == .securitiesPlatform
                    && $0.boundBankAccountID == bankAccount.id
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func bankCashAsset(for bankAccount: Account, assets: [Asset]) -> Asset? {
        currentAssets(bankAccount, in: assets)
            .first { $0.kind == .cash }
    }

    static func securitiesTransferBlocker(for cashAsset: Asset, accounts: [Account], assets: [Asset]) -> String? {
        guard cashAsset.kind == .cash, cashAsset.account?.category == .securitiesPlatform else {
            return nil
        }
        guard let account = cashAsset.account else {
            return "当前证券账户缺少所属账户，暂不能转入转出。"
        }
        guard let boundBank = boundBankAccount(for: account, accounts: accounts) else {
            return "当前证券账户未绑定银行账户，暂不能转入转出。请先在编辑账户里绑定银行账户。"
        }
        guard bankCashAsset(for: boundBank, assets: assets) != nil else {
            return "已绑定「\(boundBank.name)」，但该银行账户下还没有活期，暂不能转入转出。请先创建活期。"
        }
        return nil
    }

    static func requiredTransferCounterparty(for cashAsset: Asset, accounts: [Account], assets: [Asset]) -> Asset? {
        guard cashAsset.kind == .cash,
              cashAsset.account?.category == .securitiesPlatform,
              let account = cashAsset.account,
              let boundBank = boundBankAccount(for: account, accounts: accounts) else {
            return nil
        }
        return bankCashAsset(for: boundBank, assets: assets)
    }

    static func canTransferBetween(_ lhs: Asset, _ rhs: Asset, accounts: [Account], assets: [Asset]) -> Bool {
        if let required = requiredTransferCounterparty(for: lhs, accounts: accounts, assets: assets), required.id != rhs.id {
            return false
        }
        if lhs.kind == .cash,
           lhs.account?.category == .securitiesPlatform,
           requiredTransferCounterparty(for: lhs, accounts: accounts, assets: assets) == nil {
            return false
        }

        if let required = requiredTransferCounterparty(for: rhs, accounts: accounts, assets: assets), required.id != lhs.id {
            return false
        }
        if rhs.kind == .cash,
           rhs.account?.category == .securitiesPlatform,
           requiredTransferCounterparty(for: rhs, accounts: accounts, assets: assets) == nil {
            return false
        }

        return true
    }

    static func transferCandidates(for cashAsset: Asset, accounts: [Account], assets: [Asset]) -> [Asset] {
        cashAssets(assets: assets)
            .filter { $0.id != cashAsset.id }
            .filter { canTransferBetween(cashAsset, $0, accounts: accounts, assets: assets) }
    }

    static func cashAssets(assets: [Asset]) -> [Asset] {
        assets.filter { $0.isCashLike }
            .sorted { lhs, rhs in
                let lhsCategory = lhs.account?.category.sortIndex ?? 99
                let rhsCategory = rhs.account?.category.sortIndex ?? 99
                if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
                if (lhs.account?.name ?? "") != (rhs.account?.name ?? "") {
                    return (lhs.account?.name ?? "") < (rhs.account?.name ?? "")
                }
                if lhs.kind.sortIndex != rhs.kind.sortIndex { return lhs.kind.sortIndex < rhs.kind.sortIndex }
                return lhs.name < rhs.name
            }
    }

    static func fixedTermSourceUsages(for cashAsset: Asset, assets: [Asset]) -> [Asset] {
        assets.filter {
            $0.kind == .fixedTerm
                && $0.lifecycle != .settled
                && $0.fundingMode == .fromCash
                && $0.sourceCashAssetID == cashAsset.id
        }
        .sorted(by: fixedTermSort)
    }

    static func deleteImpact(for asset: Asset) -> DeleteImpactPreview {
        switch asset.kind {
        case .fund, .stock, .bankWealth:
            return DeleteImpactPreview(
                title: "永久删除「\(asset.name)」？",
                subtitle: "\(asset.account?.name ?? "") · \(asset.kind.title) · 当前市值 \(asset.currentAmount.currencyText)",
                totalAssetChange: .zero,
                investmentPnLChange: Money.rounded(-asset.investmentProfitLoss),
                cashImpactText: "不影响",
                footnote: "累计投入 \(asset.totalInvested.currencyText)、累计取回 \(asset.totalWithdrawn.currencyText) 与对应盈亏会一并永久消失。V1 不提供撤销。",
                confirmTitle: "永久删除该投资及其历史"
            )
        case .fixedTerm:
            if asset.lifecycle == .settled {
                return DeleteImpactPreview(
                    title: "永久删除「\(asset.name)」？",
                    subtitle: "\(asset.account?.name ?? "") · 已结清定期 · 当前金额 \(asset.currentPortfolioAmount.currencyText)",
                    totalAssetChange: .zero,
                    investmentPnLChange: Money.rounded(-asset.investmentProfitLoss),
                    cashImpactText: "不回滚已到账活期",
                    footnote: "删除历史后，对应实际盈亏会从累计投资盈亏中移除，但已经到账的活期余额保持不变。",
                    confirmTitle: "永久删除该定期历史"
                )
            }
            return DeleteImpactPreview(
                title: "删除「\(asset.name)」？",
                subtitle: "本金和本金来源保存后不可修改。删除后该定期会直接移除，不会自动重建。",
                totalAssetChange: asset.fundingMode == .existing ? -asset.principal : .zero,
                investmentPnLChange: .zero,
                cashImpactText: asset.fundingMode == .fromCash ? "退回本金到原现金资产" : "不影响其他现金资产",
                footnote: asset.fundingMode == .fromCash
                    ? "退回本金与删除定期为一次原子操作，同时取消未触发的通知。"
                    : "删除当前记录后，总资产会减少该本金，同时取消未触发的通知。",
                confirmTitle: asset.fundingMode == .fromCash ? "退回本金并删除" : "确认删除"
            )
        default:
            return DeleteImpactPreview(
                title: "永久删除「\(asset.name)」？",
                subtitle: "\(asset.account?.name ?? "") · \(asset.kind.title)",
                totalAssetChange: .zero,
                investmentPnLChange: .zero,
                cashImpactText: "不影响",
                footnote: "V1 不提供撤销。",
                confirmTitle: "永久删除"
            )
        }
    }

    static func deleteBlockerMessage(for asset: Asset, assets: [Asset]) -> String? {
        switch asset.kind {
        case .cash, .cashPlus:
            if asset.currentAmount != .zero {
                return "当前余额必须为 0 才能永久删除。"
            }
            let usages = fixedTermSourceUsages(for: asset, assets: assets)
            if !usages.isEmpty {
                return "该现金资产仍是未结清定期的本金来源，删除相关定期后才能删除。"
            }
            return nil
        case .fund, .stock, .bankWealth:
            if asset.currentAmount != .zero {
                return "当前市值必须为 0 才能永久删除。"
            }
            return nil
        case .fixedTerm:
            if asset.lifecycle == .settled { return nil }
            return "未结清定期请在详情页确认删除。"
        default:
            return "当前版本不支持删除该类型。"
        }
    }

    static func deleteBlockers(for account: Account, assets: [Asset], accounts: [Account]) -> AccountDeleteBlocker? {
        let records = accountAssets(account, in: assets).sorted(by: assetSort)
        let bindingAccounts = account.category == .bank
            ? securitiesAccounts(boundTo: account, accounts: accounts)
            : []
        guard !records.isEmpty || !bindingAccounts.isEmpty else { return nil }
        return AccountDeleteBlocker(account: account, records: records, bindingAccounts: bindingAccounts)
    }

    static func preferredSettlementCash(for term: Asset, assets: [Asset]) -> Asset? {
        assets.filter { $0.account?.id == term.account?.id && $0.kind == .cash }
            .sorted(by: assetSort)
            .first
    }

    static func autoName(for kind: AssetKind, account: Account, assets: [Asset], excluding assetID: UUID? = nil) -> String {
        let taken = Set(
            currentAssets(account, in: assets)
                .filter { $0.id != assetID }
                .map(\.name)
        )
        switch kind {
        case .cash:
            return uniqueName(base: "活期", taken: taken)
        case .cashPlus:
            return uniqueName(base: "活期+", taken: taken)
        default:
            return uniqueName(base: kind.title, taken: taken)
        }
    }

    static func fixedTermBaseName(
        principal: Decimal,
        annualRatePercent: Decimal,
        startDate: Date,
        maturityDate: Date
    ) -> String {
        let holdingDays = max(DateKit.dayCount(startDate, maturityDate), 0)
        let principalText: String
        if principal >= Decimal(10_000) {
            let wan = Money.rounded(principal / Decimal(10_000), scale: 2)
            principalText = Money.string(
                wan,
                symbol: false,
                fractionDigits: 2,
                minimumFractionDigits: 0,
                grouping: false
            ) + "W"
        } else {
            principalText = Money.string(
                principal,
                symbol: false,
                fractionDigits: 2,
                minimumFractionDigits: 0,
                grouping: false
            )
        }

        let rateText = Money.string(
            annualRatePercent,
            symbol: false,
            fractionDigits: 2,
            minimumFractionDigits: 0,
            grouping: false
        ) + "%"

        return "\(principalText) / \(rateText) / \(holdingDays)天"
    }

    static func fixedTermAutoName(
        principal: Decimal,
        annualRatePercent: Decimal,
        startDate: Date,
        maturityDate: Date,
        in account: Account,
        assets: [Asset],
        excluding assetID: UUID? = nil
    ) -> String {
        let base = fixedTermBaseName(
            principal: principal,
            annualRatePercent: annualRatePercent,
            startDate: startDate,
            maturityDate: maturityDate
        )
        let taken = Set(
            currentAssets(account, in: assets)
                .filter { $0.id != assetID }
                .map(\.name)
        )
        return uniqueName(base: base, taken: taken, duplicateSeparator: " / ")
    }

    static func uniqueName(base: String, taken: Set<String>, duplicateSeparator: String = " ") -> String {
        if !taken.contains(base) { return base }
        var index = 2
        while taken.contains("\(base)\(duplicateSeparator)\(index)") {
            index += 1
        }
        return "\(base)\(duplicateSeparator)\(index)"
    }

    static func assetNameExists(
        _ name: String,
        in account: Account,
        assets: [Asset],
        excluding assetID: UUID? = nil
    ) -> Bool {
        currentAssets(account, in: assets)
            .contains { $0.id != assetID && $0.name == name }
    }

    static func accountNameExists(_ name: String, accounts: [Account], excluding accountID: UUID? = nil) -> Bool {
        accounts.contains { $0.id != accountID && $0.name == name }
    }

    static func assetSort(_ lhs: Asset, _ rhs: Asset) -> Bool {
        if lhs.kind.sortIndex != rhs.kind.sortIndex {
            return lhs.kind.sortIndex < rhs.kind.sortIndex
        }
        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }

    static func fixedTermSort(_ lhs: Asset, _ rhs: Asset) -> Bool {
        switch (lhs.lifecycle, rhs.lifecycle) {
        case (.due, .due):
            return (lhs.maturityDate ?? .distantFuture) < (rhs.maturityDate ?? .distantFuture)
        case (.active, .active):
            return (lhs.maturityDate ?? .distantFuture) < (rhs.maturityDate ?? .distantFuture)
        case (.settled, .settled):
            return (lhs.settledAt ?? .distantPast) > (rhs.settledAt ?? .distantPast)
        default:
            return assetSort(lhs, rhs)
        }
    }
}

enum MutationService {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedNote(_ text: String) -> String? {
        let value = normalized(text)
        return value.isEmpty ? nil : value
    }

    @MainActor
    static func saveAccount(
        existing: Account?,
        name: String,
        category: AccountCategory,
        note: String,
        boundBankAccountID: UUID?,
        shAAccountCode: String,
        szAAccountCode: String,
        accounts: [Account],
        context: ModelContext
    ) throws -> Account {
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { throw BusinessError(message: "账户名称不能为空。") }
        guard !PortfolioEngine.accountNameExists(normalizedName, accounts: accounts, excluding: existing?.id) else {
            throw BusinessError(message: "账户名称必须全局唯一。")
        }

        if let existing,
           existing.category == .bank,
           category != .bank,
           !PortfolioEngine.securitiesAccounts(boundTo: existing, accounts: accounts, excluding: existing.id).isEmpty {
            throw BusinessError(message: "该银行账户已被证券账户绑定，需先去对应证券账户改绑或取消绑定。")
        }

        let resolvedBoundBankAccountID: UUID?
        let resolvedShAAccountCode: String?
        let resolvedSzAAccountCode: String?
        if category == .securitiesPlatform {
            let availableBanks = PortfolioEngine.bankAccounts(accounts: accounts, excluding: existing?.id)
            guard !availableBanks.isEmpty else {
                throw BusinessError(message: "请先创建至少一个银行账户，再创建或编辑证券账户。")
            }
            guard let boundBankAccountID,
                  let boundBank = availableBanks.first(where: { $0.id == boundBankAccountID }),
                  boundBank.category == .bank else {
                throw BusinessError(message: "请选择绑定银行账户。")
            }
            resolvedBoundBankAccountID = boundBankAccountID
            resolvedShAAccountCode = normalizedNote(shAAccountCode)
            resolvedSzAAccountCode = normalizedNote(szAAccountCode)
        } else {
            resolvedBoundBankAccountID = nil
            resolvedShAAccountCode = nil
            resolvedSzAAccountCode = nil
        }

        let account = existing ?? Account(name: normalizedName, category: category)
        account.name = normalizedName
        account.category = category
        account.note = normalizedNote(note)
        account.boundBankAccountID = resolvedBoundBankAccountID
        account.shAAccountCode = resolvedShAAccountCode
        account.szAAccountCode = resolvedSzAAccountCode
        account.touch()
        if existing == nil { context.insert(account) }
        try context.save()
        return account
    }

    @MainActor
    static func saveCashAsset(
        kind: AssetKind,
        existing: Asset?,
        account: Account,
        name: String,
        amount: Decimal,
        availability: CashAvailability?,
        note: String,
        assets: [Asset],
        context: ModelContext
    ) throws -> Asset {
        guard amount >= .zero else { throw BusinessError(message: "金额不能小于 0。") }
        if kind == .cash {
            let alreadyHasCash = assets.contains {
                $0.account?.id == account.id && $0.kind == .cash && $0.id != existing?.id
            }
            guard !alreadyHasCash else { throw BusinessError(message: "每个账户最多只能有一个活期。") }
        }

        let resolvedName = normalized(name).isEmpty
            ? PortfolioEngine.autoName(for: kind, account: account, assets: assets, excluding: existing?.id)
            : normalized(name)
        guard !PortfolioEngine.assetNameExists(resolvedName, in: account, assets: assets, excluding: existing?.id) else {
            throw BusinessError(message: "同一账户下当前资产名称不能重复。")
        }

        let asset = existing ?? Asset(account: account, kind: kind, name: resolvedName)
        asset.account = account
        asset.kind = kind
        asset.name = resolvedName
        asset.note = normalizedNote(note)
        asset.currentAmount = Money.rounded(amount)
        asset.cashAvailability = kind == .cashPlus ? (availability ?? .direct) : nil
        asset.touch()
        if existing == nil { context.insert(asset) }
        try context.save()
        return asset
    }

    @MainActor
    static func saveInvestment(
        kind: AssetKind,
        existing: Asset?,
        account: Account,
        name: String,
        note: String,
        currentAmount: Decimal,
        totalInvested: Decimal,
        totalWithdrawn: Decimal,
        lockEndDate: Date?,
        creationMode: FundingMode,
        sourceCashAsset: Asset?,
        actualInvested: Decimal,
        assets: [Asset],
        context: ModelContext
    ) throws -> Asset {
        guard kind.isInvestment else { throw BusinessError(message: "当前资产类型不支持该流程。") }
        guard currentAmount >= .zero, totalInvested >= .zero, totalWithdrawn >= .zero, actualInvested >= .zero else {
            throw BusinessError(message: "金额不能小于 0。")
        }

        let resolvedName = normalized(name)
        guard !resolvedName.isEmpty else { throw BusinessError(message: "名称不能为空。") }
        guard !PortfolioEngine.assetNameExists(resolvedName, in: account, assets: assets, excluding: existing?.id) else {
            throw BusinessError(message: "同一账户下当前资产名称不能重复。")
        }

        let asset = existing ?? Asset(account: account, kind: kind, name: resolvedName)
        if existing == nil && creationMode == .fromCash {
            guard let sourceCashAsset, sourceCashAsset.isCashLike else {
                throw BusinessError(message: "请选择来源现金资产。")
            }
            guard actualInvested > .zero else { throw BusinessError(message: "实际投入必须大于 0。") }
            guard sourceCashAsset.currentAmount >= actualInvested else {
                throw BusinessError(message: "来源现金资产余额不足。")
            }
            sourceCashAsset.currentAmount = Money.rounded(sourceCashAsset.currentAmount - actualInvested)
            sourceCashAsset.touch()
            asset.totalInvested = Money.rounded(actualInvested)
            asset.totalWithdrawn = .zero
        } else {
            asset.totalInvested = Money.rounded(totalInvested)
            asset.totalWithdrawn = Money.rounded(totalWithdrawn)
        }

        asset.account = account
        asset.kind = kind
        asset.name = resolvedName
        asset.note = normalizedNote(note)
        asset.currentAmount = Money.rounded(currentAmount)
        asset.lockEndDate = lockEndDate.map(DateKit.startOfDay)
        asset.touch()
        if existing == nil { context.insert(asset) }
        try context.save()
        return asset
    }

    @MainActor
    static func saveFixedTerm(
        existing: Asset?,
        account: Account,
        principal: Decimal,
        annualRatePercent: Decimal,
        startDate: Date,
        maturityDate: Date,
        note: String,
        fundingMode: FundingMode,
        sourceCashAsset: Asset?,
        assets: [Asset],
        context: ModelContext
    ) throws -> Asset {
        if let existing, existing.lifecycle == .settled {
            existing.note = normalizedNote(note)
            existing.touch()
            try context.save()
            return existing
        }

        guard principal >= .zero else { throw BusinessError(message: "本金不能小于 0。") }
        guard annualRatePercent >= .zero else { throw BusinessError(message: "年化收益率不能小于 0。") }
        guard DateKit.startOfDay(maturityDate) > DateKit.startOfDay(startDate) else {
            throw BusinessError(message: "到期日必须晚于起息日。")
        }

        let resolvedName = PortfolioEngine.fixedTermAutoName(
            principal: principal,
            annualRatePercent: annualRatePercent,
            startDate: startDate,
            maturityDate: maturityDate,
            in: account,
            assets: assets,
            excluding: existing?.id
        )

        if let existing {
            existing.name = resolvedName
            existing.note = normalizedNote(note)
            existing.annualRate = Money.rounded(annualRatePercent / 100, scale: 6)
            existing.startDate = DateKit.startOfDay(startDate)
            existing.maturityDate = DateKit.startOfDay(maturityDate)
            existing.touch()
            try context.save()
            return existing
        }

        let asset = Asset(
            account: account,
            kind: .fixedTerm,
            name: resolvedName,
            note: normalizedNote(note),
            currentAmount: Money.rounded(principal),
            principal: Money.rounded(principal),
            annualRate: Money.rounded(annualRatePercent / 100, scale: 6),
            startDate: DateKit.startOfDay(startDate),
            maturityDate: DateKit.startOfDay(maturityDate),
            fundingMode: fundingMode,
            sourceCashAssetID: sourceCashAsset?.id
        )

        if fundingMode == .fromCash {
            guard let sourceCashAsset else {
                throw BusinessError(message: "请选择来源活期。")
            }
            guard sourceCashAsset.kind == .cash else {
                throw BusinessError(message: "本金来源仅支持活期。")
            }
            guard sourceCashAsset.currentAmount >= principal else {
                throw BusinessError(message: "来源现金资产余额不足。")
            }
            sourceCashAsset.currentAmount = Money.rounded(sourceCashAsset.currentAmount - principal)
            sourceCashAsset.touch()
        }

        context.insert(asset)
        try context.save()
        return asset
    }

    @MainActor
    static func transfer(
        cashAsset: Asset,
        direction: CashTransferDirection,
        amount: Decimal,
        counterparty: TransferCounterparty,
        accounts: [Account],
        assets: [Asset],
        context: ModelContext
    ) throws {
        guard cashAsset.isCashLike else { throw BusinessError(message: "只有活期和活期+支持转入转出。") }
        guard amount > .zero else { throw BusinessError(message: "金额必须大于 0。") }

        if let blocker = PortfolioEngine.securitiesTransferBlocker(for: cashAsset, accounts: accounts, assets: assets) {
            throw BusinessError(message: blocker)
        }

        switch (direction, counterparty) {
        case (.inbound, .external):
            if cashAsset.kind == .cash, cashAsset.account?.category == .securitiesPlatform {
                throw BusinessError(message: "证券账户活期只能与绑定银行账户下的活期互转。")
            }
            cashAsset.currentAmount = Money.rounded(cashAsset.currentAmount + amount)
            cashAsset.touch()
        case (.inbound, .internalAsset(let source)):
            guard source.id != cashAsset.id else { throw BusinessError(message: "来源和目标不能是同一资产。") }
            guard PortfolioEngine.canTransferBetween(cashAsset, source, accounts: accounts, assets: assets) else {
                throw BusinessError(message: "当前转账对象不符合证券账户绑定银行规则。")
            }
            guard source.currentAmount >= amount else { throw BusinessError(message: "来源现金资产余额不足。") }
            source.currentAmount = Money.rounded(source.currentAmount - amount)
            cashAsset.currentAmount = Money.rounded(cashAsset.currentAmount + amount)
            source.touch()
            cashAsset.touch()
        case (.outbound, .external):
            if cashAsset.kind == .cash, cashAsset.account?.category == .securitiesPlatform {
                throw BusinessError(message: "证券账户活期只能与绑定银行账户下的活期互转。")
            }
            guard cashAsset.currentAmount >= amount else { throw BusinessError(message: "当前余额不足。") }
            cashAsset.currentAmount = Money.rounded(cashAsset.currentAmount - amount)
            cashAsset.touch()
        case (.outbound, .internalAsset(let target)):
            guard target.id != cashAsset.id else { throw BusinessError(message: "来源和目标不能是同一资产。") }
            guard target.isCashLike else { throw BusinessError(message: "目标必须是活期或活期+。") }
            guard PortfolioEngine.canTransferBetween(cashAsset, target, accounts: accounts, assets: assets) else {
                throw BusinessError(message: "当前转账对象不符合证券账户绑定银行规则。")
            }
            guard cashAsset.currentAmount >= amount else { throw BusinessError(message: "当前余额不足。") }
            cashAsset.currentAmount = Money.rounded(cashAsset.currentAmount - amount)
            target.currentAmount = Money.rounded(target.currentAmount + amount)
            cashAsset.touch()
            target.touch()
        }

        try context.save()
    }

    @MainActor
    static func settleFixedTerm(
        term: Asset,
        actualAmount: Decimal,
        assets: [Asset],
        context: ModelContext
    ) throws -> Asset? {
        guard term.kind == .fixedTerm, term.lifecycle != .settled else {
            throw BusinessError(message: "该定期不能再次结清。")
        }
        guard actualAmount >= .zero else { throw BusinessError(message: "实际到账金额不能小于 0。") }

        var cashAsset = PortfolioEngine.preferredSettlementCash(for: term, assets: assets)
        if cashAsset == nil && actualAmount > .zero {
            guard let account = term.account else { throw BusinessError(message: "定期缺少所属账户。") }
            let autoName = PortfolioEngine.autoName(for: .cash, account: account, assets: assets)
            let created = Asset(account: account, kind: .cash, name: autoName, currentAmount: .zero)
            context.insert(created)
            cashAsset = created
        }

        if let cashAsset, actualAmount > .zero {
            cashAsset.currentAmount = Money.rounded(cashAsset.currentAmount + actualAmount)
            cashAsset.touch()
        }

        term.currentAmount = .zero
        term.settledAmount = Money.rounded(actualAmount)
        term.settledAt = Date()
        term.touch()
        try context.save()
        return cashAsset
    }

    @MainActor
    static func deleteAsset(_ asset: Asset, assets: [Asset], context: ModelContext) throws {
        if let blocker = PortfolioEngine.deleteBlockerMessage(for: asset, assets: assets) {
            throw BusinessError(message: blocker)
        }
        context.delete(asset)
        try context.save()
    }

    @MainActor
    static func deleteActiveFixedTerm(
        _ asset: Asset,
        assets: [Asset],
        context: ModelContext
    ) throws {
        guard asset.kind == .fixedTerm, asset.lifecycle != .settled else {
            throw BusinessError(message: "只有未结清定期可以执行删除。")
        }

        if asset.fundingMode == .fromCash, let sourceID = asset.sourceCashAssetID,
           let source = assets.first(where: { $0.id == sourceID }) {
            source.currentAmount = Money.rounded(source.currentAmount + asset.principal)
            source.touch()
        }

        context.delete(asset)
        try context.save()
    }

    @MainActor
    static func deleteAccount(_ account: Account, assets: [Asset], accounts: [Account], context: ModelContext) throws {
        if let blocker = PortfolioEngine.deleteBlockers(for: account, assets: assets, accounts: accounts) {
            if !blocker.records.isEmpty {
                throw BusinessError(message: "账户下仍有 \(blocker.records.count) 项资产记录，必须先删除全部资产。")
            }
            throw BusinessError(message: "该银行账户仍被证券账户绑定，需先改绑或取消绑定。")
        }
        context.delete(account)
        try context.save()
    }
}
