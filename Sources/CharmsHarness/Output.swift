import Foundation

/// Every command answers with one JSON object on one line, so a shell
/// script can read it without parsing prose.
enum Output {
    static func emit(_ object: [String: Any]) -> Never {
        print(encode(object))
        exit(0)
    }

    static func fail(_ message: String) -> Never {
        print(encode(["error": message]))
        exit(1)
    }

    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"unencodable result\"}"
        }
        return text
    }

    static func usage() -> Never {
        FileHandle.standardError.write(Data(Self.usageText.utf8))
        exit(2)
    }

    private static let usageText = """
        usage: CharmsHarness <command> [options]

          host [--x N --y N] [--width N --height N] [--text S]
              A window with a text view ("editor"), a text field ("field") and a
              password field ("secret"). Prints {"pid", "ready"} and keeps running.
          send --op state|setText|select|focus|undo|activate|move|selectionDelay
               [--text S] [--location N --length N] [--target editor|field|secret]
               [--x N --y N] [--ms N] [--timeout seconds]
              Asks the running host to do something and prints its state.
              selectionDelay makes the editor apply a selection set through
              Accessibility N ms late, or never when N is negative; with
              --target field the text field takes the keyboard meanwhile.
          type --text S [--gap-ms N]
              Types the text as Unicode key events, one character at a time.
          key --name return|enter|tab|space|delete|escape|left|right|up|down
              [--control] [--option] [--shift] [--command] [--hold-ms N]
          hotkey --code N [--control] [--option] [--shift] [--command]
              Presses the key with that virtual key code.
          mouse --x N --y N        Moves the pointer (top-left global coordinates).
          click --x N --y N        Clicks the left button there.
          focused                  The focused element of the frontmost application.
          frontmost                The frontmost application.
          windows --pid N          That process's windows on screen, front to back.
          displays                 The displays and the pointer position.
          pasteboard [--set S]     The general pasteboard's string and change count.

        Every command prints one JSON object. Exit status: 0 success, 1 failure
        ({"error": ...}), 2 usage.

        """
}

/// `--name value` options and bare `--flag` switches.
struct Arguments {
    private static let switches: Set<String> = ["control", "option", "shift", "command"]
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ arguments: [String]) {
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else { Output.usage() }
            let name = String(argument.dropFirst(2))
            if Self.switches.contains(name) {
                flags.insert(name)
                continue
            }
            guard let value = rest.popFirst() else { Output.usage() }
            values[name] = value
        }
    }

    func string(_ name: String) -> String? { values[name] }
    func has(_ name: String) -> Bool { flags.contains(name) }

    func number(_ name: String) -> Double? {
        guard let text = values[name] else { return nil }
        guard let number = Double(text) else { Output.usage() }
        return number
    }

    func required(_ name: String) -> String {
        guard let value = values[name] else { Output.usage() }
        return value
    }
}
