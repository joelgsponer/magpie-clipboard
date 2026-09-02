import Foundation
import SwiftUI

enum PasteMode: String, CaseIterable, Identifiable {
    case paste
    case type
    var id: String { rawValue }
    var label: String { self == .paste ? "Paste" : "Type" }
}

/// What a screen capture puts on the pasteboard. Deliberately separate from
/// PasteMode, which means paste-vs-type and is wired into Paster.fire and the
/// history footer — the two are orthogonal choices.
enum CaptureCommitMode: String, CaseIterable, Identifiable {
    case textOnly
    case withContext
    var id: String { rawValue }
    var label: String { self == .textOnly ? "Text" : "Text + context" }
}

@MainActor
final class AppState: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedItemID: UUID?
    @Published var pasteMode: PasteMode = .paste
    /// Bumped each time the panel is shown. The view observes this to re-focus
    /// search and re-select the latest item, since onAppear only fires once
    /// (the panel is hidden with orderOut, never torn down).
    @Published var activationToken: Int = 0
}
