//
//  ClickyAutomationTypes.swift
//  leanring-buddy
//
//  Read-only automation snapshots used by grounding providers.
//

import AppKit
import Foundation

struct ClickyAutomationApplicationSnapshot {
    let bundleIdentifier: String?
    let localizedName: String
    let processIdentifier: pid_t
}

struct ClickyAutomationElementSnapshot {
    let role: String?
    let title: String?
    let value: String?
    let help: String?
    let identifier: String?
    let frame: CGRect?
}

struct ClickyAutomationContextSnapshot {
    let frontmostApplication: ClickyAutomationApplicationSnapshot
    let focusedElement: ClickyAutomationElementSnapshot?
    let menuBarItems: [ClickyAutomationElementSnapshot]
    let mainMenuItems: [ClickyAutomationElementSnapshot]
}

protocol ClickyAutomationProvider: AnyObject {
    func inspectCurrentContext() async -> ClickyAutomationContextSnapshot?
}
