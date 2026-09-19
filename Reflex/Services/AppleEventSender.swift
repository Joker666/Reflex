import AppKit
import CoreServices
import Foundation

enum AppleEventSender {
    private static let textTypes: Set<DescType> = [
        DescType(typeUnicodeText),
        DescType(typeUTF8Text),
        DescType(typeApplicationBundleID),
        DescType(typeChar)
    ]

    static func bundleIdentifier(
        from event: NSAppleEventDescriptor?,
        bundleIdentifierForPID: (pid_t) -> String? = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    ) -> String? {
        guard let event else { return nil }

        if let pidDesc = event.attributeDescriptor(forKeyword: keySenderPIDAttr),
           let pid = processIdentifier(from: pidDesc),
           pid > 0,
           let bundleID = bundleIdentifierForPID(pid) {
            return bundleID
        }

        if let auditDesc = event.attributeDescriptor(forKeyword: keySenderAuditTokenAttr),
           auditDesc.data.count == MemoryLayout<audit_token_t>.size {
            let token = auditDesc.data.withUnsafeBytes { $0.load(as: audit_token_t.self) }
            let pid = pid_t(token.val.5)
            if pid > 0, let bundleID = bundleIdentifierForPID(pid) {
                return bundleID
            }
        }

        for keyword in [keyAddressAttr, keyOriginalAddressAttr] {
            guard let addrDesc = event.attributeDescriptor(forKeyword: keyword) else { continue }
            if let pid = processIdentifier(from: addrDesc),
               pid > 0,
               let bundleID = bundleIdentifierForPID(pid) {
                return bundleID
            }
            if textTypes.contains(addrDesc.descriptorType),
               let stringValue = addrDesc.stringValue,
               !stringValue.isEmpty {
                return stringValue
            }
        }

        return nil
    }

    private static func processIdentifier(from descriptor: NSAppleEventDescriptor) -> pid_t? {
        if descriptor.descriptorType == DescType(typeKernelProcessID),
           descriptor.data.count >= MemoryLayout<pid_t>.size {
            return descriptor.data.withUnsafeBytes { $0.load(as: pid_t.self) }
        }
        let intVal = descriptor.int32Value
        if intVal > 0 {
            return pid_t(intVal)
        }
        return nil
    }
}
