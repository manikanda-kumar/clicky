//
//  NativeMacOSAutomationProvider.swift
//  leanring-buddy
//
//  Accessibility-backed inspection of the current macOS UI state.
//

import AppKit
import ApplicationServices
import Foundation

final class NativeMacOSAutomationProvider: ClickyAutomationProvider {
    @MainActor
    func inspectCurrentContext() async -> ClickyAutomationContextSnapshot? {
        guard WindowPositionManager.hasAccessibilityPermission() else { return nil }
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }

        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)

        let appSnapshot = ClickyAutomationApplicationSnapshot(
            bundleIdentifier: frontmostApplication.bundleIdentifier,
            localizedName: frontmostApplication.localizedName ?? "unknown",
            processIdentifier: frontmostApplication.processIdentifier
        )

        let focusedElement = readFocusedElement(from: applicationElement)
        let menuBarItems = readMenuItems(from: applicationElement, attributeName: kAXMenuBarAttribute as CFString)
        let mainMenuItems = readMenuItems(from: applicationElement, attributeName: kAXChildrenAttribute as CFString)

        return ClickyAutomationContextSnapshot(
            frontmostApplication: appSnapshot,
            focusedElement: focusedElement,
            menuBarItems: menuBarItems,
            mainMenuItems: mainMenuItems
        )
    }

    private func readFocusedElement(from applicationElement: AXUIElement) -> ClickyAutomationElementSnapshot? {
        guard let rawFocusedElement = copyAttributeValue(
            from: applicationElement,
            attributeName: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }

        return makeElementSnapshot(from: rawFocusedElement as! AXUIElement)
    }

    private func readMenuItems(
        from applicationElement: AXUIElement,
        attributeName: CFString
    ) -> [ClickyAutomationElementSnapshot] {
        guard let rawMenuBarElement = copyAttributeValue(from: applicationElement, attributeName: attributeName) else {
            return []
        }

        if CFGetTypeID(rawMenuBarElement) == AXUIElementGetTypeID() {
            return readChildElements(from: rawMenuBarElement as! AXUIElement)
        }

        if let menuBarElements = rawMenuBarElement as? [Any] {
            return menuBarElements.compactMap { element in
                guard CFGetTypeID(element as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
                return makeElementSnapshot(from: element as! AXUIElement)
            }
        }

        return []
    }

    private func readChildElements(from parentElement: AXUIElement) -> [ClickyAutomationElementSnapshot] {
        guard let children = copyAttributeValue(from: parentElement, attributeName: kAXChildrenAttribute as CFString) as? [Any] else {
            return []
        }

        return children.compactMap { element in
            guard CFGetTypeID(element as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return makeElementSnapshot(from: element as! AXUIElement)
        }
    }

    private func makeElementSnapshot(from element: AXUIElement) -> ClickyAutomationElementSnapshot? {
        let role = copyStringAttribute(from: element, attributeName: kAXRoleAttribute as CFString)
        let title = copyStringAttribute(from: element, attributeName: kAXTitleAttribute as CFString)
        let value = copyStringAttribute(from: element, attributeName: kAXValueAttribute as CFString)
        let help = copyStringAttribute(from: element, attributeName: kAXHelpAttribute as CFString)
        let identifier = copyStringAttribute(from: element, attributeName: kAXIdentifierAttribute as CFString)
        let frame = copyFrameAttribute(from: element)

        guard role != nil || title != nil || value != nil || help != nil || identifier != nil || frame != nil else {
            return nil
        }

        return ClickyAutomationElementSnapshot(
            role: role,
            title: title,
            value: value,
            help: help,
            identifier: identifier,
            frame: frame
        )
    }

    private func copyStringAttribute(from element: AXUIElement, attributeName: CFString) -> String? {
        guard let value = copyAttributeValue(from: element, attributeName: attributeName) else {
            return nil
        }

        if let stringValue = value as? String {
            let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        }

        return nil
    }

    private func copyFrameAttribute(from element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let rawPositionValue = positionValue,
              let rawSizeValue = sizeValue else {
            return nil
        }

        let resolvedPosition = rawPositionValue as! AXValue
        let resolvedSize = rawSizeValue as! AXValue

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(resolvedPosition, .cgPoint, &point),
              AXValueGetValue(resolvedSize, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    private func copyAttributeValue(from element: AXUIElement, attributeName: CFString) -> AnyObject? {
        var rawValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attributeName, &rawValue) == .success else {
            return nil
        }
        return rawValue
    }
}
