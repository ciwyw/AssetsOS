import SwiftData
import SwiftUI

private struct TransferRequest: Identifiable {
    let id = UUID()
    let direction: CashTransferDirection
}

struct AssetDetailScreen: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]
    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]

    let asset: Asset

    @State private var showDelete = false
    @State private var showCashEditor = false
    @State private var showInvestmentEditor = false
    @State private var showFixedTermEditor = false
    @State private var showSettlement = false
    @State private var transferRequest: TransferRequest?
    @State private var presentedError: BusinessError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch asset.kind {
                case .cash, .cashPlus:
                    cashContent
                case .fund, .stock, .bankWealth:
                    investmentContent
                case .fixedTerm:
                    fixedTermContent
                default:
                    Text("当前版本暂不支持该资产类型。")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") {
                    switch asset.kind {
                    case .cash, .cashPlus:
                        showCashEditor = true
                    case .fund, .stock, .bankWealth:
                        showInvestmentEditor = true
                    case .fixedTerm:
                        showFixedTermEditor = true
                    default:
                        break
                    }
                }
            }
        }
        .sheet(isPresented: $showCashEditor) {
            NavigationStack {
                CashAssetEditorView(kind: asset.kind, existingAsset: asset, presetAccount: asset.account ?? accounts.first ?? Account(name: "", category: .other))
            }
        }
        .sheet(isPresented: $showInvestmentEditor) {
            NavigationStack {
                InvestmentEditorView(kind: asset.kind, existingAsset: asset, presetAccount: asset.account, mode: .existing)
            }
        }
        .sheet(isPresented: $showFixedTermEditor) {
            NavigationStack {
                FixedTermEditorView(existingAsset: asset, presetAccount: asset.account)
            }
        }
        .sheet(isPresented: $showDelete) {
            DeleteAssetView(asset: asset) {
                showDelete = false
                DispatchQueue.main.async {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showSettlement) {
            FixedTermSettlementView(asset: asset)
        }
        .sheet(item: $transferRequest) { request in
            NavigationStack {
                CashTransferView(asset: asset, direction: request.direction)
            }
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("暂不能操作"), message: Text(error.message), dismissButton: .default(Text("知道了")))
        }
    }

    private var cashContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(asset.kind == .cash ? "当前余额" : "当前余额")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(asset.currentAmount.currencyText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    StatusPill(text: asset.fundingStatus.title, color: AppTheme.statusColor(asset.fundingStatus))
                }
                .padding(18)
            }

            HStack(spacing: 10) {
                Button("转入") { requestTransfer(.inbound) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("转出") { requestTransfer(.outbound) }
                    .buttonStyle(SecondaryButtonStyle(foreground: AppTheme.accent))
            }

            CardView {
                VStack(spacing: 0) {
                    attributeRow("名称", asset.name)
                    RowSeparator(inset: 14)
                    attributeRow("所属账户", asset.account?.name ?? "")
                    RowSeparator(inset: 14)
                    attributeRow("资产类型", asset.kind.title)
                    if asset.kind == .cashPlus {
                        RowSeparator(inset: 14)
                        attributeRow("资金状态", asset.fundingStatus.title)
                    }
                    RowSeparator(inset: 14)
                    attributeRow("备注", asset.note?.isEmpty == false ? asset.note! : "未填写", secondary: asset.note?.isEmpty != false)
                }
            }

            deleteArea(
                title: asset.kind == .cash ? "永久删除" : "永久删除",
                subtitle: deleteHintText
            )
        }
    }

    private var investmentContent: some View {
        let pnl = asset.investmentProfitLoss
        let rate = asset.totalInvested > .zero ? Money.rounded(pnl / asset.totalInvested, scale: 4) : .zero
        return VStack(alignment: .leading, spacing: 14) {
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前市值")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(asset.currentAmount.currencyText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    HStack(spacing: 10) {
                        Text(pnl.signedCurrencyText)
                            .font(.headline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.amountColor(pnl))
                        StatusPill(text: rate.percentText, color: AppTheme.amountColor(pnl))
                        Spacer()
                        StatusPill(text: asset.fundingStatus.title, color: AppTheme.statusColor(asset.fundingStatus))
                    }
                }
                .padding(18)
            }

            CardView {
                VStack(spacing: 0) {
                    attributeRow("累计投入", asset.totalInvested.currencyText)
                    RowSeparator(inset: 14)
                    attributeRow("累计取回", asset.totalWithdrawn.currencyText)
                    RowSeparator(inset: 14)
                    attributeRow("当前市值", asset.currentAmount.currencyText)
                    RowSeparator(inset: 14)
                    attributeRow("累计盈亏", pnl.signedCurrencyText, valueColor: AppTheme.amountColor(pnl))
                }
            }

            if asset.kind == .fund || asset.kind == .bankWealth {
                CardView {
                    VStack(spacing: 0) {
                        attributeRow(asset.kind == .fund ? "锁定结束日" : "解锁日", asset.lockEndDate.map(DateKit.fullDateText) ?? "未设置", secondary: asset.lockEndDate == nil)
                        RowSeparator(inset: 14)
                        attributeRow("备注", asset.note?.isEmpty == false ? asset.note! : "未填写", secondary: asset.note?.isEmpty != false)
                    }
                }
            } else {
                CardView {
                    attributeRow("备注", asset.note?.isEmpty == false ? asset.note! : "未填写", secondary: asset.note?.isEmpty != false)
                }
            }

            deleteArea(title: "永久删除", subtitle: deleteHintText)
        }
    }

    private var fixedTermContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("本金")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusPill(text: asset.fundingStatus.title, color: AppTheme.statusColor(asset.fundingStatus))
                    }
                    Text(asset.lifecycle == .settled ? "¥0.00" : asset.principal.currencyText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    HStack {
                        Text("预计利息（仅展示）")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(asset.estimatedYield.currencyText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    if asset.lifecycle != .settled {
                        HStack {
                            Text("到账本息")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Money.rounded(asset.principal + asset.estimatedYield).currencyText)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    if asset.lifecycle == .due {
                        WarningBanner(
                            title: "今天到期",
                            message: "本金仍计入总资产。结清后才会进入活期，App 不会自动到账。"
                        )
                    } else if asset.lifecycle == .active, let maturityDate = asset.maturityDate {
                        HStack {
                            Text(DateKit.relativeDueText(maturityDate))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let startDate = asset.startDate {
                                let held = max(DateKit.dayCount(startDate, Date()), 0)
                                let total = max(DateKit.dayCount(startDate, maturityDate), 0)
                                Text("已持有 \(held) / \(total) 天")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if asset.lifecycle == .settled {
                        HStack {
                            Text("实际到账")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text((asset.settledAmount ?? .zero).currencyText)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(18)
            }

            CardView {
                VStack(spacing: 0) {
                    attributeRow("所属账户", asset.account?.name ?? "")
                    RowSeparator(inset: 14)
                    attributeRow("年化收益率", Money.percent(asset.annualRate, fractionDigits: 2))
                    RowSeparator(inset: 14)
                    attributeRow("起息日", asset.startDate.map(DateKit.fullDateText) ?? "")
                    RowSeparator(inset: 14)
                    attributeRow("到期日", asset.maturityDate.map(DateKit.fullDateText) ?? "")
                    RowSeparator(inset: 14)
                    attributeRow("创建方式", asset.fundingMode?.title ?? "录入已有")
                    if let sourceID = asset.sourceCashAssetID,
                       let source = assets.first(where: { $0.id == sourceID }) {
                        RowSeparator(inset: 14)
                        attributeRow("本金来源", "\(source.account?.name ?? "") · \(source.name)")
                    }
                    RowSeparator(inset: 14)
                    attributeRow("备注", asset.note?.isEmpty == false ? asset.note! : "未填写", secondary: asset.note?.isEmpty != false)
                }
            }

            if asset.lifecycle != .settled {
                Button("结清") {
                    showSettlement = true
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("删除") {
                    showDelete = true
                }
                .buttonStyle(SecondaryButtonStyle(foreground: AppTheme.gain))
            } else {
                deleteArea(title: "永久删除", subtitle: "删除后不会回滚已到账活期，但对应历史盈亏会从累计投资盈亏中移除。")
            }
        }
    }

    private func attributeRow(_ title: String, _ value: String, secondary: Bool = false, valueColor: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(secondary ? .secondary : valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func deleteArea(title: String, subtitle: String) -> some View {
        Button {
            if PortfolioEngine.deleteBlockerMessage(for: asset, assets: assets) == nil {
                showDelete = true
            }
        } label: {
            CardView {
                HStack {
                    Text(title)
                        .foregroundStyle(PortfolioEngine.deleteBlockerMessage(for: asset, assets: assets) == nil ? AppTheme.gain : .secondary)
                    Spacer()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private var deleteHintText: String {
        if let blocker = PortfolioEngine.deleteBlockerMessage(for: asset, assets: assets) {
            return blocker
        }

        switch asset.kind {
        case .cash, .cashPlus:
            return "余额为 0 时可删除"
        case .fund, .stock, .bankWealth:
            return "当前市值为 0 时可删除"
        case .fixedTerm:
            return asset.lifecycle == .settled ? "删除该历史记录" : "删除该定期"
        default:
            return "暂不支持删除"
        }
    }

    private func requestTransfer(_ direction: CashTransferDirection) {
        if let blocker = PortfolioEngine.securitiesTransferBlocker(for: asset, accounts: accounts, assets: assets) {
            presentedError = BusinessError(message: blocker)
        } else {
            transferRequest = TransferRequest(direction: direction)
        }
    }
}
