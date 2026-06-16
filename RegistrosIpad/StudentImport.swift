import Foundation

struct ImportedStudentPreview: Identifiable, Hashable {
    var name: String
    var listNumber: String?

    var id: String { "\(listNumber ?? "")-\(name)" }
}

struct ImportedGroupPreview: Identifiable, Hashable {
    var name: String
    var students: [ImportedStudentPreview]
    var warnings: [String]

    var id: String { name }
}

struct StudentImportParser {
    static func groups(from text: String, fallbackGroupName: String) -> [ImportedGroupPreview] {
        let rows = text
            .components(separatedBy: .newlines)
            .map { delimitedValues(from: $0) }
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        return groups(from: rows, fallbackGroupName: fallbackGroupName)
    }

    static func groups(from rows: [[Int: String]], fallbackGroupName: String) -> [ImportedGroupPreview] {
        groups(from: table(from: rows), fallbackGroupName: fallbackGroupName)
    }

    static func groups(from rows: [[String]], fallbackGroupName: String, nameColumn: Int, listNumberColumn: Int?, separatesDetectedGroups: Bool) -> [ImportedGroupPreview] {
        guard !rows.isEmpty else { return [] }

        let analysis = columnAnalysis(in: rows)
        let dataRows = rows.dropFirst(analysis.dataStartIndex)
        var groupedStudents: [String: [(number: Double?, listNumber: String?, originalOrder: Int, name: String)]] = [:]
        var groupedWarnings: [String: [String]] = [:]
        var seenNamesByGroup: [String: Set<String>] = [:]
        var seenListNumbersByGroup: [String: Set<String>] = [:]

        for (offset, row) in dataRows.enumerated() {
            let lineNumber = analysis.dataStartIndex + offset + 1
            let groupName = groupName(
                from: row,
                analysis: analysis,
                fallbackGroupName: fallbackGroupName,
                separatesDetectedGroups: separatesDetectedGroups
            )
            let nameValue = value(at: nameColumn, in: row).nonEmptyTrimmed

            guard let name = nameValue, !looksLikeHeader(name) else {
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    groupedWarnings[groupName, default: []].append("Fila \(lineNumber): nombre vacío o no reconocido.")
                }
                continue
            }

            let duplicateKey = normalized(name)
            if seenNamesByGroup[groupName, default: []].contains(duplicateKey) {
                groupedWarnings[groupName, default: []].append("Fila \(lineNumber): alumno duplicado omitido (\(name)).")
                continue
            }

            seenNamesByGroup[groupName, default: []].insert(duplicateKey)
            let listNumber = listNumberColumn.flatMap { listNumberText(from: value(at: $0, in: row)) }
            if listNumberColumn != nil, listNumber == nil {
                groupedWarnings[groupName, default: []].append("Fila \(lineNumber): numero de lista vacio o no reconocido.")
            }
            if let listNumber {
                let listNumberKey = normalized(listNumber)
                if seenListNumbersByGroup[groupName, default: []].contains(listNumberKey) {
                    groupedWarnings[groupName, default: []].append("Fila \(lineNumber): numero de lista repetido (\(listNumber)).")
                }
                seenListNumbersByGroup[groupName, default: []].insert(listNumberKey)
            }
            groupedStudents[groupName, default: []].append((
                number: listNumber.flatMap { listNumberValue(from: $0) },
                listNumber: listNumber,
                originalOrder: offset,
                name: name
            ))
        }

