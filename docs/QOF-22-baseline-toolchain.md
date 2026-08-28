# QOF-22 – Baseline und Pflicht-Toolchain

Status: **Abgeschlossen – Studio-Gate n/a**

QOF-22 verändert kein Gameplay. Es bindet die vollständige QOF-01–21-Baseline an einen reproduzierbaren, gegen repository-eigene SHA-256-Werte verifizierten Linux-amd64-Werkzeugpfad, bevor Schema-, Wirtschafts- oder UI-Code weiterentwickelt wird.

## Baseline

- Arbeitsbranch: `qof-22-31-stabilization-release`
- Unveränderliche QOF-01–21-Basis: `6f453131ea6d9cd9ae59321e476987107791f25e`
- Bootstrap-Roadmap-Commit: `565c649f046aad4f1773b12036f9d1ddaedcfa46`
- QOF-22-Implementierungscommit: `8e5a37c6b8560d7f87a2f1943aad5cd7862299d5`
- `565c649^` ist exakt die genannte Basis; der Bootstrap-Diff enthält nur `QOF-22-31-ROADMAP-README.md`.
- DataSchema vor QOF-23: V11.
- Alle 21 QOF-Dokumente sind vorhanden.
- Runtime-Inventur: 77 Sources = 75 ModuleScripts, 1 Script, 1 LocalScript.
- Historisches QOF-21-Studio-Gate wird in QOF-31 übernommen; QOF-22 behandelt QOF-21 als unveränderliche Code-/Artefaktbasis.

## Gepinnte Toolchain

`tools/toolchain.lock.json` dokumentiert Plattform, Release, beobachteten Upstream-Tag-Commit, Archivgröße, Archiv-SHA-256 und jede Archivdatei. Die Lockdatei wird einmal über beim Modulstart festgehaltene, komponentenweise no-follow geöffnete Repository-/`tools`-Deskriptoren gelesen; genau dieselben Bytes liefern Konfiguration und `lockSha256`. Die ausführbaren Bytes werden gegen diese Repository-Hashes geprüft; ein reproduzierbarer Source-Build oder eine Upstream-SLSA-Attestation wird nicht behauptet. `tools/bootstrap_toolchain.py`:

1. akzeptiert nur Linux amd64 sowie den extern vorausgesetzten kanonischen CPython-/zlib-Host,
2. akzeptiert ausschließlich die hart validierten HTTPS-GitHub-Releasepfade der drei freigegebenen Upstream-Repositories oder liest mit `--archive-dir` vorab geladene Archive,
3. prüft Offline-Dateityp und Größe über denselben `O_NOFOLLOW`-Descriptor und online Größe/Redirect-Host, danach den Archivhash **vor** dem Öffnen,
4. lehnt zusätzliche, doppelte, verschachtelte oder übergroße ZIP-Einträge ab,
5. prüft jeden Payloadhash vor Installation,
6. öffnet Installations- und Offline-Archivpfade komponentenweise ab `/` mit festgehaltenen `O_DIRECTORY|O_NOFOLLOW`-Deskriptoren; spätere Umbenennungen oder Symlink-Swaps eines bereits geöffneten Pfadpräfixes können Lock, Archivlesung, Prüfung oder Zielverzeichnis nicht umlenken,
7. baut unter einem exklusiven descriptor-verankerten Installationslock einen vollständigen privaten Staging-Satz, prüft und smoketestet ihn und promotet ihn mit `renameat2(RENAME_NOREPLACE)` zwischen festgehaltenen Quell-/Zielverzeichnis-Deskriptoren; ein gültiger Satz wird idempotent wiederverwendet, ein vorhandener ungültiger/unerwarteter Baum niemals automatisch ersetzt oder rekursiv bereinigt,
8. verlangt im installierten Root exakt State-Datei, `bin/` und die vier freigegebenen Binaries; der Satz wird read/execute-only eingefroren,
9. hält auch Check, Hashprüfung und Smoke-Ausführung unter demselben Shared Lock und führt die zuvor gehashten Binaries über ihre festgehaltenen Deskriptoren aus.

Gepinnt sind:

| Werkzeug | Version / Commit | Archiv-SHA-256 | installierter SHA-256 |
|---|---|---|---|
| rbxmk | 0.9.1 / `d1f12d1d18ce773fa378bdc44b894005f7d06833` | `7c8a3d6c53f63e629f00373dc4d91513e472a829d9096fec1f6cd0d4f4fefcc5` | `057c4b3e70c928af73646975d1df11579b0a5ccfa72f274af8c6d135fc9f4d34` |
| Luau Runner | 0.735 / `367f9d83cc29804a6d5938ec85b6116d34d8743b` | `b8ea2c5dfa229840dd6fa5a16be082b9a3468c82b8b270b7f695a23233e7eceb` | `6737e0e1b38936c2cc172a8d9a8fbe68cbe0f261a4a5ecc8c161530cbfe497d7` |
| Luau Compiler | 0.735 / derselbe Commit | dasselbe Luau-Archiv | `7a06efa407a9c6a3ecbe8d84fcc0150ac4161f70e2bbf8806f7db20a4fefd481` |
| Selene | 0.31.0 / `9d531b8d3755e139b26c534914e252239014bb3d` | `dac452422747999ec4919bbb8bb52992b66aae533b60022bf005669de8616671` | `30887c8f10ab901fe5883ef655f7b9fe47e628b83c709c3d7548b02e966e67a4` |
| Python | CPython 3.9.25 | Hostvertrag | – |
| zlib | compile/runtime 1.2.11 | Hostvertrag | – |

