# Windows CJK fallback font

`NotoSansCJKkr-Regular.otf` is the unmodified Korean regional font from
[Noto Sans CJK 2.004](https://github.com/notofonts/noto-cjk/tree/Sans2.004),
commit `523d033d6cb47f4a80c58a35753646f5c3608a78`, at
`Sans/OTF/Korean/NotoSansCJKkr-Regular.otf`.
It includes Korean, Chinese and Japanese glyphs. The frontend embeds it as
a fallback after egui's existing fonts and the companion's Windows UI fonts,
independently of Windows language packs.

SHA-256: `6bcb2a0703aa137e874fc2dffa85f6c21ba9a67fa329e81b8c801663af7e992a`.

Copyright 2014-2021 Adobe (http://www.adobe.com/).
Licensed under the SIL Open Font License 1.1; see [OFL.txt](OFL.txt).
Windows packages include that notice and license under `licenses/`.