        return groupedStudents.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { groupName in
            let students = (groupedStudents[groupName] ?? [])
                .sorted { first, second in
                    switch (first.number, second.number) {
                    case let (firstNumber?, secondNumber?):
                        if firstNumber == secondNumber {
                            return first.originalOrder < second.originalOrder
                        }
                        return firstNumber < secondNumber
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return first.originalOrder < second.originalOrder
                    }
                }
                .map { ImportedStudentPreview(name: $0.name, listNumber: $0.listNumber) }

            return ImportedGroupPreview(
                name: groupName,
                students: students,
                warnings: groupedWarnings[groupName] ?? []
            )
        }
        .filter { !$0.students.isEmpty }
    }

    static func table(from rows: [[Int: String]]) -> [[String]] {
        rows.map { row in
            guard let maxColumn = row.keys.max() else { return [String]() }
            return (0...maxColumn).map { row[$0] ?? "" }
        }
    }

    private static func groups(from rows: [[String]], fallbackGroupName: String) -> [ImportedGroupPreview] {
        guard !rows.isEmpty else { return [] }

        let analysis = columnAnalysis(in: rows)
        let dataRows = rows.dropFirst(analysis.dataStartIndex)
        var groupedStudents: [String: [ImportedStudentPreview]] = [:]
        var groupedWarnings: [String: [String]] = [:]
        var seenNamesByGroup: [String: Set<String>] = [:]

        for (offset, row) in dataRows.enumerated() {
            let lineNumber = analysis.dataStartIndex + offset + 1
            let groupName = groupName(
                from: row,
                analysis: analysis,
                fallbackGroupName: fallbackGroupName,
                separatesDetectedGroups: true
            )
            let name = composedStudentName(from: row, analysis: analysis)

            guard let name else {
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    groupedWarnings[groupName, default: []].append("Fila \(lineNumber): nombre vacío o no reconocido.")
                }
                continue
            }

            let duplicateKey = normalized(name)
            if seenNamesByGroup[groupName, default: []].contains(duplicateKey) {
                groupedWarnings[groupName, default: []].append("Fila \(lineNumber): alumno duplicado omitido (\(name)).")
                continue
            }

            seenNamesByGroup[groupName, default: []].insert(duplicateKey)
            groupedStudents[groupName, default: []].append(ImportedStudentPreview(name: name, listNumber: nil))
        }

        return groupedStudents.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { groupName in
            ImportedGroupPreview(
                name: groupName,
                students: groupedStudents[groupName] ?? [],
                warnings: groupedWarnings[groupName] ?? []
            )
        }
        .filter { !$0.students.isEmpty }
    }

    private static func columnAnalysis(in rows: [[String]]) -> ColumnAnalysis {
        let headerCandidate = rows.prefix(12).enumerated().map { index, row in
            (index: index, score: headerScore(for: row))
        }
        .max { $0.score < $1.score }

        guard let headerCandidate, headerCandidate.score > 0 else {
            return ColumnAnalysis(dataStartIndex: 0, nameColumn: 0, surnameColumn: 1, fullNameColumn: 0, groupColumn: nil)
        }

        let headers = rows[headerCandidate.index].map(normalized)
        return ColumnAnalysis(
            dataStartIndex: headerCandidate.index + 1,
            nameColumn: firstColumn(in: headers, matching: isNameHeader),
            surnameColumn: firstColumn(in: headers, matching: isSurnameHeader),
            fullNameColumn: firstColumn(in: headers, matching: isFullNameHeader),
            groupColumn: firstColumn(in: headers, matching: isGroupHeader)
        )
    }

    private static func composedStudentName(from row: [String], analysis: ColumnAnalysis) -> String? {
        let name = value(at: analysis.nameColumn, in: row).nonEmptyTrimmed
        let surname = value(at: analysis.surnameColumn, in: row).nonEmptyTrimmed
        let fullName = value(at: analysis.fullNameColumn, in: row).nonEmptyTrimmed

        if let name, let surname, analysis.nameColumn != analysis.surnameColumn {
            return "\(name) \(surname)"
        }

        return fullName ?? name
    }

    private static func delimitedValues(from line: String) -> [String] {
        let delimiter: Character = line.filter { $0 == ";" }.count > line.filter { $0 == "," }.count ? ";" : ","
        var values: [String] = []
        var current = ""
        var isInsideQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if isInsideQuotes {
                    let nextIndex = index + 1
                    if characters.indices.contains(nextIndex), characters[nextIndex] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    isInsideQuotes = true
                }
            } else if character == delimiter, !isInsideQuotes {
                values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }

            index += 1
        }

        values.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    private static func value(at index: Int?, in row: [String]) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index]
    }

    private static func groupName(from row: [String], analysis: ColumnAnalysis, fallbackGroupName: String, separatesDetectedGroups: Bool) -> String {
        if separatesDetectedGroups, let detectedGroup = value(at: analysis.groupColumn, in: row).nonEmptyTrimmed {
            return detectedGroup
        }

        return fallbackGroupName.nonEmptyTrimmed ?? "Grupo importado"
    }

    private static func headerScore(for row: [String]) -> Int {
        row.reduce(0) { score, value in
            let value = normalized(value)
            if isNameHeader(value) || isSurnameHeader(value) || isFullNameHeader(value) || isGroupHeader(value) {
                return score + 1
            }
            return score
        }
    }

    private static func firstColumn(in headers: [String], matching predicate: (String) -> Bool) -> Int? {
        headers.firstIndex(where: predicate)
    }

    private static func isNameHeader(_ value: String) -> Bool {
        ["nombre", "nombres", "name"].contains(value)
    }

    private static func isSurnameHeader(_ value: String) -> Bool {
        ["apellido", "apellidos", "surname", "surnames"].contains(value)
    }

    private static func isFullNameHeader(_ value: String) -> Bool {
        ["alumno", "alumna", "alumnos", "estudiante", "nombre completo", "nombre y apellidos"].contains(value)
    }

    private static func isGroupHeader(_ value: String) -> Bool {
        ["grupo", "clase", "curso", "class", "group"].contains(value)
    }

    static func looksLikeHeader(_ value: String) -> Bool {
        let value = normalized(value)
        return isNameHeader(value) || isSurnameHeader(value) || isFullNameHeader(value) || isGroupHeader(value) || isListNumberHeader(value)
    }

    static func likelyNameColumn(in rows: [[String]]) -> Int? {
        likelyColumn(in: rows, matching: { isNameHeader($0) || isFullNameHeader($0) })
    }

    static func likelyListNumberColumn(in rows: [[String]]) -> Int? {
        likelyColumn(in: rows, matching: isListNumberHeader)
    }

    private static func likelyColumn(in rows: [[String]], matching predicate: (String) -> Bool) -> Int? {
        rows.prefix(12)
            .flatMap { row in row.enumerated().map { (index: $0.offset, value: normalized($0.element)) } }
            .first { predicate($0.value) }?
            .index
    }

    private static func isListNumberHeader(_ value: String) -> Bool {
        ["n", "no", "num", "numero", "nº", "n.", "lista", "numero lista", "numero de lista", "n lista", "orden"].contains(value)
    }

    private static func listNumberText(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeHeader(trimmed) else { return nil }

        if let number = listNumberValue(from: trimmed), number.rounded() == number {
            return String(Int(number))
        }

        return trimmed
    }

    private static func listNumberValue(from value: String) -> Double? {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalizedValue)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    private struct ColumnAnalysis {
        let dataStartIndex: Int
        let nameColumn: Int?
        let surnameColumn: Int?
        let fullNameColumn: Int?
        let groupColumn: Int?
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
