import Foundation
import SwiftUI
import Combine
import AppKit

/// UpdateManager handles checking GitHub Releases API for CoolCumber updates
/// and provides in-app notification and direct download workflows.
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    private let repoOwner = "lastkimi"
    private let repoName = "CoolCumber"
    
    @Published var isChecking: Bool = false
    @Published var hasUpdate: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var releaseURL: String = "https://github.com/lastkimi/CoolCumber/releases"
    @Published var downloadURL: String = ""
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String? = nil
    @Published var showUpdateSheet: Bool = false
    
    @AppStorage("autoCheckUpdates") var autoCheckUpdates: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        #if !APPSTORE
        if autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.checkForUpdates(isManual: false)
            }
        }
        #endif
    }
    
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    func checkForUpdates(isManual: Bool = true) {
        #if APPSTORE
        isChecking = false
        hasUpdate = false
        if isManual {
            statusMessage = LanguageManager.shared.currentLanguage == "zh"
                ? "此版本由 Mac App Store 管理更新。"
                : "Updates for this edition are managed by the Mac App Store."
        }
        return
        #else
        guard !isChecking else { return }
        
        isChecking = true
        statusMessage = nil
        
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("CoolCumber-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                
                if let error = error {
                    print("Update check error: \(error)")
                    if isManual {
                        self.statusMessage = LanguageManager.shared.currentLanguage == "zh" ? "检查更新失败，请检查网络连接。" : "Failed to check for updates. Check your connection."
                    }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if isManual {
                        self.statusMessage = LanguageManager.shared.currentLanguage == "zh" ? "解析更新信息失败。" : "Failed to parse release info."
                    }
                    return
                }
                
                let rawTag = json["tag_name"] as? String ?? ""
                let version = rawTag.replacingOccurrences(of: "v", with: "").replacingOccurrences(of: "V", with: "").trimmingCharacters(in: .whitespaces)
                let body = json["body"] as? String ?? ""
                let htmlUrl = json["html_url"] as? String ?? "https://github.com/\(self.repoOwner)/\(self.repoName)/releases"
                
                var dmgDownloadUrl = ""
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg") {
                            dmgDownloadUrl = asset["browser_download_url"] as? String ?? ""
                            break
                        }
                    }
                }
                if dmgDownloadUrl.isEmpty {
                    dmgDownloadUrl = "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/latest/download/CoolCumber.dmg"
                }
                
                self.latestVersion = version
                self.releaseNotes = body
                self.releaseURL = htmlUrl
                self.downloadURL = dmgDownloadUrl
                
                if self.isVersion(version, greaterThan: self.currentVersion) {
                    self.hasUpdate = true
                    self.showUpdateSheet = true
                    self.statusMessage = LanguageManager.shared.currentLanguage == "zh" ? "发现新版本: v\(version)" : "New version available: v\(version)"
                } else {
                    self.hasUpdate = false
                    if isManual {
                        self.statusMessage = LanguageManager.shared.currentLanguage == "zh" ? "当前已是最新版本 (v\(self.currentVersion))。" : "You're up to date (v\(self.currentVersion))."
                    }
                }
            }
        }.resume()
        #endif
    }
    
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let parts1 = v1.components(separatedBy: ".").compactMap { Int($0) }
        let parts2 = v2.components(separatedBy: ".").compactMap { Int($0) }
        
        let maxLen = max(parts1.count, parts2.count)
        for i in 0..<maxLen {
            let num1 = i < parts1.count ? parts1[i] : 0
            let num2 = i < parts2.count ? parts2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
    
    func downloadAndOpenRelease() {
        #if APPSTORE
        statusMessage = LanguageManager.shared.currentLanguage == "zh"
            ? "请在 Mac App Store 的“更新”页面获取新版本。"
            : "Open the Mac App Store Updates page to get new versions."
        #else
        // Never execute or mount an unsigned asset downloaded by the app. The
        // release page lets the user inspect checksums/signing information and
        // keeps the update channel fail-closed until a signed Sparkle feed ships.
        guard let url = URL(string: releaseURL) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}
