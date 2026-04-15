//
//  AppDelegate.swift
//  View
//
//  Created by Rainux Luo on 2026/4/15.
//

import Cocoa
import ViewCore

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("ViewCore version: %@", ViewCore.version)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
