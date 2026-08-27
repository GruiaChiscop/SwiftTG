// CallCameraPreviewView.swift

import SwiftUI

// MARK: - CallCameraPreviewView

struct CallCameraPreviewView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if selectedSource == .screen {
                        ContentUnavailableView(
                            "Everything on your screen\nwill be shared",
                            systemImage: "rectangle.on.rectangle",
                        )
                    } else if let cameraPreviewView = session.cameraPreviewView {
                        CallVideoSurfaceView(videoView: cameraPreviewView)
                            .id(ObjectIdentifier(cameraPreviewView))
                            .accessibilityHidden(true)
                    } else {
                        ProgressView("Preparing camera…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(.rect(cornerRadius: 16))

                Picker("Video Source", selection: $selectedSource) {
                    if !session.isConferenceCall {
                        Text("Phone Screen").tag(VideoSource.screen)
                    }
                    Text("Front Camera").tag(VideoSource.front)
                    Text("Back Camera").tag(VideoSource.back)
                }
                .pickerStyle(.segmented)

                ZStack {
                    Button("Continue", action: session.confirmCameraPreview)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(selectedSource != .screen && session.cameraPreviewView == nil)
                        .accessibilityHidden(selectedSource == .screen)

                    if selectedSource == .screen {
                        SystemBroadcastPickerButton(isEnabled: true, label: "Continue")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 50)
            }
            .padding()
            .navigationTitle("Video Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: session.cancelCameraPreview)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedSource = session.isUsingFrontCamera ? .front : .back
        }
        .onChange(of: selectedSource) { _, source in
            switch source {
            case .front:
                session.selectCamera(isFront: true)
            case .back:
                session.selectCamera(isFront: false)
            case .screen:
                break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.cancelCameraPreview()
            }
        }
    }

    // MARK: Private

    private enum VideoSource: Hashable {
        case screen
        case front
        case back
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSource = VideoSource.front
    @State private var session = TelegramCallSession.shared
}
