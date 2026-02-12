import Cocoa
import ScriptingBridge

// MARK: - Path Safety

struct PathValidator {
    static let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    
    // Directories that should never be used as Claude working directories (exact match)
    static let forbiddenExact: Set<String> = [
        "/",
        "/System",
        "/Library",
        "/Applications",
        "/Users",
        "/private",
        "/var",
        "/tmp",
        "/etc",
        "/bin",
        "/sbin",
        "/usr",
        "/opt",
        "/cores",
        "/Volumes",
        homeDir,  // Home dir itself is too broad
    ]
    
    // Directories where default folder should not be created (but launching in subfolders is OK)
    static let forbiddenForCreation: Set<String> = [
        homeDir + "/Library",
        homeDir + "/Applications",
        homeDir + "/Desktop",
        homeDir + "/Documents",
        homeDir + "/Downloads",
        homeDir + "/Movies",
        homeDir + "/Music",
        homeDir + "/Pictures",
        homeDir + "/Public",
    ]
    
    // Check if path is safe to LAUNCH claude in (less restrictive)
    static func isSafeToLaunch(_ path: String) -> (safe: Bool, reason: String?) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let resolvedPath = (expandedPath as NSString).standardizingPath
        
        // Block exact forbidden paths
        if forbiddenExact.contains(resolvedPath) {
            return (false, "'\(resolvedPath)' is a protected directory")
        }
        
        // Block launching directly in ~/Library, ~/Applications (but subfolders OK)
        if resolvedPath == homeDir + "/Library" || resolvedPath == homeDir + "/Applications" {
            return (false, "'\(resolvedPath)' is a protected directory")
        }
        
        // Path traversal check
        if resolvedPath.contains("..") {
            return (false, "Invalid path")
        }
        
        return (true, nil)
    }
    
    // Check if path is safe for DEFAULT DIRECTORY creation (more restrictive)
    static func isSafePath(_ path: String) -> (safe: Bool, reason: String?) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let resolvedPath = (expandedPath as NSString).standardizingPath
        
        // Must be under home directory
        guard resolvedPath.hasPrefix(homeDir) else {
            return (false, "Path must be inside your home directory")
        }
        
        // Block exact forbidden paths
        if forbiddenExact.contains(resolvedPath) || forbiddenForCreation.contains(resolvedPath) {
            return (false, "'\(resolvedPath)' is a protected directory")
        }
        
        // Block creation inside ~/Library, ~/Applications (these are system-managed)
        for forbidden in [homeDir + "/Library", homeDir + "/Applications"] {
            if resolvedPath.hasPrefix(forbidden + "/") {
                return (false, "Cannot create folders inside '\(forbidden)'")
            }
        }
        
        // Path traversal check
        if resolvedPath.contains("..") || resolvedPath.contains("//") {
            return (false, "Invalid path characters")
        }
        
        return (true, nil)
    }
}

// MARK: - Configuration

// Helper to check if a command exists in PATH
func commandExists(_ command: String) -> Bool {
    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-l", "-c", "which '\(command)' >/dev/null 2>&1"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

// Get the default claude command (agency claude if agency is installed)
func getDefaultClaudeCommand() -> String {
    if commandExists("agency") {
        return "agency claude"
    }
    return "claude"
}

struct Settings: Codable {
    var terminal: String
    var defaultDirectory: String
    var useNewWindow: Bool?
    var terminalProfile: String?
    var claudeCommand: String?
    
    // Computed accessors with defaults for backward compatibility
    var effectiveUseNewWindow: Bool { useNewWindow ?? true }
    var effectiveTerminalProfile: String { terminalProfile ?? "Default" }
    var effectiveClaudeCommand: String { claudeCommand ?? getDefaultClaudeCommand() }
    
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/openinclaudecode")
    static let configFile = configDir.appendingPathComponent("settings.json")
    
    static let defaults = Settings(
        terminal: "Terminal",
        defaultDirectory: "~/Claude",
        useNewWindow: true,
        terminalProfile: "Default",
        claudeCommand: nil  // Will use detected default
    )
    
    static func load() -> Settings {
        guard FileManager.default.fileExists(atPath: configFile.path),
              let data = try? Data(contentsOf: configFile),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return defaults
        }
        return settings
    }
    
    func expandedDefaultDirectory() -> String {
        if defaultDirectory.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(defaultDirectory.dropFirst(2))).path
        }
        return defaultDirectory
    }
    
    // Get available Terminal.app profiles
    static func getTerminalProfiles() -> [String] {
        let script = "tell application \"Terminal\" to get name of every settings set"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script),
              let result = appleScript.executeAndReturnError(&error).coerce(toDescriptorType: typeAEList) else {
            return ["Default"]
        }
        
        var profiles = ["Default"]
        for i in 1...result.numberOfItems {
            if let desc = result.atIndex(i), let name = desc.stringValue {
                profiles.append(name)
            }
        }
        return profiles
    }
}

