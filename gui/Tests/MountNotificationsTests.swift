import Testing
@testable import NtfsmacGUI

@MainActor
private final class RecordingNotificationScheduler: LocalNotificationScheduling {
    private(set) var payloads: [MountNotificationPayload] = []
    func schedule(_ payload: MountNotificationPayload) { payloads.append(payload) }
}

@Test func notificationCopyNeverIncludesRawHelperOutput() {
    let payload = MountNotificationCopy.payload(
        for: .failed(action: .mount, volumeName: "MEDIA")
    )

    #expect(payload.title == "Mount failed")
    #expect(payload.body == "MEDIA needs attention. Open ntfsmac for details.")
}

@Test func ejectAllNotificationSummarizesPartialResults() {
    let payload = MountNotificationCopy.payload(for: .ejectAll(succeeded: 1, total: 3))

    #expect(payload.title == "Eject All needs attention")
    #expect(payload.body.contains("1 of 3"))
}

@MainActor
@Test func notifierSchedulesOnlyWhenTheUserPreferenceIsEnabled() {
    var enabled = false
    let scheduler = RecordingNotificationScheduler()
    let notifier = MountEventNotifier(isEnabled: { enabled }, scheduler: scheduler)

    notifier.post(.mounted(volumeName: "MEDIA", readOnly: false))
    #expect(scheduler.payloads.isEmpty)

    enabled = true
    notifier.post(.unmounted(volumeName: "MEDIA"))
    #expect(scheduler.payloads == [MountNotificationPayload(
        title: "Drive unmounted",
        body: "MEDIA can be disconnected safely."
    )])
}
