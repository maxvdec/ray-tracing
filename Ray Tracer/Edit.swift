//
//  Edit.swift
//  Ray Tracer
//
//  Created by Max Van den Eynde on 11/7/25.
//

import SwiftUI

enum ShapeType: Int32 {
    case sphere = 0
    case null = 255

    func asString() -> String {
        switch self {
        case .sphere:
            return "Sphere"
        case .null:
            return "Unknown"
        }
    }
}

enum MaterialType: Int32 {
    case lambertian = 0
    case reflectee = 1
    case dielectric = 2
    
    func asString() -> String {
        switch self {
        case .lambertian:
            return "Lambertian"
        case .reflectee:
            return "Reflectee"
        case .dielectric:
            return "Dielectric"
        }
    }
}

struct SwiftObject: Identifiable {
    var obj: Object = .init()
    let type: ShapeType
    let id: UUID = .init()

    static func fromObject(_ obj: Object) -> SwiftObject {
        SwiftObject(obj: obj, type: ShapeType(rawValue: obj.type) ?? .null)
    }

    func toObject() -> Object {
        return obj
    }
}

extension NumberFormatter {
    static func makeFloatFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }
}

struct Edit: View {
    @ObservedObject var renderer: MetalRenderer
    @State private var raysPerPixel: Double = 16
    @State private var rayDepth: Double = 10
    @State private var renderIterations: Double = 20
    @State private var objects: [SwiftObject] = []

    init(renderer: MetalRenderer) {
        self.renderer = renderer
        _objects = State(initialValue: renderer.objects.map { SwiftObject.fromObject($0) })
        _raysPerPixel = State(initialValue: Double(renderer.uniforms.sampleCount))
        _rayDepth = State(initialValue: Double(renderer.uniforms.maxRayDepth))
        _renderIterations = State(initialValue: Double(renderer.maxIterations))
    }