// MARK: - Claude Trusted Directories Manager

struct ClaudeConfig {
    static let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")
    
    // Get list of trusted directories from ~/.claude.json
    static func getTrustedDirectories() -> [String] {
        guard FileManager.default.fileExists(atPath: configFile.path),
              let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        // Directories are top-level keys that start with "/" or "~"
        let directories = json.keys.filter { key in
            key.hasPrefix("/") || key.hasPrefix("~")
        }.sorted()
        
        return directories
    }
    
    // Remove a directory from ~/.claude.json
    static func removeDirectory(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: configFile.path),
              let data = try? Data(contentsOf: configFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Check if directory exists in config
        guard json[path] != nil else {
            return false
        }
        
        // Remove the directory
        json.removeValue(forKey: path)
        
        // Write back
        do {
            let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: configFile)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Terminal Launchers

enum TerminalLauncher {
    case terminal
    case iterm
    case warp
    case kitty
    case alacritty
    case ghostty
    
    init?(name: String) {
        switch name.lowercased() {
        case "terminal", "terminal.app": self = .terminal
        case "iterm", "iterm2", "iterm.app": self = .iterm
        case "warp", "warp.app": self = .warp
        case "kitty", "kitty.app": self = .kitty
        case "alacritty", "alacritty.app": self = .alacritty
        case "ghostty", "ghostty.app": self = .ghostty
        default: return nil
        }
    }
    
    func launch(in path: String, profile: String = "Default", command: String = "claude") -> Bool {
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
        
        switch self {
        case .terminal:
            let escapedProfile = profile.replacingOccurrences(of: "\"", with: "\\\"")
            
            if profile == "Default" {
                return runAppleScript("""
                    tell application "Terminal"
                        activate
                        do script "cd '\(escapedPath)' && \(escapedCommand)"
                    end tell
                """)
            } else {
                return runAppleScript("""
                    tell application "Terminal"
                        activate
                        do script "cd '\(escapedPath)' && \(escapedCommand)"
                        set current settings of front window to settings set "\(escapedProfile)"
                    end tell
                """)
            }
            
        case .iterm:
            return runAppleScript("""
                tell application "iTerm"
                    activate
                    try
                        set newWindow to (create window with default profile)
                        tell current session of newWindow
                            write text "cd '\(escapedPath)' && \(escapedCommand)"
                        end tell
                    on error
                        tell current window
                            create tab with default profile
                            tell current session
                                write text "cd '\(escapedPath)' && \(escapedCommand)"
                            end tell
                        end tell
                    end try
                end tell
            """)
            
        case .warp:
            return runAppleScript("""
                tell application "Warp"
                    activate
                end tell
                delay 0.5
                tell application "System Events"
                    keystroke "cd '\(escapedPath)' && \(escapedCommand)"
                    keystroke return
                end tell
            """)
            
        case .kitty:
            // Kitty: kitty -d /path sh -c "command"
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "kitty", "--args", "-d", path, "sh", "-c", command]
            do {
                try task.run()
                return true
            } catch {
                return runAppleScript("""
                    tell application "kitty" to activate
                    delay 0.3
                    tell application "System Events"
                        keystroke "cd '\(escapedPath)' && \(escapedCommand)"
                        keystroke return
                    end tell
                """)
            }
            
        case .alacritty:
            // Alacritty: alacritty --working-directory /path -e sh -c "command"
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "Alacritty", "--args", "--working-directory", path, "-e", "sh", "-c", command]
            do {
                try task.run()
                return true
            } catch {
                return runAppleScript("""
                    tell application "Alacritty" to activate
                    delay 0.3
                    tell application "System Events"
                        keystroke "cd '\(escapedPath)' && \(escapedCommand)"
                        keystroke return
                    end tell
                """)
            }
            
        case .ghostty:
            // Ghostty: ghostty -e sh -c "cd /path && command"
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "Ghostty", "--args", "-e", "sh", "-c", "cd '\(escapedPath)' && \(escapedCommand)"]
            do {
                try task.run()
                return true
            } catch {
                return runAppleScript("""
                    tell application "Ghostty" to activate
                    delay 0.3
                    tell application "System Events"
                        keystroke "cd '\(escapedPath)' && \(escapedCommand)"
                        keystroke return
                    end tell
                """)
            }
        }
    }
    
    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
        return error == nil
    }
}

