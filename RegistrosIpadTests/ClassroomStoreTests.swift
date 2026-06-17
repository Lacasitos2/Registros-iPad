import XCTest
@testable import RegistrosIpad

@MainActor
final class ClassroomStoreTests: XCTestCase {
    func testBackupRoundTripRestoresGroupsRecordsAndQuickNotes() throws {
        let initialData = AppData(
            groups: [
                ClassGroup(
                    name: "2 ESO A",
                    students: [
                        Student(name: "Ana Ruiz", listNumber: "1")
                    ]
                )
            ],
            records: []
        )
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: initialData)
        let group = try XCTUnwrap(store.data.groups.first)
        let student = try XCTUnwrap(group.students.first)

        store.setHomework(.done, for: student, in: group)
        store.addQuickNoteTemplate("Ha mejorado la entrega")

        let backupURL = try XCTUnwrap(store.exportBackup())
        let restoredStore = ClassroomStore(
            fileURL: temporaryJSONURL(),
            fallbackData: AppData(groups: [], records: [])
        )

        try restoredStore.restoreBackup(from: backupURL)

        XCTAssertEqual(restoredStore.data.groups.map(\.name), ["2 ESO A"])
        XCTAssertEqual(restoredStore.data.groups.first?.students.map(\.name), ["Ana Ruiz"])
        XCTAssertEqual(restoredStore.data.records.count, 1)
        XCTAssertEqual(restoredStore.data.records.first?.homework, .done)
        XCTAssertTrue(restoredStore.quickNotes.contains("Ha mejorado la entrega"))
    }

    func testBackupUsesVersionedEnvelope() throws {
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: AppData.sample)

        let backupURL = try XCTUnwrap(store.exportBackup())
        let backup = try String(contentsOf: backupURL, encoding: .utf8)

        XCTAssertTrue(backup.contains("\"schemaVersion\""))
        XCTAssertTrue(backup.contains("\"data\""))
    }

    func testStoreLoadsLegacyUnversionedAppData() throws {
        let legacyData = AppData(
            groups: [
                ClassGroup(
                    name: "Legacy",
                    students: [
                        Student(name: "Alumno antiguo", listNumber: "4")
                    ]
                )
            ],
            records: []
        )
        let legacyURL = temporaryJSONURL()
        let encoded = try JSONEncoder().encode(legacyData)
        try encoded.write(to: legacyURL, options: .atomic)

        let store = ClassroomStore(fileURL: legacyURL, fallbackData: AppData(groups: [], records: []))

        XCTAssertEqual(store.data.groups.first?.name, "Legacy")
        XCTAssertEqual(store.data.groups.first?.students.first?.displayName, "4. Alumno antiguo")
    }

    func testHomeworkSummaryCSVIncludesMarkedCountsAndPercentage() throws {
        let initialData = AppData(
            groups: [
                ClassGroup(
                    name: "1 Bach B",
                    students: [
                        Student(name: "Leo Martin", listNumber: "7")
                    ]
                )
            ],
            records: []
        )
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: initialData)
        let group = try XCTUnwrap(store.data.groups.first)
        let student = try XCTUnwrap(group.students.first)

        store.setHomework(.done, for: student, in: group)

        let csvURL = try XCTUnwrap(store.exportHomeworkSummaryCSV(for: group, startDate: nil, endDate: nil))
        let csv = try String(contentsOf: csvURL, encoding: .utf8)

        XCTAssertTrue(csv.contains("grupo,numero_lista,alumno,registros_marcados,hechos,parciales,no_hechos,porcentaje_hechos"))
        XCTAssertTrue(csv.contains("1 Bach B,7,Leo Martin,1,1,0,0,100"))
    }

    func testDeletingGroupAlsoDeletesItsRecords() throws {
        let firstStudent = Student(name: "Ana Ruiz")
        let secondStudent = Student(name: "Leo Martin")
        let firstGroup = ClassGroup(name: "2 ESO A", students: [firstStudent])
        let secondGroup = ClassGroup(name: "3 ESO B", students: [secondStudent])
        let initialData = AppData(
            groups: [firstGroup, secondGroup],
            records: [
                StudentRecord(studentID: firstStudent.id, groupID: firstGroup.id, date: Date(), homework: .done, note: ""),
                StudentRecord(studentID: secondStudent.id, groupID: secondGroup.id, date: Date(), homework: .missing, note: "")
            ]
        )
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: initialData)

        store.deleteGroup(firstGroup)

        XCTAssertEqual(store.data.groups.map(\.id), [secondGroup.id])
        XCTAssertEqual(store.data.records.map(\.groupID), [secondGroup.id])
    }

    func testDeletingStudentAlsoDeletesOnlyThatStudentsRecords() throws {
        let firstStudent = Student(name: "Ana Ruiz")
        let secondStudent = Student(name: "Leo Martin")
        let group = ClassGroup(name: "2 ESO A", students: [firstStudent, secondStudent])
        let initialData = AppData(
            groups: [group],
            records: [
                StudentRecord(studentID: firstStudent.id, groupID: group.id, date: Date(), homework: .done, note: ""),
                StudentRecord(studentID: secondStudent.id, groupID: group.id, date: Date(), homework: .missing, note: "")
            ]
        )
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: initialData)

        store.deleteStudent(firstStudent.id, in: group.id)

        XCTAssertEqual(store.data.groups.first?.students.map(\.id), [secondStudent.id])
        XCTAssertEqual(store.data.records.map(\.studentID), [secondStudent.id])
    }

    func testIncidentsCSVIncludesOnlyBehaviorAndObservationRecords() throws {
        let firstStudent = Student(name: "Ana Ruiz", listNumber: "1")
        let secondStudent = Student(name: "Leo Martin", listNumber: "2")
        let group = ClassGroup(name: "2 ESO A", students: [firstStudent, secondStudent])
        let initialData = AppData(
            groups: [group],
            records: [
                StudentRecord(studentID: firstStudent.id, groupID: group.id, date: Date(), homework: .done, behavior: .warning, note: ""),
                StudentRecord(studentID: secondStudent.id, groupID: group.id, date: Date(), homework: .done, note: "Hablar con familia"),
                StudentRecord(studentID: secondStudent.id, groupID: group.id, date: Date(), homework: .done, note: "")
            ]
        )
        let store = ClassroomStore(fileURL: temporaryJSONURL(), fallbackData: initialData)

        let csvURL = try XCTUnwrap(store.exportIncidentsCSV(for: group, startDate: nil, endDate: nil))
        let csv = try String(contentsOf: csvURL, encoding: .utf8)

        XCTAssertTrue(csv.contains("fecha,grupo,numero_lista,alumno,conducta,observacion"))
        XCTAssertTrue(csv.contains("2 ESO A,1,Ana Ruiz,Aviso,"))
        XCTAssertTrue(csv.contains("2 ESO A,2,Leo Martin,,Hablar con familia"))
        XCTAssertFalse(csv.contains("Leo Martin,,\"\""))
    }

    private func temporaryJSONURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
