import AppKit
import Combine
import Sparkle

/// Sparkle owns version comparison, download verification, installation and relaunch.
@MainActor final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?
    private var startupError: Error?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { if let self { self.canCheckForUpdates = self.startupError != nil || updater.canCheckForUpdates } }
        }
        do { try controller.updater.start() }
        catch { startupError = error; canCheckForUpdates = true }
    }

    func checkForUpdates() {
        if let error = startupError {
            let alert = NSAlert()
            alert.messageText = "無法啟動更新功能"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    static var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "版本 \(info["CFBundleShortVersionString"] as? String ?? "—")（\(info["CFBundleVersion"] as? String ?? "—")）"
    }
}

/// Cancelling termination also cancels Sparkle's relaunch, so failed saves keep the app open.
@MainActor final class LearningAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    private var preparing = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard !preparing else { return .terminateLater }
        if store.session.hasActiveRequests {
            let alert = NSAlert()
            alert.messageText = "AI 回答尚未完成"
            alert.informativeText = "請等待回答完成，或在課程中取消問答後，再結束 App 或安裝更新。"
            alert.runModal()
            return .terminateCancel
        }
        preparing = true
        Task {
            do {
                try await store.prepareToQuit()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                await store.resumeAfterCancelledQuit()
                preparing = false
                let alert = NSAlert()
                alert.messageText = "紀錄尚未保存，已暫停結束 App"
                alert.informativeText = error.localizedDescription + "\n請重試，或先匯出紀錄。"
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
