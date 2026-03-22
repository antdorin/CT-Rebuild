// MARK: - Camera Mode

enum CameraMode: String, CaseIterable, Identifiable {
    case scan   = "Scan"
    case detect = "Detect"
    var id: Self { self }
}
