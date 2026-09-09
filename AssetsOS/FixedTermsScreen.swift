import SwiftData
import SwiftUI

struct FixedTermsScreen: View {
    @Query(sort: [SortDescriptor(\Asset.createdAt)]) private var assets: [Asset]

    @State private var showSettled = false
    @State private var showCreateSheet = false
    @State private var termToSettle: Asset?

    private var dueTerms: [Asset] { PortfolioEngine.fixedTerms(status: .due, assets: assets) }
    private var activeTerms: [Asset] { PortfolioEngine.fixedTerms(status: .active, assets: assets) }
    private var settledTerms: [Asset] { PortfolioEngine.fixedTerms(status: .settled, assets: assets) }
    private var summary: FixedTermSummary { PortfolioEngine.fixedTermSummary(assets: assets) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                summaryCard

                if !dueTerms.isEmpty {
                    termSection(title: "待结清 · \(dueTerms.count)", tint: AppTheme.gain, terms: dueTerms, quickSettle: true)
                }

                termSection(title: "进行中 · \(activeTerms.count)", tint: .secondary, terms: activeTerms, quickSettle: false)

                if !settledTerms.isEmpty {
                    settledSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("定期")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                FixedTermEditorView(existingAsset: nil, presetAccount: nil)
            }
        }
        .sheet(item: $termToSettle) { asset in
            FixedTermSettlementView(asset: asset)
        }
    }

    private var summaryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("进行中")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(summary.activePrincipal.currencyText)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("\(summary.activeCount) 笔 · 预计利息 \(summary.activeEstimatedYield.currencyText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                        .frame(height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("待结清")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.gain)
                        Text(summary.duePrincipal.currencyText)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.gain)
                        Text("\(summary.dueCount) 笔 · 最近到期 \(summary.nearestMaturityDate.map(DateKit.shortDateText) ?? "--")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("预计利息仅展示，不计入总资产与累计投资盈亏。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func termSection(title: String, tint: Color, terms: [Asset], quickSettle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: title)
            CardView {
                VStack(spacing: 0) {
                    ForEach(Array(terms.enumerated()), id: \.element.id) { index, asset in
                        if quickSettle {
                            dueRow(asset)
                        } else {
                            NavigationLink {
                                AssetDetailScreen(asset: asset)
                            } label: {
                                termRow(asset)
                            }
                            .buttonStyle(.plain)
                        }

                        if index < terms.count - 1 { RowSeparator(inset: 14) }
                    }
                }
            }
        }
    }

    private func dueRow(_ asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(asset.account?.name ?? "") · \(Money.percent(asset.annualRate, fractionDigits: 2)) · \(asset.startDate.map(DateKit.dateOnlyString) ?? "") 起息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(asset.currentPortfolioAmount.currencyText)
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("\(DateKit.relativeDueText(asset.maturityDate ?? Date())) · 预计利息 \(asset.estimatedYield.currencyText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("结清") {
                    termToSettle = asset
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(14)
    }

    private func termRow(_ asset: Asset) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(asset.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text(asset.currentPortfolioAmount.currencyText)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            HStack {
                Text("\(asset.account?.name ?? "") · \(Money.percent(asset.annualRate, fractionDigits: 2)) · \(asset.maturityDate.map(DateKit.shortDateText) ?? "--") 到期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DateKit.relativeDueText(asset.maturityDate ?? Date()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.warning)
            }
            Text("预计利息 \(asset.estimatedYield.currencyText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var settledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderText(title: "已结清 · \(settledTerms.count)")
            CardView {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut) {
                            showSettled.toggle()
                        }
                    } label: {
                        HStack {
                            Text("已结清 · \(settledTerms.count)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showSettled ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)

                    if showSettled {
                        RowSeparator(inset: 14)
                        VStack(spacing: 0) {
                            ForEach(Array(settledTerms.enumerated()), id: \.element.id) { index, asset in
                                NavigationLink {
                                    AssetDetailScreen(asset: asset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .top) {
                                            Text(asset.name)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Text(asset.investmentProfitLoss.signedCurrencyText)
                                                .font(.body)
                                                .monospacedDigit()
                                                .foregroundStyle(AppTheme.amountColor(asset.investmentProfitLoss))
                                        }
                                        HStack {
                                            Text("\(asset.account?.name ?? "") · 本金 \(asset.principal.currencyText)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(asset.settledAt.map(DateKit.fullDateText) ?? "")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("实际到账 \((asset.settledAmount ?? .zero).currencyText) · 当前金额 \(asset.currentPortfolioAmount.currencyText)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                                if index < settledTerms.count - 1 { RowSeparator(inset: 14) }
                            }
                        }
                    }
                }
            }

            Text("已结清不计入总资产，但仍参与累计投资盈亏，并会阻止账户删除。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}
