// Copyright © 2021 Compass. All rights reserved.

import Foundation

typealias JSON = [String: Any]

class ServerManager {
    private let server = HttpServer()
    private let pushEndpoint = "/simulatorPush"
    private let universalLinkEndpoint = "/simulatorUniversalLink"
    private let uninstallAppEndpoint = "/simulatorUninstallApp"
    private let overrideStatusBarEndpoint = "/overrideStatusBar"
    private let addmediaEndpoint = "/addmedia"
    private let resetPermissionEndpoint = "/resetPermission"

    public func startServer() {
        do {
            try server.start(10004)
            setupPushEndpoint()
            setupUniversalLinkEndpoint()
            setupUninstallAppEndpoint()
            setupOverrideStatusBarEndpoint()
            setupMediaUploadEndpoint()
            setupResetPermissionEndpoint()
        } catch {
            _ = SocketError.bindFailed(Errno.description()).localizedDescription
            print("Error starting Mussel server")
            print(error)
            print(error.localizedDescription)
        }
    }

    private func setupPushEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String,
                  let appBundleId = json["appBundleId"] as? String,
                  let payload = json["pushPayload"] as? JSON
            else {
                return HttpResponse.badRequest(nil)
            }

            if let pushFileUrl = self?.createTemporaryPushFile(payload: payload) {
                let command = ["xcrun", "simctl", "push", simId, appBundleId, pushFileUrl.path]
                let result = self?.run(command: command, simulatorId: simId)

                do {
                    try FileManager.default.removeItem(at: pushFileUrl)
                } catch {
                    print("Error removing file!")
                }

                let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
                print(responseInfo)
                return .ok(.text(responseInfo))
            } else {
                return .internalServerError
            }
        }

        server.POST[pushEndpoint] = response
    }

    private func setupUniversalLinkEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String,
                  let universalLink = json["link"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = ["xcrun", "simctl", "openurl", simId, universalLink]
            let result = self?.run(command: command, simulatorId: simId)
            let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[universalLinkEndpoint] = response
    }
    
    private func setupResetPermissionEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simulatorId = json["simulatorId"] as? String,
                  let appBundleId = json["appBundleId"] as? String,
                  let permission = json["permission"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = ["xcrun", "simctl", "privacy", simulatorId, "reset", permission, appBundleId]
            let result = self?.run(command: command, simulatorId: simulatorId)
            let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[resetPermissionEndpoint] = response
    }
    
    private func setupMediaUploadEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String,
                  let path = json["path"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = ["xcrun", "simctl", "addmedia", simId, path]
            let result = self?.run(command: command, simulatorId: simId)
            let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[addmediaEndpoint] = response
    }
    
    private func setupOverrideStatusBarEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = ["xcrun", "simctl", "status_bar", simId, "override", "--time", "2007-01-09T09:41:00+01:00"]
            let result = self?.run(command: command, simulatorId: simId)
            let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[overrideStatusBarEndpoint] = response
    }
    
    private func setupUninstallAppEndpoint() {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String,
                  let appBundleId = json["appBundleId"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = ["xcrun", "simctl", "uninstall", simId, appBundleId]
            let result = self?.run(command: command, simulatorId: simId)
            let responseInfo = "Ran command: \(command.joined(separator: " ")) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[uninstallAppEndpoint] = response
    }

    private func createTemporaryPushFile(payload: JSON) -> URL? {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let temporaryFilename = ProcessInfo().globallyUniqueString + ".apns"
        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            try jsonData.write(to: temporaryFileURL, options: .atomic)
        } catch {
            print("Error writing temporary file!")
            return nil
        }
        return temporaryFileURL
    }

    private var testingSetSimulatorIds = Set<String>()
    private let testingSetLock = NSLock()

    @discardableResult func run(command: [String], simulatorId: String? = nil) -> String {
        var effectiveCommand = command
        if let simulatorId, isInTestingSet(simulatorId) {
            effectiveCommand = testingSetVariant(of: command)
        }

        var result = launch(command: effectiveCommand)
        // xcodebuild's parallel-testing simulator clones live in a separate device set
        // that plain simctl cannot see ("Invalid device") — retry against the testing set
        // and remember the simulator so its next commands skip the failing attempt.
        if result.contains("Invalid device"),
           !usesDeviceSet(effectiveCommand) {
            let testingSetCommand = testingSetVariant(of: command)
            print("Retrying with testing device set: \(testingSetCommand.joined(separator: " "))")
            result = launch(command: testingSetCommand)
            if let simulatorId, !result.contains("Invalid device") {
                remember(testingSetSimulatorId: simulatorId)
            }
        }
        return result
    }

    // Positional check: a device set can only appear right after `xcrun simctl`, so argument
    // VALUES that happen to equal "--set" can't be mistaken for the flag.
    private func usesDeviceSet(_ command: [String]) -> Bool {
        command.count >= 3 && command[0] == "xcrun" && command[1] == "simctl" && command[2] == "--set"
    }

    private func testingSetVariant(of command: [String]) -> [String] {
        guard command.count >= 2, command[0] == "xcrun", command[1] == "simctl",
              !usesDeviceSet(command)
        else { return command }
        var variant = command
        variant.insert(contentsOf: ["--set", "testing"], at: 2)
        return variant
    }

    private func isInTestingSet(_ simulatorId: String) -> Bool {
        testingSetLock.lock()
        defer { testingSetLock.unlock() }
        return testingSetSimulatorIds.contains(simulatorId)
    }

    private func remember(testingSetSimulatorId: String) {
        testingSetLock.lock()
        defer { testingSetLock.unlock() }
        // Ephemeral clone UDIDs accumulate in long-lived servers; a stale entry only costs
        // one extra retry, so resetting is safe.
        if testingSetSimulatorIds.count >= 512 {
            testingSetSimulatorIds.removeAll()
        }
        testingSetSimulatorIds.insert(testingSetSimulatorId)
    }

    private func launch(command: [String]) -> String {
        let pipe = Pipe()
        let task = Process()
        // argv execution — request values never pass through a shell, so they can't inject
        // commands. xcrun is addressed by absolute path so a minimal launch PATH can't break it.
        if command.first == "xcrun" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            task.arguments = Array(command.dropFirst())
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = command
        }
        task.standardOutput = pipe
        task.standardError = pipe
        let file = pipe.fileHandleForReading
        do {
            try task.run()
        } catch {
            let errorString = "--- Failed to start command: \(error.localizedDescription) ---"
            print(errorString)
            return errorString
        }
        let output = NSString(data: file.readDataToEndOfFile(), encoding: String.Encoding.utf8.rawValue) as String?
        task.waitUntilExit()

        guard var result = output else {
            let errorString = "--- Error running command - Unable to initialize string from file data ---"
            print(errorString)
            return errorString
        }
        // A failing command would otherwise look like success to callers that don't parse the text
        if task.terminationStatus != 0 {
            let failure = "--- Command failed with exit status \(task.terminationStatus) ---"
            let hasOutput = !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            result = hasOutput ? "\(result)\n\(failure)" : failure
        }
        print(result)
        return result
    }
}
