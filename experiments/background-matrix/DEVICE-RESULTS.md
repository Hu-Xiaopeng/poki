# Stripped Lab iPhone run

The **safety gate did not pass**, so the four background fixture trials did not run. The host installed the three development-signed Lab bundles, launched Poki Lab for the safety check, and never received a ready state within 10 seconds. That is consistent with an iOS authorization prompt, a Lab startup or session failure, or a container-read problem. It does not establish which occurred. No consent was answered, and the run was not retried.

| Run | Result |
| --- | --- |
| Device | iPhone 17 Pro, iOS 27.3 (24C5037i), wired, Developer Mode enabled |
| Tested build | `0918cbcf`, stripped Debug, signed with existing local Xcode profiles |
| Elapsed | 24.72 seconds for host preflight, installation, run attempt, and removal |
| Local Stop and session close | Not verified. The launch was observed, but the safety-ready phase and session invalidation were not. |
| UIKit read, bar-button activate, field set, plain UIButton refusal | Not reached. The host did not launch either fixture or enter the action lane. |
| Delivery, action timing, foreground witness and Sentinel input | Not measured. The JSONL export had zero rows. |
| Automation Running watermark | Unconfirmed. The run produced no system AX observation and took no physical-device screenshot. |
| Live Activity | Not applicable to this build. The stripped Lab has no widget or App Group. |
| Cleanup | All three uninstall commands succeeded. A follow-up query for each of the three exact bundle IDs confirmed it was absent. |

No ordinary Poki bundle, private content, system settings, or signing registrations were modified. This run provides no physical-device compatibility or indicator-clearance result and does not support shipping background control.

## Simulator verification

All six Swift and seven Python matrix tests passed. The existing eight-case UIKit simulator smoke recorded four verified operations and four unsupported operations. All eight rows had sampled foreground evidence, zero sampled switches, and no sampled unexpected Sentinel input. The stripped Lab rendered the local controls with the runtime opt-in off and no probe state at launch. Its opt-in simulator safety check subsequently reached ready, accepted the host Stop signal, and exported a verified cleanup row with no action sent.
