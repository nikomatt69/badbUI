# PC & graphics profile

`/badb system` classifies this machine and `/badb system apply` (or the options page) applies it.

An add-on cannot read GPU model, CPU, RAM or operating system — WoW exposes none of those. BadbUI uses the legal signals: physical display resolution (`GetPhysicalScreenSize`), measured frame rate (`GetFramerate`, sampled on world entry, never per frame), and the graphics CVars that actually exist on this client (probed with `Badb.CVars:Exists`, saved/restored by `Badb.CVars`).

Tiers: **performance** (<30 FPS or very high pixel count with low FPS), **balanced** (up to 1080p), **quality** (1440p at 55+ FPS), **ultra** (4K at 55+ FPS). Each tier suggests a UI scale and a small set of candidate CVars (shadow quality, particle density, view distance); CVars missing on Forever are skipped and reported as none. Restore returns the original values. On macOS/Windows/Linux the same rules apply because they depend on the client, not the OS.
