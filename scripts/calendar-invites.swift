#!/usr/bin/env swift

import EventKit
import Foundation

// MARK: - Main CLI

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)
var authGranted = false

// Request calendar access
func requestAccess() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)

    switch status {
    case .authorized, .fullAccess:
        return true
    case .notDetermined:
        store.requestFullAccessToEvents { granted, error in
            authGranted = granted
            if let error = error {
                fputs("Error requesting calendar access: \(error.localizedDescription)\n", stderr)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
        return authGranted
    case .denied, .restricted, .writeOnly:
        fputs("Error: Calendar access denied. Please enable in System Settings > Privacy & Security > Calendars\n", stderr)
        return false
    @unknown default:
        fputs("Error: Unknown authorization status\n", stderr)
        return false
    }
}

// MARK: - Data Structures

struct Invitation: Codable {
    let eventId: String
    let title: String
    let start: String
    let end: String
    let calendar: String
    let organizer: Organizer?
    let myStatus: String
    let location: String?
    let notes: String?
    let attendees: [Attendee]

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case title, start, end, calendar, organizer
        case myStatus = "my_status"
        case location, notes, attendees
    }
}

struct Organizer: Codable {
    let name: String?
    let email: String?
}

struct Attendee: Codable {
    let name: String?
    let email: String?
    let status: String
}

struct InvitationList: Codable {
    let invitations: [Invitation]
    let count: Int
}

struct EventDetail: Codable {
    let eventId: String
    let title: String
    let start: String
    let end: String
    let calendar: String
    let organizer: Organizer?
    let myStatus: String
    let location: String?
    let notes: String?
    let attendees: [Attendee]
    let url: String?
    let recurrence: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case title, start, end, calendar, organizer
        case myStatus = "my_status"
        case location, notes, attendees, url, recurrence
    }
}

// MARK: - Helpers

let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func statusString(_ status: EKParticipantStatus) -> String {
    switch status {
    case .unknown: return "unknown"
    case .pending: return "pending"
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .delegated: return "delegated"
    case .completed: return "completed"
    case .inProcess: return "in_process"
    @unknown default: return "unknown"
    }
}

func findCurrentUserAttendee(in event: EKEvent) -> EKParticipant? {
    return event.attendees?.first { $0.isCurrentUser }
}

func isPendingInvitation(_ event: EKEvent) -> Bool {
    guard let attendee = findCurrentUserAttendee(in: event) else { return false }
    return attendee.participantStatus == .pending
}

func eventToInvitation(_ event: EKEvent) -> Invitation {
    let currentUser = findCurrentUserAttendee(in: event)
    let status = currentUser.map { statusString($0.participantStatus) } ?? "unknown"

    var organizerInfo: Organizer? = nil
    if let org = event.organizer {
        organizerInfo = Organizer(
            name: org.name,
            email: org.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        )
    }

    let attendeeList: [Attendee] = event.attendees?.map { att in
        Attendee(
            name: att.name,
            email: att.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: statusString(att.participantStatus)
        )
    } ?? []

    return Invitation(
        eventId: event.eventIdentifier,
        title: event.title ?? "(No title)",
        start: iso8601.string(from: event.startDate),
        end: iso8601.string(from: event.endDate),
        calendar: event.calendar.title,
        organizer: organizerInfo,
        myStatus: status,
        location: event.location,
        notes: event.notes,
        attendees: attendeeList
    )
}

func eventToDetail(_ event: EKEvent) -> EventDetail {
    let currentUser = findCurrentUserAttendee(in: event)
    let status = currentUser.map { statusString($0.participantStatus) } ?? "unknown"

    var organizerInfo: Organizer? = nil
    if let org = event.organizer {
        organizerInfo = Organizer(
            name: org.name,
            email: org.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        )
    }

    let attendeeList: [Attendee] = event.attendees?.map { att in
        Attendee(
            name: att.name,
            email: att.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: statusString(att.participantStatus)
        )
    } ?? []

    var recurrence: String? = nil
    if let rules = event.recurrenceRules, !rules.isEmpty {
        recurrence = rules.map { $0.description }.joined(separator: "; ")
    }

    return EventDetail(
        eventId: event.eventIdentifier,
        title: event.title ?? "(No title)",
        start: iso8601.string(from: event.startDate),
        end: iso8601.string(from: event.endDate),
        calendar: event.calendar.title,
        organizer: organizerInfo,
        myStatus: status,
        location: event.location,
        notes: event.notes,
        attendees: attendeeList,
        url: event.url?.absoluteString,
        recurrence: recurrence
    )
}

// MARK: - Commands

