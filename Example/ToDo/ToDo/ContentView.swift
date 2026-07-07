import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            TodoListWrapper()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TodoListWrapper()
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
