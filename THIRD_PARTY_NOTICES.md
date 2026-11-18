# Third-party UI artwork and presentation

The Lua runtime and Hailstone integration in this repository have their own
repository license. That license does not relicense third-party interface
artwork, game artwork, names, or other material owned by their original authors.

This pack includes presentation tables adapted from the following user-supplied
interfaces: Default, Default Old, AYA, Delta, Drakah Pers Adeptus, Duxa UI,
Graphite, IB, Lodidodi, Lords, Nemesis, PO2, PO2 Alternate, QQ Custom, QQ UI,
SARS, Sparxx, Takus, Vert, and Warcraft. Their original artwork is represented
by deduplicated, lossless RGBA PNGs with non-pixel metadata removed. The pack
does not claim authorship of those images. Logical resource names and per-image
content hashes are retained in `assets/manifest.json`; identical artwork used
by several interfaces is stored once.

Credits retained from the supplied interface documentation include:

- Default Old: update by Drakah, July 16, 2014; [Shakahr](http://www.shakahr.com/).
- Drakah Pers Adeptus: created by Drakah, version 6.9, April 18, 2013;
  spell icons and book by T.King.
- Lords: Drakah Integrated UI, Lords of Everquest, version 6.9, April 18, 2013;
  spell icons by Etasi.
- Warcraft: Drakah Emulated UI, Warcraft, version 11.7, April 18, 2013. Its
  documentation credits graphics adapted from public screenshots, user
  submissions, and the author's interface art. Blizzard and other game material
  retains its respective owners' rights.
- Lodidodi: LODI DODI UI Modification, version 3.3.6, copyright 2002-2009 D-MONEY;
  [original project](http://www.lodidodi.net/).
- Graphite: TDS-compatible interface, version November 19, 2014. Its supplied
  documentation credits combat-state indicators used with permission from AYA.
- Nemesis: [upstream project](https://github.com/fryguy503/Nemesis) and
  [interface listing](http://www.eqinterface.com/downloads/fileinfo.php?id=5653).
  The supplied project includes GNU GPL version 2; its complete license is
  retained in `licenses/Nemesis-GPL-2.0.txt`. The adapted Lua presentation tables
  are included in editable form in this repository.

The Nemesis original-source supplement for version `0.2.0-preview.6` is
`Hailstone-UI-Pack-Nemesis-Source-0.2.0-preview.6.zip`, distributed with the
release. It retains the original editable XML, image and cursor inputs and
license notices. Use it alongside the matching public GitHub source archive,
which contains the complete editable Lua runtime, conversion/build tools,
portable layouts and transformed PNGs. The source supplement is separate from
the playable addon; addon users do not install or load its XML files.

Some supplied folders do not contain separate author or license notices. Their
original authors retain their rights. Hailstone-specific additions and the
transformation do not grant additional rights in the underlying material.

Live item and spell icons continue to come from the user's configured game
assets. Private plugin resources and raw source XML are not distributed in
this pack. Where an original image was absent from the supplied folders, the
runtime uses the selected interface's themed functional control presentation;
the manifest identifies those resources rather than substituting an unrelated
atlas under an original filename.