func listInvitations(days: Int, calendarName: String?, asJSON: Bool) {
    let calendars: [EKCalendar]
    if let name = calendarName {
        calendars = store.calendars(for: .event).filter { $0.title.lowercased() == name.lowercased() }
        if calendars.isEmpty {
            fputs("Error: No calendar found named '\(name)'\n", stderr)
            exit(1)
        }
    } else {
        calendars = store.calendars(for: .event)
    }

    let now = Date()
    let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
    let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: calendars)
    let events = store.events(matching: predicate)

    // Filter to only pending invitations
    let pendingInvites = events.filter { isPendingInvitation($0) }
    let invitations = pendingInvites.map { eventToInvitation($0) }

    if asJSON {
        let result = InvitationList(invitations: invitations, count: invitations.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(result), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        if invitations.isEmpty {
            print("No pending invitations in the next \(days) days.")
        } else {
            print("Pending Invitations (\(invitations.count)):\n")
            for inv in invitations {
                let orgName = inv.organizer?.name ?? inv.organizer?.email ?? "Unknown"
                print("  \(inv.title)")
                print("    ID: \(inv.eventId)")
                print("    When: \(inv.start)")
                print("    Calendar: \(inv.calendar)")
                print("    From: \(orgName)")
                if let loc = inv.location {
                    print("    Location: \(loc)")
                }
                print()
            }
        }
    }
}

