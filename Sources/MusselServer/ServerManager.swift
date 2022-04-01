// Copyright © 2021 Compass. All rights reserved.

import Foundation

typealias JSON = [String: Any]

class ServerManager {
    private let server = HttpServer()
    private let pushEndpoint = "/simulatorPush"
    private let universalLinkEndpoint = "/simulatorUniversalLink"
    private let uninstallAppEndpoint = "/simulatorUninstallApp"

    public func startServer() {
        do {
            try server.start(10004)
            setupPushEndpoint()
            setupUniversalLinkEndpoint()
            setupUninstallAppEndpoint()
            setupEraseEndpoint()
            setupBootEndpoint()
            setupShutdownEndpoint()
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
                let command = "xcrun simctl push \(simId) \(appBundleId) \(pushFileUrl.path)"
                self?.run(command: command)

                do {
                    try FileManager.default.removeItem(at: pushFileUrl)
                } catch {
                    print("Error removing file!")
                }

                let result = self?.run(command: command)
                let responseInfo = "Ran command: \(command) \n Result:\n \(result ?? "Empty result")"
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

            let command = "xcrun simctl openurl \(simId) \"\(universalLink)\""
            let result = self?.run(command: command)
            let responseInfo = "Ran command: \(command) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[universalLinkEndpoint] = response
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

            let command = "xcrun simctl uninstall \(simId) \(appBundleId)"
            let result = self?.run(command: command)
            let responseInfo = "Ran command: \(command) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[uninstallAppEndpoint] = response
    }
    
    private func setupShutdownEndpoint() {
        executeCommand(command: "shutdown", endpoint: "/simulatorShutdown")
    }
    
    private func setupBootEndpoint() {
        executeCommand(command: "boot", endpoint: "/simulatorBoot")
    }
    
    private func setupEraseEndpoint() {
        executeCommand(command: "erase", endpoint: "/simulatorEraseDevice")
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
    
    private func executeCommand(command: String, endpoint: String) {
        let response: ((HttpRequest) -> HttpResponse) = { [weak self] request in
            guard let serializedObject = try? JSONSerialization.jsonObject(with: Data(request.body), options: []),
                  let json = serializedObject as? JSON,
                  let simId = json["simulatorId"] as? String
            else {
                return HttpResponse.badRequest(nil)
            }

            let command = "xcrun simctl \(command) \(simId)"
            let result = self?.run(command: command)
            let responseInfo = "Ran command: \(command) \n Result:\n \(result ?? "Empty result")"
            print(responseInfo)
            return .ok(.text(responseInfo))
        }

        server.POST[endpoint] = response
    }

    @discardableResult func run(command: String) -> String {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", String(format: "%@", command)]
        task.standardOutput = pipe
        let file = pipe.fileHandleForReading
        task.launch()
        if let result = NSString(data: file.readDataToEndOfFile(), encoding: String.Encoding.utf8.rawValue) {
            print(result as String)
            return result as String
        } else {
            let errorString = "--- Error running command - Unable to initialize string from file data ---"
            print(errorString)
            return errorString
        }
    }
}
