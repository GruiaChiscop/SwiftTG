// CallRatingView.swift

import SwiftUI

// MARK: - CallRatingView

struct CallRatingView: View {
    // MARK: Internal

    let request: CallRatingRequest

    var body: some View {
        NavigationStack {
            Form {
                if includesDetails {
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

                    Section {
                        TextField("Add an optional comment", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    Section {
                        Toggle("Include technical information", isOn: $includesTechnicalInformation)
                    } footer: {
                        Text(
                            "This won't reveal the contents of your conversation, but will help us fix the issue sooner.",
                        )
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            Text("Please rate the quality\nof your Telegram call")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            HStack {
                                ForEach(1...5, id: \.self) { value in
                                    Spacer(minLength: 0)
                                    Button(
                                        value == 1 ? "1 star" : "\(value) stars",
                                        systemImage: value <= rating ? "star.fill" : "star",
                                    ) {
                                        selectRating(value)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                    .font(.title2)
                                    .foregroundStyle(value <= rating ? .yellow : .secondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityAddTraits(value == rating ? .isSelected : [])
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(includesDetails ? "Call Feedback" : "Rate Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        session.dismissCallRating(request: request)
                    }
                    .disabled(isSubmitting)
                }
                if includesDetails {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: submit)
                            .disabled(isSubmitting)
                    }
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
            .onDisappear {
                session.dismissCallRating(request: request)
            }
        }
    }

    // MARK: Private

    @State private var rating = 0
    @State private var selectedProblems = Set<TelegramCallRatingProblem>()
    @State private var comment = ""
    @State private var includesTechnicalInformation = true
    @State private var isSubmitting = false
    @State private var showsSubmissionError = false
    @State private var submissionErrorMessage = ""

    private let session = TelegramCallSession.shared

    private var availableProblems: [TelegramCallRatingProblem] {
        TelegramCallRatingProblem.allCases.filter { request.isVideo || !$0.isVideoRelated }
    }

    private var includesDetails: Bool {
        (1...3).contains(rating)
    }

    private func toggle(_ problem: TelegramCallRatingProblem) {
        if selectedProblems.contains(problem) {
            selectedProblems.remove(problem)
        } else {
            selectedProblems.insert(problem)
        }
    }

    private func submit() {
        guard rating != 0, !isSubmitting else { return }
        isSubmitting = true
        let problems = includesDetails ? Array(selectedProblems) : []
        let comment = includesDetails ? comment.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        Task {
            do {
                try await session.submitCallRating(
                    request: request,
                    rating: rating,
                    problems: problems,
                    comment: comment,
                    includeTechnicalInformation: includesDetails && includesTechnicalInformation,
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

    private func selectRating(_ value: Int) {
        guard !isSubmitting else { return }
        rating = value
        if value >= 4 {
            submit()
        }
    }
}
