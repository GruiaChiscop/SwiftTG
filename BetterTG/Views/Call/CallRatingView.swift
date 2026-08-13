// CallRatingView.swift

import SwiftUI

// MARK: - CallRatingView

struct CallRatingView: View {
    // MARK: Internal

    let request: CallRatingRequest

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        ForEach(1...5, id: \.self) { value in
                            Spacer(minLength: 0)
                            Button(
                                value == 1 ? "1 star" : "\(value) stars",
                                systemImage: value <= rating ? "star.fill" : "star",
                            ) {
                                rating = value
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.title2)
                            .foregroundStyle(value <= rating ? .yellow : .secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            Spacer(minLength: 0)
                        }
                    }
                } header: {
                    Text("How was the call quality?")
                }

                if (1...3).contains(rating) {
                    Section("What went wrong?") {
                        ForEach(availableProblems) { problem in
                            Button {
                                toggle(problem)
                            } label: {
                                Label(
                                    problem.title,
                                    systemImage: selectedProblems.contains(problem)
                                        ? "checkmark.circle.fill"
                                        : "circle",
                                )
                            }
                            .accessibilityAddTraits(selectedProblems.contains(problem) ? .isSelected : [])
                        }
                    }

                    Section("Additional details") {
                        TextField("Add a comment", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Rate Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: session.dismissCallRating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: submit)
                        .disabled(rating == 0 || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView("Sending…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .alert("Couldn't Send Rating", isPresented: $showsSubmissionError) {} message: {
                Text(submissionErrorMessage)
            }
        }
    }

    // MARK: Private

    @State private var rating = 0
    @State private var selectedProblems = Set<TelegramCallRatingProblem>()
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var showsSubmissionError = false
    @State private var submissionErrorMessage = ""

    private let session = TelegramCallSession.shared

    private var availableProblems: [TelegramCallRatingProblem] {
        TelegramCallRatingProblem.allCases.filter { request.isVideo || !$0.isVideoRelated }
    }

    private func toggle(_ problem: TelegramCallRatingProblem) {
        if selectedProblems.contains(problem) {
            selectedProblems.remove(problem)
        } else {
            selectedProblems.insert(problem)
        }
    }

    private func submit() {
        isSubmitting = true
        let includesDetails = (1...3).contains(rating)
        let problems = includesDetails ? Array(selectedProblems) : []
        let comment = includesDetails ? comment.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        Task {
            do {
                try await session.submitCallRating(
                    request: request,
                    rating: rating,
                    problems: problems,
                    comment: comment,
                )
            } catch is CancellationError {
                // Dismissing the view cancels its work; no user-facing error is needed.
            } catch {
                submissionErrorMessage = error.localizedDescription
                showsSubmissionError = true
            }
            isSubmitting = false
        }
    }
}
