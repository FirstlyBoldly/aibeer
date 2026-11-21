import SpriteKit
import SwiftUI

/// Full-screen beer view: the SpriteKit scene owns everything, including the
/// swipe gesture that changes the drink.
struct MainView: View {
    @State private var scene: BeerScene = {
        let scene = BeerScene()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .statusBarHidden(true)
            .onAppear {
                // Don't let the screen sleep mid-trick.
                UIApplication.shared.isIdleTimerDisabled = true
            }
    }
}
