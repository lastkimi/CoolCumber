import AppKit
import SwiftUI

class SmartBarManager {
    static let shared = SmartBarManager()
    
    private var window: NSPanel?
    
    // MARK: - Notch Detection (from SuperIsland's ScreenDetector approach)
    
    /// Detects the notch rectangle using auxiliaryTopLeftArea and auxiliaryTopRightArea.
    /// This is the same technique SuperIsland uses in ScreenDetector.swift.
    private func notchRect(screen: NSScreen) -> NSRect? {
        if #available(macOS 12.0, *) {
            guard let topLeft = screen.auxiliaryTopLeftArea,
                  let topRight = screen.auxiliaryTopRightArea else {
                return nil
            }
            let screenFrame = screen.frame
            // The notch is the gap between the two auxiliary areas
            let notchX = screenFrame.origin.x + topLeft.width
            let notchWidth = screenFrame.width - topLeft.width - topRight.width
            let notchY = screenFrame.maxY - max(topLeft.height, topRight.height)
            let notchHeight = max(topLeft.height, topRight.height)
            return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
        }
        return nil
    }
    
    /// Returns true if the screen has a notch (i.e. has auxiliary top areas).
    private func hasNotch(screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
        return false
    }
    
    private var isExpanded: Bool = false
    private let compactWidth: CGFloat = 230
    private let compactHeight: CGFloat = 38
    private let expandedWidth: CGFloat = 340
    private let expandedHeight: CGFloat = 160
    
    func setup() {
        let initialWidth = compactWidth
        let initialHeight = compactHeight
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        
        let hostingView = NSHostingView(rootView: SmartBarView())
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
        
        let containerView = TopCenterContainerView()
        containerView.addSubview(hostingView)
        panel.contentView = containerView
        
        self.window = panel
        
        // Position AFTER setting content
        positionWindow(panel)
        
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    func updateExpandedState(_ isHovering: Bool) {
        guard isExpanded != isHovering else { return }
        self.isExpanded = isHovering
        guard let panel = window else { return }
        positionWindow(panel)
    }
    
    @objc private func screenParametersChanged() {
        guard let panel = window else { return }
        positionWindow(panel)
    }
    
    private func positionWindow(_ panel: NSPanel) {
        // 1. Find the best screen: prefer screen with notch, then mouse screen, then first
        let targetScreen: NSScreen? = {
            // Prefer a screen with a physical notch
            if let notched = NSScreen.screens.first(where: { hasNotch(screen: $0) }) {
                return notched
            }
            // Fallback: screen with mouse
            let mouseLocation = NSEvent.mouseLocation
            if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
                return mouseScreen
            }
            return NSScreen.screens.first
        }()
        
        guard let screen = targetScreen else { return }
        
        // Hide panel if the target screen has no physical notch
        if !hasNotch(screen: screen) {
            panel.orderOut(nil)
            return
        }
        
        let screenFrame = screen.frame
        let currentWidth = isExpanded ? expandedWidth : compactWidth
        let currentHeight = isExpanded ? expandedHeight : compactHeight
        
        // 2. Compute X position: center on the notch if it exists
        let xPos: CGFloat
        if let notch = notchRect(screen: screen) {
            let notchCenterX = notch.midX
            xPos = notchCenterX - (currentWidth / 2)
        } else {
            xPos = screenFrame.midX - (currentWidth / 2)
        }
        
        // 3. Y position: top of window touches top of screen
        let yPos = screenFrame.maxY - currentHeight
        
        panel.setFrame(NSRect(x: xPos, y: yPos, width: currentWidth, height: currentHeight), display: true)
        panel.orderFront(nil)
    }
}

// MARK: - Container View
private final class TopCenterContainerView: NSView {
    override func layout() {
        super.layout()
        guard let hostingView = subviews.first else { return }
        hostingView.frame = bounds
    }
}

