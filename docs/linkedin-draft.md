I kept running into a small annoyance at my desk: looking at my other screen, starting to type, and realizing the keyboard focus was still on the first one.

So I built LookFocus, an experimental macOS app that follows head direction between calibrated screens and brings the target window forward.

It uses Apple Vision locally. Camera frames stay in memory—there is no upload or cloud inference. I also added multiple posture samples, a work-monitor setting that keeps the camera off at home, and an optional battery saver.

The most useful addition during development was a simple indicator showing which screen it thought I was facing and why a switch was being held. It made missed switches much easier to investigate.

It is still an experiment: accuracy needs more work, and the 150 ms setting is a hold time, not a measured total switching latency.

Inspired by GlanceSwitch, implemented independently in Swift. I’m sharing the source so others can explore it and help improve it.

GitHub: https://github.com/KareemDa/LookFocus

#macOS #Swift #ComputerVision #OpenSource
