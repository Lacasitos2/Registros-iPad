import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ClassroomStore
    @State private var selectedStudent: Student?
    @State private var showingImport = false
    @State private var exportURL: URL?
    @State private var groupPendingRename: ClassGroup?
    @State private var draftGroupName = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedGroupID) {
                Section("Grupos") {
                    ForEach(store.data.groups) { group in
                        Text(group.name)
                            .tag(group.id)
                            .swipeActions {
                                Button {
                                    groupPendingRename = group
                                    draftGroupName = group.name
                                } label: {
                                    Label("Renombrar", systemImage: "pencil")
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    store.deleteGroup(group)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        store.moveGroups(from: source, to: destination)
                    }
                }
            }
            .navigationTitle("Registros")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(store.data.groups.count < 2)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Importar", systemImage: "square.and.arrow.down")
                    }
                }
            }
        } detail: {
            if let group = store.selectedGroup {
                GroupDashboardView(
                    group: group,
                    selectedStudent: $selectedStudent,
                    exportURL: $exportURL
                )
            } else {
                ContentUnavailableView("Sin grupos", systemImage: "person.3", description: Text("Importa una lista de alumnos para empezar."))
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportGroupView()
        }
        .alert("Renombrar grupo", isPresented: renameGroupAlertIsPresented) {
            TextField("Nombre del grupo", text: $draftGroupName)
                .textInputAutocapitalization(.words)

            Button("Guardar") {
                if let groupPendingRename {
                    store.renameGroup(groupPendingRename.id, to: draftGroupName)
                }
                clearRenameDraft()
            }
            .disabled(draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancelar", role: .cancel) {
                clearRenameDraft()
            }
        } message: {
            Text("El cambio no afecta a los registros guardados.")
        }
        .sheet(item: $selectedStudent) { student in
            if let group = store.selectedGroup {
                StudentDetailView(group: group, student: student)
            }
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportURL = nil
                }
            }
        )) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    private var renameGroupAlertIsPresented: Binding<Bool> {
        Binding(
            get: { groupPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameDraft()
                }
            }
        )
    }

    private func clearRenameDraft() {
        groupPendingRename = nil
        draftGroupName = ""
    }
}

