import AppKit
import SwiftUI
import Combine

class MenuBarManager {
    static let shared = MenuBarManager()
    
    var items: [String: NSStatusItem] = [:]
    private var dashboardWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    func setup() {
        // Create standard NSWindow instead of NSPopover
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = false
        window.center()
        window.title = "CoolCumber Dashboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        
        let hostingController = NSHostingController(rootView: DashboardView())
        window.contentViewController = hostingController
        
        // Hide standard window buttons for custom styling
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.dashboardWindow = window
        
        // Unified variable length status item
        setupItem(id: "main", length: NSStatusItem.variableLength) { button in
            let img = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "CoolCumber") ?? NSImage(systemSymbolName: "wind", accessibilityDescription: "CoolCumber")
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            let configuredImg = img?.withSymbolConfiguration(config)
            configuredImg?.isTemplate = true
            button.image = configuredImg
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(self.handleMainClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Observe DaemonManager publishers to update status bar text
        DaemonManager.shared.$temperatures
            .combineLatest(DaemonManager.shared.$currentCpuPercent, DaemonManager.shared.$currentMemPercent)
            .receive(on: RunLoop.main)
            .sink { [weak self] temps, cpu, mem in
                self?.updateStatusItemTitle(cpu: cpu, mem: mem, temp: temps["CPU"] ?? 0.0)
            }
            .store(in: &cancellables)
    }
    
    private func setupItem(id: String, length: CGFloat, configuration: ((NSStatusBarButton) -> Void)? = nil) {
        let item = NSStatusBar.system.statusItem(withLength: length)
        if let button = item.button {
            if let config = configuration {
                config(button)
            } else {
                button.title = "--"
                button.target = self
                button.action = #selector(self.openDashboard)
            }
        }
        items[id] = item
    }
    
    @objc func handleMainClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let quitItem = NSMenuItem(title: "Quit CoolCumber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quitItem.target = NSApp
            menu.addItem(quitItem)
            items["main"]?.menu = menu
            items["main"]?.button?.performClick(nil)
            items["main"]?.menu = nil // reset so left click works again
        } else {
            openDashboard()
        }
    }
    
    @objc func openDashboard() {
        guard let window = dashboardWindow else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            // Center the window on the screen where the mouse is (fallback to main screen)
            let mouseLocation = NSEvent.mouseLocation
            if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                let screenFrame = mouseScreen.frame
                let x = screenFrame.midX - (window.frame.width / 2)
                let y = screenFrame.midY - (window.frame.height / 2)
                window.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func closePopover() {
        dashboardWindow?.orderOut(nil)
    }
    
    private func updateStatusItemTitle(cpu: Double, mem: Double, temp: Double) {
        guard let button = items["main"]?.button else { return }
        
        let cpuStr = String(format: "%.0f%%", cpu)
        let memStr = String(format: "%.0f%%", mem)
        let tempStr = temp > 0 ? String(format: "%.0f°C", temp) : "--°C"
        
        button.title = " \(tempStr)  \(cpuStr)  \(memStr)"
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    }
}
