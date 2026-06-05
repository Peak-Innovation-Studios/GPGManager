import AppKit
import Foundation

ProcessInfo.processInfo.processName = "GPG Manager"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let isRunningForPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

if !isRunningForPreviews {
    let stdout = FileHandle.standardOutput
    let reader = AssuanLineReader(handle: FileHandle.standardInput)
    let controller = PinentryController()

    let session = AssuanSession(
        read: reader.readLine,
        write: { string in
            if let data = string.data(using: .utf8) {
                try? stdout.write(contentsOf: data)
            }
        },
        handler: controller
    )

    DispatchQueue.global(qos: .userInteractive).async {
        session.run()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

app.run()
