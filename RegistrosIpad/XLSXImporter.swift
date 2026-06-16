import Foundation
import ZIPFoundation

enum XLSXImportError: Error {
    case missingWorksheet
    case unreadableWorksheet
}

struct XLSXSheet: Identifiable, Hashable {
    var name: String
    var path: String

    var id: String { path }
}

struct XLSXImporter {
    static func sheets(from url: URL) throws -> [XLSXSheet] {
        let archive = try Archive(url: url, accessMode: .read)
        return try sheets(from: archive)
    }

    static func table(from url: URL) throws -> [[String]] {
        let archive = try Archive(url: url, accessMode: .read)

        let sharedStrings = try sharedStrings(from: archive)
        let sheet = try sheets(from: archive).first
        let rows = try worksheetRows(from: archive, sharedStrings: sharedStrings, sheetPath: sheet?.path)

        return StudentImportParser.table(from: rows)
    }

    static func table(from url: URL, sheet: XLSXSheet) throws -> [[String]] {
        let archive = try Archive(url: url, accessMode: .read)

        let sharedStrings = try sharedStrings(from: archive)
        let rows = try worksheetRows(from: archive, sharedStrings: sharedStrings, sheetPath: sheet.path)

        return StudentImportParser.table(from: rows)
    }

    static func importedGroups(from url: URL, fallbackGroupName: String) throws -> [ImportedGroupPreview] {
        let archive = try Archive(url: url, accessMode: .read)

        let sharedStrings = try sharedStrings(from: archive)
        let sheet = try sheets(from: archive).first
        let rows = try worksheetRows(from: archive, sharedStrings: sharedStrings, sheetPath: sheet?.path)

        return StudentImportParser.groups(from: rows, fallbackGroupName: fallbackGroupName)
    }

    static func studentNames(from url: URL) throws -> [String] {
        try importedGroups(from: url, fallbackGroupName: "Grupo importado")
            .flatMap(\.students)
            .map(\.name)
    }

    private static func sharedStrings(from archive: Archive) throws -> [String] {
        guard let entry = archive["xl/sharedStrings.xml"] else {
            return []
        }

        let data = try data(for: entry, in: archive)
        let parser = XMLParser(data: data)
        let delegate = SharedStringsParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.values
    }

    private static func sheets(from archive: Archive) throws -> [XLSXSheet] {
        guard let workbookEntry = archive["xl/workbook.xml"],
              let relationshipsEntry = archive["xl/_rels/workbook.xml.rels"] else {
            return [XLSXSheet(name: "Hoja 1", path: "xl/worksheets/sheet1.xml")]
        }

        let workbookData = try data(for: workbookEntry, in: archive)
        let workbookParser = XMLParser(data: workbookData)
        let workbookDelegate = WorkbookParserDelegate()
        workbookParser.delegate = workbookDelegate
        workbookParser.parse()

        let relationshipsData = try data(for: relationshipsEntry, in: archive)
        let relationshipsParser = XMLParser(data: relationshipsData)
        let relationshipsDelegate = WorkbookRelationshipsParserDelegate()
        relationshipsParser.delegate = relationshipsDelegate
        relationshipsParser.parse()

        let sheets = workbookDelegate.sheets.compactMap { sheet -> XLSXSheet? in
            guard let target = relationshipsDelegate.targetsByID[sheet.relationshipID] else {
                return nil
            }

            return XLSXSheet(name: sheet.name, path: normalizedSheetPath(from: target))
        }

        return sheets.isEmpty ? [XLSXSheet(name: "Hoja 1", path: "xl/worksheets/sheet1.xml")] : sheets
    }

    private static func worksheetRows(from archive: Archive, sharedStrings: [String], sheetPath: String?) throws -> [[Int: String]] {
        let path = sheetPath ?? "xl/worksheets/sheet1.xml"
        guard let entry = archive[path] else {
            throw XLSXImportError.missingWorksheet
        }

        let data = try data(for: entry, in: archive)
        let parser = XMLParser(data: data)
        let delegate = WorksheetParserDelegate(sharedStrings: sharedStrings)
        parser.delegate = delegate

        guard parser.parse() else {
            throw XLSXImportError.unreadableWorksheet
        }

        return delegate.rows
    }

    private static func normalizedSheetPath(from target: String) -> String {
        let trimmedTarget = target.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedTarget.hasPrefix("xl/") {
            return trimmedTarget
        }
        return "xl/\(trimmedTarget)"
    }

    private static func data(for entry: Entry, in archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }
}

private final class WorkbookParserDelegate: NSObject, XMLParserDelegate {
    struct WorkbookSheet {
        var name: String
        var relationshipID: String
    }

    private(set) var sheets: [WorkbookSheet] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "sheet",
              let name = attributeDict["name"],
              let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] else {
            return
        }

        sheets.append(WorkbookSheet(name: name, relationshipID: relationshipID))
    }
}

private final class WorkbookRelationshipsParserDelegate: NSObject, XMLParserDelegate {
    private(set) var targetsByID: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship",
              let id = attributeDict["Id"],
              let target = attributeDict["Target"] else {
            return
        }

        targetsByID[id] = target
    }
}

private final class SharedStringsParserDelegate: NSObject, XMLParserDelegate {
    private var valuesByStringItem: [String] = []
    private var currentText = ""
    private var isInsideStringItem = false
    private var isInsideText = false

    var values: [String] { valuesByStringItem }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" {
            isInsideStringItem = true
            currentText = ""
        } else if isInsideStringItem && elementName == "t" {
            isInsideText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" {
            isInsideText = false
        } else if elementName == "si" {
            valuesByStringItem.append(currentText)
            isInsideStringItem = false
            currentText = ""
        }
    }
}

private final class WorksheetParserDelegate: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var currentRowIndex: Int?
    private var currentColumnIndex: Int?
    private var currentCellType: String?
    private var currentValue = ""
    private var isInsideValue = false

    private(set) var rows: [[Int: String]] = []

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRowIndex = nil
        } else if elementName == "c" {
            currentCellType = attributeDict["t"]
            currentValue = ""

            if let reference = attributeDict["r"] {
                currentRowIndex = Self.rowIndex(from: reference)
                currentColumnIndex = Self.columnIndex(from: reference)
            }
        } else if elementName == "v" || elementName == "t" {
            isInsideValue = true
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue {
            currentValue += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" {
            isInsideValue = false
        } else if elementName == "c" {
            guard let rowIndex = currentRowIndex, let columnIndex = currentColumnIndex else {
                return
            }

            let value = resolvedValue(currentValue, type: currentCellType)
            ensureRow(rowIndex)
            rows[rowIndex][columnIndex] = value

            currentCellType = nil
            currentColumnIndex = nil
            currentValue = ""
        }
    }

    private func resolvedValue(_ value: String, type: String?) -> String {
        if type == "s", let index = Int(value), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }

        return value
    }

    private func ensureRow(_ index: Int) {
        while rows.count <= index {
            rows.append([:])
        }
    }

    private static func rowIndex(from reference: String) -> Int? {
        let digits = reference.filter(\.isNumber)
        guard let oneBasedIndex = Int(digits), oneBasedIndex > 0 else {
            return nil
        }
        return oneBasedIndex - 1
    }

    private static func columnIndex(from reference: String) -> Int? {
        let letters = reference
            .uppercased()
            .prefix { $0.isLetter }

        guard !letters.isEmpty else {
            return nil
        }

        return letters.reduce(0) { result, character in
            let value = Int(character.asciiValue ?? 64) - 64
            return result * 26 + value
        } - 1
    }
}
