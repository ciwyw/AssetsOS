import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private enum PickerTarget {
    case folder
    case restoreFile
}

private struct RestoreRequest: Identifiable {
    enum Source {
        case pending
        case file(URL)
    }

    let id = UUID()
    let source: Source
    let preview: BackupPreview
}

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(BackupManager.self) private var backupManager

    @State private var pickerTarget: PickerTarget?
    @State private var restoreRequest: RestoreRequest?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var presentedError: BusinessError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if case .failed(let message) = backupManager.state {
                        WarningBanner(title: "最近一次备份失败", message: message, tint: AppTheme.gain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderText(title: "备份")
                        backupCard
                    }

                    if case .awaitingExistingBackup(let preview) = backupManager.state {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderText(title: "目录中发现旧备份")
                            pendingBackupCard(preview: preview)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderText(title: "通知")
                        notificationCard
                    }
                }
                .padding(16)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                notificationStatus = await TermNotificationManager.refreshAuthorizationStatus()
            }
            .fileImporter(
                isPresented: Binding(
                    get: { pickerTarget != nil },
                    set: { if !$0 { pickerTarget = nil } }
                ),
                allowedContentTypes: pickerTarget == .folder ? [.folder] : [.json],
                allowsMultipleSelection: false
            ) { result in
                handlePickerResult(result)
            }
            .sheet(item: $restoreRequest) { request in
                RestoreConfirmationView(request: request) {
                    Task {
                        do {
                            switch request.source {
                            case .pending:
                                try await backupManager.restorePendingBackup(into: modelContext)
                            case .file(let url):
                                try await backupManager.restore(fileAt: url, into: modelContext)
                            }
                            notificationStatus = await TermNotificationManager.refreshAuthorizationStatus()
                        } catch let error as BusinessError {
                            presentedError = error
                        } catch {
                            presentedError = BusinessError(message: error.localizedDescription)
                        }
                    }
                }
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("操作失败"), message: Text(error.message), dismissButton: .default(Text("知道了")))
            }
        }
    }

    private var backupCard: some View {
        CardView {
            VStack(spacing: 0) {
                infoRow(label: "状态", value: backupStatusText, valueColor: backupStatusColor)

                if let folderName = backupManager.folderName {
                    RowSeparator(inset: 14)
                    infoRow(label: "备份目录", value: folderName, secondary: true)
                }

                if let lastSuccessAt = backupManager.lastSuccessAt {
                    RowSeparator(inset: 14)
                    infoRow(label: "最近成功备份", value: DateKit.fullDateTimeText(lastSuccessAt), secondary: true)
                }

                if backupManager.isConfigured, !backupManager.state.isAwaitingExistingBackup {
                    RowSeparator(inset: 14)
                    actionRow(title: backupManager.isRunning ? "备份中…" : "立即备份") {
                        Task { await backupManager.backupNow(from: modelContext) }
                    }
                }

                RowSeparator(inset: 14)
                actionRow(title: chooseFolderTitle) {
                    pickerTarget = .folder
                }

                RowSeparator(inset: 14)
                actionRow(title: "恢复备份") {
                    pickerTarget = .restoreFile
                }
            }
        }
    }

    private func pendingBackupCard(preview: BackupPreview) -> some View {
        CardView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("备份时间 \(DateKit.fullDateTimeText(preview.exportedAt))")
                        .font(.body)
                    Text("\(preview.accountCount) 个账户 · \(preview.assetCount) 项资产 · \(preview.fixedTermCount) 笔定期 · schemaVersion \(preview.schemaVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                RowSeparator(inset: 14)
                actionRow(title: "恢复该备份（整库替换）") {
                    do {
                        let preview = try backupManager.previewPendingBackup()
                        restoreRequest = RestoreRequest(source: .pending, preview: preview)
                    } catch let error as BusinessError {
                        presentedError = error
                    } catch {
                        presentedError = BusinessError(message: error.localizedDescription)
                    }
                }

                RowSeparator(inset: 14)
                actionRow(title: "用当前数据覆盖旧备份") {
                    Task { await backupManager.overwritePendingBackup(from: modelContext) }
                }

                RowSeparator(inset: 14)
                actionRow(title: "选择新备份目录") {
                    pickerTarget = .folder
                }
            }
        }
    }

    private var notificationCard: some View {
        CardView {
            VStack(spacing: 0) {
                infoRow(label: "通知权限", value: notificationStatusText, valueColor: notificationStatusColor)
                RowSeparator(inset: 14)
                infoRow(label: "定期提醒", value: "到期前 3 天 / 当天 09:00", secondary: true)
            }
        }
    }

    private var chooseFolderTitle: String {
        if case .failed = backupManager.state { return "重新选择目录" }
        return backupManager.isConfigured ? "更换备份目录" : "选择备份目录"
    }

    private var backupStatusText: String {
        switch backupManager.state {
        case .normal: return "正常"
        case .unconfigured: return "未配置"
        case .failed: return "失败"
        case .awaitingExistingBackup: return "等待处理已有备份"
        }
    }

    private var backupStatusColor: Color {
        switch backupManager.state {
        case .normal: return AppTheme.loss
        case .unconfigured: return .secondary
        case .failed: return AppTheme.gain
        case .awaitingExistingBackup: return AppTheme.warning
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "已拒绝"
        case .notDetermined: return "未决定"
        @unknown default: return "未知"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return AppTheme.loss
        case .denied: return AppTheme.gain
        default: return .secondary
        }
    }

    private func infoRow(label: String, value: String, secondary: Bool = false, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(secondary ? .secondary : valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func actionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        pickerTarget = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch url.pathExtension.lowercased() {
            case "json":
                do {
                    let preview = try backupManager.previewRestore(fileAt: url)
                    restoreRequest = RestoreRequest(source: .file(url), preview: preview)
                } catch let error as BusinessError {
                    presentedError = error
                } catch {
                    presentedError = BusinessError(message: error.localizedDescription)
                }
            default:
                Task {
                    if backupManager.isConfigured {
                        await backupManager.changeDirectory(url, context: modelContext)
                    } else {
                        await backupManager.configureInitialDirectory(url, context: modelContext)
                    }
                }
            }
        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError { return }
            presentedError = BusinessError(message: error.localizedDescription)
        }
    }
}

private struct RestoreConfirmationView: View {
    let request: RestoreRequest
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                CardView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("恢复备份")
                            .font(.title3.weight(.semibold))
                        Text("恢复采用整库替换，不做合并。恢复前会先校验备份并额外保存当前数据。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }

                CardView {
                    VStack(spacing: 0) {
                        row(label: "备份时间", value: DateKit.fullDateTimeText(request.preview.exportedAt))
                        RowSeparator(inset: 14)
                        row(label: "账户数量", value: "\(request.preview.accountCount)")
                        RowSeparator(inset: 14)
                        row(label: "资产数量", value: "\(request.preview.assetCount)")
                        RowSeparator(inset: 14)
                        row(label: "定期数量", value: "\(request.preview.fixedTermCount)")
                        RowSeparator(inset: 14)
                        row(label: "schemaVersion", value: "\(request.preview.schemaVersion)")
                    }
                }

                Spacer()

                Button("确认恢复") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("恢复备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
