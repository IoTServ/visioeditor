# External VSD fixtures

Files in this directory are **third-party samples** used only for parser
coverage (ConnectList `0x72`, Hyperlink `0xc4`, edge-case CFB chunks).

| Source | License | Notes |
|--------|---------|-------|
| [Apache POI](https://github.com/apache/poi) `test-data/diagram/` | Apache License 2.0 | `visio_with_embeded.vsd` (Hyperlink), `44594*.vsd` (empty ConnectList), `Test_Visio-Some_Random_Text.vsd` / `44501e.vsd` (Event RUNADDONW), short-chunk / embed samples |
| vsdump `chunks_parse_cmds.tbl` | (tool table; field offsets for reverse-engineering) | Not a Visio drawing |

Do not redistribute these as product assets. Prefer regenerating from upstream
POI when refreshing fixtures.

`visio_with_embeded.vsd` is also the LibreOffice visual-parity fixture for
PNG, OLE2, Excel chart/table, WMF and EMF rendering. Its SHA-256 is
`ce31a269ff6ca0b8a25394c8ae81114895a2eafb4328d72fc9b9450d79a48cf5`.
