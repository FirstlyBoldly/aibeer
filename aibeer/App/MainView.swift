import SwiftUI

/// Full-screen beer view: direct Metal rendering (no SpriteKit).
struct MainView: View {
    @State private var engine = BeerEngine()

    var body: some View {
        MetalBeerView(engine: engine)
            .ignoresSafeArea()
            .statusBarHidden(true)
            .onAppear {
                // Don't let the screen sleep mid-trick.
                UIApplication.shared.isIdleTimerDisabled = true
            }
    }
}
