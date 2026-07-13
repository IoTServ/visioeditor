# Test fixtures

Most of these `.vsdx` sample files (`test*.vsdx`) are copied verbatim from the
**`vsdx`** project by Dave Howard, licensed under **BSD-3-Clause**.

- Source: <https://github.com/dave-howard/vsdx> (`tests/`)
- License: BSD-3-Clause (see the upstream `LICENSE`)

`workflow.vsdx` is the app's own bundled example (mirrors
`assets/examples/workflow.vsdx`); it is included here so the engine's parse
tests cover the same real-world drawing the editor ships as a sample.

They are used only as read/round-trip parsing fixtures for `package:vsdx`.