struct GroupDashboardView: View {
    @EnvironmentObject private var store: ClassroomStore
    let group: ClassGroup
    @Binding var selectedStudent: Student?
    @Binding var exportURL: URL?
    @State private var showingDeskMode = false
    @State private var showingStudentManager = false
    @State private var showingHomeworkExport = false
    @State private var showingIncidentsExport = false
    @State private var showingGroupPDFExport = false
    @State private var showingGroupStudentReportsPDFExport = false
    @State private var searchText = ""
    @State private var quickFilter: GroupQuickFilter = .all
    @State private var cardDensity: StudentCardDensity = .complete

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cardDensity.minimumCardWidth), spacing: 12)
        ]
    }

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return group.students.filter { student in
            let matchesSearch = query.isEmpty ||
                student.displayName.localizedCaseInsensitiveContains(query) ||
                student.name.localizedCaseInsensitiveContains(query) ||
                (student.listNumber?.localizedCaseInsensitiveContains(query) ?? false)

            return matchesSearch && quickFilter.matches(store.record(for: student, in: group))
        }
    }

    private var pendingCount: Int {
        group.students.filter { store.record(for: $0, in: group).homework == .unmarked }.count
    }

    private var missingCount: Int {
        group.students.filter { store.record(for: $0, in: group).homework == .missing }.count
    }

    private var incidentsCount: Int {
        group.students.filter { GroupQuickFilter.incidents.matches(store.record(for: $0, in: group)) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if filteredStudents.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text("No hay alumnos que coincidan con la busqueda.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredStudents) { student in
                            StudentCardView(group: group, student: student, density: cardDensity) {
                                selectedStudent = student
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.name)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar alumno")
        .fullScreenCover(isPresented: $showingDeskMode) {
            DeskModeView(group: group)
        }
        .sheet(isPresented: $showingStudentManager) {
            ManageStudentsView(groupID: group.id)
        }
        .sheet(isPresented: $showingHomeworkExport) {
            FilteredGroupExportView(
                group: group,
                title: "Resumen de deberes",
                buttonTitle: "Compartir resumen CSV",
                export: { group, startDate, endDate, _ in
                    store.exportHomeworkSummaryCSV(for: group, startDate: startDate, endDate: endDate)
                }
            )
        }
        .sheet(isPresented: $showingIncidentsExport) {
            FilteredGroupExportView(
                group: group,
                title: "Incidencias y observaciones",
                buttonTitle: "Compartir incidencias CSV",
                export: { group, startDate, endDate, _ in
                    store.exportIncidentsCSV(for: group, startDate: startDate, endDate: endDate)
                }
            )
        }
        .sheet(isPresented: $showingGroupPDFExport) {
            FilteredGroupExportView(
                group: group,
                title: "PDF del grupo",
                buttonTitle: "Compartir PDF del grupo",
                export: store.exportGroupPDF
            )
        }
        .sheet(isPresented: $showingGroupStudentReportsPDFExport) {
            FilteredGroupExportView(
                group: group,
                title: "PDF informes individuales",
                buttonTitle: "Compartir informes PDF",
                export: store.exportGroupStudentReportsPDF
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                DatePicker("Fecha", selection: $store.selectedDate, displayedComponents: .date)
                    .labelsHidden()

                Button {
                    showingStudentManager = true
                } label: {
                    Label("Alumnos", systemImage: "person.3.sequence")
                }

                Button {
                    store.undoLastHomeworkChange()
                } label: {
                    Label("Deshacer", systemImage: "arrow.uturn.backward")
                }
                .disabled(store.lastHomeworkChange == nil)

                Menu {
                    Button {
                        exportURL = store.exportCSV(for: group)
                    } label: {
                        Label("Registros completos", systemImage: "tablecells")
                    }

                    Button {
                        showingHomeworkExport = true
                    } label: {
                        Label("Resumen de deberes", systemImage: "checklist")
                    }

                    Button {
                        showingIncidentsExport = true
                    } label: {
                        Label("Incidencias y observaciones", systemImage: "text.bubble")
                    }

                    Button {
                        showingGroupPDFExport = true
                    } label: {
                        Label("PDF del grupo", systemImage: "doc.richtext")
                    }

                    Button {
                        showingGroupStudentReportsPDFExport = true
                    } label: {
                        Label("PDF informes individuales", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    headerTitle
                    Spacer(minLength: 12)
                    sessionTools
                }

                VStack(alignment: .leading, spacing: 12) {
                    headerTitle
                    sessionTools
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    filterPicker
                    densityPicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    filterPicker
                    densityPicker
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Sesión de clase")
                    .font(.title.bold())

                Text(store.selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Text(studentCountText)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionTools: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sessionMetrics
                HomeworkSummaryView(group: group)
                deskModeButton
            }

            VStack(alignment: .leading, spacing: 10) {
                sessionMetrics
                HStack(spacing: 12) {
                    HomeworkSummaryView(group: group)
                    deskModeButton
                }
            }
        }
    }

    private var sessionMetrics: some View {
        HStack(spacing: 8) {
            SessionMetricPill(title: "Pendientes", value: pendingCount, systemImage: "circle.dotted", color: .secondary)
            SessionMetricPill(title: "No hechos", value: missingCount, systemImage: "xmark.circle", color: .red)
            SessionMetricPill(title: "Incidencias", value: incidentsCount, systemImage: "exclamationmark.triangle", color: .orange)
        }
    }

    private var deskModeButton: some View {
        Button {
            showingDeskMode = true
        } label: {
            Label("Pupitres", systemImage: "figure.walk")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
    }

    private var filterPicker: some View {
        Picker("Filtro", selection: $quickFilter) {
            ForEach(GroupQuickFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.systemImage)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var densityPicker: some View {
        Picker("Vista", selection: $cardDensity) {
            ForEach(StudentCardDensity.allCases) { density in
                Label(density.title, systemImage: density.systemImage)
                    .tag(density)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }

    private var studentCountText: String {
        let total = group.students.count
        let hasSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSearch || quickFilter != .all else {
            return "\(total) alumnos"
        }

        return "\(filteredStudents.count) de \(total) alumnos"
    }
}

struct SessionMetricPill: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text("\(value) \(title.lowercased())")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum GroupQuickFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case missing
    case incidents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todos"
        case .pending: "Pendientes"
        case .missing: "No hechos"
        case .incidents: "Incidencias"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "person.3"
        case .pending: "circle.dotted"
        case .missing: "xmark.circle"
        case .incidents: "exclamationmark.triangle"
        }
    }

    func matches(_ record: StudentRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .pending:
            return record.homework == .unmarked
        case .missing:
            return record.homework == .missing
        case .incidents:
            return record.behavior == .warning ||
                record.behavior == .disruption ||
                !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum StudentCardDensity: String, CaseIterable, Identifiable {
    case complete
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .complete: "Completa"
        case .compact: "Compacta"
        }
    }

    var systemImage: String {
        switch self {
        case .complete: "rectangle.grid.2x2"
        case .compact: "rectangle.grid.3x2"
        }
    }

    var minimumCardWidth: CGFloat {
        switch self {
        case .complete: 220
        case .compact: 180
        }
    }
}

struct FilteredGroupExportView: View {
    @EnvironmentObject private var store: ClassroomStore
    @Environment(\.dismiss) private var dismiss
    let group: ClassGroup
    let title: String
    let buttonTitle: String
    let export: (ClassGroup, Date?, Date?, String) -> URL?

    @State private var historyFilter: StudentHistoryFilter = .trimester
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var exportURL: URL?

    private var dateBounds: (start: Date?, end: Date?) {
        historyFilter.dateBounds(
            referenceDay: store.selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    private var periodDescription: String {
        historyFilter.periodDescription(
            referenceDay: store.selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Periodo") {
                    Picker("Periodo", selection: $historyFilter) {
                        ForEach(StudentHistoryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if historyFilter == .custom {
                        DatePicker("Desde", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("Hasta", selection: $customEndDate, displayedComponents: .date)
                    }
                }

                Section("Archivo") {
                    Button {
                        exportFile()
                    } label: {
                        Label(buttonTitle, systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { isPresented in
                    if !isPresented {
                        exportURL = nil
                    }
                }
            )) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    private func exportFile() {
        exportURL = export(group, dateBounds.start, dateBounds.end, periodDescription)
    }
}

struct ManageStudentsView: View {
    @EnvironmentObject private var store: ClassroomStore
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var newStudentName = ""
    @State private var newStudentListNumber = ""
    @State private var studentPendingDeletion: Student?

    private var group: ClassGroup? {
        store.data.groups.first { $0.id == groupID }
    }

    private var canAddStudent: Bool {
        !newStudentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && group != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nuevo alumno") {
                    HStack {
                        TextField("Nº", text: $newStudentListNumber)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .submitLabel(.next)

                        TextField("Nombre y apellidos", text: $newStudentName)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit(addStudent)

                        Button(action: addStudent) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(!canAddStudent)
                        .accessibilityLabel("Añadir alumno")
                    }
                }

                Section("Lista") {
                    if let group {
                        ForEach(group.students) { student in
                            HStack(spacing: 10) {
                                TextField("Nº", text: Binding(
                                    get: { student.listNumber ?? "" },
                                    set: { store.updateStudentListNumber(student.id, in: groupID, to: $0) }
                                ))
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.center)
                                .frame(width: 64)

                                TextField("Alumno", text: Binding(
                                    get: { student.name },
                                    set: { store.renameStudent(student.id, in: groupID, to: $0) }
                                ))
                                .textInputAutocapitalization(.words)

                                Button(role: .destructive) {
                                    studentPendingDeletion = student
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Quitar \(student.displayName)")
                            }
                        }
                        .onDelete { offsets in
                            store.deleteStudents(at: offsets, in: groupID)
                        }
                        .onMove { source, destination in
                            store.moveStudents(from: source, to: destination, in: groupID)
                        }

                        if group.students.isEmpty {
                            Text("Este grupo todavía no tiene alumnos.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No se ha encontrado el grupo.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Alumnos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(group?.students.isEmpty ?? true)
                }
            }
            .alert("Quitar alumno", isPresented: deleteConfirmationIsPresented, presenting: studentPendingDeletion) { student in
                Button("Quitar", role: .destructive) {
                    store.deleteStudent(student.id, in: groupID)
                    studentPendingDeletion = nil
                }
                Button("Cancelar", role: .cancel) {
                    studentPendingDeletion = nil
                }
            } message: { student in
                Text("Se quitara \(student.displayName) del grupo y tambien sus registros guardados.")
            }
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { studentPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    studentPendingDeletion = nil
                }
            }
        )
    }

    private func addStudent() {
        guard canAddStudent else { return }
        store.addStudent(named: newStudentName, listNumber: newStudentListNumber, to: groupID)
        newStudentName = ""
        newStudentListNumber = ""
    }
}

struct DeskModeView: View {
    @EnvironmentObject private var store: ClassroomStore
    @Environment(\.dismiss) private var dismiss
    let group: ClassGroup
    @State private var index = 0

    private var currentStudent: Student? {
        guard group.students.indices.contains(index) else { return nil }
        return group.students[index]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                progressHeader

                if let student = currentStudent {
                    studentPanel(student)
                } else {
                    ContentUnavailableView("Sin alumnos", systemImage: "person.slash")
                }

                Spacer(minLength: 0)
                navigationControls
            }
            .padding(24)
            .navigationTitle("Pasar por pupitres")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.undoLastHomeworkChange()
                    } label: {
                        Label("Deshacer", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(store.lastHomeworkChange == nil)
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text(group.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(min(index + 1, group.students.count)) de \(group.students.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(min(index + 1, group.students.count)), total: Double(max(group.students.count, 1)))
                .tint(.blue)

            HomeworkSummaryView(group: group)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func studentPanel(_ student: Student) -> some View {
        let record = store.record(for: student, in: group)

        return VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(student.displayName)
                    .font(.system(size: 42, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)

                Text(record.homework.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor(record.homework))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)

            HStack(spacing: 14) {
                deskHomeworkButton(.done, color: .green, icon: "checkmark", student: student)
                deskHomeworkButton(.partial, color: .orange, icon: "slash.circle", student: student)
                deskHomeworkButton(.missing, color: .red, icon: "xmark", student: student)
            }

            Button {
                store.setHomework(.unmarked, for: student, in: group)
            } label: {
                Label("Limpiar marca", systemImage: "eraser")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor(record.homework).opacity(0.45), lineWidth: 2)
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 14) {
            Button {
                index = max(0, index - 1)
            } label: {
                Label("Anterior", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.bordered)
            .disabled(index == 0)

            Button {
                goNext()
            } label: {
                Label(index == group.students.count - 1 ? "Terminar" : "Siguiente", systemImage: index == group.students.count - 1 ? "checkmark" : "chevron.right")
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .disabled(group.students.isEmpty)
        }
    }

    private func deskHomeworkButton(_ status: HomeworkStatus, color: Color, icon: String, student: Student) -> some View {
        Button {
            store.setHomework(status, for: student, in: group)
            goNext()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                Text(status.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 136)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func goNext() {
        if index < group.students.count - 1 {
            index += 1
        } else {
            dismiss()
        }
    }

    private func statusColor(_ status: HomeworkStatus) -> Color {
        switch status {
        case .done: .green
        case .partial: .orange
        case .missing: .red
        case .unmarked: .secondary
        }
    }
}

struct StudentCardView: View {
    @EnvironmentObject private var store: ClassroomStore
    let group: ClassGroup
    let student: Student
    let density: StudentCardDensity
    let openDetail: () -> Void

    var record: StudentRecord {
        store.record(for: student, in: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: openDetail) {
                HStack {
                    Text(student.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                homeworkButton(.done, color: .green, icon: "checkmark")
                homeworkButton(.partial, color: .orange, icon: "slash.circle")
                homeworkButton(.missing, color: .red, icon: "xmark")
            }

            if density == .complete {
                completeQuickActions
            }

            statusLine
        }
        .padding(density == .complete ? 14 : 12)
        .frame(minHeight: density == .complete ? 236 : 142, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor.opacity(0.55), lineWidth: 1.5)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }

    private var completeQuickActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                quickActionButton(
                    label: "Participación",
                    systemImage: "hand.raised",
                    color: .blue,
                    isActive: (record.participation ?? 0) > 0
                ) {
                    store.toggleParticipation(for: student, in: group)
                }

                quickActionButton(
                    label: "Material",
                    systemImage: "backpack",
                    color: .brown,
                    isActive: record.hasMaterial ?? false
                ) {
                    store.toggleMaterial(for: student, in: group)
                }

                boardGradeButton
            }

            HStack(spacing: 8) {
                quickActionButton(
                    label: "Conducta positiva",
                    systemImage: "plus.circle",
                    color: .green,
                    isActive: record.behavior == .positive
                ) {
                    store.toggleBehavior(.positive, for: student, in: group)
                }

                quickActionButton(
                    label: "Aviso",
                    systemImage: "exclamationmark.circle",
                    color: .orange,
                    isActive: record.behavior == .warning
                ) {
                    store.toggleBehavior(.warning, for: student, in: group)
                }

                quickActionButton(
                    label: "Molesta",
                    systemImage: "exclamationmark.triangle",
                    color: .red,
                    isActive: record.behavior == .disruption
                ) {
                    store.toggleBehavior(.disruption, for: student, in: group)
                }
            }
        }
    }

    private var statusLine: some View {
        HStack {
            if let boardGrade = record.boardGrade {
                Label(String(format: "Pizarra %.1f", boardGrade), systemImage: "rectangle.and.pencil.and.ellipsis")
            } else if density == .complete {
                Label("Sin pizarra", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            Spacer(minLength: 8)
            if (record.participation ?? 0) > 0 {
                Label("Participa", systemImage: "hand.raised")
            }
            if record.hasMaterial ?? false {
                Label("Material", systemImage: "backpack")
            }
            if let behavior = record.behavior {
                Text(behavior.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(minHeight: 24)
    }

    private var boardGradeButton: some View {
        Button {
            store.incrementBoardGrade(for: student, in: group)
        } label: {
            if let boardGrade = record.boardGrade {
                Text(String(format: "%.1f", boardGrade).replacingOccurrences(of: ".", with: ","))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "number")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.secondary.opacity(0.11))
                    .foregroundStyle(.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pizarra")
    }

    private var borderColor: Color {
        switch record.homework {
        case .done: .green
        case .partial: .orange
        case .missing: .red
        case .unmarked: .secondary
        }
    }

    private func homeworkButton(_ status: HomeworkStatus, color: Color, icon: String) -> some View {
        Button {
            store.setHomework(status, for: student, in: group)
        } label: {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: density == .complete ? 44 : 40)
                .background(record.homework == status ? color : Color.secondary.opacity(0.13))
                .foregroundStyle(record.homework == status ? .white : color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.title)
    }

    private func quickActionButton(label: String, systemImage: String, color: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isActive ? color : Color.secondary.opacity(0.11))
                .foregroundStyle(isActive ? .white : color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct HomeworkSummaryView: View {
    @EnvironmentObject private var store: ClassroomStore
    let group: ClassGroup

    var body: some View {
        HStack(spacing: 10) {
            summary(.done, color: .green)
            summary(.partial, color: .orange)
            summary(.missing, color: .red)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func summary(_ status: HomeworkStatus, color: Color) -> some View {
        let count = group.students.filter { store.record(for: $0, in: group).homework == status }.count
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StudentDetailView: View {
    @EnvironmentObject private var store: ClassroomStore
    @Environment(\.dismiss) private var dismiss
    let group: ClassGroup
    let student: Student

    @State private var draft: StudentRecord
    @State private var newQuickNote = ""
    @State private var historyFilter: StudentHistoryFilter = .all
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var exportURL: URL?
    private let summaryColumns = [
        GridItem(.adaptive(minimum: 130), spacing: 10)
    ]

    init(group: ClassGroup, student: Student) {
        self.group = group
        self.student = student
        _draft = State(initialValue: StudentRecord(studentID: student.id, groupID: group.id, date: Date(), homework: .unmarked, note: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resumen") {
                    Picker("Periodo", selection: $historyFilter) {
                        ForEach(StudentHistoryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if historyFilter == .custom {
                        DatePicker("Desde", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("Hasta", selection: $customEndDate, displayedComponents: .date)
                    }

                    LazyVGrid(columns: summaryColumns, spacing: 10) {
                        StudentSummaryTile(title: "Deberes", value: homeworkDoneText, systemImage: "checkmark.circle")
                        StudentSummaryTile(title: "Pizarra", value: boardAverageText, systemImage: "number")
                        StudentSummaryTile(title: "Participa", value: "\(participationCount)", systemImage: "hand.raised")
                        StudentSummaryTile(title: "Material", value: "\(materialCount)", systemImage: "backpack")
                        StudentSummaryTile(title: "Positivos", value: "\(behaviorCount(.positive))", systemImage: "plus.circle")
                        StudentSummaryTile(title: "Avisos", value: "\(behaviorCount(.warning) + behaviorCount(.disruption))", systemImage: "exclamationmark.circle")
                    }

                    if let lastObservation {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Última observación", systemImage: "text.bubble")
                                .font(.subheadline.weight(.semibold))
                            Text(lastObservation.note)
                            Text(lastObservation.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Hoy") {
                    Picker("Deberes", selection: $draft.homework) {
                        ForEach(HomeworkStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Pizarra")
                        Spacer()
                        Stepper(
                            draft.boardGrade.map { String(format: "%.1f", $0) } ?? "Sin nota",
                            value: Binding(
                                get: { draft.boardGrade ?? 0 },
                                set: { draft.boardGrade = $0 }
                            ),
                            in: 0...10,
                            step: 0.5
                        )
                    }

                    Toggle("Participación", isOn: Binding(
                        get: { (draft.participation ?? 0) > 0 },
                        set: { draft.participation = $0 ? 1 : nil }
                    ))

                    Toggle("Material", isOn: Binding(
                        get: { draft.hasMaterial ?? false },
                        set: { draft.hasMaterial = $0 ? true : nil }
                    ))

                    Picker("Conducta", selection: Binding(
                        get: { draft.behavior },
                        set: { draft.behavior = $0 }
                    )) {
                        Text("Sin marcar").tag(BehaviorMark?.none)
                        ForEach(BehaviorMark.allCases) { mark in
                            Text(mark.title).tag(Optional(mark))
                        }
                    }

                    TextField("Observación", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Comentarios rápidos") {
                    HStack {
                        TextField("Nuevo comentario rápido", text: $newQuickNote)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(addQuickNoteTemplate)

                        Button(action: addQuickNoteTemplate) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(newQuickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Añadir comentario rápido")
                    }

                    ForEach(store.quickNotes, id: \.self) { note in
                        HStack {
                            Button {
                                appendQuickNote(note)
                            } label: {
                                Text(note)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                store.deleteQuickNoteTemplate(note)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Quitar comentario rápido \(note)")
                        }
                    }
                }

                Section("Historial") {
                    if filteredStudentRecords.isEmpty {
                        ContentUnavailableView(
                            "Sin registros",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("No hay datos de este alumno en el periodo seleccionado.")
                        )
                    } else {
                        ForEach(filteredStudentRecords) { record in
                            StudentHistoryRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle(student.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Menu {
                        Button {
                            exportCurrentFilterAsCSV()
                        } label: {
                            Label("CSV", systemImage: "tablecells")
                        }

                        Button {
                            exportCurrentFilterAsPDF()
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }

                    Button("Guardar") {
                        store.updateRecord(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draft = store.record(for: student, in: group)
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { isPresented in
                    if !isPresented {
                        exportURL = nil
                    }
                }
            )) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    private func addQuickNoteTemplate() {
        store.addQuickNoteTemplate(newQuickNote)
        newQuickNote = ""
    }

    private var studentRecords: [StudentRecord] {
        store.records(for: student)
    }

    private var filteredStudentRecords: [StudentRecord] {
        filteredRecords(from: recordsIncludingDraft)
    }

    private var recordsIncludingDraft: [StudentRecord] {
        var records = studentRecords.filter { $0.id != draft.id }
        if shouldIncludeDraft {
            records.append(draft)
        }
        return records.sorted { $0.date > $1.date }
    }

    private var shouldIncludeDraft: Bool {
        studentRecords.contains { $0.id == draft.id } || recordHasContent(draft)
    }

    private func filteredRecords(from records: [StudentRecord]) -> [StudentRecord] {
        let bounds = historyDateBounds
        return records.filter { record in
            let day = Calendar.current.startOfDay(for: record.date)
            if let start = bounds.start, day < start {
                return false
            }
            if let end = bounds.end, day > end {
                return false
            }
            return true
        }
    }

    private var historyDateBounds: (start: Date?, end: Date?) {
        historyFilter.dateBounds(
            referenceDay: store.selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    private var periodDescription: String {
        historyFilter.periodDescription(
            referenceDay: store.selectedDate,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    private var homeworkDoneText: String {
        let markedRecords = filteredStudentRecords.filter { $0.homework != .unmarked }
        guard !markedRecords.isEmpty else { return "Sin datos" }

        let doneCount = markedRecords.filter { $0.homework == .done }.count
        let percentage = (Double(doneCount) / Double(markedRecords.count) * 100).rounded()
        return "\(Int(percentage))%"
    }

    private var boardAverageText: String {
        let grades = filteredStudentRecords.compactMap(\.boardGrade)
        guard !grades.isEmpty else { return "Sin datos" }

        let average = grades.reduce(0, +) / Double(grades.count)
        return String(format: "%.1f", average).replacingOccurrences(of: ".", with: ",")
    }

    private var participationCount: Int {
        filteredStudentRecords.filter { ($0.participation ?? 0) > 0 }.count
    }

    private var materialCount: Int {
        filteredStudentRecords.filter { $0.hasMaterial ?? false }.count
    }

    private var lastObservation: StudentRecord? {
        filteredStudentRecords.first { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func behaviorCount(_ behavior: BehaviorMark) -> Int {
        filteredStudentRecords.filter { $0.behavior == behavior }.count
    }

    private func exportCurrentFilterAsCSV() {
        if shouldIncludeDraft {
            store.updateRecord(draft)
        }
        exportURL = store.exportCSV(
            for: student,
            in: group,
            records: filteredRecords(from: recordsIncludingDraft)
        )
    }

    private func exportCurrentFilterAsPDF() {
        if shouldIncludeDraft {
            store.updateRecord(draft)
        }
        exportURL = store.exportStudentPDF(
            for: student,
            in: group,
            records: filteredRecords(from: recordsIncludingDraft),
            periodDescription: periodDescription
        )
    }

    private func appendQuickNote(_ note: String) {
        let trimmed = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingNotes = trimmed
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard !existingNotes.contains(note.lowercased()) else { return }

        draft.note = trimmed.isEmpty ? note : "\(trimmed). \(note)"
    }

    private func recordHasContent(_ record: StudentRecord) -> Bool {
        record.homework != .unmarked ||
            record.boardGrade != nil ||
            record.behavior != nil ||
            (record.participation ?? 0) > 0 ||
            (record.hasMaterial ?? false) ||
            !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

private enum StudentHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case last30Days
    case trimester
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todo"
        case .last30Days: "30 dias"
        case .trimester: "Trimestre"
        case .custom: "Rango"
        }
    }

    func dateBounds(referenceDay: Date, customStartDate: Date, customEndDate: Date) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDay)

        switch self {
        case .all:
            return (nil, nil)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: day), day)
        case .trimester:
            return trimesterBounds(containing: day)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let end = calendar.startOfDay(for: max(customStartDate, customEndDate))
            return (start, end)
        }
    }

    func periodDescription(referenceDay: Date, customStartDate: Date, customEndDate: Date) -> String {
        let bounds = dateBounds(
            referenceDay: referenceDay,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )

        switch self {
        case .all:
            return "Todo el historial"
        case .last30Days:
            guard let start = bounds.start, let end = bounds.end else { return "Últimos 30 días" }
            return "Últimos 30 días (\(formattedDate(start)) - \(formattedDate(end)))"
        case .trimester:
            guard let start = bounds.start, let end = bounds.end else { return "Trimestre" }
            return "Trimestre (\(formattedDate(start)) - \(formattedDate(end)))"
        case .custom:
            guard let start = bounds.start, let end = bounds.end else { return "Rango personalizado" }
            return "Rango personalizado (\(formattedDate(start)) - \(formattedDate(end)))"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    }

    private func trimesterBounds(containing date: Date) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return (nil, nil)
        }

        let period: (startYear: Int, startMonth: Int, endYear: Int, endMonth: Int)
        switch month {
        case 9...12:
            period = (year, 9, year, 12)
        case 1...3:
            period = (year, 1, year, 3)
        case 4...6:
            period = (year, 4, year, 6)
        default:
            period = (year, 7, year, 8)
        }

        guard
            let start = calendar.date(from: DateComponents(year: period.startYear, month: period.startMonth, day: 1)),
            let endMonthStart = calendar.date(from: DateComponents(year: period.endYear, month: period.endMonth, day: 1)),
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endMonthStart)
        else {
            return (nil, nil)
        }

        return (start, end)
    }
}

struct StudentHistoryRow: View {
    let record: StudentRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.date, style: .date)
                    .font(.headline)
                Spacer()
                Text(record.homework.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(homeworkColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(homeworkColor)
            }

            FlowLayout(spacing: 6) {
                if let boardGrade = record.boardGrade {
                    HistoryChip(text: String(format: "Pizarra %.1f", boardGrade).replacingOccurrences(of: ".", with: ","), systemImage: "number")
                }
                if (record.participation ?? 0) > 0 {
                    HistoryChip(text: "Participa", systemImage: "hand.raised")
                }
                if record.hasMaterial ?? false {
                    HistoryChip(text: "Material", systemImage: "backpack")
                }
                if let behavior = record.behavior {
                    HistoryChip(text: behavior.title, systemImage: behaviorIcon(for: behavior))
                }
            }

            if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    private var homeworkColor: Color {
        switch record.homework {
        case .done: .green
        case .partial: .orange
        case .missing: .red
        case .unmarked: .secondary
        }
    }

    private func behaviorIcon(for behavior: BehaviorMark) -> String {
        switch behavior {
        case .positive: "plus.circle"
        case .warning: "exclamationmark.circle"
        case .disruption: "exclamationmark.triangle"
        }
    }
}

struct HistoryChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.secondary)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowRow.Item] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let item = FlowRow.Item(subview: subview, size: size)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if nextWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [item]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(item)
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct FlowRow {
    struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }

    let items: [Item]
    let width: CGFloat
    let height: CGFloat
}

struct StudentSummaryTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ImportGroupView: View {
    @EnvironmentObject private var store: ClassroomStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var csvText = ""
    @State private var showingFileImporter = false
    @State private var importError: String?
    @State private var spreadsheetRows: [[String]] = []
    @State private var spreadsheetSheets: [ImportedSpreadsheetSheet] = []
    @State private var selectedSpreadsheetSheetIndex = 0
    @State private var selectedListNumberColumn: Int?
    @State private var selectedNameColumn: Int?
    @State private var separatesDetectedGroups = false

    private var importedGroups: [ImportedGroupPreview] {
        if !spreadsheetRows.isEmpty, let selectedNameColumn {
            return StudentImportParser.groups(
                from: spreadsheetRows,
                fallbackGroupName: groupName,
                nameColumn: selectedNameColumn,
                listNumberColumn: selectedListNumberColumn,
                separatesDetectedGroups: separatesDetectedGroups
            )
        }

        return ClassroomStore.importedGroups(from: csvText, fallbackGroupName: groupName)
    }

    private var detectedStudentCount: Int {
        importedGroups.reduce(0) { $0 + $1.students.count }
    }

    private var spreadsheetColumnIndexes: [Int] {
        guard let maxColumn = spreadsheetRows.map(\.count).max(), maxColumn > 0 else { return [] }
        return Array(0..<maxColumn)
    }

    private var canCreate: Bool {
        if spreadsheetRows.isEmpty {
            return !importedGroups.isEmpty
        }

        return selectedListNumberColumn != nil &&
            selectedNameColumn != nil &&
            selectedListNumberColumn != selectedNameColumn &&
            !importedGroups.isEmpty
    }

    private var validationMessages: [String] {
        if spreadsheetRows.isEmpty {
            return importedGroups.isEmpty && !csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ["No se han detectado alumnos. Revisa que la primera columna tenga nombres o que exista una cabecera reconocible."]
                : []
        }

        var messages: [String] = []
        if spreadsheetColumnIndexes.isEmpty {
            messages.append("La hoja seleccionada esta vacia.")
        }
        if selectedListNumberColumn == nil {
            messages.append("Selecciona la columna del numero de lista.")
        }
        if selectedNameColumn == nil {
            messages.append("Selecciona la columna del nombre.")
        }
        if selectedListNumberColumn != nil, selectedListNumberColumn == selectedNameColumn {
            messages.append("El numero de lista y el nombre deben estar en columnas distintas.")
        }
        if selectedNameColumn != nil, importedGroups.isEmpty {
            messages.append("No se han detectado alumnos con la columna de nombre elegida.")
        }
        return messages
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Grupo") {
                    TextField("Nombre por defecto", text: $groupName)
                }

                Section("Archivo") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Seleccionar Excel o CSV", systemImage: "doc.badge.plus")
                    }

                    if let importError {
                        Text(importError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Alumnos") {
                    if spreadsheetRows.isEmpty {
                        TextEditor(text: $csvText)
                            .frame(minHeight: 220)
                            .font(.body.monospaced())
                        Text("Pega una lista o selecciona un Excel/CSV desde Archivos. Se detectan columnas como nombre, apellidos y grupo; si hay una columna de grupo, se crearán varios grupos.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        if spreadsheetSheets.count > 1 {
                            Picker("Hoja", selection: Binding(
                                get: { selectedSpreadsheetSheetIndex },
                                set: { selectSpreadsheetSheet(at: $0) }
                            )) {
                                ForEach(spreadsheetSheets.indices, id: \.self) { index in
                                    Text(spreadsheetSheets[index].name).tag(index)
                                }
                            }
                        }

                        Picker("Número de lista", selection: Binding(
                            get: { selectedListNumberColumn ?? -1 },
                            set: { selectedListNumberColumn = $0 == -1 ? nil : $0 }
                        )) {
                            Text("Seleccionar").tag(-1)
                            ForEach(spreadsheetColumnIndexes, id: \.self) { index in
                                Text(columnLabel(for: index)).tag(index)
                            }
                        }

                        Picker("Nombre", selection: Binding(
                            get: { selectedNameColumn ?? -1 },
                            set: { selectedNameColumn = $0 == -1 ? nil : $0 }
                        )) {
                            Text("Seleccionar").tag(-1)
                            ForEach(spreadsheetColumnIndexes, id: \.self) { index in
                                Text(columnLabel(for: index)).tag(index)
                            }
                        }

                        Picker("Grupos detectados", selection: $separatesDetectedGroups) {
                            Text("Unir en un grupo").tag(false)
                            Text("Separar por clase").tag(true)
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(spreadsheetRows.prefix(5).indices, id: \.self) { rowIndex in
                                Text(rowPreview(spreadsheetRows[rowIndex]))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Previsualización") {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if importedGroups.isEmpty {
                        Text("No hay alumnos detectados todavía.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(detectedStudentCount) alumnos detectados")
                            .font(.headline)

                        ForEach(importedGroups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(group.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(group.students.count)")
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(group.students.prefix(4)) { student in
                                    if let listNumber = student.listNumber {
                                        Text("\(listNumber). \(student.name)")
                                    } else {
                                        Text(student.name)
                                    }
                                }

                                if group.students.count > 4 {
                                    Text("Y \(group.students.count - 4) más")
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(group.warnings.prefix(3), id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Importar grupo")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.spreadsheet, .commaSeparatedText, .plainText, .text, .xlsx],
                allowsMultipleSelection: false
            ) { result in
                importFile(result)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        store.addGroups(importedGroups)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if url.pathExtension.lowercased() == "xlsx" {
                let fallbackName = groupName.isEmpty ? url.deletingPathExtension().lastPathComponent : groupName
                let sheets = try XLSXImporter.sheets(from: url)
                spreadsheetSheets = try sheets.map { sheet in
                    ImportedSpreadsheetSheet(name: sheet.name, rows: try XLSXImporter.table(from: url, sheet: sheet))
                }
                selectedSpreadsheetSheetIndex = 0
                spreadsheetRows = spreadsheetSheets.first?.rows ?? []
                updateSuggestedColumns()
                separatesDetectedGroups = false
                csvText = ""
                groupName = fallbackName
            } else {
                csvText = try String(contentsOf: url, encoding: .utf8)
                spreadsheetRows = []
                spreadsheetSheets = []
                selectedSpreadsheetSheetIndex = 0
                selectedListNumberColumn = nil
                selectedNameColumn = nil
                separatesDetectedGroups = true
            }
            importError = nil

            if groupName.isEmpty {
                groupName = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            importError = "No se pudo leer el archivo seleccionado."
        }
    }

    private func selectSpreadsheetSheet(at index: Int) {
        guard spreadsheetSheets.indices.contains(index) else { return }
        selectedSpreadsheetSheetIndex = index
        spreadsheetRows = spreadsheetSheets[index].rows
        updateSuggestedColumns()
    }

    private func updateSuggestedColumns() {
        selectedListNumberColumn = StudentImportParser.likelyListNumberColumn(in: spreadsheetRows)
        selectedNameColumn = StudentImportParser.likelyNameColumn(in: spreadsheetRows)
    }

    private func columnLabel(for index: Int) -> String {
        let letter = spreadsheetColumnName(for: index)
        let sample = spreadsheetRows
            .prefix(8)
            .compactMap { row in
                guard row.indices.contains(index) else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            .prefix(2)
            .joined(separator: " / ")

        return sample.isEmpty ? letter : "\(letter) - \(sample)"
    }

    private func spreadsheetColumnName(for zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex
        var name = ""

        repeat {
            let remainder = index % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            index = (index / 26) - 1
        } while index >= 0

        return name
    }

    private func rowPreview(_ row: [String]) -> String {
        spreadsheetColumnIndexes.prefix(8).map { index in
            let value = row.indices.contains(index) ? row[index] : ""
            return "\(spreadsheetColumnName(for: index)):\(value)"
        }
        .joined(separator: "  ")
    }
}

private struct ImportedSpreadsheetSheet {
    var name: String
    var rows: [[String]]
}

private extension UTType {
    static let xlsx = UTType(filenameExtension: "xlsx")!
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
