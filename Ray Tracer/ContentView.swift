//
//  ContentView.swift
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

import Cocoa
import Combine
import Metal
import MetalKit
import SwiftUI

struct ContentView: View {
    @StateObject var renderer = MetalRenderer()
    
    var body: some View {
        GeometryReader { geometry in
            MetalView(renderer: renderer)
                .onAppear {
                    renderer.setupTexture(width: Int(geometry.size.width),
                                          height: Int(geometry.size.height))
                    
                    initRayTracing(renderer: renderer, geometry: geometry)
                    
                    renderer.runComputeShader()
                }
        }
        .ignoresSafeArea()
    }
}

func initRayTracing(renderer: MetalRenderer, geometry: GeometryProxy) {
    let focalLength: Float = 1.0
    let viewportHeight: Float = 2.0
    let viewportWidth = viewportHeight * Float(geometry.size.width / geometry.size.height)
    let cameraCenter = SIMD3<Float>(0.0, 0.0, 0.0)
    
    // Use Metal's native top-left origin
    let viewportU = SIMD3<Float>(viewportWidth, 0, 0)
    let viewportV = SIMD3<Float>(0, -viewportHeight, 0) // Negative Y for top-left origin
    
    let pixelDeltaX = viewportU / Float(geometry.size.width)
    let pixelDeltaY = viewportV / Float(geometry.size.height)
    
    // Calculate the viewport upper-left corner position
    let viewportUpperLeft = cameraCenter - SIMD3<Float>(0, 0, focalLength) - viewportU / 2 - viewportV / 2
    
    // First pixel center (top-left pixel)
    let firstPixelPos = viewportUpperLeft + 0.5 * (pixelDeltaX + pixelDeltaY)
    
    renderer.uniforms.pixelOrigin = firstPixelPos
    renderer.uniforms.pixelDeltaX = pixelDeltaX
    renderer.uniforms.pixelDeltaY = pixelDeltaY
    renderer.uniforms.cameraCenter = cameraCenter
    renderer.uniforms.viewportSize = SIMD2<Float>(Float(geometry.size.width), Float(geometry.size.height))
}

struct MetalView: NSViewRepresentable {
    let renderer: MetalRenderer
    
    func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = renderer.device
        metalView.delegate = renderer
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        return metalView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update view if needed
    }
}

class MetalRenderer: NSObject, ObservableObject, MTKViewDelegate {
    let objectWillChange = ObservableObjectPublisher()
    
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var texture: MTLTexture?
    var renderPipelineState: MTLRenderPipelineState!
    
    var computePipelineState: MTLComputePipelineState?
    
    public var uniforms: Uniforms = .init()
    
    private var pixelData: [SIMD4<Float>] = []
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0
    private var needsUpdate = false
    
    private var time: Float = 0.0
    
    override init() {
        super.init()
        setupMetal()
    }
    
    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create render pipeline state: \(error)")
        }
        
        // Create compute pipeline
        if let computeFunction = library?.makeFunction(name: "computeShader") {
            do {
                computePipelineState = try device.makeComputePipelineState(function: computeFunction)
            } catch {
                print("Failed to create compute pipeline state: \(error)")
            }
        }
    }
    
    func setupTexture(width: Int, height: Int) {
        textureWidth = width
        textureHeight = height
        
        pixelData = Array(repeating: SIMD4<Float>(0.0, 0.0, 1.0, 1.0), count: width * height)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        texture = device.makeTexture(descriptor: textureDescriptor)
        updateTexture()
    }
    
    func runComputeShader() {
        guard let texture = texture,
              let computePipelineState = computePipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(texture, index: 0)
        
        uniforms.time = time
        
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (textureHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Update time for next frame
        time += 0.016 // ~60 FPS
    }
    
    /// Run compute shader with custom parameters
    func runComputeShader(time: Float) {
        guard let texture = texture,
              let computePipelineState = computePipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(texture, index: 0)
        
        // Pass custom time parameter
        var timeBuffer = time
        computeEncoder.setBytes(&timeBuffer, length: MemoryLayout<Float>.size, index: 0)
        
        // Calculate thread group size
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (textureHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    /// Run compute shader with custom buffer data
    func runComputeShader<T>(withData data: T) {
        guard let texture = texture,
              let computePipelineState = computePipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(texture, index: 0)
        
        // Pass custom data
        var dataBuffer = data
        computeEncoder.setBytes(&dataBuffer, length: MemoryLayout<T>.size, index: 0)
        
        // Calculate thread group size
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (textureWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (textureHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func updateTexture() {
        guard let texture = texture else { return }
        
        let region = MTLRegionMake2D(0, 0, textureWidth, textureHeight)
        let bytesPerRow = textureWidth * MemoryLayout<SIMD4<Float>>.size
        
        pixelData.withUnsafeBytes { bytes in
            texture.replace(region: region, mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: bytesPerRow)
        }
    }
    
    /// Set a single pixel color
    func setPixel(x: Int, y: Int, red: Float, green: Float, blue: Float, alpha: Float) {
        guard x >= 0 && x < textureWidth && y >= 0 && y < textureHeight else { return }
        
        let index = y * textureWidth + x
        pixelData[index] = SIMD4<Float>(red, green, blue, alpha)
        needsUpdate = true
    }
    
    /// Set a single pixel color using SIMD4<Float>
    func setPixel(x: Int, y: Int, color: SIMD4<Float>) {
        guard x >= 0 && x < textureWidth && y >= 0 && y < textureHeight else { return }
        
        let index = y * textureWidth + x
        pixelData[index] = color
        needsUpdate = true
    }
    
    /// Fill entire texture with a color
    func fillTexture(red: Float, green: Float, blue: Float, alpha: Float) {
        let color = SIMD4<Float>(red, green, blue, alpha)
        for i in 0..<pixelData.count {
            pixelData[i] = color
        }
        needsUpdate = true
    }
    
    /// Fill a rectangular region with a color
    func fillRect(x: Int, y: Int, width: Int, height: Int, red: Float, green: Float, blue: Float, alpha: Float) {
        let color = SIMD4<Float>(red, green, blue, alpha)
        
        for row in y..<min(y + height, textureHeight) {
            for col in x..<min(x + width, textureWidth) {
                let index = row * textureWidth + col
                pixelData[index] = color
            }
        }
        needsUpdate = true
    }
    
    /// Get pixel color at position
    func getPixel(x: Int, y: Int) -> SIMD4<Float>? {
        guard x >= 0 && x < textureWidth && y >= 0 && y < textureHeight else { return nil }
        
        let index = y * textureWidth + x
        return pixelData[index]
    }
    
    /// Get texture dimensions
    func getTextureSize() -> (width: Int, height: Int) {
        return (textureWidth, textureHeight)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }
        
        if needsUpdate {
            updateTexture()
            needsUpdate = false
        }
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        
        renderEncoder.setFragmentTexture(texture, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
