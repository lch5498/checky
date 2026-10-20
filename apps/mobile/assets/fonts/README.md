# Bundled Checky fonts

Sources:

- Gowun Dodum, Gowun Batang, Poor Story: https://github.com/google/fonts/tree/47d54ca1ebb14fd864695f1d39dc734f39017c33/ofl
- Ownglyph Park Dahyun (Version 1.0): https://www.ownglyph.com/trial/11ebf7f8-0997-4f03-a393-0959a07286aa
- Ownglyph original font license: https://www.ownglyph.com/font → 온글잎 폰트 라이선스 (checked 2026-10-19)
- Original Park Dahyun TTF: https://ownglyph-out-bucket.s3.ap-northeast-2.amazonaws.com/11ebf7f8-0997-4f03-a393-0959a07286aa/%EC%98%A8%EA%B8%80%EC%9E%8E%20%EB%B0%95%EB%8B%A4%ED%98%84%EC%B2%B4.ttf
- Incheon Education Himchan: https://www.ice.go.kr/ice/cm/cntnts/cntntsView.do?cntntsId=943&mi=10874
- Original Himchan ZIP: https://www.ice.go.kr/common/nttFileDownload.do?fileKey=77d5a92f2f21877e2d9d3d907e119586 (original TTF extracted without modification)

The TTF files are unmodified upstream files. Google Fonts files use the fixed
revision above; Park Dahyun uses Ownglyph's original TTF, not a converted webfont.
Google Fonts families include their copyright notice and SIL Open Font License 1.1
in `OFL.txt`. Park Dahyun is NOT OFL: `parkdahyun/LICENSE.txt` includes its original
copyright notices and Ownglyph's license/permission table. App/SW UI, embedding,
and font distribution are permitted; font modification and standalone sales are
not. Do not modify, convert, or subset Park Dahyun. The licenses are readable
under Settings → Display → Font → Font licenses.

Himchan is also NOT OFL. Its `LICENSE.txt` includes the embedded copyright
notice and its official publisher's usage terms. Incheon permits free use in
mobile and commercial works but not selling the font itself. Keep the TTF file
unmodified, including format and glyph set.
Checky distributes no standalone font download/export feature. Sources and terms
were checked on 2026-10-19; do not substitute third-party webfont conversions.

| App label | Upstream directory | Weights bundled |
| --- | --- | --- |
| 고운돋움 | gowundodum | 400 |
| 고운바탕 | gowunbatang | 400, 700 |
| 온글잎 박다현체 | parkdahyun (Ownglyph) | 400 |
| 푸어스토리 | poorstory (Google Fonts) | 400 |
| 인천교육힘찬체 | incheonhimchan (Incheon Metropolitan City Office of Education) | 400 |

All five families include Korean, Latin letters and digits. The platform font
supplies any unsupported characters. Do not
subset the Korean font files to a fixed set of UI strings: group names, schedule
titles and user-entered text are arbitrary.

Flutter family aliases use a `Checky` prefix only for asset registration. The
font files, internal font names and copyright notices have not been renamed.

The iOS home-widget extension also bundles this original directory, including
licenses, as its `fonts` resource folder. Do not copy/edit a separate native font
version. UIAppFonts and SwiftUI use the upstream PostScript names, not Flutter
aliases. Android widgets load the same Flutter-packaged assets; no extra font
download or second Android copy is required. Custom-font RemoteViews are drawn
locally to a size-bounded image for launcher compatibility.

SHA-256 of newly added originals:

- `parkdahyun/Ownglyph-ParkDaHyun.ttf`: `fbcc7e2e16abd0c9192aff6561871ab95c369bc58284879e813055bde7c5568f`
- `poorstory/PoorStory-Regular.ttf`: `831ab87f7b5463f9cd83ac249bf386816f3a478f1d226427c88cac907adb7ee2`
- `incheonhimchan/ICEHimchan-Regular.ttf`: `60bc561b6ea3c00ea8ec8e004dd5bf69510b10c1d6ff080eaa1935a718a5e960`
