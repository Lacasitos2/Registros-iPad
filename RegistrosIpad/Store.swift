import Foundation
import SwiftUI
import UIKit

@MainActor
final class ClassroomStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var lastHomeworkChange: HomeworkChange?
    @Published var selectedGroupID: UUID?
    @Published var selectedDate: Date

    private let fileURL: URL
    private static let defaultQuickNotes = [
        "Buen trabajo",
        "Participa bien",
        "No trae material",
        "Interrumpe",
        "Debe mejorar la presentación",
        "Necesita revisar en casa"
    ]

    struct HomeworkChange {
        let groupID: UUID
        let studentID: UUID
        let previousRecord: StudentRecord?
        let newRecordID: UUID
        let studentName: String
        let previousStatus: HomeworkStatus
        let newStatus: HomeworkStatus
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documents.appendingPathComponent("registros-ipad.json")
        selectedDate = Calendar.current.startOfDay(for: Date())

        if let savedData = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.registros.decode(AppData.self, from: savedData) {
            data = decoded
        } else {
            data = .sample
        }

        selectedGroupID = data.groups.first?.id
    }

    var selectedGroup: ClassGroup? {
        guard let selectedGroupID else { return data.groups.first }
        return data.groups.first(where: { $0.id == selectedGroupID })
    }

    var quickNotes: [String] {
        data.quickNotes ?? Self.defaultQuickNotes
    }

    static func studentNames(from csvText: String) -> [String] {
        StudentImportParser.groups(from: csvText, fallbackGroupName: "Grupo importado")
            .flatMap(\.students)
            .map(\.name)
    }

    static func importedGroups(from text: String, fallbackGroupName: String) -> [ImportedGroupPreview] {
        StudentImportParser.groups(from: text, fallbackGroupName: fallbackGroupName)
    }

    func addGroup(name: String, csvText: String) {
        let previews = Self.importedGroups(from: csvText, fallbackGroupName: name)
        addGroups(previews)
    }

    func addGroups(_ previews: [ImportedGroupPreview]) {
        let groups = previews.compactMap { preview -> ClassGroup? in
            let groupName = preview.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !groupName.isEmpty, !preview.students.isEmpty else { return nil }

            return ClassGroup(
                name: groupName,
                students: preview.students.map { Student(name: $0.name, listNumber: $0.listNumber) }
            )
        }

        guard !groups.isEmpty else { return }

        data.groups.append(contentsOf: groups)
        selectedGroupID = groups.first?.id
        save()
    }

    func deleteGroup(_ group: ClassGroup) {
        data.groups.removeAll { $0.id == group.id }
        data.records.removeAll { $0.groupID == group.id }
        selectedGroupID = data.groups.first?.id
        save()
    }

    func renameGroup(_ groupID: UUID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let groupIndex = groupIndex(for: groupID) else {
            return
        }

        data.groups[groupIndex].name = trimmedName
        save()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        data.groups.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func addStudent(named name: String, listNumber: String? = nil, to groupID: UUID) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let groupIndex = groupIndex(for: groupID) else { return }

        data.groups[groupIndex].students.append(Student(name: trimmedName, listNumber: sanitizedListNumber(listNumber)))
        save()
    }

    func renameStudent(_ studentID: UUID, in groupID: UUID, to name: String) {
        guard let groupIndex = groupIndex(for: groupID),
              let studentIndex = data.groups[groupIndex].students.firstIndex(where: { $0.id == studentID }) else {
            return
        }

        data.groups[groupIndex].students[studentIndex].name = name
        save()
    }

    func updateStudentListNumber(_ studentID: UUID, in groupID: UUID, to listNumber: String) {
        guard let groupIndex = groupIndex(for: groupID),
              let studentIndex = data.groups[groupIndex].students.firstIndex(where: { $0.id == studentID }) else {
            return
        }

        data.groups[groupIndex].students[studentIndex].listNumber = sanitizedListNumber(listNumber)
        save()
    }

    func addQuickNoteTemplate(_ note: String) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }

        var notes = quickNotes
        guard !notes.contains(where: { $0.localizedCaseInsensitiveCompare(trimmedNote) == .orderedSame }) else { return }

        notes.append(trimmedNote)
        data.quickNotes = notes
        save()
    }

    func deleteQuickNoteTemplate(_ note: String) {
        var notes = quickNotes
        notes.removeAll { $0 == note }
        data.quickNotes = notes
        save()
    }

    func deleteStudents(at offsets: IndexSet, in groupID: UUID) {
        guard let groupIndex = groupIndex(for: groupID) else { return }

        let deletedStudentIDs = offsets.map { data.groups[groupIndex].students[$0].id }
        data.groups[groupIndex].students.remove(atOffsets: offsets)
        data.records.removeAll { record in
            record.groupID == groupID && deletedStudentIDs.contains(record.studentID)
        }
        save()
    }

    func deleteStudent(_ studentID: UUID, in groupID: UUID) {
        guard let groupIndex = groupIndex(for: groupID) else { return }

        data.groups[groupIndex].students.removeAll { $0.id == studentID }
        data.records.removeAll { record in
            record.groupID == groupID && record.studentID == studentID
        }
        save()
    }

    func moveStudents(from source: IndexSet, to destination: Int, in groupID: UUID) {
        guard let groupIndex = groupIndex(for: groupID) else { return }

        data.groups[groupIndex].students.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func record(for student: Student, in group: ClassGroup) -> StudentRecord {
        if let existing = data.records.first(where: {
            $0.studentID == student.id &&
            $0.groupID == group.id &&
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }) {
            return existing
        }

        return StudentRecord(
            studentID: student.id,
            groupID: group.id,
            date: selectedDate,
            homework: .unmarked,
            note: ""
        )
    }

    func updateRecord(_ record: StudentRecord) {
        if let index = data.records.firstIndex(where: { $0.id == record.id }) {
            data.records[index] = record
        } else {
            data.records.append(record)
        }
        save()
    }

    func setHomework(_ status: HomeworkStatus, for student: Student, in group: ClassGroup) {
        let previousRecord = existingRecord(for: student, in: group)
        var record = record(for: student, in: group)
        let previousStatus = record.homework
        record.homework = status
        updateRecord(record)
        lastHomeworkChange = HomeworkChange(
            groupID: group.id,
            studentID: student.id,
            previousRecord: previousRecord,
            newRecordID: record.id,
            studentName: student.name,
            previousStatus: previousStatus,
            newStatus: status
        )
    }

    func toggleParticipation(for student: Student, in group: ClassGroup) {
        var record = record(for: student, in: group)
        record.participation = (record.participation ?? 0) > 0 ? nil : 1
        updateRecord(record)
    }

    func toggleMaterial(for student: Student, in group: ClassGroup) {
        var record = record(for: student, in: group)
        record.hasMaterial = (record.hasMaterial ?? false) ? nil : true
        updateRecord(record)
    }

    func incrementBoardGrade(for student: Student, in group: ClassGroup) {
        var record = record(for: student, in: group)
        let currentGrade = record.boardGrade ?? 0
        record.boardGrade = min(currentGrade + 0.5, 10)
        updateRecord(record)
    }

    func toggleBehavior(_ behavior: BehaviorMark, for student: Student, in group: ClassGroup) {
        var record = record(for: student, in: group)
        record.behavior = record.behavior == behavior ? nil : behavior
        updateRecord(record)
    }

    func undoLastHomeworkChange() {
        guard let change = lastHomeworkChange else { return }

        if let previousRecord = change.previousRecord {
            if let index = data.records.firstIndex(where: { $0.id == previousRecord.id }) {
                data.records[index] = previousRecord
            } else {
                data.records.append(previousRecord)
            }
        } else {
            data.records.removeAll { $0.id == change.newRecordID }
        }

        lastHomeworkChange = nil
        save()
    }

    func records(for student: Student) -> [StudentRecord] {
        data.records
            .filter { $0.studentID == student.id }
            .sorted { $0.date > $1.date }
    }

    func exportCSV(for group: ClassGroup) -> URL? {
        let rows = csvRows(for: group)
        let fileName = "registros-\(group.name.normalizedFileName).csv"
        return writeCSV(rows: rows, fileName: fileName)
    }

    func exportCSV(for student: Student, in group: ClassGroup, records: [StudentRecord]) -> URL? {
        let rows = csvRows(for: student, in: group, records: records)
        let fileName = "registros-\(group.name.normalizedFileName)-\(student.name.normalizedFileName).csv"
        return writeCSV(rows: rows, fileName: fileName)
    }

    func exportStudentPDF(for student: Student, in group: ClassGroup, records: [StudentRecord], periodDescription: String) -> URL? {
        let sortedRecords = records
            .filter { $0.studentID == student.id && $0.groupID == group.id }
            .sorted { $0.date < $1.date }
        let fileName = "informe-\(group.name.normalizedFileName)-\(student.name.normalizedFileName).pdf"
        return writeStudentPDF(student: student, group: group, records: sortedRecords, periodDescription: periodDescription, fileName: fileName)
    }

    func exportGroupPDF(for group: ClassGroup, startDate: Date?, endDate: Date?, periodDescription: String) -> URL? {
        let calendar = Calendar.current
        let studentNames = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.name) })
        let filteredRecords = records(for: group, startDate: startDate, endDate: endDate, calendar: calendar)
            .sorted {
                if calendar.isDate($0.date, inSameDayAs: $1.date) {
                    return (studentNames[$0.studentID] ?? "") < (studentNames[$1.studentID] ?? "")
                }
                return $0.date < $1.date
            }
        let fileName = "informe-\(group.name.normalizedFileName).pdf"
        return writeGroupPDF(group: group, records: filteredRecords, periodDescription: periodDescription, fileName: fileName)
    }

    func exportGroupStudentReportsPDF(for group: ClassGroup, startDate: Date?, endDate: Date?, periodDescription: String) -> URL? {
        let calendar = Calendar.current
        let filteredRecords = records(for: group, startDate: startDate, endDate: endDate, calendar: calendar)
        let fileName = "informes-alumnos-\(group.name.normalizedFileName).pdf"
        return writeGroupStudentReportsPDF(group: group, records: filteredRecords, periodDescription: periodDescription, fileName: fileName)
    }

    func exportHomeworkSummaryCSV(for group: ClassGroup, startDate: Date?, endDate: Date?) -> URL? {
        let rows = homeworkSummaryRows(for: group, startDate: startDate, endDate: endDate)
        let fileName = "deberes-\(group.name.normalizedFileName).csv"
        return writeCSV(rows: rows, fileName: fileName)
    }

    func exportIncidentsCSV(for group: ClassGroup, startDate: Date?, endDate: Date?) -> URL? {
        let rows = incidentRows(for: group, startDate: startDate, endDate: endDate)
        let fileName = "incidencias-\(group.name.normalizedFileName).csv"
        return writeCSV(rows: rows, fileName: fileName)
    }

    private func csvRows(for group: ClassGroup) -> [[String]] {
        let studentNames = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.name) })
        let studentListNumbers = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.listNumber ?? "") })
        let records = data.records
            .filter { $0.groupID == group.id }
            .sorted {
                if $0.date == $1.date {
                    return (studentNames[$0.studentID] ?? "") < (studentNames[$1.studentID] ?? "")
                }
                return $0.date < $1.date
            }

        var rows = [["fecha", "grupo", "numero_lista", "alumno", "deberes", "pizarra", "conducta", "participacion", "material", "observacion"]]
        rows += records.map { record in
            csvRow(
                for: record,
                groupName: group.name,
                studentName: studentNames[record.studentID] ?? "Alumno eliminado",
                listNumber: studentListNumbers[record.studentID] ?? ""
            )
        }
        return rows
    }

    private func csvRows(for student: Student, in group: ClassGroup, records: [StudentRecord]) -> [[String]] {
        let sortedRecords = records
            .filter { $0.studentID == student.id && $0.groupID == group.id }
            .sorted { $0.date < $1.date }

        var rows = [["fecha", "grupo", "numero_lista", "alumno", "deberes", "pizarra", "conducta", "participacion", "material", "observacion"]]
        rows += sortedRecords.map { record in
            csvRow(
                for: record,
                groupName: group.name,
                studentName: student.name,
                listNumber: student.listNumber ?? ""
            )
        }
        return rows
    }

    private func csvRow(for record: StudentRecord, groupName: String, studentName: String, listNumber: String) -> [String] {
        [
            DateFormatter.registros.string(from: record.date),
            groupName,
            listNumber,
            studentName,
            record.homework.csvValue,
            record.boardGrade.map { String(format: "%.1f", $0) } ?? "",
            record.behavior?.title ?? "",
            (record.participation ?? 0) > 0 ? "si" : "",
            (record.hasMaterial ?? false) ? "si" : "",
            record.note
        ]
    }

    private func homeworkSummaryRows(for group: ClassGroup, startDate: Date?, endDate: Date?) -> [[String]] {
        let calendar = Calendar.current
        let filteredRecords = records(for: group, startDate: startDate, endDate: endDate, calendar: calendar)

        let recordsByStudent = Dictionary(grouping: filteredRecords, by: \.studentID)

        var rows = [["grupo", "numero_lista", "alumno", "registros_marcados", "hechos", "parciales", "no_hechos", "porcentaje_hechos"]]
        rows += group.students.map { student in
            let studentRecords = recordsByStudent[student.id] ?? []
            let markedRecords = studentRecords.filter { $0.homework != .unmarked }
            let done = markedRecords.filter { $0.homework == .done }.count
            let partial = markedRecords.filter { $0.homework == .partial }.count
            let missing = markedRecords.filter { $0.homework == .missing }.count
            let percentage = markedRecords.isEmpty ? "" : String(Int((Double(done) / Double(markedRecords.count) * 100).rounded()))

            return [
                group.name,
                student.listNumber ?? "",
                student.name,
                "\(markedRecords.count)",
                "\(done)",
                "\(partial)",
                "\(missing)",
                percentage
            ]
        }
        return rows
    }

    private func incidentRows(for group: ClassGroup, startDate: Date?, endDate: Date?) -> [[String]] {
        let calendar = Calendar.current
        let studentNames = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.name) })
        let studentListNumbers = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.listNumber ?? "") })
        let records = records(for: group, startDate: startDate, endDate: endDate, calendar: calendar)
            .filter { record in
                record.behavior != nil ||
                    !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted {
                if calendar.isDate($0.date, inSameDayAs: $1.date) {
                    return (studentNames[$0.studentID] ?? "") < (studentNames[$1.studentID] ?? "")
                }
                return $0.date < $1.date
            }

        var rows = [["fecha", "grupo", "numero_lista", "alumno", "conducta", "observacion"]]
        rows += records.map { record in
            [
                DateFormatter.registros.string(from: record.date),
                group.name,
                studentListNumbers[record.studentID] ?? "",
                studentNames[record.studentID] ?? "Alumno eliminado",
                record.behavior?.title ?? "",
                record.note
            ]
        }
        return rows
    }

    private func records(for group: ClassGroup, startDate: Date?, endDate: Date?, calendar: Calendar) -> [StudentRecord] {
        data.records.filter { record in
            guard record.groupID == group.id else { return false }

            let day = calendar.startOfDay(for: record.date)
            if let startDate, day < calendar.startOfDay(for: startDate) {
                return false
            }
            if let endDate, day > calendar.startOfDay(for: endDate) {
                return false
            }
            return true
        }
    }

    private func writeCSV(rows: [[String]], fileName: String) -> URL? {
        let csv = rows.map { $0.map(Self.escapeCSV).joined(separator: ",") }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func writeStudentPDF(student: Student, group: ClassGroup, records: [StudentRecord], periodDescription: String, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 42
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { context in
                var y = margin

                func beginPage() {
                    context.beginPage()
                    y = margin
                }

                func ensureSpace(_ height: CGFloat) {
                    if y + height > pageRect.height - margin {
                        beginPage()
                    }
                }

                func drawText(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 8) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                    let height = (text as NSString).boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    ).height.rounded(.up)
                    ensureSpace(height + spacing)
                    (text as NSString).draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                    y += height + spacing
                }

                func divider() {
                    ensureSpace(16)
                    UIColor.separator.setStroke()
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y + 4))
                    path.addLine(to: CGPoint(x: pageRect.width - margin, y: y + 4))
                    path.stroke()
                    y += 16
                }

                beginPage()
                drawText("Informe del alumno", font: .boldSystemFont(ofSize: 24), spacing: 10)
                drawText(student.displayName, font: .boldSystemFont(ofSize: 18), spacing: 4)
                drawText(group.name, font: .systemFont(ofSize: 13), color: .secondaryLabel, spacing: 4)
                drawText("Periodo: \(periodDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 4)
                drawText("Generado el \(DateFormatter.registros.string(from: Date()))", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 14)

                divider()
                drawText("Resumen", font: .boldSystemFont(ofSize: 16), spacing: 8)

                let markedRecords = records.filter { $0.homework != .unmarked }
                let done = markedRecords.filter { $0.homework == .done }.count
                let partial = markedRecords.filter { $0.homework == .partial }.count
                let missing = markedRecords.filter { $0.homework == .missing }.count
                let homeworkPercentage = markedRecords.isEmpty ? "Sin datos" : "\(Int((Double(done) / Double(markedRecords.count) * 100).rounded()))%"
                let grades = records.compactMap(\.boardGrade)
                let gradeAverage = grades.isEmpty ? "Sin datos" : String(format: "%.1f", grades.reduce(0, +) / Double(grades.count)).replacingOccurrences(of: ".", with: ",")
                let participation = records.filter { ($0.participation ?? 0) > 0 }.count
                let material = records.filter { $0.hasMaterial ?? false }.count
                let positives = records.filter { $0.behavior == .positive }.count
                let warnings = records.filter { $0.behavior == .warning || $0.behavior == .disruption }.count

                drawText(
                    "Deberes hechos: \(homeworkPercentage)\nMarcados: \(markedRecords.count) · Hechos: \(done) · Parciales: \(partial) · No hechos: \(missing)\nPizarra media: \(gradeAverage)\nParticipaciones: \(participation) · Material: \(material)\nPositivos: \(positives) · Avisos/incidencias: \(warnings)",
                    font: .systemFont(ofSize: 12),
                    spacing: 14
                )

                divider()
                drawText("Historial", font: .boldSystemFont(ofSize: 16), spacing: 8)

                if records.isEmpty {
                    drawText("No hay registros en el periodo seleccionado.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
                } else {
                    for record in records {
                        var details = ["Deberes: \(record.homework.title)"]
                        if let boardGrade = record.boardGrade {
                            details.append(String(format: "Pizarra: %.1f", boardGrade).replacingOccurrences(of: ".", with: ","))
                        }
                        if (record.participation ?? 0) > 0 {
                            details.append("Participa")
                        }
                        if record.hasMaterial ?? false {
                            details.append("Material")
                        }
                        if let behavior = record.behavior {
                            details.append("Conducta: \(behavior.title)")
                        }

                        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
                        let body = note.isEmpty
                            ? details.joined(separator: " · ")
                            : "\(details.joined(separator: " · "))\n\(note)"

                        drawText(DateFormatter.registros.string(from: record.date), font: .boldSystemFont(ofSize: 12), spacing: 3)
                        drawText(body, font: .systemFont(ofSize: 11), spacing: 12)
                    }
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private func writeGroupPDF(group: ClassGroup, records: [StudentRecord], periodDescription: String, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 42
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let recordsByStudent = Dictionary(grouping: records, by: \.studentID)
        let studentNames = Dictionary(uniqueKeysWithValues: group.students.map { ($0.id, $0.displayName) })

        do {
            try renderer.writePDF(to: url) { context in
                var y = margin

                func beginPage() {
                    context.beginPage()
                    y = margin
                }

                func ensureSpace(_ height: CGFloat) {
                    if y + height > pageRect.height - margin {
                        beginPage()
                    }
                }

                func drawText(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 8) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                    let height = (text as NSString).boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    ).height.rounded(.up)
                    ensureSpace(height + spacing)
                    (text as NSString).draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                    y += height + spacing
                }

                func divider() {
                    ensureSpace(16)
                    UIColor.separator.setStroke()
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y + 4))
                    path.addLine(to: CGPoint(x: pageRect.width - margin, y: y + 4))
                    path.stroke()
                    y += 16
                }

                beginPage()
                drawText("Informe del grupo", font: .boldSystemFont(ofSize: 24), spacing: 10)
                drawText(group.name, font: .boldSystemFont(ofSize: 18), spacing: 4)
                drawText("\(group.students.count) alumnos · \(records.count) registros en el periodo", font: .systemFont(ofSize: 13), color: .secondaryLabel, spacing: 4)
                drawText("Periodo: \(periodDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 4)
                drawText("Generado el \(DateFormatter.registros.string(from: Date()))", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 14)

                divider()
                drawText("Resumen por alumno", font: .boldSystemFont(ofSize: 16), spacing: 8)

                if group.students.isEmpty {
                    drawText("No hay alumnos en el grupo.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
                } else {
                    for student in group.students {
                        let studentRecords = recordsByStudent[student.id] ?? []
                        let markedRecords = studentRecords.filter { $0.homework != .unmarked }
                        let done = markedRecords.filter { $0.homework == .done }.count
                        let partial = markedRecords.filter { $0.homework == .partial }.count
                        let missing = markedRecords.filter { $0.homework == .missing }.count
                        let percentage = markedRecords.isEmpty ? "Sin datos" : "\(Int((Double(done) / Double(markedRecords.count) * 100).rounded()))%"
                        let positives = studentRecords.filter { $0.behavior == .positive }.count
                        let warnings = studentRecords.filter { $0.behavior == .warning || $0.behavior == .disruption }.count
                        let observations = studentRecords.filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count

                        drawText(student.displayName, font: .boldSystemFont(ofSize: 12), spacing: 3)
                        drawText(
                            "Deberes: \(percentage) · Marcados: \(markedRecords.count) · Hechos: \(done) · Parciales: \(partial) · No hechos: \(missing)\nPositivos: \(positives) · Avisos/incidencias: \(warnings) · Observaciones: \(observations)",
                            font: .systemFont(ofSize: 10.5),
                            spacing: 9
                        )
                    }
                }

                divider()
                drawText("Cronología", font: .boldSystemFont(ofSize: 16), spacing: 8)

                if records.isEmpty {
                    drawText("No hay registros en el periodo seleccionado.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
                } else {
                    for record in records {
                        var details = ["Deberes: \(record.homework.title)"]
                        if let boardGrade = record.boardGrade {
                            details.append(String(format: "Pizarra: %.1f", boardGrade).replacingOccurrences(of: ".", with: ","))
                        }
                        if (record.participation ?? 0) > 0 {
                            details.append("Participa")
                        }
                        if record.hasMaterial ?? false {
                            details.append("Material")
                        }
                        if let behavior = record.behavior {
                            details.append("Conducta: \(behavior.title)")
                        }

                        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = "\(DateFormatter.registros.string(from: record.date)) · \(studentNames[record.studentID] ?? "Alumno eliminado")"
                        let body = note.isEmpty
                            ? details.joined(separator: " · ")
                            : "\(details.joined(separator: " · "))\n\(note)"

                        drawText(title, font: .boldSystemFont(ofSize: 12), spacing: 3)
                        drawText(body, font: .systemFont(ofSize: 10.5), spacing: 12)
                    }
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private func writeGroupStudentReportsPDF(group: ClassGroup, records: [StudentRecord], periodDescription: String, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 42
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let recordsByStudent = Dictionary(grouping: records, by: \.studentID)

        do {
            try renderer.writePDF(to: url) { context in
                var y = margin

                func beginPage() {
                    context.beginPage()
                    y = margin
                }

                func ensureSpace(_ height: CGFloat) {
                    if y + height > pageRect.height - margin {
                        beginPage()
                    }
                }

                func drawText(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 8) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                    let height = (text as NSString).boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    ).height.rounded(.up)
                    ensureSpace(height + spacing)
                    (text as NSString).draw(
                        with: CGRect(x: margin, y: y, width: contentWidth, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attributes,
                        context: nil
                    )
                    y += height + spacing
                }

                func divider() {
                    ensureSpace(16)
                    UIColor.separator.setStroke()
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y + 4))
                    path.addLine(to: CGPoint(x: pageRect.width - margin, y: y + 4))
                    path.stroke()
                    y += 16
                }

                if group.students.isEmpty {
                    beginPage()
                    drawText("Informes individuales", font: .boldSystemFont(ofSize: 24), spacing: 10)
                    drawText(group.name, font: .boldSystemFont(ofSize: 18), spacing: 12)
                    drawText("Periodo: \(periodDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 4)
                    drawText("No hay alumnos en el grupo.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
                    return
                }

                for student in group.students {
                    beginPage()
                    let studentRecords = (recordsByStudent[student.id] ?? []).sorted { $0.date < $1.date }

                    drawText("Informe del alumno", font: .boldSystemFont(ofSize: 24), spacing: 10)
                    drawText(student.displayName, font: .boldSystemFont(ofSize: 18), spacing: 4)
                    drawText(group.name, font: .systemFont(ofSize: 13), color: .secondaryLabel, spacing: 4)
                    drawText("Periodo: \(periodDescription)", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 4)
                    drawText("Generado el \(DateFormatter.registros.string(from: Date()))", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacing: 14)

                    divider()
                    drawText("Resumen", font: .boldSystemFont(ofSize: 16), spacing: 8)

                    let markedRecords = studentRecords.filter { $0.homework != .unmarked }
                    let done = markedRecords.filter { $0.homework == .done }.count
                    let partial = markedRecords.filter { $0.homework == .partial }.count
                    let missing = markedRecords.filter { $0.homework == .missing }.count
                    let homeworkPercentage = markedRecords.isEmpty ? "Sin datos" : "\(Int((Double(done) / Double(markedRecords.count) * 100).rounded()))%"
                    let grades = studentRecords.compactMap(\.boardGrade)
                    let gradeAverage = grades.isEmpty ? "Sin datos" : String(format: "%.1f", grades.reduce(0, +) / Double(grades.count)).replacingOccurrences(of: ".", with: ",")
                    let participation = studentRecords.filter { ($0.participation ?? 0) > 0 }.count
                    let material = studentRecords.filter { $0.hasMaterial ?? false }.count
                    let positives = studentRecords.filter { $0.behavior == .positive }.count
                    let warnings = studentRecords.filter { $0.behavior == .warning || $0.behavior == .disruption }.count

                    drawText(
                        "Deberes hechos: \(homeworkPercentage)\nMarcados: \(markedRecords.count) · Hechos: \(done) · Parciales: \(partial) · No hechos: \(missing)\nPizarra media: \(gradeAverage)\nParticipaciones: \(participation) · Material: \(material)\nPositivos: \(positives) · Avisos/incidencias: \(warnings)",
                        font: .systemFont(ofSize: 12),
                        spacing: 14
                    )

                    divider()
                    drawText("Historial", font: .boldSystemFont(ofSize: 16), spacing: 8)

                    if studentRecords.isEmpty {
                        drawText("No hay registros en el periodo seleccionado.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
                    } else {
                        for record in studentRecords {
                            var details = ["Deberes: \(record.homework.title)"]
                            if let boardGrade = record.boardGrade {
                                details.append(String(format: "Pizarra: %.1f", boardGrade).replacingOccurrences(of: ".", with: ","))
                            }
                            if (record.participation ?? 0) > 0 {
                                details.append("Participa")
                            }
                            if record.hasMaterial ?? false {
                                details.append("Material")
                            }
                            if let behavior = record.behavior {
                                details.append("Conducta: \(behavior.title)")
                            }

                            let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
                            let body = note.isEmpty
                                ? details.joined(separator: " · ")
                                : "\(details.joined(separator: " · "))\n\(note)"

                            drawText(DateFormatter.registros.string(from: record.date), font: .boldSystemFont(ofSize: 12), spacing: 3)
                            drawText(body, font: .systemFont(ofSize: 11), spacing: 12)
                        }
                    }
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private func existingRecord(for student: Student, in group: ClassGroup) -> StudentRecord? {
        data.records.first {
            $0.studentID == student.id &&
            $0.groupID == group.id &&
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    private func groupIndex(for groupID: UUID) -> Int? {
        data.groups.firstIndex { $0.id == groupID }
    }

    private func sanitizedListNumber(_ listNumber: String?) -> String? {
        let trimmed = listNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        do {
            let encoded = try JSONEncoder.registros.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("No se pudieron guardar los datos: \(error)")
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

private extension JSONEncoder {
    static var registros: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var registros: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension DateFormatter {
    static let registros: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension String {
    var normalizedFileName: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
