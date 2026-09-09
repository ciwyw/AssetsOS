import SwiftData
import SwiftUI

private struct AccountDeleteRequest: Identifiable {
    let id = UUID()
    let account: Account
}

private struct AccountDeleteBlockerPresenter: Identifiable {
    let id = UUID()
    let blocker: AccountDeleteBlocker
}

private struct AccountAssetGroupKey: Hashable {
    let accountID: UUID
    let kind: AssetKind
}

struct AccountsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var coordinator

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    @State private var expandedAccounts = Set<UUID>()
    @State private var expandedGroups = Set<AccountAssetGroupKey>()
    @State private var showAddAccount = false
    @State private var editingAccount: Account?
    @State private var kindPickerAccount: Account?
    @State private var showSettings = false
    @State private var deleteRequest: AccountDeleteRequest?
    @State private var deleteBlockerPresenter: AccountDeleteBlockerPresenter?
    @State private var presentedError: BusinessError?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if accounts.isEmpty {
                    ContentUnavailableView {
                        Label("尚未创建账户", systemImage: "rectangle.grid.1x2")
                    } description: {
                        Text("先创建银行、支付平台、基金平台、证券平台或其他账户，再在账户里录入资产。")
                    } actions: {
                        Button("新增账户") { showAddAccount = true }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(PortfolioEngine.accountSections(accounts: accounts), id: \.category.rawValue) { section in
                    Section(section.category.title) {
                        ForEach(section.accounts, id: \.id) { account in
                            accountRow(account)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        prepareDelete(for: account)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    .tint(AppTheme.gain)

                                    Button {
                                        editingAccount = account
                                    } label: {
                                        Label("编辑", systemImage: "square.and.pencil")
                                    }
                                    .tint(AppTheme.warning)

                                    Button {
                                        kindPickerAccount = account
                                    } label: {
                                        Label("添加资产", systemImage: "plus")
                                    }
                                    .tint(AppTheme.accent)
                                }

                            if expandedAccounts.contains(account.id) {
                                accountAssetRows(account)
                            }
                        }
                    }
                    .id(section.category.rawValue)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("账户")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                presentAddAccountFromCoordinatorIfNeeded()
            }
            .onChange(of: coordinator.shouldPresentAddAccount) { _, _ in
                presentAddAccountFromCoordinatorIfNeeded()
            }
            .onChange(of: coordinator.accountsTabRetapCount) { _, _ in
                toggleAllExpansions()
            }
            .onChange(of: coordinator.focusedCategory) { _, category in
                guard let category else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo(category.rawValue, anchor: .top)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AccountEditorView(existingAccount: nil)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(existingAccount: account)
            }
            .sheet(item: $kindPickerAccount) { account in
                AssetKindPickerView(account: account) {
                    kindPickerAccount = nil
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsScreen()
            }
            .sheet(item: $deleteRequest) { request in
                AccountDeleteConfirmView(account: request.account) {
                    do {
                        try MutationService.deleteAccount(request.account, assets: assets, accounts: accounts, context: modelContext)
                    } catch let error as BusinessError {
                        presentedError = error
                    } catch {
                        presentedError = BusinessError(message: error.localizedDescription)
                    }
                }
            }
            .sheet(item: $deleteBlockerPresenter) { presenter in
                AccountDeleteBlockerView(blocker: presenter.blocker)
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("无法完成操作"), message: Text(error.message), dismissButton: .default(Text("知道了")))
            }
        }
    }

    @ViewBuilder
    private func accountAssetRows(_ account: Account) -> some View {
        ForEach(AssetKind.v1Cases, id: \.rawValue) { kind in
            let scopedAssets = assetsForDisplay(account: account, kind: kind)
            if !scopedAssets.isEmpty {
                if kind == .cash || kind == .cashPlus {
                    ForEach(scopedAssets, id: \.id) { asset in
                        assetRow(asset, indentation: 60)
                    }
                } else {
                    assetGroupRow(kind: kind, assets: scopedAssets, account: account)

                    if expandedGroups.contains(groupKey(for: account, kind: kind)) {
                        ForEach(scopedAssets, id: \.id) { asset in
                            assetRow(asset, indentation: 76)
                        }
                    }
                }
            }
        }

        addAssetRow(account)
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            toggleExpansion(for: account)
        } label: {
            HStack(spacing: 11) {
                Text(account.category.badge)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(expandedAccounts.contains(account.id) ? Color.white : AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(expandedAccounts.contains(account.id) ? AppTheme.accent : AppTheme.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let note = account.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(PortfolioEngine.accountAmount(account, in: assets).currencyText)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                disclosureImage(expanded: expandedAccounts.contains(account.id))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
    }

    private func assetGroupRow(kind: AssetKind, assets: [Asset], account: Account) -> some View {
        let key = groupKey(for: account, kind: kind)
        let summaryAmount = Money.rounded(assets.reduce(.zero) { $0 + $1.currentPortfolioAmount })
        let summaryPnL = Money.rounded(assets.reduce(.zero) { $0 + $1.investmentProfitLoss })
        let subtitle = assetGroupSubtitle(kind: kind, assets: assets)

        return Button {
            if expandedGroups.contains(key) {
                expandedGroups.remove(key)
            } else {
                expandedGroups.insert(key)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(summaryAmount.currencyText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if kind.isInvestment {
                        Text(summaryPnL.signedCurrencyText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.amountColor(summaryPnL))
                    }
                }

                disclosureImage(expanded: expandedGroups.contains(key))
            }
            .padding(.leading, 60)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
    }

    private func assetRow(_ asset: Asset, indentation: CGFloat) -> some View {
        NavigationLink {
            AssetDetailScreen(asset: asset)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(assetSubtitle(asset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(asset.currentPortfolioAmount.currencyText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if asset.kind.isInvestment {
                        Text(asset.investmentProfitLoss.signedCurrencyText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.amountColor(asset.investmentProfitLoss))
                    }
                }
            }
            .padding(.leading, indentation)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .listRowInsets(EdgeInsets())
    }

    private func addAssetRow(_ account: Account) -> some View {
        Button {
            kindPickerAccount = account
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("新增资产")
                    .font(.body)
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 40)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
    }

    private func assetsForDisplay(account: Account, kind: AssetKind) -> [Asset] {
        PortfolioEngine.currentAssets(account, in: assets).filter { $0.kind == kind }
    }

    private func assetGroupSubtitle(kind: AssetKind, assets: [Asset]) -> String? {
        switch kind {
        case .fixedTerm:
            if let nearestMaturity = assets.compactMap(\.maturityDate).min() {
                return "最近 \(DateKit.relativeDueText(nearestMaturity))"
            }
            return nil
        case .fund, .stock, .bankWealth:
            return nil
        default:
            return nil
        }
    }

    private func disclosureImage(expanded: Bool) -> some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 24, height: 24)
    }

    private func assetSubtitle(_ asset: Asset) -> String {
        switch asset.kind {
        case .cash, .cashPlus:
            return asset.fundingStatus.title
        case .fixedTerm:
            let dueText = asset.maturityDate.map { DateKit.relativeDueText($0) } ?? "未设置到期日"
            return "\(asset.fundingStatus.title) · \(dueText)"
        case .fund, .stock, .bankWealth:
            return asset.fundingStatus.title
        default:
            return asset.kind.title
        }
    }

    private func groupKey(for account: Account, kind: AssetKind) -> AccountAssetGroupKey {
        AccountAssetGroupKey(accountID: account.id, kind: kind)
    }

    private func allGroupKeys() -> Set<AccountAssetGroupKey> {
        Set(accounts.flatMap { account in
            AssetKind.v1Cases
                .filter { $0 != .cash && $0 != .cashPlus }
                .filter { !assetsForDisplay(account: account, kind: $0).isEmpty }
                .map { groupKey(for: account, kind: $0) }
        })
    }

    private func toggleAllExpansions() {
        let allAccountIDs = Set(accounts.map(\.id))
        let allGroupKeys = allGroupKeys()
        let isFullyExpanded = expandedAccounts == allAccountIDs && expandedGroups.isSuperset(of: allGroupKeys)

        if isFullyExpanded {
            expandedAccounts.removeAll()
            expandedGroups.removeAll()
        } else {
            expandedAccounts = allAccountIDs
            expandedGroups = allGroupKeys
        }
    }

    private func toggleExpansion(for account: Account) {
        if expandedAccounts.contains(account.id) {
            expandedAccounts.remove(account.id)
        } else {
            expandedAccounts.insert(account.id)
        }
    }

    private func prepareDelete(for account: Account) {
        if let blocker = PortfolioEngine.deleteBlockers(for: account, assets: assets, accounts: accounts) {
            deleteBlockerPresenter = AccountDeleteBlockerPresenter(blocker: blocker)
        } else {
            deleteRequest = AccountDeleteRequest(account: account)
        }
    }

    private func presentAddAccountFromCoordinatorIfNeeded() {
        guard coordinator.shouldPresentAddAccount else { return }
        coordinator.shouldPresentAddAccount = false
        showAddAccount = true
    }
}

private struct AccountDeleteConfirmView: View {
    let account: Account
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("永久删除「\(account.name)」？")
                            .font(.title3.weight(.semibold))
                        Text("账户为空时才允许删除。该操作不可恢复。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }

                CardView {
                    VStack(spacing: 0) {
                        row(label: "当前总资产变化", value: "¥0.00")
                        RowSeparator(inset: 14)
                        row(label: "累计投资盈亏变化", value: "¥0.00")
                        RowSeparator(inset: 14)
                        row(label: "是否影响现金资产", value: "不影响")
                        RowSeparator(inset: 14)
                        row(label: "是否可恢复", value: "不可恢复", valueColor: AppTheme.gain)
                    }
                }

                Spacer()

                Button("永久删除账户") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("删除账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct AccountDeleteBlockerView: View {
    let blocker: AccountDeleteBlocker

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CardView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("无法删除「\(blocker.account.name)」")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.gain)
                            Text(blockerDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                    }

                    if !blocker.records.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderText(title: "仍存在的记录")
                            CardView {
                                VStack(spacing: 0) {
                                    ForEach(Array(blocker.records.enumerated()), id: \.element.id) { index, asset in
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(asset.name)
                                                    .font(.body)
                                                Text(recordHint(asset))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if asset.kind == .fixedTerm && asset.lifecycle != .settled {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.tertiary)
                                            } else {
                                                Text(asset.currentPortfolioAmount.currencyText)
                                                    .font(.body)
                                                    .monospacedDigit()
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        if index < blocker.records.count - 1 { RowSeparator(inset: 14) }
                                    }
                                }
                            }
                        }
                    }

                    if !blocker.bindingAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderText(title: "仍绑定的证券账户")
                            CardView {
                                VStack(spacing: 0) {
                                    ForEach(Array(blocker.bindingAccounts.enumerated()), id: \.element.id) { index, account in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.name)
                                                .font(.body)
                                            Text("需先去该证券账户里改绑或取消绑定")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        if index < blocker.bindingAccounts.count - 1 { RowSeparator(inset: 14) }
                                    }
                                }
                            }
                        }
                    }

                    if blocker.records.contains(where: { $0.kind == .fixedTerm && $0.lifecycle == .settled }) {
                        Button("前往定期页查看已结清") {
                            coordinator.routeToFixedTerms()
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("删除账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var blockerDescription: String {
        switch (!blocker.records.isEmpty, !blocker.bindingAccounts.isEmpty) {
        case (true, true):
            return "该账户下仍有 \(blocker.records.count) 项资产记录，且仍被 \(blocker.bindingAccounts.count) 个证券账户绑定。必须先清空这些阻塞项后才能删除。"
        case (true, false):
            return "账户下仍有 \(blocker.records.count) 项资产记录。必须先删除全部资产，包括已结清定期，才能删除账户。V1 不提供账户级级联删除。"
        case (false, true):
            return "该银行账户仍被 \(blocker.bindingAccounts.count) 个证券账户绑定。必须先到对应证券账户里改绑或取消绑定后，才能删除该银行账户。"
        case (false, false):
            return "当前没有可删除的阻塞项。"
        }
    }

    private func recordHint(_ asset: Asset) -> String {
        switch asset.kind {
        case .cash, .cashPlus:
            return "余额需先归零"
        case .fund, .stock, .bankWealth:
            return "当前市值需先归零"
        case .fixedTerm:
            switch asset.lifecycle {
            case .active: return "进行中"
            case .due: return "待结清"
            case .settled: return "已结清 · 仍属于本账户历史"
            case .none: return asset.kind.title
            }
        default:
            return asset.kind.title
        }
    }
}
