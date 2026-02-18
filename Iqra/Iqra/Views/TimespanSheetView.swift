import SwiftUI
import SwiftData

struct TimespanSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayerService.self) private var playerService

    let trackId: UUID
    let trackDuration: TimeInterval

    @State private var timespans: [TrackTimespan] = []
    @State private var isCreating = false
    @State private var newName = ""
    @State private var startTime: Double = 0
    @State private var endTime: Double = 30
    @State private var startMinutes = ""
    @State private var startSeconds = ""
    @State private var endMinutes = ""
    @State private var endSeconds = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Active loop indicator
                        if playerService.isLooping, let span = playerService.activeTimespan {
                            activeLoopBanner(span)
                        }

                        // Create new section
                        createSection

                        // Saved timespans
                        if !timespans.isEmpty {
                            savedSection
                        } else if !isCreating {
                            emptyState
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Loops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .task { fetchTimespans() }
    }

    // MARK: - Active Loop Banner

    private func activeLoopBanner(_ span: TrackTimespan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(span.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(span.formattedRange)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                playerService.deactivateTimespan()
            } label: {
                Text("Stop Loop")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(16)
        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Create Section

    private var createSection: some View {
        VStack(spacing: 12) {
            if !isCreating {
                Button {
                    startTime = max(0, playerService.currentTime - 5)
                    endTime = min(trackDuration, playerService.currentTime + 25)
                    newName = ""
                    syncFieldsFromStartTime()
                    syncFieldsFromEndTime()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCreating = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("New Loop")
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
                }
            } else {
                createForm
            }
        }
    }

    private var createForm: some View {
        VStack(spacing: 16) {
            HStack {
                Text("New Loop")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCreating = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            // Name field
            TextField("Name (e.g. Ayah 1-5)", text: $newName)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.textPrimary)

            // Start time
            timeInputRow(
                label: "Start",
                minutes: $startMinutes,
                seconds: $startSeconds,
                time: $startTime,
                onCurrent: {
                    startTime = playerService.currentTime
                    syncFieldsFromStartTime()
                }
            )

            // End time
            timeInputRow(
                label: "End",
                minutes: $endMinutes,
                seconds: $endSeconds,
                time: $endTime,
                onCurrent: {
                    endTime = playerService.currentTime
                    syncFieldsFromEndTime()
                }
            )

            // Validation message
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            }

            // Track duration hint
            Text("Track duration: \(TimeFormatter.format(timeInterval: trackDuration))")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            // Save button
            Button {
                saveTimespan()
            } label: {
                Text("Save Loop")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSave ? Theme.accent : Theme.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSave)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.glassBorder, lineWidth: 1))
    }

    private var canSave: Bool {
        validationError == nil && !newName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var validationError: String? {
        if startTime >= trackDuration {
            return "Start time exceeds track duration"
        }
        if endTime > trackDuration {
            return "End time exceeds track duration"
        }
        if endTime - startTime < 2 {
            return "Loop must be at least 2 seconds"
        }
        if startTime < 0 {
            return "Start time cannot be negative"
        }
        return nil
    }

    // MARK: - Saved Section

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ForEach(timespans, id: \.id) { span in
                timespanRow(span)
            }
        }
    }

    private func timespanRow(_ span: TrackTimespan) -> some View {
        let isActive = playerService.activeTimespan?.id == span.id && playerService.isLooping

        return HStack(spacing: 12) {
            Button {
                if isActive {
                    playerService.deactivateTimespan()
                } else {
                    playerService.activateTimespan(span)
                }
            } label: {
                Image(systemName: isActive ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(span.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary)
                Text(span.formattedRange)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Button(role: .destructive) {
                deleteTimespan(span)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(
            isActive ? Theme.accent.opacity(0.1) : Theme.surface,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Theme.accent.opacity(0.3) : Theme.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("No loops yet")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Create a loop to repeat a section of this track")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    // MARK: - Time Input

    private func timeInputRow(
        label: String,
        minutes: Binding<String>,
        seconds: Binding<String>,
        time: Binding<Double>,
        onCurrent: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Current", action: onCurrent)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    TextField("0", text: minutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 48)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Theme.textPrimary)
                        .font(.body.monospacedDigit().weight(.medium))
                        .onChange(of: minutes.wrappedValue) {
                            syncTimeFromFields(minutes: minutes.wrappedValue, seconds: seconds.wrappedValue, time: time)
                        }
                    Text("m")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 4) {
                    TextField("00", text: seconds)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 48)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceLight, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Theme.textPrimary)
                        .font(.body.monospacedDigit().weight(.medium))
                        .onChange(of: seconds.wrappedValue) {
                            syncTimeFromFields(minutes: minutes.wrappedValue, seconds: seconds.wrappedValue, time: time)
                        }
                    Text("s")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(TimeFormatter.format(timeInterval: time.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func syncTimeFromFields(minutes: String, seconds: String, time: Binding<Double>) {
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        let value = max(0, min(m * 60 + s, trackDuration))
        time.wrappedValue = value
    }

    private func syncFieldsFromStartTime() {
        startTime = max(0, min(startTime, trackDuration))
        let totalSeconds = Int(startTime)
        startMinutes = String(totalSeconds / 60)
        startSeconds = String(totalSeconds % 60)
    }

    private func syncFieldsFromEndTime() {
        endTime = max(0, min(endTime, trackDuration))
        let totalSeconds = Int(endTime)
        endMinutes = String(totalSeconds / 60)
        endSeconds = String(totalSeconds % 60)
    }

    // MARK: - Data

    private func fetchTimespans() {
        let id = trackId
        let descriptor = FetchDescriptor<TrackTimespan>(
            predicate: #Predicate { $0.trackId == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        timespans = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveTimespan() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, endTime - startTime >= 2 else { return }

        let timespan = TrackTimespan(
            trackId: trackId,
            name: name,
            startTime: startTime,
            endTime: endTime
        )
        modelContext.insert(timespan)
        try? modelContext.save()
        fetchTimespans()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isCreating = false
        }
        newName = ""
    }

    private func deleteTimespan(_ timespan: TrackTimespan) {
        if playerService.activeTimespan?.id == timespan.id {
            playerService.deactivateTimespan()
        }
        modelContext.delete(timespan)
        try? modelContext.save()
        fetchTimespans()
    }
}
