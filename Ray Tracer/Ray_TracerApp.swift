//
//  Ray_TracerApp.swift
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

import SwiftUI

@main
struct Ray_TracerApp: App {
    @StateObject private var renderer = MetalRenderer()
    var body: some Scene {
        WindowGroup {
            ContentView(renderer: renderer)
                .frame(width: 1000, height: 800)
        }

        Window("Explorer", id: "explr-win") {
            Edit(renderer: renderer)
                .frame(maxWidth: 300)
        }
        .keyboardShortcut(.init("e", modifiers: []))
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}