// MARK: - ScriptingBridge protocols for Finder

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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.load()
    
    // Paths that indicate the app was double-clicked, not used from toolbar
    static let launchLocationPaths: Set<String> = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path,
    ]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring app to front for any dialogs
        NSApp.activate(ignoringOtherApps: true)
        
        let finderPath = getFinderPath()
        
        // Check if this looks like a double-click launch vs toolbar click
        // If no Finder path, or path is a launch location (Applications, Downloads, etc.)
        if finderPath == nil || isLaunchLocation(finderPath!) {
            // Always show onboarding when launched from Applications etc.
            // Don't offer to launch Claude - that would be confusing
            showOnboarding()
            exit(0)
        }
        
        // Toolbar click - validate path before launching
        let (isSafe, reason) = PathValidator.isSafeToLaunch(finderPath!)
        if !isSafe {
            showAlert(title: "Protected Directory", 
                      message: "Can't open Claude Code in this directory:\n\n\(reason ?? "Unknown reason")\n\nNavigate to a project folder and try again.")
            exit(0)
        }
        
        launchInPath(finderPath!)
        exit(0)
    }
    
    func launchInPath(_ path: String) {
        let claudeCmd = settings.effectiveClaudeCommand
        
        // Check if the base command (first word) exists
        let baseCommand = claudeCmd.split(separator: " ").first.map(String.init) ?? claudeCmd
        if !commandExists(baseCommand) {
            // Offer to install Claude
            if promptInstallClaude(command: baseCommand) {
                return  // User chose to install, don't try to launch
            }
        }
        
        guard let launcher = TerminalLauncher(name: settings.terminal) else {
            showAlert(title: "Unknown Terminal", 
                      message: "Terminal '\(settings.terminal)' is not supported.\n\nSupported: Terminal, iTerm, Warp, Kitty, Alacritty, Ghostty")
            return
        }
        
        if !launcher.launch(in: path, profile: settings.effectiveTerminalProfile, command: claudeCmd) {
            showAlert(title: "Launch Failed", 
                      message: "Could not open \(settings.terminal) in \(path)")
        }
    }
    
    func promptInstallClaude(command: String) -> Bool {
        // Only offer to install if the missing command is "claude" or "agency"
        guard command == "claude" || command == "agency" else {
            showAlert(title: "Command Not Found", 
                      message: "'\(command)' was not found in your PATH.\n\nPlease install it or change the command in Settings.")
            return true
        }
        
        let alert = NSAlert()
        alert.messageText = "'\(command)' Not Found"
        alert.informativeText = "The '\(command)' command was not found.\n\nWould you like to install Claude Code?"
        alert.addButton(withTitle: "Install Claude")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            installClaude()
            return true
        } else if response == .alertSecondButtonReturn {
            showSettingsDialog()
            return true
        }
        return true  // Don't proceed with launch
    }
    
    func installClaude() {
        // Run the installation script in Terminal
        let installScript = "cd /tmp && curl -fsSL https://claude.ai/install.sh | bash"
        
        var error: NSDictionary?
        let script = NSAppleScript(source: """
            tell application "Terminal"
                activate
                do script "\(installScript)"
            end tell
        """)
        script?.executeAndReturnError(&error)
        
        if error != nil {
            showAlert(title: "Error", message: "Could not open Terminal for installation")
            return
        }
        
        showAlert(title: "Installing Claude", 
                  message: "Claude Code is being installed in your terminal.\n\nOnce installation completes, try again.")
    }
    
    func isLaunchLocation(_ path: String) -> Bool {
        // Check if this path is where the app lives (indicating double-click)
        let resolvedPath = (path as NSString).standardizingPath
        
        // Check exact match or if inside a launch location
        for launchPath in Self.launchLocationPaths {
            if resolvedPath == launchPath || resolvedPath.hasPrefix(launchPath + "/") {
                return true
            }
        }
        return false
    }
    
    func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        let defaultPath = settings.expandedDefaultDirectory()
        let defaultName = (defaultPath as NSString).lastPathComponent
        let defaultExists = FileManager.default.fileExists(atPath: defaultPath)
        
        let alert = NSAlert()
        alert.messageText = "Open in Claude Code"
        
        if defaultExists {
            alert.informativeText = """
            This app is designed for use from the Finder toolbar.
            
            Setup:
            1. Hold ⌘ and drag this app to the Finder toolbar
            
            Usage:
            2. Navigate to any project folder
            3. Click the toolbar icon to open Claude Code there
            """
            alert.addButton(withTitle: "Setup in Finder")
            alert.addButton(withTitle: "Settings...")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.informativeText = """
            This app is designed for use from the Finder toolbar.
            
            Setup:
            1. Hold ⌘ and drag this app to the Finder toolbar
            
            Usage:
            2. Navigate to any project folder
            3. Click the toolbar icon to open Claude Code there
            """
            alert.addButton(withTitle: "Create ~/\(defaultName)")
            alert.addButton(withTitle: "Setup in Finder")
            alert.addButton(withTitle: "Cancel")
        }
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if defaultExists {
            if response == .alertFirstButtonReturn {
                openSetupInstructions()
            } else if response == .alertSecondButtonReturn {
                showSettingsDialog()
            }
        } else {
            if response == .alertFirstButtonReturn {
                createAndLaunchInDefaultDirectory()
            } else if response == .alertSecondButtonReturn {
                openSetupInstructions()
            }
        }
    }
    
    func createAndLaunchInDefaultDirectory() {
        let defaultPath = settings.expandedDefaultDirectory()
        
        // Validate path safety
        let (isSafe, reason) = PathValidator.isSafePath(defaultPath)
        if !isSafe {
            showAlert(title: "Unsafe Directory", 
                      message: "The configured default directory is not safe:\n\n\(reason ?? "Unknown reason")\n\nPlease edit ~/.config/openinclaudecode/settings.json")
            return
        }
        
        do {
            try FileManager.default.createDirectory(atPath: defaultPath, 
                                                    withIntermediateDirectories: true)
            setFolderOrange(defaultPath)
            addToFinderSidebar(defaultPath)
            launchInPath(defaultPath)
        } catch {
            showAlert(title: "Error", message: "Could not create \(defaultPath): \(error.localizedDescription)")
        }
    }
    
    func showSettingsDialog() {
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.alertStyle = .informational
        
        // Create accessory view with settings
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 285))
        
        // Terminal label
        let termLabel = NSTextField(labelWithString: "Terminal:")
        termLabel.frame = NSRect(x: 0, y: 255, width: 80, height: 20)
        container.addSubview(termLabel)
        
        // Terminal popup
        let termPopup = NSPopUpButton(frame: NSRect(x: 85, y: 253, width: 150, height: 25))
        termPopup.addItems(withTitles: ["Terminal", "iTerm", "Warp", "Kitty", "Alacritty", "Ghostty"])
        termPopup.selectItem(withTitle: settings.terminal)
        container.addSubview(termPopup)
        
        // Profile label (Terminal.app only)
        let profileLabel = NSTextField(labelWithString: "Profile:")
        profileLabel.frame = NSRect(x: 0, y: 220, width: 80, height: 20)
        container.addSubview(profileLabel)
        
        // Profile popup
        let profilePopup = NSPopUpButton(frame: NSRect(x: 85, y: 218, width: 150, height: 25))
        let profiles = Settings.getTerminalProfiles()
        profilePopup.addItems(withTitles: profiles)
        if profiles.contains(settings.effectiveTerminalProfile) {
            profilePopup.selectItem(withTitle: settings.effectiveTerminalProfile)
        }
        container.addSubview(profilePopup)
        
        // Enable/disable profile based on terminal selection
        func updateProfileVisibility() {
            let isTerminal = termPopup.titleOfSelectedItem == "Terminal"
            profileLabel.isHidden = !isTerminal
            profilePopup.isHidden = !isTerminal
        }
        updateProfileVisibility()
        
        // Command label
        let cmdLabel = NSTextField(labelWithString: "Command:")
        cmdLabel.frame = NSRect(x: 0, y: 185, width: 80, height: 20)
        container.addSubview(cmdLabel)
        
        // Command text field
        let cmdField = NSTextField(frame: NSRect(x: 85, y: 183, width: 250, height: 22))
        cmdField.stringValue = settings.effectiveClaudeCommand
        cmdField.placeholderString = "claude"
        container.addSubview(cmdField)
        
        // Directory label
        let dirLabel = NSTextField(labelWithString: "Default folder:")
        dirLabel.frame = NSRect(x: 0, y: 150, width: 80, height: 20)
        container.addSubview(dirLabel)
        
        // Directory text field
        let dirField = NSTextField(frame: NSRect(x: 85, y: 148, width: 250, height: 22))
        dirField.stringValue = settings.defaultDirectory
        dirField.placeholderString = "~/Claude"
        container.addSubview(dirField)
        
        // Trusted directories button
        let trustedButton = NSButton(frame: NSRect(x: 0, y: 110, width: 200, height: 25))
        trustedButton.title = "Manage Trusted Directories..."
        trustedButton.bezelStyle = .rounded
        trustedButton.target = self
        trustedButton.action = #selector(showTrustedDirectoriesDialog)
        container.addSubview(trustedButton)
        
        // Config file info
        let configLabel = NSTextField(wrappingLabelWithString: "Config file:\n~/.config/openinclaudecode/settings.json")
        configLabel.frame = NSRect(x: 0, y: 60, width: 350, height: 35)
        configLabel.font = NSFont.systemFont(ofSize: 11)
        configLabel.textColor = .secondaryLabelColor
        container.addSubview(configLabel)
        
        // Toolbar instructions
        let instructLabel = NSTextField(wrappingLabelWithString: "To add to Finder toolbar:\nHold ⌘ and drag this app from /Applications to the toolbar")
        instructLabel.frame = NSRect(x: 0, y: 15, width: 350, height: 40)
        instructLabel.font = NSFont.systemFont(ofSize: 11)
        instructLabel.textColor = .secondaryLabelColor
        container.addSubview(instructLabel)
        
        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Open Config File")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Save settings
            let selectedProfile = termPopup.titleOfSelectedItem == "Terminal" 
                ? (profilePopup.titleOfSelectedItem ?? "Default") 
                : "Default"
            saveSettings(
                terminal: termPopup.titleOfSelectedItem ?? "Terminal",
                defaultDirectory: dirField.stringValue,
                terminalProfile: selectedProfile,
                claudeCommand: cmdField.stringValue
            )
        } else if response == .alertSecondButtonReturn {
            // Open config file in default editor
            let configPath = Settings.configFile.path
            if FileManager.default.fileExists(atPath: configPath) {
                NSWorkspace.shared.open(Settings.configFile)
            } else {
                // Create default config first
                try? FileManager.default.createDirectory(at: Settings.configDir, withIntermediateDirectories: true)
                let defaultConfig = """
                {
                  "terminal": "Terminal",
                  "defaultDirectory": "~/Claude",
                  "terminalProfile": "Default",
                  "claudeCommand": "claude"
                }
                """
                try? defaultConfig.write(to: Settings.configFile, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(Settings.configFile)
            }
        }
    }
    
    func saveSettings(terminal: String, defaultDirectory: String, terminalProfile: String, claudeCommand: String) {
        // Use nil for claudeCommand if it matches the detected default (to allow future auto-detection)
        let cmdToSave: String? = claudeCommand.isEmpty || claudeCommand == getDefaultClaudeCommand() ? nil : claudeCommand
        
        let newSettings = Settings(
            terminal: terminal, 
            defaultDirectory: defaultDirectory,
            useNewWindow: true,
            terminalProfile: terminalProfile,
            claudeCommand: cmdToSave
        )
        
        // Validate the directory path first
        let (isSafe, reason) = PathValidator.isSafePath(defaultDirectory)
        if !isSafe {
            showAlert(title: "Invalid Directory", 
                      message: reason ?? "The specified directory is not safe")
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: Settings.configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(newSettings)
            try data.write(to: Settings.configFile)
            
            showAlert(title: "Settings Saved", message: "Your settings have been saved.")
        } catch {
            showAlert(title: "Error", message: "Could not save settings: \(error.localizedDescription)")
        }
    }
    
    func openSetupInstructions() {
        let defaultPath = settings.expandedDefaultDirectory()
        let defaultName = (defaultPath as NSString).lastPathComponent
        let parentPath = (defaultPath as NSString).deletingLastPathComponent
        let defaultExists = FileManager.default.fileExists(atPath: defaultPath)
        
        // Ask if they want to create the default folder (if it doesn't exist)
        if !defaultExists {
            let (isSafe, _) = PathValidator.isSafePath(defaultPath)
            if isSafe {
                let createAlert = NSAlert()
                createAlert.messageText = "Create ~/\(defaultName)?"
                createAlert.informativeText = "This will create a folder for your Claude projects and open it in Finder so you can add it to your sidebar."
                createAlert.addButton(withTitle: "Create Folder")
                createAlert.addButton(withTitle: "Skip")
                createAlert.alertStyle = .informational
                
                if createAlert.runModal() == .alertFirstButtonReturn {
                    do {
                        try FileManager.default.createDirectory(atPath: defaultPath, 
                                                                withIntermediateDirectories: true)
                        setFolderOrange(defaultPath)
                    } catch {
                        showAlert(title: "Error", message: "Could not create folder: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Open parent directory in Finder and select the folder if it exists
        let folderExists = FileManager.default.fileExists(atPath: defaultPath)
        if folderExists {
            NSWorkspace.shared.selectFile(defaultPath, inFileViewerRootedAtPath: parentPath)
        } else {
            // Fall back to /Applications so they can see the app to drag
            let appPath = "/Applications/Open in Claude Code.app"
            if FileManager.default.fileExists(atPath: appPath) {
                NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "/Applications")
            } else {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
            }
        }
        
        // Give Finder time to open before we exit
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // Escape path for use in AppleScript strings
    func escapeForAppleScript(_ path: String) -> String {
        return path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    func setFolderOrange(_ path: String) {
        let safePath = escapeForAppleScript(path)
        // Orange is label index 1 in Finder (0=none, 1=orange, 2=red, 3=yellow, etc.)
        let script = """
        tell application "Finder"
            set theFolder to POSIX file "\(safePath)" as alias
            set label index of theFolder to 1
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
    
    func addToFinderSidebar(_ path: String) {
        let safePath = escapeForAppleScript(path)
        // URL-encode the path for file:// URLs
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return
        }
        
        var sidebarAdded = false
        
        // Try sfltool first (macOS built-in, but may not work on all versions)
        let sfltool = Process()
        sfltool.launchPath = "/usr/bin/sfltool"
        sfltool.arguments = ["add-item", "com.apple.LSSharedFileList.FavoriteItems", "file://\(encodedPath)"]
        sfltool.standardOutput = FileHandle.nullDevice
        sfltool.standardError = FileHandle.nullDevice
        do {
            try sfltool.run()
            sfltool.waitUntilExit()
            if sfltool.terminationStatus == 0 {
                sidebarAdded = true
            }
        } catch {}
        
        // Try mysides if sfltool failed
        if !sidebarAdded {
            let mysides = Process()
            mysides.launchPath = "/bin/sh"
            mysides.arguments = ["-c", "command -v mysides && mysides add 'Claude' 'file://\(encodedPath)'"]
            mysides.standardOutput = FileHandle.nullDevice
            mysides.standardError = FileHandle.nullDevice
            do {
                try mysides.run()
                mysides.waitUntilExit()
                if mysides.terminationStatus == 0 {
                    sidebarAdded = true
                }
            } catch {}
        }
        
        // Open a Finder window to the folder regardless
        let script = """
        tell application "Finder"
            set theFolder to POSIX file "\(safePath)" as alias
            try
                make new Finder window
                set target of front Finder window to theFolder
            end try
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        
        // Inform user if sidebar addition failed
        if !sidebarAdded {
            // Don't block, just note it - folder still created
            NSLog("Could not add folder to Finder sidebar. Install 'mysides' with: brew install mysides")
        }
    }
    
    func getFinderPath() -> String? {
        guard let finder = SBApplication(bundleIdentifier: "com.apple.finder") as FinderApplication? else {
            return nil
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
        
        return nil
    }
    
    @objc func showTrustedDirectoriesDialog() {
        NSApp.activate(ignoringOtherApps: true)
        
        let directories = ClaudeConfig.getTrustedDirectories()
        
        if directories.isEmpty {
            showAlert(title: "No Trusted Directories", 
                      message: "No directories have been trusted by Claude Code yet.\n\nDirectories are added when you run Claude Code in a folder for the first time.")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Trusted Directories"
        alert.informativeText = "Select a directory to remove it from Claude's trusted list.\n\nThis will require re-trusting the directory next time you use Claude Code there."
        alert.alertStyle = .informational
        
        // Create scroll view with table
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 20
        tableView.allowsMultipleSelection = false
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.width = 380
        tableView.addTableColumn(column)
        
        // Create data source
        class DirectoryDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
            var directories: [String]
            
            init(directories: [String]) {
                self.directories = directories
            }
            
            func numberOfRows(in tableView: NSTableView) -> Int {
                return directories.count
            }
            
            func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
                return directories[row]
            }
            
            func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
                let cell = NSTextField(labelWithString: directories[row])
                cell.lineBreakMode = .byTruncatingMiddle
                cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                return cell
            }
        }
        
        let dataSource = DirectoryDataSource(directories: directories)
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        
        scrollView.documentView = tableView
        alert.accessoryView = scrollView
        
        alert.addButton(withTitle: "Remove Selected")
        alert.addButton(withTitle: "Done")
        
        // Keep showing the dialog until user clicks Done
        var shouldContinue = true
        while shouldContinue {
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                let selectedRow = tableView.selectedRow
                if selectedRow >= 0 && selectedRow < dataSource.directories.count {
                    let pathToRemove = dataSource.directories[selectedRow]
                    
                    // Confirm removal
                    let confirmAlert = NSAlert()
                    confirmAlert.messageText = "Remove Directory?"
                    confirmAlert.informativeText = "Remove '\(pathToRemove)' from Claude's trusted directories?\n\nYou'll need to re-trust it next time you run Claude Code there."
                    confirmAlert.addButton(withTitle: "Remove")
                    confirmAlert.addButton(withTitle: "Cancel")
                    confirmAlert.alertStyle = .warning
                    
                    if confirmAlert.runModal() == .alertFirstButtonReturn {
                        if ClaudeConfig.removeDirectory(pathToRemove) {
                            // Update the list
                            dataSource.directories.remove(at: selectedRow)
                            tableView.reloadData()
                            
                            if dataSource.directories.isEmpty {
                                showAlert(title: "All Directories Removed", 
                                          message: "No more trusted directories.")
                                shouldContinue = false
                            }
                        } else {
                            showAlert(title: "Error", message: "Could not remove directory from ~/.claude.json")
                        }
                    }
                } else {
                    showAlert(title: "No Selection", message: "Please select a directory to remove.")
                }
            } else {
                shouldContinue = false
            }
        }
    }
    
    func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
