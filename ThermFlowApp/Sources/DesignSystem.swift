import SwiftUI

/// CoolCumber Design System (v3.0 - Redesign)
/// A fully redesigned premium visual identity matching macOS HIG and SuperIsland style.
enum DesignSystem {
    
    // MARK: - Color Palette
    
    enum Colors {
        // Base surfaces
        static let windowBg = Color(white: 0.040) // #0A0A0A
        static let sidebarBg = Color(white: 0.070, opacity: 0.85) // #121212
        
        // Glassmorphism overlays
        static let glassBg = Color(white: 0.10, opacity: 0.60)
        static let glassBgHover = Color(white: 0.15, opacity: 0.70)
        static let glassBgActive = Color(white: 0.20, opacity: 0.75)
        
        // Text & Icons
        static let textPrimary = Color(white: 0.94) // #F0F0F0
        static let textSecondary = Color(white: 0.63) // #A0A0A0
        static let textTertiary = Color(white: 0.42) // #6B6B6B
        static let textInverse = Color(white: 0.04) // #0A0A0A
        
        // Brand Color - CoolCumber Premium Teal
        static let accentBrand = Color(red: 0.00, green: 0.83, blue: 0.67) // #00D4AA
        static let accentAI = Color(red: 0.65, green: 0.55, blue: 0.98) // AI Purple #A78BFA
        
        // Thermal State Semantic Colors
        static let statusIdle = Color(red: 0.38, green: 0.65, blue: 0.98) // Blue #60A5FA
        static let statusHealthy = Color(red: 0.20, green: 0.83, blue: 0.60) // Emerald #34D399
        static let statusWarning = Color(red: 0.98, green: 0.75, blue: 0.14) // Amber #FBBF24
        static let statusElevated = Color(red: 0.98, green: 0.57, blue: 0.24) // Orange #FB923C
        static let statusCritical = Color(red: 0.94, green: 0.27, blue: 0.27) // Red #EF4444
        
        // Glass Borders & Dividers
        static let glassBorder = Color(white: 1.0, opacity: 0.08)
        static let glassBorderHover = Color(white: 1.0, opacity: 0.15)
        static let divider = Color(white: 1.0, opacity: 0.06)
    }
    
    // MARK: - Typography (Data vs UI Split)
    
    enum Typography {
        // UI Typography (SF Pro)
        static let display = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title = Font.system(size: 18, weight: .semibold, design: .default)
        static let headline = Font.system(size: 13, weight: .semibold, design: .default)
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 11, weight: .medium, design: .default)
        static let micro = Font.system(size: 9, weight: .bold, design: .default)
        
        // Data Typography (SF Mono to prevent layout jitter)
        static let dataHero = Font.system(size: 24, weight: .bold, design: .monospaced)
        static let dataTitle = Font.system(size: 18, weight: .semibold, design: .monospaced)
        static let dataHeadline = Font.system(size: 13, weight: .bold, design: .monospaced)
        static let dataBody = Font.system(size: 13, weight: .medium, design: .monospaced)
        static let dataCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let dataMicro = Font.system(size: 9, weight: .regular, design: .monospaced)
    }
    
    // MARK: - Spacing & Grid (8pt System)
    
    enum Spacing {
        static let tight: CGFloat = 4
        static let normal: CGFloat = 8
        static let cardPadding: CGFloat = 12
        static let comfortable: CGFloat = 16
        static let sectionGap: CGFloat = 20
        static let pageMargin: CGFloat = 24
    }
    
    // MARK: - Corner Radius
    
    enum Corners {
        static let badge: CGFloat = 4
        static let smallButton: CGFloat = 6
        static let normal: CGFloat = 8
        static let card: CGFloat = 12
        static let popover: CGFloat = 16
        static let smartBarCompact: CGFloat = 18
        static let smartBarExpanded: CGFloat = 20
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let ambientColor = Color.black.opacity(0.15)
        static let ambientRadius: CGFloat = 8
        static let ambientY: CGFloat = 2
        
        static let keyColor = Color.black.opacity(0.30)
        static let keyRadius: CGFloat = 24
        static let keyY: CGFloat = 12
    }
    
    // MARK: - Animations (HIG Physical Spacing)
    
    enum Animations {
        static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.73)
        static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.85)
        static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.58)
        static let hover = Animation.spring(response: 0.25, dampingFraction: 0.80)
        static let spin = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)
    }
}

// MARK: - View Modifiers

struct GlassCardModifier: ViewModifier {
    var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Corners.card, style: .continuous)
                    .fill(isHovered ? DesignSystem.Colors.glassBgHover : DesignSystem.Colors.glassBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Corners.card, style: .continuous)
                    .stroke(isHovered ? DesignSystem.Colors.glassBorderHover : DesignSystem.Colors.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: DesignSystem.Shadows.ambientColor,
                radius: DesignSystem.Shadows.ambientRadius,
                y: DesignSystem.Shadows.ambientY
            )
    }
}

struct StatusBadgeModifier: ViewModifier {
    var color: Color
    
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.micro)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(DesignSystem.Corners.badge)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Corners.badge)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
    }
}

extension View {
    /// Applies a premium glassmorphic card look
    func glassCard(isHovered: Bool = false) -> some View {
        self.modifier(GlassCardModifier(isHovered: isHovered))
    }
    
    /// Applies a tinted status badge
    func statusBadge(color: Color) -> some View {
        self.modifier(StatusBadgeModifier(color: color))
    }
    
    /// Applies high-contrast double shadow for windows/overlays
    func windowShadow() -> some View {
        self
            .shadow(
                color: DesignSystem.Shadows.ambientColor,
                radius: DesignSystem.Shadows.ambientRadius,
                y: DesignSystem.Shadows.ambientY
            )
            .shadow(
                color: DesignSystem.Shadows.keyColor,
                radius: DesignSystem.Shadows.keyRadius,
                y: DesignSystem.Shadows.keyY
            )
    }
}
