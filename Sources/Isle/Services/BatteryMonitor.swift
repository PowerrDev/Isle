/*
 *  BatteryMonitor.swift
 *  Isle
 *
 *  Reports the internal battery's charge and power source. IOKit delivers a
 *  callback whenever the power state changes, so the monitor never polls.
 */

import Foundation
import IOKit.ps

@Observable
final class BatteryMonitor {

    // MARK: State

    private(set) var level = 100
    private(set) var isConnectedToPower = false
    private(set) var isCharging = false
    private(set) var hasBattery = false

    /** Called when the Mac is connected to power after launch. */
    @ObservationIgnored var onConnectToPower: () -> Void = {}

    // MARK: Lifecycle

    init() {
        refresh(notifyingChanges: false)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
                .refresh(notifyingChanges: true)
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    // MARK: Reading Power State

    private func refresh(notifyingChanges: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let wasConnected = isConnectedToPower
            hasBattery = true
            level = description[kIOPSCurrentCapacityKey] as? Int ?? level
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isConnectedToPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            if notifyingChanges, isConnectedToPower, !wasConnected {
                onConnectToPower()
            }
        }
    }
}
