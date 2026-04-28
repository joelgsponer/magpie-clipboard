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
}
