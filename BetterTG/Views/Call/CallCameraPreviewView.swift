// CallCameraPreviewView.swift

import SwiftUI

// MARK: - CallCameraPreviewView

struct CallCameraPreviewView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if let cameraPreviewView = session.cameraPreviewView {
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

                Picker("Camera", selection: $selectedCamera) {
                    Text("Front Camera").tag(Camera.front)
                    Text("Back Camera").tag(Camera.back)
                }
                .pickerStyle(.segmented)

                Button("Continue", action: session.confirmCameraPreview)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(session.cameraPreviewView == nil)
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
            selectedCamera = session.isUsingFrontCamera ? .front : .back
        }
        .onChange(of: selectedCamera) { _, camera in
            session.selectCamera(isFront: camera == .front)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.cancelCameraPreview()
            }
        }
    }

    // MARK: Private

    private enum Camera: Hashable {
        case front
        case back
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedCamera = Camera.front
    @State private var session = TelegramCallSession.shared
}
