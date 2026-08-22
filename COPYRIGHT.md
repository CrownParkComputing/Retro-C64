# Copyright and licence

Retro-C64 — Copyright (C) 2025-2026 CrownParkComputing.

This program is free software: you can redistribute it and/or modify it under
the terms of the **GNU General Public License version 2, or (at your option)
any later version**, as published by the Free Software Foundation. The full
text is in `LICENSE`.

## Why the GPL

Not a preference — a consequence. The app links VICE (GPL v2 or later)
directly, so the shipped binary is a combined work and must be offered under
GPL-compatible terms. Until now this repository declared no licence at all,
which for a GPL-derived work is not a state it can be distributed in. See
`docs/LICENCE_COMPLIANCE.md`.

If the core is ever moved off VICE — `docs/CORE_ALTERNATIVES.md` looks at
that — the code in this repository is ours to relicense, and this file is the
place that changes.

## Components with their own terms

| Component | Licence |
|---|---|
| VICE | GPL-2.0-or-later |
| reSID (within VICE) | GPL-2.0-or-later |
| MEGA65 Open ROMs (`flutter_app/assets/vice/OPENROMS/`) | LGPL-3.0-or-later, some routines MIT (Microsoft) |
| Bundled SID tunes | the composers'; see About in the app |

No Commodore ROM is included in this repository or in any build. Those remain
under copyright and are the user's to supply.
