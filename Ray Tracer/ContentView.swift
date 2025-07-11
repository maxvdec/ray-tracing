//
//  ContentView.swift
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

import Cocoa
import Combine
import Foundation
import Metal
import MetalKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var renderer: MetalRenderer
    @State private var isRendering = false
    @State private var showSettings = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MetalView(renderer: renderer)
                    .onAppear {
                        renderer.setupTexture(width: Int(geometry.size.width),
                                              height: Int(geometry.size.height))
                        
                        initRayTracing(renderer: renderer, geometry: geometry)
                        renderer.objects.append(Object(type: 0, s: Sphere(center: SIMD3<Float>(0, 0, 3), radius: 1), mat: Material(type: 0, emission: 10, albedo: SIMD4<Float>(0.5, 0.5, 0.5, 1))))
                        renderer.objects.append(Object(type: 0, s: Sphere(center: SIMD3<Float>(0, 0, -1), radius: 0.2), mat: Material(type: 0, emission: 0, albedo: SIMD4<Float>(0.5, 0.5, 0.5, 1))))
                        renderer.objects.append(Object(type: 0, s: Sphere(center: SIMD3<Float>(0, -100.5, -1), radius: 100), mat: Material(type: 0, emission: 0, albedo: SIMD4<Float>(0.5, 0.5, 0.5, 1))))
                    }
                Button {
                    showSettings.toggle()
                } label: {}.hidden().keyboardShortcut("h", modifiers: [])
                if showSettings {
                    // Progress overlay
                    VStack {
                        Spacer()
                        HStack {
                            if isRendering {
                                VStack {
                                    Text("Rendering: \(Int(renderer.renderProgress * 100))%")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .cornerRadius(8)
                                        .glassEffect()
                                    
                                    Text("Tile: \(renderer.currentTile + 1)/\(renderer.totalTiles)")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .cornerRadius(8)
                                        .glassEffect()
                                    
                                    Button("Stop") {
                                        renderer.stopProgressiveRender()
                                        isRendering = false
                                    }.buttonStyle(.borderless)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .glassEffect()
                                        .focusable(false)
                                        .keyboardShortcut(" ", modifiers: [])
                                }
                            } else {
                                Button("Start Render") {
                                    renderer.startProgressiveRender()
                                    isRendering = true
                                }.buttonStyle(.borderless)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .focusable(false)
                                    .glassEffect().keyboardShortcut(" ", modifiers: [])
                            }
                    
                            Spacer()
                        }
                        .padding()
                    }
                }
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
    
    let viewportU = SIMD3<Float>(viewportWidth, 0, 0)
    let viewportV = SIMD3<Float>(0, -viewportHeight, 0)
    
    let pixelDeltaX = viewportU / Float(geometry.size.width)
    let pixelDeltaY = viewportV / Float(geometry.size.height)
    
    let viewportUpperLeft = cameraCenter - SIMD3<Float>(0, 0, focalLength) - viewportU / 2 - viewportV / 2
    
    let firstPixelPos = viewportUpperLeft + 0.5 * (pixelDeltaX + pixelDeltaY)
    
    renderer.uniforms.pixelOrigin = firstPixelPos
    renderer.uniforms.pixelDeltaX = pixelDeltaX
    renderer.uniforms.pixelDeltaY = pixelDeltaY
    renderer.uniforms.cameraCenter = cameraCenter
    renderer.uniforms.viewportSize = SIMD2<Float>(Float(geometry.size.width), Float(geometry.size.height))
    renderer.maxIterations = 30
    
    renderer.uniforms.sampleCount = 64
    renderer.uniforms.maxRayDepth = 10
    renderer.uniforms.pixelSampleScale = 1.0 / Float(renderer.uniforms.sampleCount)
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
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var texture: MTLTexture?
    var renderPipelineState: MTLRenderPipelineState!
    var computePipelineState: MTLComputePipelineState?
        
    @Published var objects: [Object] = [] {
        didSet {
            // Trigger UI update when objects change
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
        
    @Published var uniforms: Uniforms = .init() {
        didSet {
            // Trigger UI update when uniforms change
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
        
    private var pixelData: [SIMD4<Float>] = []
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0
    private var needsUpdate = false
        
    private var time: Float = 0.0
        
    // Tile-based rendering properties
    private var isRendering = false
    @Published var renderProgress: Float = 0.0
    private var currentSample = 0
    @Published var maxIterations = 3 {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    private var renderTimer: Timer?
        
    // Tile management
    private let tileSize = 64
    private var tiles: [TileInfo] = []
    private var currentTileIndex = 0
    @Published var currentTile: Int = 0
    @Published var totalTiles: Int = 0
    
    func updateSampleCount(_ count: Int32) {
        uniforms.sampleCount = count
        uniforms.pixelSampleScale = 1.0 / Float(count)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
        
    func updateMaxRayDepth(_ depth: Int32) {
        uniforms.maxRayDepth = depth
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
        
    func updateMaxIterations(_ iterations: Int) {
        maxIterations = iterations
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
        
    func updateObjects(_ newObjects: [Object]) {
        objects = newObjects
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
        
    // Tile structure
    struct TileInfo {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        var completedSamples: Int = 0
    }
    
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
        
        pixelData = Array(repeating: SIMD4<Float>(0.0, 0.0, 0.0, 1.0), count: width * height)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        texture = device.makeTexture(descriptor: textureDescriptor)
        
        // Generate tiles
        generateTiles()
        
        updateTexture()
    }
    
    private func generateTiles() {
        tiles.removeAll()
           
        let tilesX = (textureWidth + tileSize - 1) / tileSize
        let tilesY = (textureHeight + tileSize - 1) / tileSize
           
        for y in 0..<tilesY {
            for x in 0..<tilesX {
                let tileX = x * tileSize
                let tileY = y * tileSize
                let tileWidth = min(tileSize, textureWidth - tileX)
                let tileHeight = min(tileSize, textureHeight - tileY)
                   
                tiles.append(TileInfo(x: tileX, y: tileY, width: tileWidth, height: tileHeight))
            }
        }
           
        DispatchQueue.main.async {
            self.totalTiles = self.tiles.count
            self.objectWillChange.send()
        }
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
        uniforms.objCount = Int32(objects.count)
       
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if objects.count != 0 {
            computeEncoder.setBytes(&objects, length: MemoryLayout<Object>.stride * objects.count, index: 1)
        } else {
            var dummy = Object()
            computeEncoder.setBytes(&dummy, length: MemoryLayout<Object>.stride, index: 1)
        }
  
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
        
        time += 0.016
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
        
        uniforms.time = time
        uniforms.objCount = Int32(objects.count)
       
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        if objects.count != 0 {
            computeEncoder.setBytes(&objects, length: MemoryLayout<Object>.stride * objects.count, index: 1)
        } else {
            var dummy = Object()
            computeEncoder.setBytes(&dummy, length: MemoryLayout<Object>.stride, index: 1)
        }
        
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
    
    func startProgressiveRender() {
        guard !isRendering else {
            return
        }
        
        isRendering = true
        currentSample = 0
        currentTileIndex = 0
        renderProgress = 0.0
        
        // Reset all tiles
        for i in 0..<tiles.count {
            tiles[i].completedSamples = 0
        }
        
        clearTexture()
        
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            self.renderTile()
        }
    }
    
    func stopProgressiveRender() {
        renderTimer?.invalidate()
        renderTimer = nil
        isRendering = false
    }
       
    private func renderTile() {
        guard currentTileIndex < tiles.count else {
            currentSample += 1
            if maxIterations > 500 {
            } else if currentSample >= maxIterations {
                stopProgressiveRender()
                return
            }
                
            currentTileIndex = 0
            for i in 0..<tiles.count {
                tiles[i].completedSamples = 0
            }
            return
        }
            
        let tile = tiles[currentTileIndex]
            
        runComputeShaderForTile(tile: tile, sampleIndex: currentSample)
            
        tiles[currentTileIndex].completedSamples += 1
        currentTileIndex += 1
            
        let totalWork = tiles.count * maxIterations
        let completedWork = currentSample * tiles.count + currentTileIndex
            
        DispatchQueue.main.async {
            self.renderProgress = Float(completedWork) / Float(totalWork)
            self.currentTile = self.currentTileIndex - 1
            self.objectWillChange.send()
        }
    }
    
    private func clearTexture() {
        fillTexture(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        updateTexture()
    }
    
    func runComputeShaderForTile(tile: TileInfo, sampleIndex: Int) {
        guard let texture = texture,
              let computePipelineState = computePipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
            
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(texture, index: 0)
            
        var sampleUniforms = uniforms
        sampleUniforms.currentSample = Int32(sampleIndex)
        sampleUniforms.totalSamples = Int32(maxIterations)
        sampleUniforms.time = time
        sampleUniforms.objCount = Int32(objects.count)
        
        sampleUniforms.tileX = Int32(tile.x)
        sampleUniforms.tileY = Int32(tile.y)
        sampleUniforms.tileWidth = Int32(tile.width)
        sampleUniforms.tileHeight = Int32(tile.height)
            
        computeEncoder.setBytes(&sampleUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            
        if objects.count != 0 {
            computeEncoder.setBytes(&objects, length: MemoryLayout<Object>.stride * objects.count, index: 1)
        } else {
            var dummy = Object()
            computeEncoder.setBytes(&dummy, length: MemoryLayout<Object>.stride, index: 1)
        }
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (tile.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (tile.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
            
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // Keep the old method for backward compatibility
    func runComputeShaderSample(sampleIndex: Int) {
        guard let texture = texture,
              let computePipelineState = computePipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return
        }
            
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(texture, index: 0)
            
        var sampleUniforms = uniforms
        sampleUniforms.sampleCount = 1
        sampleUniforms.currentSample = Int32(sampleIndex)
        sampleUniforms.totalSamples = Int32(maxIterations)
        sampleUniforms.time = time
        sampleUniforms.objCount = Int32(objects.count)
            
        computeEncoder.setBytes(&sampleUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            
        if objects.count != 0 {
            computeEncoder.setBytes(&objects, length: MemoryLayout<Object>.stride * objects.count, index: 1)
        } else {
            var dummy = Object()
            computeEncoder.setBytes(&dummy, length: MemoryLayout<Object>.stride, index: 1)
        }
            
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
}
