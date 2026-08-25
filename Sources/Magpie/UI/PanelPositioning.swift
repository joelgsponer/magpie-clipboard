import AppKit

/// Shared by the overlay panels (history, emoji, dictation): centers a panel
/// on whichever screen currently has the mouse cursor.
enum PanelPositioning {
    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    static func centerOrigin(for frame: NSRect, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
    }

    /// Gives a panel a persistent position across launches: wires up AppKit's
    /// frame-autosave (`setFrameAutosaveName`), which restores the last saved
    /// frame as a side effect and thereafter saves automatically whenever the
    /// user moves/resizes the window — no per-drag bookkeeping needed. Only
    /// on the very first-ever show (no saved frame yet, tracked by our own
    /// marker rather than AppKit's internal storage) does it fall back to
    /// centering under the mouse cursor.
    static func applyPersistentPosition(to panel: NSPanel, autosaveName: String) {
        panel.setFrameAutosaveName(autosaveName)

        let positionedKey = "\(autosaveName).hasPositioned"
        guard !UserDefaults.standard.bool(forKey: positionedKey) else { return }

        if let screen = screenUnderMouse() ?? NSScreen.main {
            panel.setFrameOrigin(centerOrigin(for: panel.frame, on: screen))
        }
        UserDefaults.standard.set(true, forKey: positionedKey)
    }
}
