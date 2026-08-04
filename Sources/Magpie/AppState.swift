import Foundation
import SwiftUI

enum PasteMode: String, CaseIterable, Identifiable {
    case paste
    case type
    var id: String { rawValue }
    var label: String { self == .paste ? "Paste" : "Type" }
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
