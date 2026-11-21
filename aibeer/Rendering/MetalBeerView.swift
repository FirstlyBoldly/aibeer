import BeerCore
import MetalKit
import SwiftUI

/// Full-screen Metal view rendering the beer liquid shader.
struct MetalBeerView: UIViewRepresentable {
    let engine: BeerEngine

    func makeCoordinator() -> Renderer {
        Renderer(engine: engine)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device: nothing we can render. The view stays empty.
            return view
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.024, blue: 0.035, alpha: 1)
        view.isOpaque = true
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        context.coordinator.setup(device: device)
        engine.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    /// Drives the frame loop: advances the engine, uploads uniforms, draws a
    /// fullscreen triangle through the liquid pipeline.
    final class Renderer: NSObject, MTKViewDelegate {
        private let engine: BeerEngine
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var lastTimestamp: CFTimeInterval = 0

        init(engine: BeerEngine) {
            self.engine = engine
        }

        func setup(device: MTLDevice) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            guard let library = device.makeDefaultLibrary(),
                let vertex = library.makeFunction(name: "beerVertex"),
                let fragment = library.makeFunction(name: "beerFragment")
            else {
                return
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            engine.uniforms.spriteSize = SIMD2(Float(size.width), Float(size.height))
        }

        func draw(in view: MTKView) {
            let dt =
                lastTimestamp == 0
                ? 1.0 / 60.0
                : min(view.timestamp - lastTimestamp, 0.1)
            lastTimestamp = view.timestamp

            engine.advance(dt: dt)
            engine.uniforms.spriteSize = SIMD2(
                Float(view.drawableSize.width), Float(view.drawableSize.height))

            guard
                let pipeline,
                let commandQueue,
                let drawable = view.currentDrawable,
                let renderPass = view.currentRenderPassDescriptor,
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
            else { return }

            renderEncoder.setRenderPipelineState(pipeline)
            var uniforms = engine.uniforms
            renderEncoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<BeerUniforms>.stride,
                index: 0)
            renderEncoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<BeerUniforms>.stride,
                index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
