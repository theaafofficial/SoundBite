import SwiftUI
import AppKit

@main
struct SoundBiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var musicService: MusicService!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Core Service
        self.musicService = MusicService()
        // Provide visibility check to prevent background UI thrashes
        self.musicService.isUIVisible = { [weak self] in
            return self?.popover?.isShown ?? false
        }
        
        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 510) 
        popover.behavior = .transient
        // Use a clear background so our VisualEffectView shines through
        popover.contentViewController = NSHostingController(rootView: ContentView(musicService: self.musicService))
        
        // Ensure the hosting view itself is clear
        if let rootView = popover.contentViewController?.view {
            rootView.layer?.backgroundColor = .clear
            rootView.wantsLayer = true
        }
        
        // Make the popover look "native" and glass-like
        popover.animates = true
        self.popover = popover
        
        // Create the menu bar item
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = self.statusItem?.button {
            button.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: "SoundBite")
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        musicService.saveState()
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = self.statusItem?.button, let popover = self.popover else { return }
        
        // Check if it was a right click
        let event = NSApplication.shared.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "SoundBite", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Sign Out", action: #selector(signOutAction), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            // Reset menu after showing so subsequent clicks work normally
            statusItem?.menu = nil
            return
        }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure app is active to receive events
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func signOutAction() {
        musicService.signOut()
    }
}
