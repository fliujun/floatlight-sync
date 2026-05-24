import Foundation
import EventKit

// MARK: - Native Messaging I/O

/// Read a message from stdin (4-byte little-endian length prefix + JSON)
func readMessage() -> [String: Any]? {
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    guard fread(&lengthBytes, 1, 4, stdin) == 4 else { return nil }
    let length = Int(lengthBytes[0]) | Int(lengthBytes[1]) << 8 | Int(lengthBytes[2]) << 16 | Int(lengthBytes[3]) << 24
    guard length > 0, length < 10_000_000 else { return nil }

    var buffer = [UInt8](repeating: 0, count: length)
    guard fread(&buffer, 1, length, stdin) == length else { return nil }
    let data = Data(buffer)
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

/// Write a message to stdout (4-byte little-endian length prefix + JSON)
func writeMessage(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
    var length = UInt32(data.count)
    let lengthBytes = withUnsafeBytes(of: &length) { Array($0) }
    fwrite(lengthBytes, 1, 4, stdout)
    fwrite([UInt8](data), 1, data.count, stdout)
    fflush(stdout)
}

/// Send a success response
func sendSuccess(id: String?, data: [String: Any]) {
    writeMessage(["id": id as Any, "success": true, "data": data])
}

/// Send an error response
func sendError(id: String?, code: String, message: String) {
    writeMessage(["id": id as Any, "success": false, "error": ["code": code, "message": message]])
}

/// Send a push event (no request id)
func sendEvent(event: String, data: [String: Any]) {
    writeMessage(["id": NSNull(), "event": event, "data": data])
}

// MARK: - EventKit Manager

class ReminderManager {
    let store = EKEventStore()
    var floatlightListId: String?
    private var lastKnownState: [String: Date] = [:] // ekId -> modificationDate

    /// Request access to Reminders
    func requestAccess() -> Bool {
        var granted = false
        let semaphore = DispatchSemaphore(value: 0)

        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { g, _ in
                granted = g
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { g, _ in
                granted = g
                semaphore.signal()
            }
        }
        semaphore.wait()
        return granted
    }

    /// Find or create the "浮光" list
    func ensureList(title: String) -> (id: String, created: Bool)? {
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == title }) {
            floatlightListId = existing.calendarIdentifier
            return (existing.calendarIdentifier, false)
        }
        // Create new list
        let newCal = EKCalendar(for: .reminder, eventStore: store)
        newCal.title = title
        // Use default reminder source
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            return nil
        }
        newCal.source = source
        do {
            try store.saveCalendar(newCal, commit: true)
            floatlightListId = newCal.calendarIdentifier
            return (newCal.calendarIdentifier, true)
        } catch {
            return nil
        }
    }

    /// Get all reminders in a calendar
    func getReminders(listId: String, includeCompleted: Bool) -> [[String: Any]] {
        guard let calendar = store.calendar(withIdentifier: listId) else { return [] }
        let predicate: NSPredicate
        if includeCompleted {
            predicate = store.predicateForReminders(in: [calendar])
        } else {
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        }

        var results: [EKReminder] = []
        let semaphore = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: predicate) { reminders in
            results = reminders ?? []
            semaphore.signal()
        }
        semaphore.wait()

        return results.map { reminderToDict($0) }
    }

    /// Convert EKReminder to dictionary
    func reminderToDict(_ r: EKReminder) -> [String: Any] {
        var dict: [String: Any] = [
            "ekId": r.calendarItemIdentifier,
            "title": r.title ?? "",
            "isCompleted": r.isCompleted,
            "flagged": r.isFlagged,
            "notes": r.notes ?? "",
            "creationDate": r.creationDate?.iso8601String ?? "",
            "modificationDate": r.lastModifiedDate?.iso8601String ?? ""
        ]

        if let dueDate = r.dueDateComponents?.date {
            dict["dueDate"] = dueDate.iso8601String
        } else {
            dict["dueDate"] = NSNull()
        }

        // Section support (macOS 14+)
        if #available(macOS 14.0, *) {
            // Note: EKReminderSection API may not be directly available in all SDK versions
            // We store section info if available via alternative means
        }

        return dict
    }

    /// Create a reminder
    func createReminder(listId: String, title: String, notes: String?, dueDate: String?, flagged: Bool, sectionId: String?) -> [String: Any]? {
        guard let calendar = store.calendar(withIdentifier: listId) else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.isFlagged = flagged

        if let dueDateStr = dueDate, let date = Date.fromISO8601(dueDateStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }

        do {
            try store.save(reminder, commit: true)
            return [
                "ekId": reminder.calendarItemIdentifier,
                "creationDate": reminder.creationDate?.iso8601String ?? "",
                "modificationDate": reminder.lastModifiedDate?.iso8601String ?? ""
            ]
        } catch {
            return nil
        }
    }

    /// Update a reminder
    func updateReminder(ekId: String, fields: [String: Any]) -> String? {
        guard let reminder = fetchReminderById(ekId) else { return nil }

        if let title = fields["title"] as? String { reminder.title = title }
        if let completed = fields["isCompleted"] as? Bool { reminder.isCompleted = completed }
        if let flagged = fields["flagged"] as? Bool { reminder.isFlagged = flagged }
        if let notes = fields["notes"] as? String { reminder.notes = notes }

        if let dueDate = fields["dueDate"] as? String {
            if let date = Date.fromISO8601(dueDate) {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
        } else if fields["dueDate"] is NSNull {
            reminder.dueDateComponents = nil
        }

        do {
            try store.save(reminder, commit: true)
            return reminder.lastModifiedDate?.iso8601String
        } catch {
            return nil
        }
    }

    /// Delete a reminder
    func deleteReminder(ekId: String) -> Bool {
        guard let reminder = fetchReminderById(ekId) else { return false }
        do {
            try store.remove(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// Fetch a single reminder by identifier
    private func fetchReminderById(_ ekId: String) -> EKReminder? {
        return store.calendarItem(withIdentifier: ekId) as? EKReminder
    }

    /// Batch sync for initial merge
    func batchSync(listId: String, pluginReminders: [[String: Any]]) -> [[String: Any]] {
        let ekReminders = getReminders(listId: listId, includeCompleted: true)
        var mappings: [[String: Any]] = []
        var matchedEkIds = Set<String>()

        for pluginItem in pluginReminders {
            let pluginId = pluginItem["pluginId"] as? String ?? ""
            let pluginTitle = pluginItem["title"] as? String ?? ""
            let pluginSection = pluginItem["sectionTitle"] as? String ?? ""
            let pluginModified = pluginItem["modifiedAt"] as? Double ?? 0

            // Try to match by title (+ section if available)
            var matched = false
            for ekItem in ekReminders {
                let ekId = ekItem["ekId"] as? String ?? ""
                if matchedEkIds.contains(ekId) { continue }
                let ekTitle = ekItem["title"] as? String ?? ""
                if ekTitle == pluginTitle {
                    // Matched! Resolve conflict by modification time
                    matchedEkIds.insert(ekId)
                    let ekModStr = ekItem["modificationDate"] as? String ?? ""
                    let ekModDate = Date.fromISO8601(ekModStr)?.timeIntervalSince1970 ?? 0
                    let pluginModSec = pluginModified / 1000.0

                    if pluginModSec > ekModDate {
                        // Plugin is newer, update EK
                        let _ = updateReminder(ekId: ekId, fields: pluginItem)
                        mappings.append(["pluginId": pluginId, "ekId": ekId, "action": "matched", "winner": "plugin"])
                    } else {
                        // EK is newer (or same), plugin should pull
                        mappings.append(["pluginId": pluginId, "ekId": ekId, "action": "matched", "winner": "apple", "reminder": ekItem])
                    }
                    matched = true
                    break
                }
            }

            if !matched {
                // Plugin item not in EK → push to EK
                let result = createReminder(
                    listId: listId,
                    title: pluginTitle,
                    notes: pluginItem["notes"] as? String,
                    dueDate: pluginItem["dueDate"] as? String,
                    flagged: pluginItem["flagged"] as? Bool ?? false,
                    sectionId: nil
                )
                if let r = result {
                    mappings.append(["pluginId": pluginId, "ekId": r["ekId"] as Any, "action": "pushed"])
                }
            }
        }

        // EK items not matched → need to pull to plugin
        for ekItem in ekReminders {
            let ekId = ekItem["ekId"] as? String ?? ""
            if !matchedEkIds.contains(ekId) {
                mappings.append(["pluginId": NSNull(), "ekId": ekId, "action": "pulled", "reminder": ekItem])
            }
        }

        return mappings
    }

    // MARK: - Change Monitoring

    /// Snapshot current state for change detection
    func snapshotState(listId: String) {
        let reminders = getReminders(listId: listId, includeCompleted: true)
        lastKnownState.removeAll()
        for r in reminders {
            if let ekId = r["ekId"] as? String, let modStr = r["modificationDate"] as? String, let date = Date.fromISO8601(modStr) {
                lastKnownState[ekId] = date
            }
        }
    }

    /// Detect changes since last snapshot
    func detectChanges(listId: String) -> [[String: Any]] {
        let currentReminders = getReminders(listId: listId, includeCompleted: true)
        var changes: [[String: Any]] = []
        var currentIds = Set<String>()

        for r in currentReminders {
            guard let ekId = r["ekId"] as? String else { continue }
            currentIds.insert(ekId)
            let modStr = r["modificationDate"] as? String ?? ""
            let modDate = Date.fromISO8601(modStr)

            if let lastMod = lastKnownState[ekId] {
                if let current = modDate, current > lastMod {
                    changes.append(["ekId": ekId, "type": "modified", "reminder": r])
                }
            } else {
                changes.append(["ekId": ekId, "type": "added", "reminder": r])
            }
        }

        // Detect deletions
        for ekId in lastKnownState.keys {
            if !currentIds.contains(ekId) {
                changes.append(["ekId": ekId, "type": "deleted"])
            }
        }

        // Update snapshot
        snapshotState(listId: listId)
        return changes
    }
}

// MARK: - Date Helpers

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }

    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }()
    }
}

