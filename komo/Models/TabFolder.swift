import Foundation

class TabFolder: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var tabIDs: [UUID] = []
    @Published var isExpanded: Bool = true

    init(name: String) {
        self.name = name
    }
}
