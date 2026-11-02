// SPDX-License-Identifier: Apache-2.0
import SwiftUI

@main
struct ReuseLabApp: App {
    @StateObject private var model = LabModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            LabView(model: model)
                .task { await model.handleLaunchArguments() }
                .onChange(of: model.busy) { _, _ in UIApplication.shared.isIdleTimerDisabled = model.busy || model.recording }
                .onChange(of: model.recording) { _, _ in UIApplication.shared.isIdleTimerDisabled = model.busy || model.recording }
                .onChange(of: phase) { _, value in
                    if value == .background { model.stopAll() }
                }
        }
    }
}
