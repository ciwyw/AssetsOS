import SwiftData
import SwiftUI

struct OverviewScreen: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BackupManager.self) private var backupManager

    @Query(sort: [SortDescriptor(\Account.name)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    @State private var expandedStatuses = Set<FundingStatus>()

    private var totalAssets: Decimal { PortfolioEngine.totalAssets(in: assets) }
    private var investmentRows: [InvestmentPnLRow] { PortfolioEngine.investmentBreakdown(assets: assets) }
    private var totalInvestmentPnL: Decimal { PortfolioEngine.totalInvestmentPnL(assets: assets) }
    private var fundingRows: [FundingStatusBreakdown] { PortfolioEngine.fundingBreakdown(assets: assets) }
    private var categoryRows: [CategoryBreakdown] { PortfolioEngine.categoryBreakdown(accounts: accounts, assets: assets) }
    private var processingItems: [ProcessingItem] { PortfolioEngine.processingItems(assets: assets) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                heading
                summaryCard
                backupBanner

                if accounts.isEmpty {
                    emptyStateCard
                } else {
                    if !processingItems.isEmpty {
                        processingSection
                    }
                    fundingSection
                    categorySection
                    investmentSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("总览")
        .navigationBarTitleDisplayMode(.large)
    }

    private var heading: some View {
        EmptyView()
    }

    private var summaryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("净资产")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(totalAssets.currencyText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accounts.isEmpty ? .secondary : .primary)

                Divider()

                HStack {
                    Text("累计投资盈亏")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(totalInvestmentPnL.signedCurrencyText)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.amountColor(totalInvestmentPnL))
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var backupBanner: some View {
        switch backupManager.state {
        case .unconfigured:
            WarningBanner(
                title: "尚未配置备份",
                message: "数据只保存在本机。前往账户页右上角的设置，选择 iCloud Drive 目录。"
            )
        case .failed(let message):
            WarningBanner(
                title: "最近一次备份失败",
                message: message,
                tint: AppTheme.gain
            )
        case .awaitingExistingBackup:
            WarningBanner(
                title: "目录中发现旧备份待处理",
                message: "你已经选择空白开始，当前暂停自动写入。请前往设置决定恢复旧备份、覆盖旧备份或更换目录。"
            )
        case .normal:
            EmptyView()
        }
    }

    private var emptyStateCard: some View {
        CardView {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.grid.1x2")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 56, height: 56)
                    .background(AppTheme.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 6) {
                    Text("尚未创建账户")
                        .font(.title3.weight(.semibold))
                    Text("先按银行、支付平台、基金平台或证券平台创建账户，再在账户里录入活期、定期和投资。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("新增账户") {
                    coordinator.openAddAccount()
                }
                .buttonStyle(PrimaryButtonStyle())

                Text("不预置任何银行、平台或示例资产。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: "需处理")
            VStack(spacing: 8) {
                ForEach(processingItems) { item in
                    Button {
                        coordinator.routeToFixedTerms()
                    } label: {
                        CardView {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.kind.title) · 1 笔")
                                        .font(.headline)
                                        .foregroundStyle(item.kind == .due ? AppTheme.gain : .primary)
                                    Text(item.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Text(item.asset.currentPortfolioAmount.currencyText)
                                        .font(.headline)
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(14)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var fundingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: "资金状态")
            CardView {
                VStack(spacing: 0) {
                    ForEach(Array(fundingRows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            if expandedStatuses.contains(row.status) {
                                expandedStatuses.remove(row.status)
                            } else {
                                expandedStatuses.insert(row.status)
                            }
                        } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(AppTheme.statusColor(row.status))
                                        .frame(width: 8, height: 8)
                                    Text(row.status.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(row.amount.currencyText)
                                        .font(.body)
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                    Image(systemName: expandedStatuses.contains(row.status) ? "chevron.down" : "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if expandedStatuses.contains(row.status), !row.assets.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(Array(row.assets.enumerated()), id: \.element.id) { assetIndex, asset in
                                            if assetIndex > 0 { RowSeparator(inset: 32) }
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(asset.name)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.primary)
                                                    Text(asset.account?.name ?? "")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text(asset.currentPortfolioAmount.currencyText)
                                                    .font(.subheadline)
                                                    .monospacedDigit()
                                                    .foregroundStyle(.primary)
                                            }
                                            .padding(.leading, 32)
                                            .padding(.trailing, 14)
                                            .padding(.vertical, 9)
                                        }
                                    }
                                    .background(Color(uiColor: .systemGray6).opacity(0.45))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        if index < fundingRows.count - 1 { RowSeparator(inset: 32) }
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: "账户类别分布")
            CardView {
                VStack(spacing: 0) {
                    ForEach(Array(categoryRows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            coordinator.routeToAccounts(category: row.category)
                        } label: {
                            HStack {
                                Text(row.category.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(row.amount.currencyText)
                                    .font(.body)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if index < categoryRows.count - 1 { RowSeparator(inset: 14) }
                    }
                }
            }
        }
    }

    private var investmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: "累计投资盈亏")
            CardView {
                VStack(spacing: 0) {
                    ForEach(Array(investmentRows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            Text(row.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(row.amount.signedCurrencyText)
                                .font(.body)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.amountColor(row.amount))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < investmentRows.count - 1 { RowSeparator(inset: 14) }
                    }

                    RowSeparator(inset: 14)
                    HStack {
                        Text("合计")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(totalInvestmentPnL.signedCurrencyText)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.amountColor(totalInvestmentPnL))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGray6).opacity(0.5))
                }
            }

            Text("根据当前记录的投资资产计算")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}
