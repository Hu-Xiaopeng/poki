# Poki Lab background matrix results

Measured on the iPhone 17 Pro Simulator, iOS 27.3 (24C5049d), with Xcode 27.3 (27C5035i). Poki Lab and AXFixture were built from [`c3c52532`](https://github.com/JosssphZhou/poki/commit/c3c52532bc852e1d3c4dad496f4b3fb0edee8ecf), based on main at `e6b35b0e`. The optional Flutter 3.50.1, Compose Multiplatform 1.12.2 and React Native 0.88.1 fixtures built unmodified from [`523e13b2`](https://github.com/JosssphZhou/poki/commit/523e13b265007dd3322500f17014829ce421b94b). Nine suites ran on three dedicated simulators, five fresh trials per cell, for **130 rows in 26 cells**. No physical device, iPad, Apple account, model, network connector or MCP session was used.

- **Verified, 50 rows.** Each passed 5/5: UIKit background read, bar item, field set, scroll and back; SwiftUI button; Flutter read; React Native read, explicit accessibility tap and field set. A field set is not a submit.
- **Unsupported or safely blocked, 45 rows.** Plain UIKit button, switch and Return, and React Native's plain Pressable and tab all returned explicit AX refusal rather than falling back to touch. Live screenshot was refused by design. The unseen target was never launched, and the unasserted control's background tree was unavailable. WebKit's button had a foreground baseline but failed the target-bound AX reference check in all five background trials, before dispatch. This reports a route refusal, not proof that WebKit has no background capabilities.
- **Unverified, 15 rows.** Flutter button, tab and field calls returned a reply but didn't show their expected AX readback. The harness didn't retry or claim a handler fired.
- **Not applicable, 20 rows.** Compose installed and launched, but Lab could not confirm the expected foreground AX marker in any of five staging trials. All four Compose cells recorded that stop reason with no dispatch. This is inconclusive about Compose background support; the next useful comparison is a foreground snapshot via the standalone XCTest probe.
- **Foreground evidence.** All 105 fully witnessed rows observed zero switches and zero unexpected sentinel input. Five controls had partial witness coverage and 20 had none. This is sampled evidence from an idle synthetic sentinel, not proof against transient switches or concurrent physical use. The OS watermark and Live Activity were not measured. These results do not qualify a physical or production build.

Six Swift package tests passed, seven aggregator tests passed, and the enabled Poki Lab, AXFixture and sentinel simulator builds succeeded. A Lab launch without the opt-in created no probe state. A separate simulator run started with Stop set and returned eight cancellations, all before opening the session or dispatching. Neither ordinary project spec nor the release workflows or PokiCore MCP code wires in the experiment.

The tables below were generated from the normalized JSONL. Timings are simulator wall duration measured with a monotonic clock; staging includes authorization and foreground fixture checks and is recorded only on the first cell in a trial. Raw rows and simulator logs are not committed.

## Background matrix summary

Attempts: 130

Timings are in milliseconds; p50 and p95 use nearest rank over non-null samples.
Witnessed attempts have sampled telemetry and both switch and sentinel observations.
Sampling does not establish continuous monitoring.
Switches are observed transitions, not attributed to the tool; sentinel counts are attempts reporting unexpected input.

### iphone-simulator / OS 24C5049d / build c3c52532bc852e1d3c4dad496f4b3fb0edee8ecf

| Cell | Route | App | Control | Operation | Scenario | Case | Attempts | Verified | Witnessed | Outcomes | Delivery | Verification | Error reasons |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | lab\_ax | ax\_fixture | bar\_item | activate | warm\_asserted\_other\_app\_front | uikit-bar | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 2 | lab\_ax | ax\_fixture | controls | look | unseen | unseen-read | 5 | 0/5 | 5/5 | blocked: 5 | not\_sent: 5 | not\_applicable: 5 | target\_not\_seen: 5 |
| 3 | lab\_ax | ax\_fixture | controls | look | warm\_asserted\_other\_app\_front | uikit-read | 5 | 5/5 | 5/5 | verified: 5 | not\_sent: 5 | matched: 5 | — |
| 4 | lab\_ax | ax\_fixture | controls | look | warm\_unasserted\_other\_app\_front | unasserted-read | 5 | 0/5 | 0/5 | blocked: 5 | not\_sent: 5 | not\_applicable: 5 | ax\_unavailable: 5 |
| 5 | lab\_ax | ax\_fixture | display | screenshot | warm\_asserted\_other\_app\_front | uikit-screenshot | 5 | 0/5 | 5/5 | unsupported: 5 | not\_sent: 5 | not\_applicable: 5 | live\_screenshot\_unsupported: 5 |
| 6 | lab\_ax | ax\_fixture | native\_switch | activate | warm\_asserted\_other\_app\_front | uikit-switch | 5 | 0/5 | 5/5 | unsupported: 5 | sent: 5 | not\_applicable: 5 | ax\_action\_refused: 5 |
| 7 | lab\_ax | ax\_fixture | navigation\_bar | back | warm\_asserted\_other\_app\_front | uikit-back | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 8 | lab\_ax | ax\_fixture | plain\_button | activate | warm\_asserted\_other\_app\_front | uikit-plain | 5 | 0/5 | 5/5 | unsupported: 5 | sent: 5 | not\_applicable: 5 | ax\_action\_refused: 5 |
| 9 | lab\_ax | ax\_fixture | swiftui\_button | activate | warm\_asserted\_other\_app\_front | swiftui-button | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 10 | lab\_ax | ax\_fixture | table | scroll | warm\_asserted\_other\_app\_front | uikit-scroll | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 11 | lab\_ax | ax\_fixture | text\_field | set | warm\_asserted\_other\_app\_front | uikit-set | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 12 | lab\_ax | ax\_fixture | text\_field | submit | warm\_asserted\_other\_app\_front | uikit-return | 5 | 0/5 | 5/5 | unsupported: 5 | sent: 5 | not\_applicable: 5 | ax\_action\_refused: 5 |
| 13 | lab\_ax | ax\_fixture | webkit\_button | activate | warm\_asserted\_other\_app\_front | webkit-button | 5 | 0/5 | 5/5 | safety\_abort: 5 | not\_sent: 5 | unavailable: 5 | stale\_ref: 5 |
| 14 | lab\_ax | compose | button | activate | warm\_asserted\_other\_app\_front | compose-activate | 5 | 0/5 | 0/5 | not\_applicable: 5 | not\_sent: 5 | not\_applicable: 5 | fixture\_baseline\_unconfirmed: 5 |
| 15 | lab\_ax | compose | button | look | warm\_asserted\_other\_app\_front | compose-read | 5 | 0/5 | 0/5 | not\_applicable: 5 | not\_sent: 5 | not\_applicable: 5 | fixture\_baseline\_unconfirmed: 5 |
| 16 | lab\_ax | compose | tab | activate | warm\_asserted\_other\_app\_front | compose-tab | 5 | 0/5 | 0/5 | not\_applicable: 5 | not\_sent: 5 | not\_applicable: 5 | fixture\_baseline\_unconfirmed: 5 |
| 17 | lab\_ax | compose | text\_field | set | warm\_asserted\_other\_app\_front | compose-text | 5 | 0/5 | 0/5 | not\_applicable: 5 | not\_sent: 5 | not\_applicable: 5 | fixture\_baseline\_unconfirmed: 5 |
| 18 | lab\_ax | flutter | button | activate | warm\_asserted\_other\_app\_front | flutter-activate | 5 | 0/5 | 5/5 | unverified: 5 | sent: 5 | no\_expected\_effect: 5 | no\_effect: 5 |
| 19 | lab\_ax | flutter | button | look | warm\_asserted\_other\_app\_front | flutter-read | 5 | 5/5 | 5/5 | verified: 5 | not\_sent: 5 | matched: 5 | — |
| 20 | lab\_ax | flutter | tab | activate | warm\_asserted\_other\_app\_front | flutter-tab | 5 | 0/5 | 5/5 | unverified: 5 | sent: 5 | no\_expected\_effect: 5 | no\_effect: 5 |
| 21 | lab\_ax | flutter | text\_field | set | warm\_asserted\_other\_app\_front | flutter-text | 5 | 0/5 | 5/5 | unverified: 5 | sent: 5 | no\_expected\_effect: 5 | no\_effect: 5 |
| 22 | lab\_ax | react\_native | accessible\_pressable | activate | warm\_asserted\_other\_app\_front | rn-accessible | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |
| 23 | lab\_ax | react\_native | button | look | warm\_asserted\_other\_app\_front | rn-read | 5 | 5/5 | 5/5 | verified: 5 | not\_sent: 5 | matched: 5 | — |
| 24 | lab\_ax | react\_native | plain\_pressable | activate | warm\_asserted\_other\_app\_front | rn-plain | 5 | 0/5 | 5/5 | unsupported: 5 | sent: 5 | not\_applicable: 5 | ax\_action\_refused: 5 |
| 25 | lab\_ax | react\_native | tab | activate | warm\_asserted\_other\_app\_front | rn-tab | 5 | 0/5 | 5/5 | unsupported: 5 | sent: 5 | not\_applicable: 5 | ax\_action\_refused: 5 |
| 26 | lab\_ax | react\_native | text\_field | set | warm\_asserted\_other\_app\_front | rn-text | 5 | 5/5 | 5/5 | verified: 5 | sent: 5 | matched: 5 | — |

| Cell | Stage | Measured | p50 | p95 |
| --- | --- | --- | --- | --- |
| 1 | total | 5/5 | 2055 | 2065 |
| 1 | attach | 0/5 | — | — |
| 1 | dispatch | 5/5 | 105 | 110 |
| 1 | snapshot\_before | 5/5 | 435 | 440 |
| 1 | verify | 5/5 | 868 | 871 |
| 2 | total | 5/5 | 884 | 969 |
| 2 | attach | 5/5 | 3203 | 3383 |
| 2 | dispatch | 0/5 | — | — |
| 2 | snapshot\_before | 0/5 | — | — |
| 2 | verify | 0/5 | — | — |
| 3 | total | 5/5 | 1094 | 1195 |
| 3 | attach | 5/5 | 5817 | 6101 |
| 3 | dispatch | 0/5 | — | — |
| 3 | snapshot\_before | 5/5 | 445 | 546 |
| 3 | verify | 0/5 | — | — |
| 4 | total | 5/5 | 426 | 438 |
| 4 | attach | 5/5 | 5644 | 5883 |
| 4 | dispatch | 0/5 | — | — |
| 4 | snapshot\_before | 5/5 | 110 | 110 |
| 4 | verify | 0/5 | — | — |
| 5 | total | 5/5 | 640 | 652 |
| 5 | attach | 0/5 | — | — |
| 5 | dispatch | 0/5 | — | — |
| 5 | snapshot\_before | 0/5 | — | — |
| 5 | verify | 0/5 | — | — |
| 6 | total | 5/5 | 1511 | 1521 |
| 6 | attach | 0/5 | — | — |
| 6 | dispatch | 5/5 | 109 | 112 |
| 6 | snapshot\_before | 5/5 | 431 | 445 |
| 6 | verify | 0/5 | — | — |
| 7 | total | 5/5 | 2040 | 2052 |
| 7 | attach | 5/5 | 5208 | 7451 |
| 7 | dispatch | 5/5 | 319 | 327 |
| 7 | snapshot\_before | 5/5 | 111 | 112 |
| 7 | verify | 5/5 | 967 | 981 |
| 8 | total | 5/5 | 1519 | 1525 |
| 8 | attach | 0/5 | — | — |
| 8 | dispatch | 5/5 | 109 | 111 |
| 8 | snapshot\_before | 5/5 | 440 | 444 |
| 8 | verify | 0/5 | — | — |
| 9 | total | 5/5 | 1403 | 1414 |
| 9 | attach | 5/5 | 5443 | 5532 |
| 9 | dispatch | 5/5 | 109 | 111 |
| 9 | snapshot\_before | 5/5 | 110 | 111 |
| 9 | verify | 5/5 | 538 | 547 |
| 10 | total | 5/5 | 2055 | 2067 |
| 10 | attach | 0/5 | — | — |
| 10 | dispatch | 5/5 | 107 | 111 |
| 10 | snapshot\_before | 5/5 | 431 | 437 |
| 10 | verify | 5/5 | 869 | 875 |
| 11 | total | 5/5 | 2058 | 2067 |
| 11 | attach | 0/5 | — | — |
| 11 | dispatch | 5/5 | 112 | 112 |
| 11 | snapshot\_before | 5/5 | 434 | 443 |
| 11 | verify | 5/5 | 872 | 877 |
| 12 | total | 5/5 | 1519 | 1530 |
| 12 | attach | 0/5 | — | — |
| 12 | dispatch | 5/5 | 110 | 113 |
| 12 | snapshot\_before | 5/5 | 430 | 437 |
| 12 | verify | 0/5 | — | — |
| 13 | total | 5/5 | 1075 | 1094 |
| 13 | attach | 5/5 | 6448 | 6777 |
| 13 | dispatch | 5/5 | 1 | 2 |
| 13 | snapshot\_before | 5/5 | 107 | 111 |
| 13 | verify | 0/5 | — | — |
| 14 | total | 0/5 | — | — |
| 14 | attach | 0/5 | — | — |
| 14 | dispatch | 0/5 | — | — |
| 14 | snapshot\_before | 0/5 | — | — |
| 14 | verify | 0/5 | — | — |
| 15 | total | 0/5 | — | — |
| 15 | attach | 5/5 | 14728 | 15255 |
| 15 | dispatch | 0/5 | — | — |
| 15 | snapshot\_before | 0/5 | — | — |
| 15 | verify | 0/5 | — | — |
| 16 | total | 0/5 | — | — |
| 16 | attach | 0/5 | — | — |
| 16 | dispatch | 0/5 | — | — |
| 16 | snapshot\_before | 0/5 | — | — |
| 16 | verify | 0/5 | — | — |
| 17 | total | 0/5 | — | — |
| 17 | attach | 0/5 | — | — |
| 17 | dispatch | 0/5 | — | — |
| 17 | snapshot\_before | 0/5 | — | — |
| 17 | verify | 0/5 | — | — |
| 18 | total | 5/5 | 2728 | 2740 |
| 18 | attach | 0/5 | — | — |
| 18 | dispatch | 5/5 | 109 | 111 |
| 18 | snapshot\_before | 5/5 | 106 | 111 |
| 18 | verify | 5/5 | 1870 | 1874 |
| 19 | total | 5/5 | 756 | 762 |
| 19 | attach | 5/5 | 5576 | 9463 |
| 19 | dispatch | 0/5 | — | — |
| 19 | snapshot\_before | 5/5 | 111 | 111 |
| 19 | verify | 0/5 | — | — |
| 20 | total | 5/5 | 2715 | 2744 |
| 20 | attach | 0/5 | — | — |
| 20 | dispatch | 5/5 | 107 | 109 |
| 20 | snapshot\_before | 5/5 | 109 | 111 |
| 20 | verify | 5/5 | 1858 | 1876 |
| 21 | total | 5/5 | 2721 | 2738 |
| 21 | attach | 0/5 | — | — |
| 21 | dispatch | 5/5 | 106 | 111 |
| 21 | snapshot\_before | 5/5 | 107 | 111 |
| 21 | verify | 5/5 | 1861 | 1880 |
| 22 | total | 5/5 | 1393 | 1403 |
| 22 | attach | 0/5 | — | — |
| 22 | dispatch | 5/5 | 110 | 111 |
| 22 | snapshot\_before | 5/5 | 106 | 112 |
| 22 | verify | 5/5 | 532 | 542 |
| 23 | total | 5/5 | 763 | 767 |
| 23 | attach | 5/5 | 5328 | 5411 |
| 23 | dispatch | 0/5 | — | — |
| 23 | snapshot\_before | 5/5 | 111 | 111 |
| 23 | verify | 0/5 | — | — |
| 24 | total | 5/5 | 1180 | 1194 |
| 24 | attach | 0/5 | — | — |
| 24 | dispatch | 5/5 | 107 | 108 |
| 24 | snapshot\_before | 5/5 | 110 | 111 |
| 24 | verify | 0/5 | — | — |
| 25 | total | 5/5 | 1183 | 1186 |
| 25 | attach | 0/5 | — | — |
| 25 | dispatch | 5/5 | 107 | 111 |
| 25 | snapshot\_before | 5/5 | 108 | 110 |
| 25 | verify | 0/5 | — | — |
| 26 | total | 5/5 | 1407 | 1410 |
| 26 | attach | 0/5 | — | — |
| 26 | dispatch | 5/5 | 109 | 111 |
| 26 | snapshot\_before | 5/5 | 111 | 111 |
| 26 | verify | 5/5 | 536 | 544 |

| Cell | Expected foreground | Telemetry | Switch coverage | Switches | Attempts with switches | Sentinel coverage | Attempts with unexpected input |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 2 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 3 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 4 | matrix\_sentinel: 5 | incomplete: 5 | 5/5 | 0 | 0 | 0/5 | — |
| 5 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 6 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 7 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 8 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 9 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 10 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 11 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 12 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 13 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 14 | matrix\_sentinel: 5 | not\_measured: 5 | 0/5 | — | — | 0/5 | — |
| 15 | matrix\_sentinel: 5 | not\_measured: 5 | 0/5 | — | — | 0/5 | — |
| 16 | matrix\_sentinel: 5 | not\_measured: 5 | 0/5 | — | — | 0/5 | — |
| 17 | matrix\_sentinel: 5 | not\_measured: 5 | 0/5 | — | — | 0/5 | — |
| 18 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 19 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 20 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 21 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 22 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 23 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 24 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 25 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
| 26 | matrix\_sentinel: 5 | sampled: 5 | 5/5 | 0 | 0 | 5/5 | 0 |
