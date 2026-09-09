import SwiftData
import SwiftUI

struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]

    let existingAccount: Account?

    @State private var name: String
    @State private var note: String
    @State private var category: AccountCategory
    @State private var boundBankAccountID: UUID?
    @State private var shAAccountCode: String
    @State private var szAAccountCode: String
    @State private var presentedError: BusinessError?

    init(existingAccount: Account?) {
        self.existingAccount = existingAccount
        _name = State(initialValue: existingAccount?.name ?? "")
        _note = State(initialValue: existingAccount?.note ?? "")
        _category = State(initialValue: existingAccount?.category ?? .bank)
        _boundBankAccountID = State(initialValue: existingAccount?.boundBankAccountID)
        _shAAccountCode = State(initialValue: existingAccount?.shAAccountCode ?? "")
        _szAAccountCode = State(initialValue: existingAccount?.szAAccountCode ?? "")
    }

    private var bankAccounts: [Account] {
        PortfolioEngine.bankAccounts(accounts: accounts, excluding: existingAccount?.id)
    }

    private var canSave: Bool {
        let hasName = !MutationService.normalized(name).isEmpty
        if category == .securitiesPlatform {
            return hasName && boundBankAccountID != nil && !bankAccounts.isEmpty
        }
        return hasName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：招商银行", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("名称")
                } footer: {
                    Text("账户名称全局唯一，一家平台通常只建一个账户。")
                }

                Section {
                    Picker("类别", selection: $category) {
                        ForEach(AccountCategory.v1Cases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                } header: {
                    Text("类别")
                }

                if category == .securitiesPlatform {
                    Section {
                        if bankAccounts.isEmpty {
                            Text("当前还没有银行账户，请先创建银行账户，再保存证券账户。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.gain)
                        } else {
                            Picker("绑定银行账户", selection: $boundBankAccountID) {
                                Text("请选择").tag(Optional<UUID>.none)
                                ForEach(bankAccounts, id: \.id) { account in
                                    Text(account.name).tag(Optional(account.id))
                                }
                            }
                        }

                        TextField("沪A 股东账号（选填）", text: $shAAccountCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("深A 股东账号（选填）", text: $szAAccountCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("证券资料")
                    } footer: {
                        Text("证券账户必须绑定一个现有银行账户；沪A / 深A 仅作资料保存，不参与计算。")
                    }
                }

                Section {
                    TextField("选填", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("备注（可选）")
                } footer: {
                    Text("账户只负责分组，本身不保存金额；保存后可以先是空账户。")
                }
            }
            .navigationTitle(existingAccount == nil ? "新增账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onChange(of: category) { _, newValue in
                if newValue != .securitiesPlatform {
                    boundBankAccountID = nil
                    shAAccountCode = ""
                    szAAccountCode = ""
                }
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("无法保存"), message: Text(error.message), dismissButton: .default(Text("知道了")))
            }
        }
    }

    private func save() {
        do {
            _ = try MutationService.saveAccount(
                existing: existingAccount,
                name: name,
                category: category,
                note: note,
                boundBankAccountID: boundBankAccountID,
                shAAccountCode: shAAccountCode,
                szAAccountCode: szAAccountCode,
                accounts: accounts,
                context: modelContext
            )
            dismiss()
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

struct AssetKindPickerView: View {
    let account: Account
    let onAssetSaved: (() -> Void)?

    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    init(account: Account, onAssetSaved: (() -> Void)? = nil) {
        self.account = account
        self.onAssetSaved = onAssetSaved
    }

    private var hasCash: Bool {
        assets.contains { $0.account?.id == account.id && $0.kind == .cash }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasCash {
                    disabledKindRow(title: AssetKind.cash.title, subtitle: "该账户已有活期，每账户最多一个")
                } else {
                    NavigationLink {
                        CashAssetEditorView(kind: .cash, existingAsset: nil, presetAccount: account, onSaveSuccess: onAssetSaved)
                    } label: {
                        kindLabel(.cash)
                    }
                }

                NavigationLink {
                    CashAssetEditorView(kind: .cashPlus, existingAsset: nil, presetAccount: account, onSaveSuccess: onAssetSaved)
                } label: {
                    kindLabel(.cashPlus)
                }

                NavigationLink {
                    FixedTermEditorView(existingAsset: nil, presetAccount: account, onSaveSuccess: onAssetSaved)
                } label: {
                    kindLabel(.fixedTerm)
                }

                NavigationLink {
                    InvestmentCreationModeView(kind: .fund, presetAccount: account, onSaveSuccess: onAssetSaved)
                } label: {
                    kindLabel(.fund)
                }

                NavigationLink {
                    InvestmentCreationModeView(kind: .stock, presetAccount: account, onSaveSuccess: onAssetSaved)
                } label: {
                    kindLabel(.stock)
                }

                NavigationLink {
                    InvestmentCreationModeView(kind: .bankWealth, presetAccount: account, onSaveSuccess: onAssetSaved)
                } label: {
                    kindLabel(.bankWealth)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("新增资产")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func kindLabel(_ kind: AssetKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kind.title)
                .foregroundStyle(.primary)
            Text(kind.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func disabledKindRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .opacity(0.55)
    }
}

struct InvestmentCreationModeView: View {
    let kind: AssetKind
    let presetAccount: Account
    let onSaveSuccess: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("这笔\(kind.title)是已经持有、只是补录到 App，还是现在用 App 里的现金买入？")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                NavigationLink {
                    InvestmentEditorView(kind: kind, existingAsset: nil, presetAccount: presetAccount, mode: .existing, onSaveSuccess: onSaveSuccess)
                } label: {
                    creationModeCard(
                        title: "录入已有资产",
                        detail: "只创建当前状态，不修改任何其他资产。适合首次建账和补录遗漏。请自行确认其他现金余额没有重复包含这笔钱。",
                        selected: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    InvestmentEditorView(kind: kind, existingAsset: nil, presetAccount: presetAccount, mode: .fromCash, onSaveSuccess: onSaveSuccess)
                } label: {
                    creationModeCard(
                        title: "从现有资金买入",
                        detail: "从一项活期或活期+扣减实际投入，同时创建投资。总资产只变化“当前市值 − 实际投入”。",
                        selected: false
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("新增\(kind.title)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creationModeCard(title: String, detail: String, selected: Bool) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppTheme.accent : Color.secondary)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? AppTheme.accent : Color.clear, lineWidth: 1.5)
        )
    }
}

struct CashAssetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let kind: AssetKind
    let existingAsset: Asset?
    let presetAccount: Account
    let onSaveSuccess: (() -> Void)?

    @State private var name: String
    @State private var amount: Decimal?
    @State private var note: String
    @State private var availability: CashAvailability
    @State private var presentedError: BusinessError?

    init(kind: AssetKind, existingAsset: Asset?, presetAccount: Account, onSaveSuccess: (() -> Void)? = nil) {
        self.kind = kind
        self.existingAsset = existingAsset
        self.presetAccount = presetAccount
        self.onSaveSuccess = onSaveSuccess
        _name = State(initialValue: existingAsset?.name ?? "")
        _amount = State(initialValue: existingAsset?.currentAmount)
        _note = State(initialValue: existingAsset?.note ?? "")
        _availability = State(initialValue: existingAsset?.cashAvailability ?? .direct)
    }

    private var canSave: Bool { amount != nil }

    var body: some View {
        Form {
            Section {
                TextField(kind == .cashPlus ? "可省略，自动命名为活期+ / 活期+ 2" : "可省略，默认命名为活期", text: $name)
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind == .cash ? "当前余额" : "当前余额")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AmountField(amount: $amount)
                }
                LabeledContent("所属账户") { Text(presetAccount.name).foregroundStyle(.secondary) }
            }

            if kind == .cashPlus {
                Section {
                    Picker("资金状态", selection: $availability) {
                        ForEach(CashAvailability.allCases) { availability in
                            VStack(alignment: .leading) {
                                Text(availability.title)
                                Text(availability.detail)
                            }
                            .tag(availability)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("资金状态")
                } footer: {
                    Text("仅活期+需要用户选择资金状态；其余资产由类型与日期派生。")
                }
            }

            Section {
                TextField("选填", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            } header: {
                Text("备注（可选）")
            }
        }
        .navigationTitle(existingAsset == nil ? "新增\(kind.title)" : "编辑\(kind.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("无法保存"), message: Text(error.message), dismissButton: .default(Text("知道了")))
        }
    }

    private func save() {
        guard let amount else {
            presentedError = BusinessError(message: "请输入金额。")
            return
        }
        do {
            _ = try MutationService.saveCashAsset(
                kind: kind,
                existing: existingAsset,
                account: presetAccount,
                name: name,
                amount: amount,
                availability: kind == .cashPlus ? availability : nil,
                note: note,
                assets: assets,
                context: modelContext
            )
            if let onSaveSuccess {
                onSaveSuccess()
            } else {
                dismiss()
            }
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

struct InvestmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let kind: AssetKind
    let existingAsset: Asset?
    let presetAccount: Account?
    let mode: FundingMode
    let onSaveSuccess: (() -> Void)?

    @State private var accountID: UUID?
    @State private var name: String
    @State private var note: String
    @State private var currentAmount: Decimal?
    @State private var totalInvested: Decimal?
    @State private var totalWithdrawn: Decimal?
    @State private var actualInvested: Decimal?
    @State private var lockEndEnabled: Bool
    @State private var lockEndDate: Date
    @State private var sourceCashAssetID: UUID?
    @State private var presentedError: BusinessError?

    init(kind: AssetKind, existingAsset: Asset?, presetAccount: Account?, mode: FundingMode, onSaveSuccess: (() -> Void)? = nil) {
        self.kind = kind
        self.existingAsset = existingAsset
        self.presetAccount = presetAccount
        self.mode = mode
        self.onSaveSuccess = onSaveSuccess

        _accountID = State(initialValue: existingAsset?.account?.id ?? presetAccount?.id)
        _name = State(initialValue: existingAsset?.name ?? "")
        _note = State(initialValue: existingAsset?.note ?? "")
        _currentAmount = State(initialValue: existingAsset?.currentAmount)
        _totalInvested = State(initialValue: existingAsset?.totalInvested)
        _totalWithdrawn = State(initialValue: existingAsset?.totalWithdrawn)
        _actualInvested = State(initialValue: existingAsset?.totalInvested)
        _lockEndEnabled = State(initialValue: existingAsset?.lockEndDate != nil)
        _lockEndDate = State(initialValue: existingAsset?.lockEndDate ?? DateKit.today())
        _sourceCashAssetID = State(initialValue: nil)
    }

    private var selectedAccount: Account? {
        accounts.first(where: { $0.id == accountID }) ?? presetAccount
    }

    private var cashAssets: [Asset] { PortfolioEngine.cashAssets(assets: assets) }
    private var selectedSourceCashAsset: Asset? { cashAssets.first(where: { $0.id == sourceCashAssetID }) }
    private var supportsLockEndDate: Bool { kind == .fund || kind == .bankWealth }
    private var title: String { existingAsset == nil ? "新增\(kind.title)" : "编辑\(kind.title)" }

    private var canSave: Bool {
        guard selectedAccount != nil, !MutationService.normalized(name).isEmpty else { return false }
        if existingAsset == nil && mode == .fromCash {
            return actualInvested != nil && currentAmount != nil && selectedSourceCashAsset != nil
        }
        return currentAmount != nil && totalInvested != nil && totalWithdrawn != nil
    }

    var body: some View {
        Form {
            Section {
                if existingAsset?.canEditOnlyNote == true {
                    LabeledContent("名称") {
                        Text(existingAsset?.name ?? "")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("名称", text: $name)
                }
                if existingAsset == nil, presetAccount == nil {
                    Picker("所属账户", selection: $accountID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(accounts, id: \.id) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } else {
                    LabeledContent("所属账户") { Text(selectedAccount?.name ?? "").foregroundStyle(.secondary) }
                }
            } header: {
                Text("基本信息")
            }

            if existingAsset == nil && mode == .fromCash {
                Section {
                    Picker("来源现金资产", selection: $sourceCashAssetID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(cashAssets, id: \.id) { asset in
                            Text("\(asset.name) · \(asset.account?.name ?? "") · 可用 \(asset.currentAmount.currencyText)")
                                .tag(Optional(asset.id))
                        }
                    }
                } header: {
                    Text("来源现金资产")
                } footer: {
                    Text("来源可以与投资所属账户不同，仅限活期与活期+。")
                }
            }

            Section {
                if existingAsset == nil && mode == .fromCash {
                    labeledAmountField(title: "实际投入", value: $actualInvested)
                    labeledAmountField(title: "当前市值", value: $currentAmount)
                } else {
                    labeledAmountField(title: "累计投入", value: $totalInvested)
                    labeledAmountField(title: "累计取回", value: $totalWithdrawn)
                    labeledAmountField(title: "当前市值", value: $currentAmount)
                }
            } header: {
                Text("金额")
            } footer: {
                Text(existingAsset == nil && mode == .fromCash ? "当前市值默认等于实际投入，可改为含申购费后的真实市值。" : "累计盈亏 = 当前市值 + 累计取回 − 累计投入。三项金额都可直接编辑。")
            }

            if supportsLockEndDate {
                Section {
                    Toggle("设置日期", isOn: $lockEndEnabled.animation())
                    if lockEndEnabled {
                        DatePicker("日期", selection: $lockEndDate, displayedComponents: .date)
                    }
                } header: {
                    Text(kind == .fund ? "锁定结束日" : "解锁日")
                }
            }

            Section {
                TextField("选填", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            } header: {
                Text("备注（可选）")
            }

            if existingAsset == nil && mode == .fromCash {
                Section {
                    HStack {
                        Text(selectedSourceCashAsset.map { "\($0.account?.name ?? "") · \($0.name)" } ?? "来源现金资产")
                        Spacer()
                        let actualInvestedAmount = actualInvested ?? .zero
                        Text((-actualInvestedAmount).signedCurrencyText)
                            .foregroundStyle(AppTheme.amountColor(-actualInvestedAmount))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("新建\(kind.title) · 当前市值")
                        Spacer()
                        Text((currentAmount ?? .zero).currencyText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("总资产变化")
                            .fontWeight(.semibold)
                        Spacer()
                        let delta = Money.rounded((currentAmount ?? .zero) - (actualInvested ?? .zero))
                        Text(delta.signedCurrencyText)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.amountColor(delta))
                            .monospacedDigit()
                    }
                } header: {
                    Text("保存后的变化")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onChange(of: actualInvested) { oldValue, newValue in
            guard existingAsset == nil, mode == .fromCash, currentAmount == oldValue || currentAmount == nil else { return }
            currentAmount = newValue
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("无法保存"), message: Text(error.message), dismissButton: .default(Text("知道了")))
        }
    }

    @ViewBuilder
    private func labeledAmountField(title: String, value: Binding<Decimal?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AmountField(amount: value)
        }
    }

    private func save() {
        guard let selectedAccount else {
            presentedError = BusinessError(message: "请选择所属账户。")
            return
        }
        let resolvedCurrentAmount: Decimal
        let resolvedTotalInvested: Decimal
        let resolvedTotalWithdrawn: Decimal
        let resolvedActualInvested: Decimal

        if existingAsset == nil && mode == .fromCash {
            guard let currentAmount, let actualInvested else {
                presentedError = BusinessError(message: "请填写全部金额。")
                return
            }
            resolvedCurrentAmount = currentAmount
            resolvedActualInvested = actualInvested
            resolvedTotalInvested = .zero
            resolvedTotalWithdrawn = .zero
        } else {
            guard let currentAmount, let totalInvested, let totalWithdrawn else {
                presentedError = BusinessError(message: "请填写全部金额。")
                return
            }
            resolvedCurrentAmount = currentAmount
            resolvedTotalInvested = totalInvested
            resolvedTotalWithdrawn = totalWithdrawn
            resolvedActualInvested = actualInvested ?? totalInvested
        }
        do {
            _ = try MutationService.saveInvestment(
                kind: kind,
                existing: existingAsset,
                account: selectedAccount,
                name: name,
                note: note,
                currentAmount: resolvedCurrentAmount,
                totalInvested: resolvedTotalInvested,
                totalWithdrawn: resolvedTotalWithdrawn,
                lockEndDate: supportsLockEndDate && lockEndEnabled ? lockEndDate : nil,
                creationMode: mode,
                sourceCashAsset: selectedSourceCashAsset,
                actualInvested: resolvedActualInvested,
                assets: assets,
                context: modelContext
            )
            if let onSaveSuccess {
                onSaveSuccess()
            } else {
                dismiss()
            }
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

private enum FixedTermDateAnchor {
    case startDate
    case maturityDate
}

struct FixedTermEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let existingAsset: Asset?
    let presetAccount: Account?
    let onSaveSuccess: (() -> Void)?

    @State private var accountID: UUID?
    @State private var principal: Decimal?
    @State private var annualRatePercent: Decimal?
    @State private var startDate: Date
    @State private var maturityDate: Date
    @State private var note: String
    @State private var fundingMode: FundingMode
    @State private var sourceCashAssetID: UUID?
    @State private var holdingDaysInput: Decimal?
    @State private var dateAnchor: FixedTermDateAnchor
    @State private var presentedError: BusinessError?

    init(existingAsset: Asset?, presetAccount: Account?, onSaveSuccess: (() -> Void)? = nil) {
        self.existingAsset = existingAsset
        self.presetAccount = presetAccount
        self.onSaveSuccess = onSaveSuccess

        let fallbackStart = DateKit.today()
        let fallbackMaturity = DateKit.adding(days: 30, to: fallbackStart)
        let resolvedStart = existingAsset?.startDate ?? fallbackStart
        let resolvedMaturity = existingAsset?.maturityDate ?? fallbackMaturity

        _accountID = State(initialValue: existingAsset?.account?.id ?? presetAccount?.id)
        _principal = State(initialValue: existingAsset?.principal)
        _annualRatePercent = State(initialValue: existingAsset.map { Money.rounded($0.annualRate * 100, scale: 4) })
        _startDate = State(initialValue: resolvedStart)
        _maturityDate = State(initialValue: resolvedMaturity)
        _note = State(initialValue: existingAsset?.note ?? "")
        _fundingMode = State(initialValue: existingAsset?.fundingMode ?? .existing)
        _sourceCashAssetID = State(initialValue: existingAsset?.sourceCashAssetID)
        _holdingDaysInput = State(initialValue: Decimal(max(DateKit.dayCount(resolvedStart, resolvedMaturity), 0)))
        _dateAnchor = State(initialValue: .startDate)
    }

    private var selectedAccount: Account? {
        accounts.first(where: { $0.id == accountID }) ?? presetAccount
    }

    private var availableCashAssets: [Asset] {
        PortfolioEngine.cashAssets(assets: assets).filter { $0.kind == .cash }
    }

    private var sourceCashAsset: Asset? {
        availableCashAssets.first(where: { $0.id == sourceCashAssetID })
    }

    private var principalAmount: Decimal {
        existingAsset?.principal ?? principal ?? .zero
    }

    private var annualRatePercentValue: Decimal {
        annualRatePercent ?? .zero
    }

    private var holdingDays: Int {
        max(DateKit.dayCount(startDate, maturityDate), 0)
    }

    private var estimatedInterest: Decimal {
        Money.rounded(principalAmount * (annualRatePercentValue / 100) * Decimal(holdingDays) / 365)
    }

    private var expectedPayout: Decimal {
        Money.rounded(principalAmount + estimatedInterest)
    }

    private var generatedName: String? {
        guard let selectedAccount, let annualRatePercent else { return nil }
        guard let principalValue = existingAsset?.principal ?? principal else { return nil }
        return PortfolioEngine.fixedTermAutoName(
            principal: principalValue,
            annualRatePercent: annualRatePercent,
            startDate: startDate,
            maturityDate: maturityDate,
            in: selectedAccount,
            assets: assets,
            excluding: existingAsset?.id
        )
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newValue in
                startDate = DateKit.startOfDay(newValue)
                dateAnchor = .startDate
                holdingDaysInput = Decimal(holdingDays)
            }
        )
    }

    private var maturityDateBinding: Binding<Date> {
        Binding(
            get: { maturityDate },
            set: { newValue in
                maturityDate = DateKit.startOfDay(newValue)
                dateAnchor = .maturityDate
                holdingDaysInput = Decimal(holdingDays)
            }
        )
    }

    private var holdingDaysBinding: Binding<Decimal?> {
        Binding(
            get: { holdingDaysInput },
            set: { newValue in
                guard let newValue else {
                    holdingDaysInput = nil
                    return
                }
                let sanitizedDays = max(NSDecimalNumber(decimal: newValue).intValue, 0)
                holdingDaysInput = Decimal(sanitizedDays)
                switch dateAnchor {
                case .startDate:
                    maturityDate = DateKit.startOfDay(DateKit.adding(days: sanitizedDays, to: startDate))
                case .maturityDate:
                    startDate = DateKit.startOfDay(DateKit.adding(days: -sanitizedDays, to: maturityDate))
                }
            }
        )
    }

    private var canSave: Bool {
        guard selectedAccount != nil, annualRatePercent != nil else { return false }
        if existingAsset == nil, principal == nil { return false }
        if existingAsset == nil, fundingMode == .fromCash, sourceCashAsset == nil { return false }
        return true
    }

    var body: some View {
        Form {
            if existingAsset == nil {
                Section {
                    Picker("创建方式", selection: $fundingMode) {
                        Text("录入已有定期").tag(FundingMode.existing)
                        Text("从现有资金创建").tag(FundingMode.fromCash)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                if existingAsset == nil, presetAccount == nil {
                    Picker("账户", selection: $accountID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(accounts, id: \.id) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } else {
                    LabeledContent("账户") { Text(selectedAccount?.name ?? "").foregroundStyle(.secondary) }
                }

                if existingAsset == nil && fundingMode == .fromCash {
                    Picker("现金资产", selection: $sourceCashAssetID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(availableCashAssets, id: \.id) { asset in
                            Text("\(asset.account?.name ?? asset.name) \(asset.currentAmount.currencyText)")
                                .tag(Optional(asset.id))
                        }
                    }
                }

                if existingAsset == nil {
                    labeledAmountField(title: "本金", value: $principal)
                } else {
                    LabeledContent("本金") {
                        Text(existingAsset?.principal.currencyText ?? "")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("年化")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if existingAsset?.canEditOnlyNote == true {
                        Text(annualRatePercentValue.percentText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        PercentField(percent: $annualRatePercent)
                    }
                }

                if existingAsset?.canEditOnlyNote == true {
                    LabeledContent("起息日") { Text(DateKit.fullDateText(startDate)).foregroundStyle(.secondary) }
                    LabeledContent("到期日") { Text(DateKit.fullDateText(maturityDate)).foregroundStyle(.secondary) }
                    LabeledContent("持有天数") { Text("\(holdingDays) 天").foregroundStyle(.secondary) }
                } else {
                    DatePicker("起息日", selection: startDateBinding, displayedComponents: .date)
                    DatePicker("到期日", selection: maturityDateBinding, displayedComponents: .date)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("持有天数（选填）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            AmountField(
                                amount: holdingDaysBinding,
                                placeholder: "自动计算",
                                showsCurrencySymbol: false,
                                fractionDigits: 0,
                                alignment: .trailing,
                                font: .system(size: 28, weight: .semibold, design: .rounded),
                                selectsAllOnFocus: true
                            )
                            Text("天")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("基本信息")
            } footer: {
                Group {
                    if existingAsset?.canEditOnlyNote != true || (existingAsset == nil && fundingMode == .fromCash) {
                        VStack(alignment: .leading, spacing: 4) {
                            if existingAsset == nil && fundingMode == .fromCash {
                                Text("从现有资金创建仅支持活期作为本金来源。")
                            }
                            if existingAsset?.canEditOnlyNote != true {
                                if let generatedName {
                                    Text("保存后名称会自动设置为「\(generatedName)」。")
                                } else {
                                    Text("填写本金和年化后会自动生成名称。")
                                }
                            }
                        }
                    }
                }
            }

            if let existingAsset, existingAsset.kind == .fixedTerm {
                Section {
                    LabeledContent("创建方式") {
                        Text(existingAsset.fundingMode?.title ?? "录入已有")
                            .foregroundStyle(.secondary)
                    }
                    if let sourceID = existingAsset.sourceCashAssetID,
                       let source = assets.first(where: { $0.id == sourceID }) {
                        LabeledContent("本金来源") {
                            Text("\(source.account?.name ?? "") · \(source.name)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("只读字段")
                } footer: {
                    Text(existingAsset.canEditOnlyNote ? "已结清定期只允许修改备注。" : "本金、本金来源和创建方式保存后不可修改。")
                }
            }

            if existingAsset?.canEditOnlyNote != true {
                Section {
                    HStack {
                        Text("预计利息")
                        Spacer()
                        Text(estimatedInterest.currencyText)
                            .font(.headline)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("到账本息")
                        Spacer()
                        Text(expectedPayout.currencyText)
                            .font(.headline)
                            .monospacedDigit()
                    }
                } header: {
                    Text("收益预览")
                } footer: {
                    Text("预计利息 = 本金 × 年化 × 持有天数 ÷ 365，仅展示，不计入总资产与累计投资盈亏。")
                }
            }

            Section {
                TextField("选填", text: $note, axis: .vertical)
                    .lineLimit(3...5)
            } header: {
                Text("备注（可选）")
            }
        }
        .navigationTitle(existingAsset == nil ? "新增定期" : "编辑定期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onChange(of: fundingMode) { _, newValue in
            if newValue != .fromCash {
                sourceCashAssetID = nil
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("无法保存"), message: Text(error.message), dismissButton: .default(Text("知道了")))
        }
    }

    @ViewBuilder
    private func labeledAmountField(title: String, value: Binding<Decimal?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AmountField(amount: value)
        }
    }

    private func save() {
        guard let selectedAccount else {
            presentedError = BusinessError(message: "请选择账户。")
            return
        }

        let resolvedPrincipal: Decimal
        if let existingAsset {
            resolvedPrincipal = existingAsset.principal
        } else if let principal {
            resolvedPrincipal = principal
        } else {
            presentedError = BusinessError(message: "请填写本金。")
            return
        }

        guard let annualRatePercent else {
            presentedError = BusinessError(message: "请填写年化收益率。")
            return
        }

        do {
            let saved = try MutationService.saveFixedTerm(
                existing: existingAsset,
                account: selectedAccount,
                principal: resolvedPrincipal,
                annualRatePercent: annualRatePercent,
                startDate: startDate,
                maturityDate: maturityDate,
                note: note,
                fundingMode: existingAsset?.fundingMode ?? fundingMode,
                sourceCashAsset: sourceCashAsset,
                assets: assets,
                context: modelContext
            )
            Task {
                if saved.lifecycle == .settled {
                    TermNotificationManager.cancel(for: saved.id)
                } else {
                    await TermNotificationManager.schedule(for: saved)
                }
            }
            if let onSaveSuccess {
                onSaveSuccess()
            } else {
                dismiss()
            }
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

struct CashTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let asset: Asset
    let direction: CashTransferDirection

    @State private var amount: Decimal?
    @State private var counterpartyID: UUID?
    @State private var presentedError: BusinessError?

    init(asset: Asset, direction: CashTransferDirection) {
        self.asset = asset
        self.direction = direction
        _amount = State(initialValue: nil)
        _counterpartyID = State(initialValue: nil)
    }

    private var isSecuritiesCash: Bool {
        asset.kind == .cash && asset.account?.category == .securitiesPlatform
    }

    private var requiredCounterparty: Asset? {
        PortfolioEngine.requiredTransferCounterparty(for: asset, accounts: accounts, assets: assets)
    }

    private var internalCandidates: [Asset] {
        if let requiredCounterparty { return [requiredCounterparty] }
        return PortfolioEngine.transferCandidates(for: asset, accounts: accounts, assets: assets)
    }

    private var selectedCounterparty: Asset? {
        if let requiredCounterparty { return requiredCounterparty }
        guard let counterpartyID else { return nil }
        return internalCandidates.first(where: { $0.id == counterpartyID })
    }

    private var usesExternalPath: Bool {
        !isSecuritiesCash && selectedCounterparty == nil
    }

    private var balanceAfter: Decimal {
        let resolvedAmount = amount ?? .zero
        switch direction {
        case .inbound:
            return asset.currentAmount + resolvedAmount
        case .outbound:
            return asset.currentAmount - resolvedAmount
        }
    }

    private var counterpartyBalanceAfter: Decimal? {
        guard let selectedCounterparty else { return nil }
        let resolvedAmount = amount ?? .zero
        switch direction {
        case .inbound:
            return selectedCounterparty.currentAmount - resolvedAmount
        case .outbound:
            return selectedCounterparty.currentAmount + resolvedAmount
        }
    }

    private var totalAssetDelta: Decimal {
        let resolvedAmount = amount ?? .zero
        switch (direction, usesExternalPath) {
        case (.inbound, true): return resolvedAmount
        case (.outbound, true): return -resolvedAmount
        default: return .zero
        }
    }

    private var canConfirm: Bool {
        guard let amount, amount > .zero else { return false }
        if isSecuritiesCash {
            return selectedCounterparty != nil
        }
        return true
    }

    private var directionCounterpartyLabel: String {
        direction == .inbound ? "来源" : "去向"
    }

    private var selectionFootnote: String {
        if isSecuritiesCash {
            return "证券账户活期只能与已绑定银行账户下的活期互转。"
        }
        if internalCandidates.isEmpty {
            return "当前没有可选现金资产，仅可与外部互转。"
        }
        return "外部转入转出会改变总资产；现金资产互转总资产不变。切回外部会清空已选现金资产。"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(direction == .inbound ? "转入到" : "从")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(asset.account?.name ?? "") · \(asset.name)")
                            .font(.headline)
                    }
                    Spacer()
                    if direction == .outbound {
                        Button("全部") {
                            amount = asset.currentAmount
                        }
                        .font(.footnote.weight(.semibold))
                        .disabled(asset.currentAmount <= .zero)
                    }
                }

                AmountField(amount: $amount)

                Text("未填写金额前无法确认。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if !isSecuritiesCash {
                    Button {
                        counterpartyID = nil
                    } label: {
                        HStack {
                            Text("外部")
                            Spacer()
                            Text(direction == .inbound ? "从 App 外转入" : "转出到 App 外")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if usesExternalPath {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let requiredCounterparty {
                    LabeledContent("现金资产") {
                        Text(counterpartyLabel(for: requiredCounterparty))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    Picker("现金资产", selection: $counterpartyID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(internalCandidates, id: \.id) { candidate in
                            Text(counterpartyLabel(for: candidate))
                                .tag(Optional(candidate.id))
                        }
                    }
                }
            } header: {
                Text(directionCounterpartyLabel)
            } footer: {
                Text(selectionFootnote)
            }

            Section {
                HStack {
                    Text("当前余额")
                    Spacer()
                    Text("\(asset.currentAmount.currencyText) → \(Money.rounded(balanceAfter).currencyText)")
                        .foregroundStyle(balanceAfter < .zero ? AppTheme.gain : .primary)
                        .monospacedDigit()
                }

                if let selectedCounterparty, let counterpartyBalanceAfter {
                    HStack {
                        Text(direction == .inbound ? "来源余额" : "去向余额")
                        Spacer()
                        Text("\(selectedCounterparty.currentAmount.currencyText) → \(Money.rounded(counterpartyBalanceAfter).currencyText)")
                            .monospacedDigit()
                    }
                }

                HStack {
                    Text("总资产变化")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(totalAssetDelta.signedCurrencyText)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.amountColor(totalAssetDelta))
                        .monospacedDigit()
                }
            } header: {
                Text("影响")
            }
        }
        .navigationTitle(direction.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("确认") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canConfirm)
            }
        }
        .onAppear {
            if let requiredCounterparty {
                counterpartyID = requiredCounterparty.id
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("无法完成操作"), message: Text(error.message), dismissButton: .default(Text("知道了")))
        }
    }

    private func counterpartyLabel(for candidate: Asset) -> String {
        "\(candidate.account?.name ?? "") · \(candidate.name) · 当前 \(candidate.currentAmount.currencyText)"
    }

    private func save() {
        guard let amount, amount > .zero else {
            presentedError = BusinessError(message: "请填写金额。")
            return
        }

        let counterparty: TransferCounterparty
        if usesExternalPath {
            counterparty = .external
        } else if let selectedCounterparty {
            counterparty = .internalAsset(selectedCounterparty)
        } else {
            presentedError = BusinessError(message: "请选择另一项现金资产。")
            return
        }

        do {
            try MutationService.transfer(
                cashAsset: asset,
                direction: direction,
                amount: amount,
                counterparty: counterparty,
                accounts: accounts,
                assets: assets,
                context: modelContext
            )
            dismiss()
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

struct FixedTermSettlementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let asset: Asset

    @State private var actualAmount: Decimal
    @State private var presentedError: BusinessError?

    init(asset: Asset) {
        self.asset = asset
        _actualAmount = State(initialValue: Money.rounded(asset.principal + asset.estimatedYield))
    }

    private var receivingCashAsset: Asset? {
        PortfolioEngine.preferredSettlementCash(for: asset, assets: assets)
    }

    private var resultingCashBalance: Decimal {
        let base = receivingCashAsset?.currentAmount ?? .zero
        return Money.rounded(base + actualAmount)
    }

    private var pnl: Decimal { Money.rounded(actualAmount - asset.principal) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.name)
                            .font(.headline)
                        Text("\(asset.account?.name ?? "") · 本金 \(asset.principal.currencyText) · 预计利息 \(asset.estimatedYield.currencyText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    AmountField(amount: $actualAmount)
                    Text("可以与“到账本息”不同，按银行实际到账填写。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("实际到账金额")
                }

                Section {
                    if let receivingCashAsset {
                        LabeledContent("到账到") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(receivingCashAsset.name) · \(receivingCashAsset.account?.name ?? "")")
                                Text(receivingCashAsset.currentAmount.currencyText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if actualAmount > .zero {
                        Text("该账户当前没有活期。结清时会自动创建名称为“活期”的资产并到账。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("实际到账为 0 时，不要求创建活期。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("到账资产")
                }

                Section {
                    HStack {
                        Text("\(asset.account?.name ?? "") · 活期")
                        Spacer()
                        Text(receivingCashAsset == nil && actualAmount > .zero
                             ? "¥0.00 → \(resultingCashBalance.currencyText)"
                             : "\((receivingCashAsset?.currentAmount ?? .zero).currencyText) → \(resultingCashBalance.currencyText)")
                        .monospacedDigit()
                    }
                    HStack {
                        Text("定期当前金额")
                        Spacer()
                        Text("\(asset.currentPortfolioAmount.currencyText) → ¥0.00")
                            .monospacedDigit()
                    }
                    HStack {
                        Text("实际盈亏")
                        Spacer()
                        Text(pnl.signedCurrencyText)
                            .foregroundStyle(AppTheme.amountColor(pnl))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("总资产变化")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(pnl.signedCurrencyText)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.amountColor(pnl))
                            .monospacedDigit()
                    }
                } header: {
                    Text("结清后的变化")
                }
            }
            .navigationTitle("结清定期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认结清") { settle() }
                        .fontWeight(.semibold)
                }
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("无法结清"), message: Text(error.message), dismissButton: .default(Text("知道了")))
            }
        }
    }

    private func settle() {
        do {
            _ = try MutationService.settleFixedTerm(
                term: asset,
                actualAmount: actualAmount,
                assets: assets,
                context: modelContext
            )
            TermNotificationManager.cancel(for: asset.id)
            dismiss()
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

struct DeleteAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    let asset: Asset
    let onDeleted: (() -> Void)?

    @State private var presentedError: BusinessError?

    private var preview: DeleteImpactPreview { PortfolioEngine.deleteImpact(for: asset) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preview.title)
                            .font(.title3.weight(.semibold))
                        Text(preview.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }

                CardView {
                    VStack(spacing: 0) {
                        deleteRow(label: "当前总资产变化", value: preview.totalAssetChange.signedCurrencyText, color: AppTheme.amountColor(preview.totalAssetChange))
                        RowSeparator(inset: 14)
                        deleteRow(label: "累计投资盈亏", value: preview.investmentPnLChange.signedCurrencyText, color: AppTheme.amountColor(preview.investmentPnLChange))
                        RowSeparator(inset: 14)
                        deleteRow(label: "是否影响现金资产", value: preview.cashImpactText)
                        RowSeparator(inset: 14)
                        deleteRow(label: "是否可恢复", value: "不可恢复", color: AppTheme.gain)
                    }
                }

                Text(preview.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Spacer()

                Button(preview.confirmTitle) {
                    confirm()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("返回") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle(foreground: AppTheme.accent))
            }
            .padding(16)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle(asset.kind == .fixedTerm && asset.lifecycle != .settled ? "删除" : "永久删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("无法完成操作"), message: Text(error.message), dismissButton: .default(Text("知道了")))
            }
        }
    }

    private func deleteRow(label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func confirm() {
        do {
            if asset.kind == .fixedTerm, asset.lifecycle != .settled {
                try MutationService.deleteActiveFixedTerm(asset, assets: assets, context: modelContext)
                TermNotificationManager.cancel(for: asset.id)
                completeDeletion()
                return
            }

            try MutationService.deleteAsset(asset, assets: assets, context: modelContext)
            if asset.kind == .fixedTerm { TermNotificationManager.cancel(for: asset.id) }
            completeDeletion()
        } catch let error as BusinessError {
            presentedError = error
        } catch {
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }

    private func completeDeletion() {
        if let onDeleted {
            onDeleted()
        } else {
            dismiss()
        }
    }
}
