import Foundation

enum HomeworkStatus: String, Codable, CaseIterable, Identifiable {
    case done
    case partial
    case missing
    case unmarked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .done: "Hecho"
        case .partial: "Parcial"
        case .missing: "No hecho"
        case .unmarked: "Sin marcar"
        }
    }

    var csvValue: String {
        switch self {
        case .done: "hecho"
        case .partial: "parcial"
        case .missing: "no hecho"
        case .unmarked: ""
        }
    }
}

enum BehaviorMark: String, Codable, CaseIterable, Identifiable {
    case positive
    case warning
    case disruption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positive: "Positivo"
        case .warning: "Aviso"
        case .disruption: "Molesta"
        }
    }
}

struct Student: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var listNumber: String?

    var displayName: String {
        guard let listNumber, !listNumber.isEmpty else { return name }
        return "\(listNumber). \(name)"
    }
}

struct ClassGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var students: [Student]
}

struct StudentRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var studentID: UUID
    var groupID: UUID
    var date: Date
    var homework: HomeworkStatus
    var boardGrade: Double?
    var behavior: BehaviorMark?
    var participation: Int? = nil
    var hasMaterial: Bool? = nil
    var note: String
}

struct AppData: Codable {
    var groups: [ClassGroup]
    var records: [StudentRecord]
    var quickNotes: [String]? = nil

    static let sample = AppData(
        groups: [
            ClassGroup(
                name: "Grupo de ejemplo",
                students: [
                    Student(name: "Alumno 1"),
                    Student(name: "Alumno 2"),
                    Student(name: "Alumno 3"),
                    Student(name: "Alumno 4"),
                    Student(name: "Alumno 5"),
                    Student(name: "Alumno 6")
                ]
            )
        ],
        records: []
    )
}

struct PersistedAppData: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var data: AppData

    init(schemaVersion: Int = Self.currentSchemaVersion, data: AppData) {
        self.schemaVersion = schemaVersion
        self.data = data
    }
}