func showEvent(eventId: String) {
    guard let event = store.event(withIdentifier: eventId) else {
        fputs("Error: Event not found with ID '\(eventId)'\n", stderr)
        exit(1)
    }

    let detail = eventToDetail(event)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(detail), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func respondToEvent(eventId: String, response: String) {
    guard let event = store.event(withIdentifier: eventId) else {
        fputs("Error: Event not found with ID '\(eventId)'\n", stderr)
        exit(1)
    }

    // Get the external UID for CalDAV
    let eventUID = event.calendarItemExternalIdentifier ?? eventId

    // Try CalDAV first (proper protocol, notifies organizers)
    let caldavScript = "\(NSHomeDirectory())/.claude-mind/bin/calendar-caldav"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: caldavScript)
    process.arguments = [response, eventUID]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               output.contains("\"status\": \"success\"") {
                print("Successfully \(response)ed invitation via CalDAV: \(event.title ?? eventId)")
                return
            }
        }
    } catch {
        // Fall through to AppleScript
    }

    // Fallback: AppleScript approach
    fputs("CalDAV failed, trying AppleScript...\n", stderr)

    let appleScriptStatus: String
    switch response {
    case "accept": appleScriptStatus = "accepted"
    case "decline": appleScriptStatus = "declined"
    case "maybe", "tentative": appleScriptStatus = "tentative"
    default:
        fputs("Error: Invalid response '\(response)'. Use accept, decline, or maybe.\n", stderr)
        exit(1)
    }

    let script = """
    tell application "Calendar"
        set targetEvent to every event whose uid is "\(eventUID)"
        if (count of targetEvent) > 0 then
            set theEvent to item 1 of targetEvent
            set participation status of theEvent to \(appleScriptStatus)
            return "success"
        else
            return "not_found"
        end if
    end tell
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            fputs("AppleScript error: \(error)\n", stderr)
            fputs("Falling back to opening Calendar.app...\n", stderr)
            openEvent(eventId: eventId)
            return
        }

        let resultStr = result.stringValue ?? ""
        if resultStr == "success" {
            print("Successfully \(response)ed invitation via AppleScript: \(event.title ?? eventId)")
        } else if resultStr == "not_found" {
            fputs("Event not found via AppleScript. Opening Calendar.app instead...\n", stderr)
            openEvent(eventId: eventId)
        } else {
            fputs("Unexpected result: \(resultStr)\n", stderr)
            openEvent(eventId: eventId)
        }
    } else {
        fputs("Failed to create AppleScript. Opening Calendar.app instead...\n", stderr)
        openEvent(eventId: eventId)
    }
}

func acceptAll(days: Int) {
    let now = Date()
    let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
    let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: nil)
    let events = store.events(matching: predicate)

    let pendingInvites = events.filter { isPendingInvitation($0) }

    if pendingInvites.isEmpty {
        print("No pending invitations to accept.")
        return
    }

    print("Accepting \(pendingInvites.count) invitation(s)...")

    for event in pendingInvites {
        respondToEvent(eventId: event.eventIdentifier, response: "accept")
    }
}

func openEvent(eventId: String) {
    guard let event = store.event(withIdentifier: eventId) else {
        fputs("Error: Event not found with ID '\(eventId)'\n", stderr)
        exit(1)
    }

    // Try to open the event in Calendar.app using its external identifier
    let externalId = event.calendarItemExternalIdentifier ?? eventId

    // First activate Calendar
    let activateScript = """
    tell application "Calendar"
        activate
    end tell
    """

    if let appleScript = NSAppleScript(source: activateScript) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }

    // Try to show the event - this approach works by switching to the event's date
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MMMM d, yyyy"
    let dateStr = dateFormatter.string(from: event.startDate)

    let showScript = """
    tell application "Calendar"
        tell (first calendar whose name is "\(event.calendar.title)")
            set targetEvents to (every event whose uid is "\(externalId)")
            if (count of targetEvents) > 0 then
                show (item 1 of targetEvents)
            end if
        end tell
    end tell
    """

    if let appleScript = NSAppleScript(source: showScript) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if error == nil {
            print("Opened Calendar.app to event: \(event.title ?? eventId)")
            return
        }
    }

    // Fallback: just view the date
    let viewScript = """
    tell application "Calendar"
        view calendar at date "\(dateStr)"
    end tell
    """

    if let appleScript = NSAppleScript(source: viewScript) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }

    print("Opened Calendar.app to date: \(dateStr)")
    print("Event: \(event.title ?? "(No title)")")
}

// MARK: - Event Creation

struct CreatedEvent: Codable {
    let eventId: String
    let title: String
    let start: String
    let end: String
    let calendar: String
    let location: String?
    let notes: String?
    let allDay: Bool

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case title, start, end, calendar, location, notes
        case allDay = "all_day"
    }
}

func parseDateTime(_ input: String) -> Date? {
    // Try ISO8601 first
    if let date = iso8601.date(from: input) {
        return date
    }

    // Try common formats
    let formats = [
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy"
    ]

    for format in formats {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: input) {
            return date
        }
    }

    // Try natural language
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    if let match = detector?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
        return match.date
    }

    return nil
}

func findCalendar(named name: String?) -> EKCalendar? {
    let calendars = store.calendars(for: .event)

    if let name = name {
        return calendars.first { $0.title.lowercased() == name.lowercased() }
    }

    // Return default calendar
    return store.defaultCalendarForNewEvents
}

func createEvent(
    title: String,
    startDate: Date,
    endDate: Date?,
    duration: Int,
    calendarName: String?,
    location: String?,
    notes: String?,
    url: String?,
    allDay: Bool
) {
    guard let calendar = findCalendar(named: calendarName) else {
        if let name = calendarName {
            fputs("Error: Calendar '\(name)' not found\n", stderr)
        } else {
            fputs("Error: No default calendar available\n", stderr)
        }
        exit(1)
    }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = startDate
    event.isAllDay = allDay

    if allDay {
        // For all-day events, end date should be the same day or span multiple days
        event.endDate = endDate ?? startDate
    } else {
        event.endDate = endDate ?? Calendar.current.date(byAdding: .minute, value: duration, to: startDate)!
    }

    event.calendar = calendar

    if let location = location {
        event.location = location
    }

    if let notes = notes {
        event.notes = notes
    }

    if let urlStr = url, let eventUrl = URL(string: urlStr) {
        event.url = eventUrl
    }

    do {
        try store.save(event, span: .thisEvent)

        let created = CreatedEvent(
            eventId: event.eventIdentifier,
            title: event.title ?? title,
            start: iso8601.string(from: event.startDate),
            end: iso8601.string(from: event.endDate),
            calendar: calendar.title,
            location: event.location,
            notes: event.notes,
            allDay: event.isAllDay
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(created), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } catch {
        fputs("Error creating event: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func listCalendars() {
    let calendars = store.calendars(for: .event)
    print("Available calendars:\n")
    for cal in calendars.sorted(by: { $0.title < $1.title }) {
        let isDefault = cal == store.defaultCalendarForNewEvents ? " (default)" : ""
        print("  - \(cal.title)\(isDefault)")
    }
}

// MARK: - Calendar Sync

func syncCalendars() {
    // Force calendar refresh by restarting CalendarAgent and refreshing via Calendar.app
    let script = """
    do shell script "killall CalendarAgent 2>/dev/null || true"
    delay 1
    tell application "Calendar"
        activate
        delay 0.5
        tell application "System Events"
            tell process "Calendar"
                -- Trigger refresh via View menu
                click menu item "Refresh Calendars" of menu "View" of menu bar 1
            end tell
        end tell
        delay 2
    end tell
    return "synced"
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        _ = appleScript.executeAndReturnError(&error)
        if let error = error {
            fputs("Sync warning: \(error)\n", stderr)
        }
        print("Calendar sync triggered. Calendars are refreshing...")
    } else {
        fputs("Failed to trigger calendar sync.\n", stderr)
        exit(1)
    }
}

