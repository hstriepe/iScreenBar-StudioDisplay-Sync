import Foundation

// Internal so Automation.swift and ScriptingSupport.swift can log too.
func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}
