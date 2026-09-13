# Brand Guide — Zavithar Manager

## Logo
**Status: deferred / not yet decided.** Two rounds of concepts (a blocky badge Z, then abstract sync/growth/gem symbols, then several hand-drawn "meteor crack" and "rune blade" Z letterforms) were explored and none were a fit yet. The mockups currently use plain text ("Zavithar") in place of a logo mark. Revisit this later — either try a different creative direction, commission/draw one outside this session, or launch v1 with a text wordmark and add a mark later. No logo files are in current use.

## Color palette (dark theme)

| Token | Hex | Role |
|---|---|---|
| `page` | `#0d0d0d` | App background |
| `surface-1` | `#1a1a19` | Cards, screens, headers |
| `surface-2` | `#161413` | Sidebar/secondary panels |
| `text-primary` | `#ffffff` | Primary text |
| `text-secondary` | `#c3c2b7` | Secondary text |
| `muted` | `#898781` | Labels, timestamps |
| `gridline` | `#2c2c2a` | Borders, dividers |
| `brand-primary` | `#b3122b` | Buttons, active nav/tabs, links |
| `brand-primary-light` | `#ff3b57` | Gradient highlight, hover |
| `brand-primary-dark` | `#6e0d1a` | Gradient shadow, pressed state |

## Category colors (todos)
| Category | Hex | Notes |
|---|---|---|
| Work | `#d95926` (orange) | |
| Hobbies | `#199e70` (aqua/green) | |
| Study | `#c98500` (gold) | uses dark text for contrast |
| Home | `#9085e9` (violet) | |

These follow a validated categorical order (fixed hue order, not cycled) so they stay distinguishable from each other and from status colors even for colorblind users.

## Status colors (fixed, never restyled)
| Status | Hex | Used for |
|---|---|---|
| Good | `#0ca30c` | income, completed |
| Warning | `#fab219` | due soon |
| Serious | `#ec835a` | approaching deadline |
| Critical | `#e66767` | overdue, expenses |

Chosen to sit at a different hue/lightness than `brand-primary` so an overdue/expense red is never confused with a brand-red button — status meaning always pairs with an icon or text label, never color alone.

## Rationale
Dark surfaces + a single strong red as the brand accent, with the todo category colors doing the "colorful" work — keeps the UI from feeling flat while still reading as one cohesive system rather than a rainbow of buttons. All text/background combinations were checked for contrast (white on `brand-primary` ≈ 6.9:1, well above the 4.5:1 minimum for normal text). This color system is settled and in use in the mockups; only the logo mark is still open.
