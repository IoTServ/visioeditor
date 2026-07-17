# External VSD fixtures

Files in this directory are **third-party samples** used only for parser
coverage (ConnectList `0x72`, Hyperlink `0xc4`, edge-case CFB chunks).

| Source | License | Notes |
|--------|---------|-------|
| [Apache POI](https://github.com/apache/poi) `test-data/diagram/` | Apache License 2.0 | `visio_with_embeded.vsd` (Hyperlink), `44594*.vsd` (empty ConnectList), `Test_Visio-Some_Random_Text.vsd` / `44501e.vsd` (Event RUNADDONW), short-chunk / embed samples |
| vsdump `chunks_parse_cmds.tbl` | (tool table; field offsets for reverse-engineering) | Not a Visio drawing |

Do not redistribute these as product assets. Prefer regenerating from upstream
POI when refreshing fixtures.
