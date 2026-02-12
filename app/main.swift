import Cocoa
import ScriptingBridge

// ScriptingBridge protocols for Finder
@objc protocol FinderApplication {
    @objc optional var selection: SBObject? { get }
    @objc optional func FinderWindows() -> SBElementArray?
}

@objc protocol FinderItem {
    @objc optional var URL: String? { get }
}

@objc protocol FinderFinderWindow {
    @objc optional var target: SBObject? { get }
}

extension SBApplication: FinderApplication {}
extension SBObject: FinderItem, FinderFinderWindow {}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let path = try getFinderPath()
            openClaudeInPath(path)
        } catch {
            showAlert(title: "Error", message: error.localizedDescription)
        }
        NSApp.terminate(nil)
    }
    
    func getFinderPath() throws -> String {
        guard let finder = SBApplication(bundleIdentifier: "com.apple.finder") as FinderApplication? else {
            throw NSError(domain: "OpenInClaudeCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access Finder"])
        }
        
        // Try to get selected items first
        if let selection = finder.selection as? SBObject,
           let items = selection.get() as? [SBObject],
           let firstItem = items.first,
           let urlString = (firstItem as FinderItem).URL ?? nil,
           let url = URL(string: urlString) {
            var path = url.path
            // If it's a file, get the parent directory
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue {
                path = (path as NSString).deletingLastPathComponent
            }
            return path
        }
        
        // Fall back to front Finder window
        if let windows = finder.FinderWindows?(),
           let firstWindow = windows.firstObject as? FinderFinderWindow,
           let target = firstWindow.target as? SBObject,
           let resolved = target.get() as? SBObject,
           let urlString = (resolved as FinderItem).URL ?? nil,
           let url = URL(string: urlString) {
            return url.path
        }
        
        // Fall back to Desktop
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    }
    
    func openClaudeInPath(_ path: String) {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedPath)' && claude"
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        
        if let error = error {
            showAlert(title: "Error", message: error.description)
        }
    }
    
    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
