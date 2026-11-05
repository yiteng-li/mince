import PhotosUI
import SwiftUI
import UIKit

/// Shared review step for Photo Log and Voice Log: fix names and grams, pick the matching food, log.
struct AIReviewList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    @Binding var items: [AIService.Item]
    var suggestions: [AIService.Item] = []
    var source: DiaryEntry.Source
    var allowSaveAsRecipe = false

    @State private var matches: [UUID: Food] = [:]
    @State private var picking: AIService.Item?
    @State private var saving = false
    @State private var saveAsRecipe = false
    @State private var recipeName = ""

    var body: some View {
        Form {
            Section {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        TextField("Food", text: $item.name).font(Theme.Fonts.heading)
                        HStack {
                            NumberField(title: "Grams", value: Binding(get: { item.grams }, set: { item.grams = $0 ?? 0 }), unit: "g")
                        }
                        Button {
                            picking = item
                        } label: {
                            Label(matches[item.id]?.name ?? "Choose a matching food", systemImage: matches[item.id] == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                                .foregroundStyle(matches[item.id] == nil ? Theme.Colors.warning : Theme.Colors.success)
                                .font(Theme.Fonts.footnote)
                        }
                        .buttonStyle(.borderless)   // the row also holds text fields
                        if let note = item.note { Text(note).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted) }
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
            } header: { Text("Check what we found") } footer: { Text("Estimates from AI. Adjust amounts before logging.") }

            let extras = suggestions.filter { s in !items.contains { $0.name.lowercased() == s.name.lowercased() } }
            if !extras.isEmpty {
                Section("Often hidden in dishes like this") {
                    ForEach(extras) { s in
                        Button { items.append(s); Task { await match(s) } } label: {
                            Label("\(s.name), \(Int(s.grams)) g", systemImage: "plus.circle")
                        }
                    }
                }
            }

            if allowSaveAsRecipe {
                Section {
                    Toggle("Also save as a recipe", isOn: $saveAsRecipe)
                    if saveAsRecipe { TextField("Recipe name", text: $recipeName) }
                }
            }

            let kcal = items.reduce(0.0) { $0 + (matches[$1.id]?.nutrients[.energy] ?? 0) * $1.grams / 100 }
            Section { LabeledContent("Total", value: Units.energy(kcal, app.energyUnit)) }
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log all") { Task { await logAll() } }
                    .disabled(saving || items.isEmpty || items.contains { matches[$0.id] == nil || $0.grams <= 0 })
            }
        }
        .task { for item in items where matches[item.id] == nil { await match(item) } }
        .sheet(item: $picking) { item in
            FoodPicker(initialQuery: item.name) { food in
                matches[item.id] = food
                picking = nil
            }
        }
    }

    private func match(_ item: AIService.Item) async {
        if let id = item.foodId, let food = try? await FoodService().food(id: id) { matches[item.id] = food; return }
        if let first = try? await FoodService().search(item.name, limit: 1).first { matches[item.id] = first }
    }

    private func logAll() async {
        guard let uid = app.userId else { return }
        saving = true
        defer { saving = false }
        let group = groupId ?? app.defaultGroupId()
        let entries = items.compactMap { item -> DiaryEntry? in
            guard let food = matches[item.id] else { return nil }
            return DiaryEntry(userId: uid, day: app.selectedDay, kind: .food, groupId: group, foodId: food.id, servingQty: item.grams,
                              amountG: item.grams, source: source)
        }
        if saveAsRecipe, !recipeName.isEmpty {
            let recipe = Food(userId: uid, kind: .recipe, source: .recipe, name: recipeName)
            let lines = items.compactMap { i in matches[i.id].map { FoodLine(parentId: recipe.id, foodId: $0.id, servingId: nil, servingQty: i.grams, amountG: i.grams) } }
            do { try await FoodService().saveRecipe(recipe, ingredients: lines, servings: []) } catch { app.report(error) }
        }
        if await app.log(entries) { dismiss() }
    }
}

/// Pick a food from search (used to fix AI matches and to add recipe/meal ingredients).
struct FoodPicker: View {
    @Environment(\.dismiss) private var dismiss
    var initialQuery = ""
    var onPick: (Food) -> Void
    @State private var query = ""
    @State private var results: [Food] = []

