import AppKit

// CharmsHarness: a text host and an input driver for checking the built
// Charms app from a script. See `scripts/e2e.sh`.

let commandLine = CommandLine.arguments.dropFirst()
guard let command = commandLine.first else { Output.usage() }
let arguments = Arguments(Array(commandLine.dropFirst()))

switch command {
case "host":
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let host = Host(arguments: arguments)
        application.delegate = host
        application.setActivationPolicy(.regular)
        signal(SIGTERM) { _ in exit(0) }
        withExtendedLifetime(host) { application.run() }
    }

case "send":
    var request: [String: Any] = ["op": arguments.required("op")]
    for name in ["text", "target"] {
        if let value = arguments.string(name) { request[name] = value }
    }
    for name in ["location", "length"] {
        if let value = arguments.number(name) { request[name] = Int(value) }
    }
    for name in ["x", "y", "ms"] {
        if let value = arguments.number(name) { request[name] = value }
    }
    let reply = Host.send(request, timeout: arguments.number("timeout") ?? 3)
    if let problem = reply["error"] as? String { Output.fail(problem) }
    Output.emit(reply)

case "type":
    let text = arguments.required("text")
    Events.type(text, gapMilliseconds: arguments.number("gap-ms") ?? 20)
    Output.emit(["typed": text.count])

case "key":
    let name = arguments.required("name")
    guard let keyCode = Events.namedKeys[name] else { Output.usage() }
    Events.press(keyCode: keyCode, arguments: arguments, holdMilliseconds: arguments.number("hold-ms") ?? 0)
    Output.emit(["key": name])

case "hotkey":
    guard let code = arguments.number("code"), code >= 0, code < 128 else { Output.usage() }
    Events.press(keyCode: CGKeyCode(code), arguments: arguments)
    Output.emit(["code": Int(code)])

case "mouse", "click":
    guard let x = arguments.number("x"), let y = arguments.number("y") else { Output.usage() }
    let point = CGPoint(x: x, y: y)
    if command == "click" {
        Events.click(at: point)
        Output.emit(["clicked": [x, y]])
    }
    Events.moveMouse(to: point)
    Output.emit(["mouse": [x, y]])

case "focused":
    Output.emit(Inspect.focused())

case "frontmost":
    Output.emit(Inspect.frontmost())

case "windows":
    guard let processID = arguments.number("pid") else { Output.usage() }
    Output.emit(Inspect.windows(ownedBy: Int(processID)))

case "displays":
    Output.emit(Inspect.displays())

case "pasteboard":
    Output.emit(Inspect.pasteboard(setting: arguments.string("set")))

default:
    Output.usage()
}
