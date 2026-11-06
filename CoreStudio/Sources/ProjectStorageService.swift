import Foundation

final class ProjectStorageService {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func saveProject(_ project: Project) {
        let fileURL = documentsDirectory.appendingPathComponent("project_\(project.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(project)
            try data.write(to: fileURL, options: .atomic)
            UserDefaults.standard.set(fileURL.path, forKey: "lastOpenedProject")
        } catch {
            print("Failed to save project: \(error)")
        }
    }

    func loadLatestProject() -> Project? {
        guard let path = UserDefaults.standard.string(forKey: "lastOpenedProject") else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let project = try JSONDecoder().decode(Project.self, from: data)
            return project
        } catch {
            print("Failed to load project: \(error)")
            return nil
        }
    }
}

