import BeerCore
import SpriteKit
import SwiftUI

/// Full-screen beer view: SpriteKit scene below, minimal glass-style controls above.
struct MainView: View {
    @State private var scene: BeerScene = {
        let scene = BeerScene()
        scene.scaleMode = .resizeFill
        return scene
    }()
    @State private var styleName = BeerStyle.lager.name

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            overlay
        }
        .statusBarHidden(true)
        .onAppear {
            // Don't let the screen sleep mid-trick.
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private var overlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                holdButton("FILL", to: 1)
                Menu {
                    ForEach(BeerStyle.all, id: \.id) { style in
                        Button(style.name) {
                            styleName = style.name
                            scene.select(style)
                        }
                    }
                } label: {
                    Text(styleName)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                holdButton("DRAIN", to: 0)
            }
            .padding(.bottom, 22)
        }
    }

    /// Press-and-hold pours (or drains) for as long as the button is held.
    private func holdButton(_ title: String, to level: Double) -> some View {
        Button {
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(
            minimumDuration: .infinity,
            pressing: { pressing in
                scene.hold(pouring: pressing, to: level)
            }, perform: {})
    }
}