Offizielle Releases: [rbxmk v0.9.1](https://github.com/Anaminus/rbxmk/releases/tag/v0.9.1), [Luau 0.735](https://github.com/luau-lang/luau/releases/tag/0.735), [Selene 0.31.0](https://github.com/Kampfkarren/selene/releases/tag/0.31.0). Releaseinformationen wurden für Lizenzkonformität sinngemäß wiedergegeben.

## Verwendung

Online:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/bootstrap_toolchain.py
```

Netzwerkfrei mit bereits geladenen, exakt benannten Archiven:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/bootstrap_toolchain.py \
  --archive-dir /path/to/authenticated-archives
```

Idempotenter Check ohne Download/Installation:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/bootstrap_toolchain.py --check
```

Der lokale Installationsordner `.tools/` ist bewusst ignoriert und kein Source-/Releasebestandteil. CPython 3.9.25 und zlib 1.2.11 werden in QOF-22 geprüft, aber nicht installiert; sie sind der externe Hostvertrag. Der digest-gepinnte Container, der diese beiden Voraussetzungen reproduzierbar bereitstellt, bleibt ausdrücklich Scope von QOF-30.

## Luau-Testharness

Der offizielle Luau-CLI-Runner sandboxed `require()`-Module und macht `_G` read-only. Die bestehenden Specs injizieren Roblox-Mocks absichtlich über `_G`; ein direkter Lauf von `tests/run_tests.lua` ist deshalb mit modernem Luau nicht ausführbar.

`tools/run_luau_tests.py` löst dies ohne Änderungen an Produktcode oder Specs:

- liest die kanonische `specFiles`-Liste aus `tests/run_tests.lua`,
- verlangt rekursiv exakte Übereinstimmung mit allen `tests/**/*.spec.lua`,
- bettet alle Projektmodule unverändert in einen temporären Harness,
- erzeugt **pro Spec** eine frische veränderbare Mockumgebung und einen frischen Require-Cache; `game`, `script`, `task`, `math`, `os` und geladene Module leaken nicht zwischen Specs,
- emuliert nur die für vorhandene Tests nötige Lua-5.4-Kompatibilität von `coroutine.running()` sowie veränderbare `math`-/`os`-Tabellen,
- prüft den Luau-Runner gegen den im Lock gepinnten SHA-256, lehnt Symlinks in jeder lexikalischen Pfadkomponente ab und führt genau den verifizierten offenen Deskriptor aus,
- kann die vollständige Liste mit `--reverse` umkehren, um versteckte Reihenfolgeabhängigkeit zu erkennen,
- löscht den temporären Harness auch bei Schreib-, Close- oder Ausführungsfehlern wieder.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/run_luau_tests.py
```

Verifiziertes Ergebnis: **345 bestanden, 0 fehlgeschlagen**, sowohl in kanonischer als auch umgekehrter Spec-Reihenfolge.

## Verifikation

Ausgeführt und bestanden:

1. `bootstrap_toolchain.py --archive-dir ...` in einen leeren Zweitordner.
2. `bootstrap_toolchain.py --check` für Primär- und Zweitinstallation.
3. Python-Compile für alle Tool-/Testskripte.
4. Luau-Compile aller 77 Runtime-Sources: 77/77.
5. Vollständige Luau-Suite in normaler und umgekehrter Reihenfolge: jeweils 345/345.
6. `verify_generated_place.py BATTLE_PETS.rbxlx` mit bytegenauer Parität aller 77 Sources.
7. Statischer unabhängiger QOF-21-Artefaktverifier.
8. `sha256sum --check BATTLE_PETS_QOF-21_SHA256SUMS.txt`.
9. Vollständiger Fresh-Build mit gepinntem rbxmk inklusive RBXL↔RBXLX-Roundtrip und `--check` gegen die getrackten Bytes.
10. Descriptor-Race-Negativtests: ein nach dem Öffnen durch einen Symlink ersetztes Pfadpräfix lenkt die Promotion nicht um; ein symlinked Luau-Runner wird abgelehnt; ein injizierter Harness-Schreibfehler hinterlässt keine temporäre Datei.
11. `git diff --check`.

Fresh-Build-Ergebnis:

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.110.304 | `f093803673ce7d014cabaa6d36d56b5f24c0b169131b1bd418b8087c0c554385` |
| `BATTLE_PETS_QOF-21_TEST.rbxl` | 392.085 | `9f7c7653b982a564da415b3ba3bb8e48370a559d9e3c1552df2403d57daccaaf` |
| `BATTLE_PETS_QOF-21_RBXLX.zip` | 223.112 | `eaded3eaa3a41241e26683456e32adfd7c2dac481afebc6f60e4631c4b3aec7f` |
| `BATTLE_PETS_QOF-21_SHA256SUMS.txt` | 1.080 | `d62fd585648073eed88323df50c6c77b9162b0864cfa123e852ea89a78514982` |

## Selene-Grenze

QOF-22 authentifiziert und prüft die Selene-Binärdatei. Der heutige `std = "roblox"`-Modus erzeugt seine Roblox-Standardbibliothek jedoch über einen externen Floating-API-Dump. Ein verpflichtender offline reproduzierbarer Selene-Standardbibliothekscheck wird deshalb nicht unehrlich behauptet; QOF-30 pinnt den Roblox-Std-/Containerpfad und macht Lint verpflichtend. Luau-Compile und vollständige Tests sind bereits lokal reproduzierbar.

## Studio und Artefaktpolicy

Studio-Gate: **n/a**. QOF-22 verändert keine Runtime-Source und erzeugt daher kein künstlich neu benanntes QOF-22-Gameplay-RBXL. Stattdessen beweist der verpflichtende Fresh-Build die Byteidentität des bestehenden echten QOF-21-Binärartefakts. Das nächste Code-QOF muss wieder ein eigenes `BATTLE_PETS_QOF-XX_TEST.rbxl` liefern.
