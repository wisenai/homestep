import SwiftUI
import UniformTypeIdentifiers
import HomeStepCore

extension UTType {
    static let homeStepPlace = UTType(exportedAs: "com.sathvik.homestep.place", conformingTo: .json)
}

/// All the user's places. Markers are looked up in the one in use.
struct PlacesView: View {
    @EnvironmentObject var places: PlaceStore
    @State private var newName = ""
    @State private var addingPlace = false
    @State private var importing = false
    @State private var importError: String?
    @State private var pendingDelete: Place?

    var body: some View {
        List {
            if places.places.isEmpty {
                Section {
                    Text("A place is a home, office or any indoor space you know. Add one, give it landmarks, then print and place its markers.")
                    Button("Add a place") { addingPlace = true }
                    Button("Try the sample place") {
                        let sample = places.importSample()
                        places.activePlaceID = sample.id
                    }
                }
            } else {
                Section {
                    ForEach(places.places) { place in
                        NavigationLink {
                            PlaceDetailView(placeID: place.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(place.name).font(.headline)
                                    Text("\(place.landmarks.count) marker\(place.landmarks.count == 1 ? "" : "s")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if place.id == places.activePlaceID {
                                    Text("In use").font(.subheadline.bold()).foregroundStyle(.green)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onDelete { offsets in
                        pendingDelete = offsets.first.map { places.places[$0] }
                    }
                } footer: {
                    Text("HomeStep reads the markers of the place marked \"In use\".")
                }
            }
        }
        .navigationTitle("Places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New place", systemImage: "plus") { addingPlace = true }
                    Button("Import a shared place", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Add the sample place", systemImage: "house") { places.importSample() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .alert("New place", isPresented: $addingPlace) {
            TextField("Name, e.g. Home", text: $newName)
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                places.addPlace(named: name.isEmpty ? "My place" : name)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "place")?",
                            isPresented: .constant(pendingDelete != nil), titleVisibility: .visible) {
            Button("Delete place", role: .destructive) {
                if let id = pendingDelete?.id { places.delete(id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.id == places.activePlaceID
                 ? "This is the place in use. Its markers will stop being announced."
                 : "Its landmarks will be removed from this iPhone.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.homeStepPlace, .json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try places.importPlace(from: Data(contentsOf: url))
            } catch {
                importError = "That file isn't a HomeStep place."
            }
        }
        .alert("Couldn't import", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }
}

/// One place: its landmarks, printing and sharing.
struct PlaceDetailView: View {
    let placeID: UUID
    @EnvironmentObject var places: PlaceStore
    @State private var editing: Landmark?
    @State private var renaming = false
    @State private var newName = ""
    @State private var shareItem: ShareItem?
    @State private var shareError: String?

    private var place: Place? { places.places.first { $0.id == placeID } }

    var body: some View {
        if let place {
            List {
                Section {
                    if place.id == places.activePlaceID {
                        Label("HomeStep is using this place", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Use this place") { places.activePlaceID = place.id }
                    }
                }

                Section {
                    ForEach(place.landmarks) { lm in
                        Button { editing = lm } label: { LandmarkRow(landmark: lm) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { place.landmarks[$0].id }
                        for id in ids { places.deleteLandmark(id, in: place.id) }
                    }
                    Button("Add landmark", systemImage: "plus") {
                        editing = Landmark(marker: place.nextMarkerNumber, name: "", kind: .landmark)
                    }
                } header: {
                    Text("Landmarks")
                } footer: {
                    Text("Each landmark gets a numbered marker. Print them, then tape each one about a stride before its spot, low on a wall, door frame or baseboard.")
                }

                Section {
                    Button("Print or save markers", systemImage: "printer") {
                        share { try MarkerSheet.pdfFile(for: place) }
                    }
                    .disabled(place.landmarks.isEmpty)
                    Button("Share this place", systemImage: "square.and.arrow.up") {
                        share {
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("\(MarkerSheet.safeFileName(place.name)).homestep")
                            try places.exportData(place).write(to: url, options: .atomic)
                            return url
                        }
                    }
                    Button("Rename", systemImage: "pencil") { newName = place.name; renaming = true }
                } footer: {
                    Text("Sharing sends the landmark list only — for example so a family member can set it up on their phone. Nothing is uploaded by HomeStep.")
                }
            }
            .navigationTitle(place.name)
            .sheet(item: $editing) { lm in
                NavigationStack {
                    LandmarkEditor(landmark: lm, placeID: place.id,
                                   isNew: !place.landmarks.contains { $0.id == lm.id })
                }
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
            .alert("Rename place", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { places.rename(place.id, to: name) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't prepare file", isPresented: .constant(shareError != nil)) {
                Button("OK") { shareError = nil }
            } message: { Text(shareError ?? "") }
        } else {
            Text("This place was deleted.")
        }
    }

    private func share(_ make: () throws -> URL) {
        do { shareItem = ShareItem(url: try make()) } catch { shareError = error.localizedDescription }
    }
}

private struct LandmarkRow: View {
    let landmark: Landmark

    var body: some View {
        HStack(spacing: 14) {
            Text("\(landmark.marker)")
                .font(.title3.monospacedDigit().bold())
                .frame(minWidth: 40, minHeight: 40)
                .background(landmark.isHazard ? Color.red : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(landmark.name.isEmpty ? "Unnamed" : landmark.name).font(.headline)
                Text(landmark.kind.title + " · says \"\(landmark.spokenText)\"")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Marker \(landmark.marker), \(landmark.name), \(landmark.kind.title). Says \(landmark.spokenText)")
        .accessibilityHint("Edit")
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
