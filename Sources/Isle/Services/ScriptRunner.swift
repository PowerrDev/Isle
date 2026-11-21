/*
 *  ScriptRunner.swift
 *  Isle
 *
 *  Executes AppleScript commands against media players. Scripts with fixed
 *  source are compiled once and reused, which avoids recompiling on every play,
 *  pause, or skip.
 */

import Foundation

final class ScriptRunner {

    private var compiled: [String: NSAppleScript] = [:]

    /**
     Runs `source` and returns its result.

     - Parameter cacheable: Pass `false` for scripts that embed varying values,
       such as a seek position, so the cache stays small.
     */
    @discardableResult
    func run(_ source: String, cacheable: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript?
        if cacheable, let cached = compiled[source] {
            script = cached
        } else {
            script = NSAppleScript(source: source)
            script?.compileAndReturnError(nil)
            if cacheable { compiled[source] = script }
        }

        var error: NSDictionary?
        return script?.executeAndReturnError(&error)
    }
}