// MARK: - UI-Based Invitation Response

func respondViaUI(eventTitle: String, response: String) {
    // Use System Events to click Accept/Decline/Maybe buttons in Calendar.app
    let buttonName: String
    switch response {
    case "accept": buttonName = "Accept"
    case "decline": buttonName = "Decline"
    case "maybe", "tentative": buttonName = "Maybe"
    default:
        fputs("Error: Invalid response '\(response)'\n", stderr)
        exit(1)
    }

    let script = """
    tell application "Calendar"
        activate
        delay 0.5
    end tell

    tell application "System Events"
        tell process "Calendar"
            set frontWindow to window 1

            -- Find and click Accept/Decline/Maybe buttons
            set allElems to entire contents of frontWindow
            repeat with elem in allElems
                try
                    if class of elem is button and name of elem is "\(buttonName)" then
                        click elem
                        delay 0.5
                        return "clicked"
                    end if
                end try
            end repeat
            return "not_found"
        end tell
    end tell
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            fputs("UI automation error: \(error)\n", stderr)
            return
        }

        let resultStr = result.stringValue ?? ""
        if resultStr == "clicked" {
            print("Successfully \(response)ed invitation via UI: \(eventTitle)")
        } else {
            fputs("Could not find \(buttonName) button in Calendar UI.\n", stderr)
        }
    }
}

func respondAllViaUI(response: String) {
    // Keep clicking response buttons until none remain
    let buttonName: String
    switch response {
    case "accept": buttonName = "Accept"
    case "decline": buttonName = "Decline"
    case "maybe", "tentative": buttonName = "Maybe"
    default:
        fputs("Error: Invalid response '\(response)'\n", stderr)
        exit(1)
    }

    let script = """
    tell application "Calendar"
        activate
        delay 0.5
    end tell

    set clickCount to 0
    tell application "System Events"
        tell process "Calendar"
            set frontWindow to window 1

            repeat 20 times
                set foundOne to false
                set allElems to entire contents of frontWindow
                repeat with elem in allElems
                    try
                        if class of elem is button and name of elem is "\(buttonName)" then
                            click elem
                            set clickCount to clickCount + 1
                            set foundOne to true
                            delay 0.8
                            exit repeat
                        end if
                    end try
                end repeat
                if not foundOne then exit repeat
            end repeat
        end tell
    end tell

    return clickCount as string
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            fputs("UI automation error: \(error)\n", stderr)
            return
        }

        let count = Int(result.stringValue ?? "0") ?? 0
        if count > 0 {
            print("Successfully \(response)ed \(count) invitation(s) via UI.")
        } else {
            print("No \(buttonName) buttons found in Calendar UI.")
        }
    }
}

// MARK: - CLI Parsing

func printUsage() {
    let usage = """
    calendar-invites - Manage calendar invitations and events

    Usage:
        calendar-invites list [--json|--text] [--days N] [--calendar NAME]
        calendar-invites show <event-id>
        calendar-invites accept <event-id>
        calendar-invites decline <event-id>
        calendar-invites maybe <event-id>
        calendar-invites accept-all [--days N]
        calendar-invites accept-all-ui
        calendar-invites open <event-id>
        calendar-invites create --title TITLE --start DATETIME [options]
        calendar-invites calendars
        calendar-invites sync

    Commands:
        list          List pending invitations (default: next 30 days)
        show          Show details of a specific event
        accept        Accept an invitation (via AppleScript)
        decline       Decline an invitation (via AppleScript)
        maybe         Mark as tentative/maybe (via AppleScript)
        accept-all    Accept all pending invitations (via AppleScript)
        accept-all-ui Accept all by clicking UI buttons (more reliable)
        open          Open event in Calendar.app
        create        Create a new calendar event
        calendars     List available calendars
        sync          Force calendar refresh/sync

    List Options:
        --json      Output as JSON (default for list)
        --text      Output as human-readable text
        --days N    Look ahead N days (default: 30)
        --calendar  Filter to specific calendar

    Create Options:
        --title     Event title (required)
        --start     Start date/time: ISO8601, "2026-01-20 14:00", or "2026-01-20" (required)
        --end       End date/time (optional, defaults to start + duration)
        --duration  Duration in minutes (default: 60)
        --calendar  Calendar name (default: system default)
        --location  Event location
        --notes     Event notes/description
        --url       Event URL
        --all-day   Create an all-day event

    Examples:
        calendar-invites list --text
        calendar-invites list --json --days 7
        calendar-invites show "ABC123-DEF456"
        calendar-invites accept "ABC123-DEF456"
        calendar-invites create --title "Team Meeting" --start "2026-01-20T14:00"
        calendar-invites create --title "Vacation" --start "2026-01-25" --end "2026-01-27" --all-day
        calendar-invites create --title "Lunch" --start "2026-01-20 12:00" --duration 90 --location "Cafe"

    Note: EventKit can only read invitation status. Responses are attempted via
    AppleScript, with fallback to opening Calendar.app if that fails.
    """
    print(usage)
}