    var body: some View {
        Form {
            VStack {
                HStack {
                    VStack {
                        Text("Ray Tracing")
                            .bold()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                VStack {
                    Stepper(value: $raysPerPixel, in: 1 ... 100) {
                        Text("Rays per pixel (\(Int(raysPerPixel)))")
                    }
                    .onChange(of: raysPerPixel) { newValue in
                        renderer.updateSampleCount(Int32(newValue))
                    }

                    Slider(value: $raysPerPixel, in: 1 ... 100, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("100")
                    })
                    .onChange(of: raysPerPixel) { newValue in
                        renderer.updateSampleCount(Int32(newValue))
                    }
                    .padding(.bottom)

                    Stepper(value: $rayDepth, in: 1 ... 10) {
                        Text("Max Ray Bounces (\(Int(rayDepth)))")
                    }
                    .onChange(of: rayDepth) { newValue in
                        renderer.updateMaxRayDepth(Int32(newValue))
                    }

                    Slider(value: $rayDepth, in: 1 ... 10, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("10")
                    })
                    .onChange(of: rayDepth) { newValue in
                        renderer.updateMaxRayDepth(Int32(newValue))
                    }
                    .padding(.bottom)

                    Stepper(value: $renderIterations, in: 1 ... 200) {
                        Text("Render Passes (\(Int(renderIterations)))")
                    }
                    .onChange(of: renderIterations) { newValue in
                        renderer.updateMaxIterations(Int(newValue))
                    }

                    Slider(value: $renderIterations, in: 1 ... 501, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("∞")
                    })
                    .onChange(of: renderIterations) { newValue in
                        renderer.updateMaxIterations(Int(newValue))
                    }
                    .padding(.bottom)

                    Button {
                        raysPerPixel = 1
                        rayDepth = 1
                        renderIterations = 1
                    } label: {
                        Text("Set to Minimal Values")
                    }.buttonStyle(.bordered).focusable(false)

                    Button {
                        raysPerPixel = 4
                        rayDepth = 5
                        renderIterations = 10
                    } label: {
                        Text("Set to Debug Values")
                    }.buttonStyle(.bordered).focusable(false)

                    Button {
                        raysPerPixel = 64
                        rayDepth = 10
                        renderIterations = 100
                    } label: {
                        Text("Set to Production Values")
                    }.buttonStyle(.bordered).focusable(false)

                }.padding(.horizontal).padding(.bottom)

                HStack {
                    VStack {
                        Text("Objects")
                            .bold()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack {
                    List {
                        ForEach($objects) { obj in
                            ObjectView(obj: obj) { updatedObj in
                                // Update the renderer when object changes
                                if let index = objects.firstIndex(where: { $0.id == updatedObj.id }) {
                                    objects[index] = updatedObj
                                    renderer.updateObjects(objects.map(\.obj))
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 300)
                    .padding(.horizontal)
                }
                .onReceive(renderer.$objects) { newObjects in
                    objects = newObjects.map { SwiftObject.fromObject($0) }
                }

                Spacer()
            }
        }
        .padding()
        .frame(width: 300)
        .onReceive(renderer.$uniforms) { newUniforms in
            raysPerPixel = Double(newUniforms.sampleCount)
            rayDepth = Double(newUniforms.maxRayDepth)
        }
        .onReceive(renderer.$maxIterations) { newMaxIterations in
            renderIterations = Double(newMaxIterations)
        }
    }
}

extension Color {
    static func fromSIMD(_ c: SIMD4<Float>) -> Color {
        return Color(
            red: Double(max(0, min(1, c.x))),
            green: Double(max(0, min(1, c.y))),
            blue: Double(max(0, min(1, c.z))),
            opacity: Double(max(0, min(1, c.w)))
        )
    }
}

extension SIMD4 where Scalar == Float {
    static func fromColor(_ color: Color) -> SIMD4<Float> {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return SIMD4<Float>(
            Float(red),
            Float(green),
            Float(blue),
            Float(alpha)
        )
        #else
        let components = color.cgColor?.components ?? [0, 0, 0, 1]
        return SIMD4<Float>(
            Float(components[0]),
            Float(components.count > 1 ? components[1] : components[0]),
            Float(components.count > 2 ? components[2] : components[0]),
            Float(components.count > 3 ? components[3] : 1.0)
        )
        #endif
    }
}

struct ObjectView: View {
    @Binding var obj: SwiftObject
    let onObjectChanged: (SwiftObject) -> Void

    @State private var isShapeExpanded: Bool = true
    @State private var isMaterialExpanded: Bool = true
    @State private var showingColorPicker: Bool = false

    init(obj: Binding<SwiftObject>, onObjectChanged: @escaping (SwiftObject) -> Void) {
        self._obj = obj
        self.onObjectChanged = onObjectChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(obj.type.asString())
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShapeExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isShapeExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                    Text("Shape Properties")
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isShapeExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    switch obj.type {
                    case .sphere:
                        Text("Center:")
                            .bold().foregroundStyle(.secondary)
                        HStack {
                            Text("x:")
                                .padding(.trailing, -5)
                            TextField("x:", value: $obj.obj.s.center.x, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                                .onChange(of: obj.obj.s.center.x) {
                                    onObjectChanged(obj)
                                }
                            Text("y:")
                                .padding(.trailing, -5)
                            TextField("y:", value: $obj.obj.s.center.y, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                                .onChange(of: obj.obj.s.center.y) {
                                    onObjectChanged(obj)
                                }
                            Text("z:")
                                .padding(.trailing, -5)
                            TextField("z:", value: $obj.obj.s.center.z, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                                .onChange(of: obj.obj.s.center.z) {
                                    onObjectChanged(obj)
                                }
                        }.padding(4)

                        Text("Radius:")
                            .bold().foregroundStyle(.secondary)
                        TextField("", value: $obj.obj.s.radius, formatter: NumberFormatter.makeFloatFormatter())
                            .padding(.bottom, 4)
                            .textFieldStyle(.squareBorder)
                            .onChange(of: obj.obj.s.radius) {
                                onObjectChanged(obj)
                            }
                    case .null:
                        Text("Unknown properties")
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }

            Divider()
                .padding(.vertical, 4)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMaterialExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isMaterialExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                    Text("Material Properties")
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isMaterialExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Emission Strength:")
                        .bold()
                        .foregroundStyle(.secondary)
                    TextField("", value: $obj.obj.mat.emission, formatter: NumberFormatter.makeFloatFormatter())
                        .padding(.bottom, 4)
                        .textFieldStyle(.squareBorder)
                        .onChange(of: obj.obj.mat.emission) {
                            onObjectChanged(obj)
                        }

                    Text("Color (Albedo):")
                        .bold()
                        .foregroundStyle(.secondary)

                    HStack {
                        // Color preview
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.fromSIMD(obj.obj.mat.albedo))
                            .frame(width: 40, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary, lineWidth: 1)
                            )

                        Button("Choose Color") {
                            showingColorPicker = true
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black, lineWidth: 1)
        )
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(
                initialColor: Color.fromSIMD(obj.obj.mat.albedo),
                onColorChanged: { newColor in
                    obj.obj.mat.albedo = SIMD4<Float>.fromColor(newColor)
                    onObjectChanged(obj)
                }
            )
        }
    }
}

struct ColorPickerSheet: View {
    let initialColor: Color
    let onColorChanged: (Color) -> Void

    @State private var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    init(initialColor: Color, onColorChanged: @escaping (Color) -> Void) {
        self.initialColor = initialColor
        self.onColorChanged = onColorChanged
        self._selectedColor = State(initialValue: initialColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.secondary)

                Spacer()

                Text("Material Color")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    onColorChanged(selectedColor)
                    dismiss()
                }
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.5)

            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Color Preview")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 16) {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(initialColor)
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                            Text("Original")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedColor)
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                            Text("New")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                VStack(spacing: 16) {
                    HStack {
                        Text("Choose Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Reset button
                        Button("Reset") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedColor = initialColor
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .opacity(selectedColor != initialColor ? 1 : 0.5)
                        .disabled(selectedColor == initialColor)
                    }

                    VStack(spacing: 12) {
                        ColorPicker("", selection: $selectedColor)
                            .labelsHidden()
                            .scaleEffect(1.1)

                        VStack(spacing: 8) {
                            HStack {
                                Text("RGB Values")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                ColorValueView(label: "R", value: selectedColor.components.red)
                                ColorValueView(label: "G", value: selectedColor.components.green)
                                ColorValueView(label: "B", value: selectedColor.components.blue)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ColorValueView: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("\(Int(value * 255))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(minWidth: 30)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }
}

extension Color {
    var components: (red: Double, green: Double, blue: Double, alpha: Double) {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return (Double(red), Double(green), Double(blue), Double(alpha))
        #else
        let components = cgColor?.components ?? [0, 0, 0, 1]
        return (
            Double(components[0]),
            Double(components.count > 1 ? components[1] : components[0]),
            Double(components.count > 2 ? components[2] : components[0]),
            Double(components.count > 3 ? components[3] : 1.0)
        )
        #endif
    }
}