// MARK: - Message Handler

let manager = ReminderManager()

func handleMessage(_ msg: [String: Any]) {
    let id = msg["id"] as? String
    let action = msg["action"] as? String ?? ""
    let payload = msg["payload"] as? [String: Any] ?? [:]

    switch action {
    case "ping":
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        sendSuccess(id: id, data: ["version": "1.0.0", "os": "macOS \(osVersion)"])

    case "get_lists":
        let calendars = manager.store.calendars(for: .reminder)
        let lists = calendars.map { cal -> [String: Any] in
            ["id": cal.calendarIdentifier, "title": cal.title]
        }
        sendSuccess(id: id, data: ["lists": lists])

    case "ensure_list":
        let title = payload["title"] as? String ?? "浮光"
        if let result = manager.ensureList(title: title) {
            sendSuccess(id: id, data: ["listId": result.id, "created": result.created])
        } else {
            sendError(id: id, code: "INTERNAL_ERROR", message: "无法创建提醒事项列表")
        }

    case "ensure_section":
        // Section creation requires macOS 14+, simplified for now
        if #available(macOS 14.0, *) {
            sendSuccess(id: id, data: ["sectionId": "unsupported_yet", "created": false])
        } else {
            sendError(id: id, code: "SECTION_NOT_SUPPORTED", message: "系统版本不支持分区功能，需要 macOS 14+")
        }

    case "get_reminders":
        let listId = payload["listId"] as? String ?? ""
        let includeCompleted = payload["includeCompleted"] as? Bool ?? true
        let reminders = manager.getReminders(listId: listId, includeCompleted: includeCompleted)
        sendSuccess(id: id, data: ["reminders": reminders])

    case "create_reminder":
        let listId = payload["listId"] as? String ?? ""
        let title = payload["title"] as? String ?? ""
        let notes = payload["notes"] as? String
        let dueDate = payload["dueDate"] as? String
        let flagged = payload["flagged"] as? Bool ?? false
        let sectionId = payload["sectionId"] as? String

        if let result = manager.createReminder(listId: listId, title: title, notes: notes, dueDate: dueDate, flagged: flagged, sectionId: sectionId) {
            sendSuccess(id: id, data: result)
        } else {
            sendError(id: id, code: "INTERNAL_ERROR", message: "创建提醒失败")
        }

    case "update_reminder":
        let ekId = payload["ekId"] as? String ?? ""
        var fields = payload
        fields.removeValue(forKey: "ekId")
        if let modDate = manager.updateReminder(ekId: ekId, fields: fields) {
            sendSuccess(id: id, data: ["modificationDate": modDate])
        } else {
            sendError(id: id, code: "REMINDER_NOT_FOUND", message: "提醒不存在或更新失败")
        }

    case "delete_reminder":
        let ekId = payload["ekId"] as? String ?? ""
        if manager.deleteReminder(ekId: ekId) {
            sendSuccess(id: id, data: [:])
        } else {
            sendError(id: id, code: "REMINDER_NOT_FOUND", message: "提醒不存在或删除失败")
        }

    case "batch_sync":
        let listId = payload["listId"] as? String ?? ""
        let pluginReminders = payload["reminders"] as? [[String: Any]] ?? []
        let mappings = manager.batchSync(listId: listId, pluginReminders: pluginReminders)
        sendSuccess(id: id, data: ["mappings": mappings])

    case "start_watching":
        let listId = payload["listId"] as? String ?? ""
        manager.snapshotState(listId: listId)
        sendSuccess(id: id, data: ["watching": true])

    default:
        sendError(id: id, code: "UNKNOWN_ACTION", message: "未知操作: \(action)")
    }
}

// MARK: - Main Entry

// Request access
guard manager.requestAccess() else {
    sendError(id: nil, code: "ACCESS_DENIED", message: "用户未授权访问提醒事项。请在系统设置 → 隐私与安全 → 提醒事项中允许访问。")
    exit(1)
}

// Set up change notification monitoring
let notificationCenter = NotificationCenter.default
notificationCenter.addObserver(forName: .EKEventStoreChanged, object: manager.store, queue: .main) { _ in
    guard let listId = manager.floatlightListId else { return }
    let changes = manager.detectChanges(listId: listId)
    if !changes.isEmpty {
        sendEvent(event: "reminders_changed", data: ["listId": listId, "changes": changes])
    }
}

// Message loop (stdin reading on background thread, RunLoop for notifications)
let readQueue = DispatchQueue(label: "me.vkr.fl.stdin")
readQueue.async {
    while let msg = readMessage() {
        DispatchQueue.main.async {
            handleMessage(msg)
        }
    }
    // stdin closed, exit
    exit(0)
}

// Keep RunLoop alive for notifications
RunLoop.main.run()
