# QOF-21 – Reproduzierbare Roblox-Release-Pipeline

Status: **Code-verifiziert – Studio-Test ausstehend**

QOF-21 macht die finale RBXL zu einem reproduzierbaren Generatorziel und entfernt die ungeprüften harten Shared-/Service-/Controllerlisten aus dem Place-Generator.

## Runtime-Inventur

`tools/runtime_inventory.py` entdeckt die unterstützten Source-Flächen deterministisch aus `src/` und bricht bei unbekannten Dateien, Symlinks, ungültigem UTF-8, CRLF oder `]]>` in Script-Source fail-closed ab. Unterstützt werden:

- `ReplicatedStorage/Shared/*.lua`
- das Vide-`init.lua` plus seine Module
- `modules/formatNumber.lua` und `modules/upgradeTree/*.lua`
- `ServerScriptService/Main.server.lua` plus alle Services
- `StarterPlayerScripts/Main.client.lua` plus alle Controller

`tools/generate_rbxlx.py` konsumiert diese Inventur, setzt Referents pro Build zurück, serialisiert explizit UTF-8/LF, validiert das XML und veröffentlicht atomar. `tests/verify_generated_place.py` inventarisiert die Runtime-Flächen weiterhin unabhängig und verlangt bytegenaue eins-zu-eins-Parität.

## Gepinnte Konvertierung

`tools/convert_place.rbxmk.lua` unterstützt ausschließlich `.rbxlx → .rbxl` und `.rbxl → .rbxlx` über `fs.read`/`fs.write`.

`tools/rbxmk.lock.json` pinnt den kanonischen Builder:

- rbxmk `0.9.1`
- Linux amd64 SHA-256 `057c4b3e70c928af73646975d1df11579b0a5ccfa72f274af8c6d135fc9f4d34`
- Descriptor: ausdrücklich `null`; `desc-latest` ist verboten

Der lokale Pfad ist kein Repositoryvertrag. Er wird über `--rbxmk`, `RBXMK` oder `PATH` geliefert und vor Verwendung gegen Version und Plattformhash geprüft.

## Ein Build-Befehl

```bash
python3 tools/build_release.py --qof 21 --rbxmk /path/to/rbxmk
```

Der Befehl erzeugt zunächst den vollständigen Satz in fsync-beständigen Staging-Dateien. Beim Publish wird das Manifest zuletzt sichtbar; jeder behandelte Schreib-/Rename-/fsync-Fehler rollt alle bereits ersetzten Artefakte auf ihre vorherigen Bytes zurück:

- `BATTLE_PETS.rbxlx`
- `BATTLE_PETS_QOF-21_TEST.rbxl`
- `BATTLE_PETS_QOF-21_RBXLX.zip`
- `BATTLE_PETS_QOF-21_SHA256SUMS.txt`

Für einen temporären Build kann `--output-dir <directory>` verwendet werden. Ein non-mutating Drift-Check lautet:

```bash
python3 tools/build_release.py --qof 21 --rbxmk /path/to/rbxmk --check
```

## Fail-closed Prüfsequenz

1. Zwei getrennte Generatorprozesse müssen byteidentische RBXLX erzeugen.
2. Der Place-Verifier prüft XML und jede Runtime-Source.
3. rbxmk-Version, Plattform und Executable-Hash müssen dem Lock entsprechen.
4. Zwei getrennte rbxmk-Prozesse müssen byteidentische RBXL erzeugen.
5. Die RBXL muss exakt mit `<roblox!\x89\xff\r\n\x1a\n` beginnen.
6. RBXL wird zurück nach RBXLX konvertiert; Source-Parität und der referent-/Float-/Descriptor-normalisierte semantische Baum des **gesamten Places** müssen dem Original entsprechen. Eine zweite Konvertierung nach RBXL muss außerdem byteidentisch zur ersten Binärdatei sein.
7. Zwei ZIP-Builds müssen byteidentisch sein.
8. Das ZIP enthält exakt einen deflated Root-Eintrag `BATTLE_PETS.rbxlx`, Zeit `1980-01-01 00:00:00`, Unix-Modus `100644`, keine Extras oder Kommentare; Payload ist byteidentisch zum XML.
9. Das SHA256SUMS-Provenance-Manifest pinnt Source-Tree, Generator, Runtime-Inventur, Release-Builder, Converter, Lock, rbxmk und alle drei Artefakte. Der eigenständige Verifier importiert keine Builder-Konstanten: Er rekonstruiert Namen, Magic, ZIP und jedes Provenance-Feld unabhängig, lehnt unbekannte/fehlende/doppelte Felder ab und gleicht Tool-/Source-/Lock-Hashes neu ab.
10. `--check` vergleicht frische Bytes mit den vorhandenen Dateien, ohne sie zu verändern.

Direkte Artefaktprüfung mit optionalem Rebuild:

```bash
python3 tests/verify_release_artifacts.py --qof 21
python3 tests/verify_release_artifacts.py --qof 21 --fresh-build --rbxmk /path/to/rbxmk
```

## Reproduzierbarkeitsgrenze

Der kanonische Bytebuilder ist aktuell Linux amd64. Andere Plattformen sind nicht im Lock freigegeben. DEFLATE kann zwischen Python/zlib-Versionen variieren; ein abweichender Host wird durch den Hash-/`--check`-Vertrag sichtbar, aber Cross-OS-Bytegleichheit wird nicht behauptet. Ein späterer Lock darf weitere Plattformen nur nach nachgewiesen identischen Artefaktbytes ergänzen.

Magic, vollständiger semantischer Place-Vergleich, binäre Rückkonvertierung und Source-Parität beweisen strukturelle Integrität, ersetzen aber keinen manuellen Roblox-Studio-Open-/Play-Smoke-Test.
