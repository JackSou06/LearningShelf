import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CourseAuthoringView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var authoring: CourseAuthoringStore
    @Environment(\.dismiss) private var dismiss
    @State private var dropTarget = false
    @State private var showsSetup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI 製作課程", systemImage: "sparkles").font(.system(size: 23, weight: .semibold))
                    Text("加入教材後，自動完成教程、審閱修正與課程製作，驗證後加入書架。")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button("關閉") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dropArea
                    connection
                    if let job = authoring.selectedJob { jobContent(job) }
                    if !authoring.message.isEmpty { Text(authoring.message).foregroundColor(.red).font(.system(size: 12)).textSelection(.enabled) }
                    if !authoring.jobs.isEmpty {
                        Picker("製作紀錄", selection: $authoring.selectedJobID) {
                            ForEach(authoring.jobs) { job in
                                Text(job.title + " · " + CourseAuthoringStore.title(for: job.stage)).tag(Optional(job.id))
                            }
                        }.font(.system(size: 12)).disabled(authoring.isBusy)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Text("教材與製作結果保留在此 Mac；生成內容時會連線至 Codex。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                if authoring.isBusy { Text("關閉此頁可繼續製作").font(.system(size: 11)).foregroundColor(.secondary) }
            }.padding(16)
        }
        .frame(minWidth: 740, idealWidth: 900, maxWidth: 1100, minHeight: 580, idealHeight: 740, maxHeight: 900)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await authoring.connect(); showsSetup = !authoring.authenticated }
        .accessibilityIdentifier("authoring-page")
    }

    private var dropArea: some View {
        VStack(spacing: 11) {
            Image(systemName: "doc.badge.arrow.up").font(.system(size: 26)).foregroundColor(.accentColor)
            Text(authoring.isBusy ? "正在製作課程" : "將 PDF、PPTX 或 MD 拖到這裡").font(.system(size: 16, weight: .medium))
            Text("也可附圖片；多份教材會合成一門課，不需逐步確認。")
                .font(.system(size: 12)).foregroundColor(.secondary)
            Button("選擇教材並自動製作", action: chooseFiles).buttonStyle(.borderedProminent)
                .disabled(authoring.isBusy).accessibilityIdentifier("authoring-add-files")
        }
        .frame(maxWidth: .infinity).padding(22)
        .background(Color.accentColor.opacity(dropTarget ? 0.12 : 0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(dropTarget ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [7])))
        .cornerRadius(12)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
            guard !authoring.isBusy else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { c in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            if let data = item as? Data { c.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                            else if let url = item as? URL { c.resume(returning: url) }
                            else if let text = item as? String { c.resume(returning: URL(string: text)) }
                            else { c.resume(returning: nil) }
                        }
                    }
                    if let url, url.isFileURL { urls.append(url) }
                }
                authoring.create(urls, destination: store.currentShelfFolder)
            }
            return !providers.isEmpty
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(authoring.connection, systemImage: authoring.authenticated ? "checkmark.circle.fill" : "person.crop.circle")
                    .font(.system(size: 12)).foregroundColor(authoring.authenticated ? .green : .secondary)
                Spacer()
                if authoring.connecting { ProgressView().controlSize(.small) }
                if !authoring.authenticated {
                    Button("登入 Codex") { Task { await authoring.login() } }.disabled(authoring.executablePath.isEmpty || authoring.isBusy)
                        .accessibilityIdentifier("authoring-login")
                }
            }
            DisclosureGroup("首次設定與模型", isExpanded: $showsSetup) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Codex 執行檔", text: $authoring.executablePath).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("authoring-executable")
                        Button("選擇…", action: authoring.chooseExecutable)
                        Button("重新連線") { Task { await authoring.connect() } }.disabled(authoring.connecting)
                    }
                    if !authoring.models.isEmpty {
                        Picker("製作模型", selection: $authoring.selectedModelID) {
                            ForEach(authoring.models) { Text($0.title).tag($0.id) }
                        }
                    }
                    Link("安裝 Codex CLI", destination: URL(string: "https://learn.chatgpt.com/docs/cli")!).font(.system(size: 11))
                    Text("首次需要可用的 Codex 執行檔與登入。PPTX 另需 Keynote 或 LibreOffice；PDF、MD 不需要簡報轉換工具。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }.padding(.top, 8).disabled(authoring.isBusy)
            }.font(.system(size: 12))
        }
    }

    private func jobContent(_ job: AuthoringJob) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.courseTitle ?? job.title).font(.system(size: 17, weight: .semibold))
                    Text(CourseAuthoringStore.title(for: job.stage)).font(.system(size: 12)).foregroundColor(job.stage == "failed" ? .red : .secondary)
                        .accessibilityIdentifier("authoring-stage")
                }
                Spacer()
                if authoring.isBusy && authoring.activeJobID == job.id { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 9) {
                ForEach(Array(CourseAuthoringStore.stages.enumerated()), id: \.offset) { index, phase in
                    HStack(spacing: 6) {
                        Image(systemName: stageDone(job, index) ? "checkmark.circle.fill" : phase.0 == job.stage ? "circle.inset.filled" : "circle")
                            .foregroundColor(stageDone(job, index) ? .green : .secondary)
                        Text(phase.1).font(.system(size: 12))
                    }
                }
            }.padding(12).background(Color.gray.opacity(0.06)).cornerRadius(8)
            if let error = job.error {
                Text(error).font(.system(size: 12)).foregroundColor(.red).textSelection(.enabled)
                    .accessibilityIdentifier("authoring-error")
            }
            if !job.inputs.isEmpty { Text(job.inputs.map(\.originalName).joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(3) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(job.messages.enumerated()), id: \.offset) { i, text in Text(text).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).id(i) }
                    }.padding(10)
                }.frame(height: 130).background(Color(nsColor: .textBackgroundColor)).cornerRadius(8)
                    .onChange(of: job.messages.count) { _ in if let last = job.messages.indices.last { proxy.scrollTo(last, anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                if authoring.isBusy && authoring.activeJobID == job.id {
                    Button("取消製作", role: .destructive) { authoring.cancel() }.disabled(job.stage == "importing")
                        .accessibilityIdentifier("authoring-cancel")
                } else if ["failed", "cancelled", "interrupted", "waitingForLogin"].contains(job.stage) {
                    Button(job.stage == "waitingForLogin" ? "登入後繼續" : "重試並接續") { authoring.resume(job.id) }
                        .disabled(!authoring.authenticated || job.inputs.isEmpty).accessibilityIdentifier("authoring-retry")
                    if job.stage == "waitingForLogin" {
                        Button("取消製作", role: .destructive) { authoring.cancelWaiting(job.id) }
                    }
                }
                if FileManager.default.fileExists(atPath: authoring.workDirectory(job.id).appendingPathComponent("draft/tutorial.md").path) {
                    Button("查看教程") { NSWorkspace.shared.open(authoring.workDirectory(job.id).appendingPathComponent("draft/tutorial.md")) }
                }
                Button("查看結果") { NSWorkspace.shared.activateFileViewerSelecting([authoring.workDirectory(job.id)]) }
                Spacer()
                if let id = job.importedID, let entry = store.entries.first(where: { $0.id == id }) {
                    Button("開始閱讀") { store.open(entry); dismiss() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("authoring-read")
                }
            }.font(.system(size: 12))
        }.padding(16).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
    }

    private func stageDone(_ job: AuthoringJob, _ index: Int) -> Bool {
        if job.stage == "completed" { return true }
        if let current = CourseAuthoringStore.stages.firstIndex(where: { $0.0 == job.stage }) { return index < current }
        if index == 0 { return !job.inputs.isEmpty }
        return index < 4 && job.completedStages.contains(CourseAuthoringStore.stages[index].0)
    }
    private func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = AuthoringMaterials.extensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.message = "選擇要製作成同一門課的教材；加入後會自動開始。"
        if panel.runModal() == .OK { authoring.create(panel.urls, destination: store.currentShelfFolder) }
    }
}
