#!/usr/bin/env swift
// Prints the CoreGraphics window id of the main on-screen window owned by a process,
// so `screencapture -l<id>` can capture that window alone, in the background.
//
// Usage:  window-id.swift <pid> [<expected-bundle-id>]
// Output: "<windowID> <width> <height>" (points) on stdout, exit 0
// Exit:   1 no window yet, 2 bad arguments, 3 the pid is not the expected bundle id
//
// Matches by pid, then checks the bundle id with NSRunningApplication. Neither call
// needs Screen Recording permission (window *titles* would, so they are not used).
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 2, let pid = Int32(args[1]) else {
    FileHandle.standardError.write(Data("usage: window-id.swift <pid> [<bundle-id>]\n".utf8))
    exit(2)
}

if args.count >= 3 {
    let actual = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    guard actual == args[2] else {
        FileHandle.standardError.write(Data("pid \(pid) is \(actual ?? "unknown"), expected \(args[2])\n".utf8))
        exit(3)
    }
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }

var best: (id: Int, width: Double, height: Double)?
for window in list {
    guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let width = bounds["Width"], let height = bounds["Height"],
          width >= 200, height >= 200 else { continue }
    if best == nil || width * height > best!.width * best!.height {
        best = (id, width, height)
    }
}

guard let best else { exit(1) }
print("\(best.id) \(Int(best.width)) \(Int(best.height))")
