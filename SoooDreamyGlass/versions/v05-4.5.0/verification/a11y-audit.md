# 4.5.0 accessibility matrix

| Setting | Expected result | Automated evidence |
|---|---|---|
| Dynamic Type standard | Horizontal group label when it fits | `ViewThatFits` first branch |
| Dynamic Type AX1–AX5 | Vertical group label, no clipped badge | AX budget/layout policy tests |
| VoiceOver | Group title + pending count in one element | Explicit label/value |
| Reduce Motion | No particle timeline; static glow | particle budget returns zero |
| Differentiate Without Color | ✓/× avatar status; ellipsis while connecting | symbolic alternate branches |
| Narrow 320pt width | Vertical layout policy | threshold test |

Physical-device walkthrough: not performed in this Linux environment. The
macOS compile gate and explicit code/test matrix verify implementation, not
hardware speech quality.