// Parse arguments
var args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(0)
}

let command = args.removeFirst()

// Request calendar access
guard requestAccess() else {
    exit(1)
}

switch command {
case "list":
    var asJSON = true
    var days = 30
    var calendarName: String? = nil

    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--json":
            asJSON = true
        case "--text":
            asJSON = false
        case "--days":
            if let d = args.first, let n = Int(d) {
                days = n
                args.removeFirst()
            }
        case "--calendar":
            if let name = args.first {
                calendarName = name
                args.removeFirst()
            }
        default:
            break
        }
    }

    listInvitations(days: days, calendarName: calendarName, asJSON: asJSON)

case "show":
    guard let eventId = args.first else {
        fputs("Error: event-id required\n", stderr)
        exit(1)
    }
    showEvent(eventId: eventId)

case "accept":
    guard let eventId = args.first else {
        fputs("Error: event-id required\n", stderr)
        exit(1)
    }
    respondToEvent(eventId: eventId, response: "accept")

case "decline":
    guard let eventId = args.first else {
        fputs("Error: event-id required\n", stderr)
        exit(1)
    }
    respondToEvent(eventId: eventId, response: "decline")

case "maybe":
    guard let eventId = args.first else {
        fputs("Error: event-id required\n", stderr)
        exit(1)
    }
    respondToEvent(eventId: eventId, response: "maybe")

case "accept-all":
    var days = 30
    if let idx = args.firstIndex(of: "--days"), idx + 1 < args.count {
        days = Int(args[idx + 1]) ?? 30
    }
    acceptAll(days: days)

case "open":
    guard let eventId = args.first else {
        fputs("Error: event-id required\n", stderr)
        exit(1)
    }
    openEvent(eventId: eventId)

case "create":
    var title: String? = nil
    var startStr: String? = nil
    var endStr: String? = nil
    var duration = 60
    var calendarName: String? = nil
    var location: String? = nil
    var notes: String? = nil
    var url: String? = nil
    var allDay = false

    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--title":
            if !args.isEmpty { title = args.removeFirst() }
        case "--start":
            if !args.isEmpty { startStr = args.removeFirst() }
        case "--end":
            if !args.isEmpty { endStr = args.removeFirst() }
        case "--duration":
            if !args.isEmpty { duration = Int(args.removeFirst()) ?? 60 }
        case "--calendar":
            if !args.isEmpty { calendarName = args.removeFirst() }
        case "--location":
            if !args.isEmpty { location = args.removeFirst() }
        case "--notes":
            if !args.isEmpty { notes = args.removeFirst() }
        case "--url":
            if !args.isEmpty { url = args.removeFirst() }
        case "--all-day":
            allDay = true
        default:
            break
        }
    }

    guard let eventTitle = title else {
        fputs("Error: --title is required\n", stderr)
        exit(1)
    }

    guard let startInput = startStr else {
        fputs("Error: --start is required\n", stderr)
        exit(1)
    }

    guard let startDate = parseDateTime(startInput) else {
        fputs("Error: Could not parse start date '\(startInput)'\n", stderr)
        fputs("Try formats like: 2026-01-20T14:00:00-05:00, 2026-01-20 14:00, or 2026-01-20\n", stderr)
        exit(1)
    }

    var endDate: Date? = nil
    if let endInput = endStr {
        guard let parsed = parseDateTime(endInput) else {
            fputs("Error: Could not parse end date '\(endInput)'\n", stderr)
            exit(1)
        }
        endDate = parsed
    }

    createEvent(
        title: eventTitle,
        startDate: startDate,
        endDate: endDate,
        duration: duration,
        calendarName: calendarName,
        location: location,
        notes: notes,
        url: url,
        allDay: allDay
    )

case "calendars":
    listCalendars()

case "sync":
    syncCalendars()

case "accept-all-ui":
    respondAllViaUI(response: "accept")

case "decline-all-ui":
    respondAllViaUI(response: "decline")

default:
    fputs("Error: Unknown command '\(command)'\n", stderr)
    printUsage()
    exit(1)
}
