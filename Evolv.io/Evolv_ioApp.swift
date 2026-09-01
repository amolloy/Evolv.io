//
//  Evolv_ioApp.swift
//  Evolv.io
//
//  Created by Andy Molloy on 6/8/25.
//

import SwiftUI

@main
struct Evolv_ioApp: App {
    @AppStorage(UserDefaults.supersamplingEnabledKey) private var supersamplingEnabled = true

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Toggle("Supersampling", isOn: $supersamplingEnabled)
            }
        }
    }
}
