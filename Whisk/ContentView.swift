import SwiftUI

struct ContentView: View {
    @StateObject private var dataManager = DataManager()
    
    var body: some View {
        GroceryListView(dataManager: dataManager)
    }
}

#Preview {
    ContentView()
}
