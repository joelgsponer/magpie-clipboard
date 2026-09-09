import AppKit

/// The chrome shared by the activating overlay panels (launcher, search,
/// R console): a floating, title-less, translucent utility panel that
/// remembers its position. Mirrors HistoryWindow.makePanel.
enum OverlayPanel {
    @MainActor
    static func make(width: CGFloat, height: CGFloat, autosaveName: String, resizable: Bool = false) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .closable, .utilityWindow]
        if resizable { style.insert(.resizable) }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.title = "Magpie"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
            .ignoresCycle,
        ]
        PanelPositioning.applyPersistentPosition(to: panel, autosaveName: autosaveName)
        return panel
    }
}
