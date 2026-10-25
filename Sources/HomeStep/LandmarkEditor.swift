import SwiftUI
import HomeStepCore

/// Add or edit one landmark. The marker number is assigned, not typed, so two
/// landmarks can never share a printed code.
struct LandmarkEditor: View {
    @State private var landmark: Landmark
    let placeID: UUID
    /// Fixed when the sheet opens, so the title doesn't flip to "Edit" while
    /// the sheet animates away after Save.
    private let isNew: Bool

    init(landmark: Landmark, placeID: UUID, isNew: Bool) {
        _landmark = State(initialValue: landmark)
        self.placeID = placeID
        self.isNew = isNew
    }
    @EnvironmentObject var places: PlaceStore
    @EnvironmentObject var guide: GuideController
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Kitchen door", text: $landmark.name)
                    .font(.title3)
                    .focused($nameFocused)
                Picker("Type", selection: $landmark.kind) {
                    ForEach(Landmark.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Steps, stairs and other hazards interrupt whatever HomeStep is saying and play a warning tone first.")
            }

            Section {
                TextField(landmark.spokenText.isEmpty ? "Spoken text" : landmark.spokenText,
                          text: $landmark.cue, axis: .vertical)
                Button("Hear it", systemImage: "speaker.wave.2") { guide.preview(landmark) }
                    .disabled(landmark.spokenText.isEmpty)
            } header: {
                Text("What to say")
            } footer: {
                Text("Leave empty and HomeStep says: \(landmark.spokenText.isEmpty ? "the name" : landmark.spokenText) Keep it short.")
            }

            Section("Note for the person placing the marker") {
                TextField("e.g. Left door frame, knee height", text: $landmark.note, axis: .vertical)
            }

            Section {
                LabeledContent("Marker number", value: "\(landmark.marker)")
            } footer: {
                if landmark.isHazard {
                    Text("Put this marker about one stride BEFORE the hazard. For a step, add a second landmark (for example Step up) with its own marker on the other side, so it is announced from both directions. On LiDAR iPhones HomeStep also detects steps without any marker.")
                } else {
                    Text("Put this marker about one stride before the spot, low on a wall, door frame or baseboard, facing the way you approach.")
                }
            }

            if !isNew {
                Section {
                    Button("Delete landmark", role: .destructive) {
                        places.deleteLandmark(landmark.id, in: placeID)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New landmark" : "Edit landmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    landmark.name = landmark.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    landmark.cue = landmark.cue.trimmingCharacters(in: .whitespacesAndNewlines)
                    places.upsert(landmark, in: placeID)
                    dismiss()
                }
                .disabled(landmark.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { if isNew { nameFocused = true } }
    }
}