    var body: some View {
        NavigationStack {
            List(results) { food in
                Button { onPick(food) } label: { FoodResultRow(food: food) }.buttonStyle(.plain)
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                results = query.count >= 2 ? ((try? await FoodService().search(query)) ?? []) : ((try? await FoodService().recent()) ?? [])
            }
            .onAppear { query = initialQuery }
            .navigationTitle("Choose food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// S10 (Gold): photograph a meal; AI lists the foods and amounts.
struct PhotoLogView: View {
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var analysing = false
    @State private var items: [AIService.Item] = []
    @State private var suggestions: [AIService.Item] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if !items.isEmpty {
                    AIReviewList(groupId: groupId, items: $items, suggestions: suggestions, source: .photo, allowSaveAsRecipe: true)
                } else {
                    VStack(spacing: Theme.Space.md) {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                                .frame(maxHeight: 320).accessibilityLabel("Your meal photo")
                        } else {
                            EmptyStateView(symbol: "camera.viewfinder", title: "Snap your meal", hint: "Shoot from above with everything on the plate in view.")
                        }
                        if analysing { ProgressView("Identifying foods…") }
                        if let error { Text(error).foregroundStyle(Theme.Colors.danger).multilineTextAlignment(.center) }
                        Spacer()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo") { showCamera = true }.buttonStyle(.minced)
                        }
                        PhotosPicker("Choose from library", selection: $pickerItem, matching: .images).buttonStyle(.minced(.secondary))
                    }
                    .padding(Theme.Space.md)
                }
            }
            .navigationTitle("Photo log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { await analyse(img) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in showCamera = false; if let img { Task { await analyse(img) } } }.ignoresSafeArea()
            }
        }
    }

    private func analyse(_ img: UIImage) async {
        image = img
        analysing = true
        error = nil
        defer { analysing = false }
        guard let jpeg = img.resizedJPEG(maxSide: 1280) else { error = "Couldn't read that photo."; return }
        do {
            let r = try await AIService().recognise(photo: jpeg)
            if r.items.isEmpty { error = "No food found in that photo. Try another angle." }
            items = r.items
            suggestions = r.suggestions ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// S11 (Gold): say what you ate; AI turns it into foods and amounts.
struct VoiceLogView: View {
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    var initialText: String?
    @State private var speech = SpeechService()
    @State private var text = ""
    @State private var parsing = false
    @State private var items: [AIService.Item] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if !items.isEmpty {
                    AIReviewList(groupId: groupId, items: $items, source: .voice)
                } else {
                    VStack(spacing: Theme.Space.md) {
                        Text("Say something like “two scrambled eggs, a slice of sourdough and a black coffee”.")
                            .foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(Theme.Space.xs)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .accessibilityLabel("What you ate")
                        Button {
                            if speech.isRecording { speech.stop() } else { Task { await speech.start() } }
                        } label: {
                            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(speech.isRecording ? Theme.Colors.danger : Theme.Colors.accent)
                        }
                        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start recording")
                        if parsing { ProgressView("Working it out…") }
                        if let e = error ?? speech.errorMessage { Text(e).foregroundStyle(Theme.Colors.danger) }
                        Spacer()
                        Button("Find foods") { Task { await parse() } }
                            .buttonStyle(.minced(.primary, loading: parsing))
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || parsing)
                    }
                    .padding(Theme.Space.md)
                }
            }
            .background(Theme.Colors.bg)
            .navigationTitle("Voice log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.stop(); dismiss() } } }
            .onChange(of: speech.transcript) { _, t in text = t }
            .task {
                if let initialText, !initialText.isEmpty { text = initialText; await parse() }
            }
        }
    }

    private func parse() async {
        speech.stop()
        parsing = true
        error = nil
        defer { parsing = false }
        do {
            items = try await AIService().parse(text: text).items
            if items.isEmpty { error = "Couldn't pick out any foods. Try naming them with amounts." }
        } catch { self.error = error.localizedDescription }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}

extension UIImage {
    /// Downscales so the longest side is `maxSide` and encodes as JPEG (keeps uploads well under the 5 MB bucket limit).
    func resizedJPEG(maxSide: CGFloat, quality: CGFloat = 0.8) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }.jpegData(compressionQuality: quality)
    }
}
