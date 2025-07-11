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
    @State private var raysPerPixel: Double = 16 {
        didSet {
            renderer.uniforms.sampleCount = Int32(raysPerPixel)
        }
    }

    @State private var rayDepth: Double = 10 {
        didSet {
            renderer.uniforms.maxRayDepth = Int32(rayDepth)
        }
    }

    @State private var renderIterations: Double = 20 {
        didSet {
            renderer.maxIterations = Int(renderIterations)
        }
    }

    @State private var objects: [SwiftObject] = [] {
        didSet {
            renderer.objects = objects.map(\.obj)
        }
    }

    init(renderer: MetalRenderer) {
        self.renderer = renderer
        _objects = State(initialValue: renderer.objects.map { SwiftObject.fromObject($0) })
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
                    Slider(value: $raysPerPixel, in: 1 ... 100, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("100")
                    })
                    .padding(.bottom)

                    Stepper(value: $rayDepth, in: 1 ... 10) {
                        Text("Max Ray Bounces (\(Int(rayDepth)))")
                    }
                    Slider(value: $rayDepth, in: 1 ... 10, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("10")
                    })
                    .padding(.bottom)

                    Stepper(value: $renderIterations, in: 1 ... 200) {
                        Text("Render Passes (\(Int(renderIterations)))")
                    }
                    Slider(value: $renderIterations, in: 1 ... 501, step: 1, label: {
                        EmptyView()
                    }, minimumValueLabel: {
                        Text("1")
                    }, maximumValueLabel: {
                        Text("∞")
                    })
                    .padding(.bottom)

                    Button {} label: {
                        Text("Set to Minimal Values")
                    }.buttonStyle(.bordered).focusable(false)
                    Button {} label: {
                        Text("Set to Debug Values")
                    }.buttonStyle(.bordered).focusable(false)
                    Button {} label: {
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
                            ObjectView(obj: obj)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minHeight: 200, maxHeight: 300)
                    .padding(.horizontal)
                }

                Spacer()
            }

        }.padding()
            .frame(width: 300)
    }
}

extension Color {
    static func fromSIMD(_ c: SIMD4<Float>) -> Color {
        var color = Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
        color = color.opacity(Double(c.w))
        return color
    }
}

extension SIMD4 {
    static func fromColor(_ c: Color) -> SIMD4<Float> {
        let nsColor = NSColor(c)
        var simd = SIMD4<Float>(x: 0, y: 0, z: 0, w: 0)
        simd.x = Float(nsColor.redComponent)
        simd.y = Float(nsColor.greenComponent)
        simd.z = Float(nsColor.blueComponent)
        simd.w = Float(nsColor.alphaComponent)
        return simd
    }
}

struct ObjectView: View {
    @Binding var obj: SwiftObject
    @State private var isShapeExpanded: Bool = true
    @State private var isMaterialExpanded: Bool = true

    @State private var albedo: Color = .blue {
        didSet {
            obj.obj.mat.albedo = SIMD4<Float>.fromColor(albedo)
        }
    }

    init(obj: Binding<SwiftObject>) {
        self._obj = obj
        self._albedo = State(initialValue: Color.fromSIMD(obj.obj.mat.albedo.wrappedValue))
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
                        // The center
                        Text("Center:")
                            .bold().foregroundStyle(.secondary)
                        HStack {
                            Text("x:")
                                .padding(.trailing, -5)
                            TextField("x:", value: $obj.obj.s.center.x, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                            Text("y:")
                                .padding(.trailing, -5)
                            TextField("y:", value: $obj.obj.s.center.y, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                            Text("z:")
                                .padding(.trailing, -5)
                            TextField("z:", value: $obj.obj.s.center.z, formatter: NumberFormatter())
                                .padding(.horizontal, 4)
                                .textFieldStyle(.squareBorder)
                        }.padding(4)

                        Text("Radius:")
                            .bold().foregroundStyle(.secondary)
                        TextField("", value: $obj.obj.s.radius, formatter: NumberFormatter.makeFloatFormatter())
                            .padding(.bottom, 4)
                            .textFieldStyle(.squareBorder)
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
                    Text("Color (Albedo):")
                        .bold()
                        .foregroundStyle(.secondary)
                    ColorPicker("", selection: $albedo)
                        .labelsHidden()
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }

        }.padding(10).background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black, lineWidth: 1)
        )
    }
}

#Preview {
    let renderer = MetalRenderer()
    renderer.objects.append(Object(type: 0, s: Sphere(center: SIMD3<Float>(0.0, 5.0, 0.0), radius: 0.5), mat: Material(emission: 1, albedo: SIMD4<Float>(1.0, 0.0, 0.0, 1.0))))
    return Edit(renderer: renderer)
}
