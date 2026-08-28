# QOF-23 – DataSchema V12 und hostile Save-Normalisierung

Status: **Abgeschlossen – Fortsetzung durch ausdrückliches Nutzer-`Weiter`; Studio-Ergebnis nicht separat gemeldet**

Implementierungscommit: `21fdf0e2dbcc1607d814bb9d6f7d0986abec2d1c`

QOF-23 migriert Profile auf Schema V12, entfernt ungültige Progressionswerte fail-closed und rekonstruiert sparse Persistenzarrays deterministisch. Preise, Chancen und bestehende gültige Progression bleiben unverändert.

## Kanonische Progressionsgrenzen

`ProgressionMath` ist die gemeinsame Autorität für Load, Persistence-Clone, Clientprojektion und öffentliche Runtime-Resolver:

- Quest-Level sind nur für IDs aus `QuestData.Quests` zulässig. Das Maximum ist die zusammenhängende Länge von `levels`.
- Mastery-Level sind nur für IDs aus `MasteryData.Buffs` zulässig. Das Maximum ist `min(maxLevel, #pointsPerLevel, #bonusPerLevel)` über die jeweils zusammenhängenden Definitionen.
- Nur endliche Ganzzahlen in `0..Maximum` sind gültig.
- Negative, fraktionale, nicht endliche, überhöhte und falsch typisierte Werte sowie unbekannte IDs werden entfernt. Ein überhöhter Save wird nicht auf ein unverdientes Max-Level angehoben.
- QuestService, MasteryService und UpgradeService validieren unmittelbar vor jedem Level-/Bonusindex erneut. Ungültige Runtime-Manipulationen liefern neutral `0`.
- Mutations- und Eventgrenzen kanonisieren immer die vollständige Progressionsmap. Ein ungültiges Mastery-Ziel verbraucht keine Punkte; gültige Geschwisterwerte bleiben erhalten.
- DataService liefert nur normalisierte Progressionsprojektionen an Clients.

## Sparse Arrays und weitere Claim-Felder

`pets`, `equippedPets`, `unlockedZones` und `campaignProgress` werden über sortierte positive Ganzzahlkeys gelesen. Löcher beenden die Migration nicht mehr. Bei doppelten Pet-/Equipped-IDs gewinnt der erste gültige Wert in aufsteigender Quellkey-Reihenfolge; Zahlenarrays werden anschließend eindeutig numerisch sortiert.

`campaignBossRewards` wird ebenfalls fail-closed rekonstruiert: Nur Stringkeys kanonischer `CampaignData`-Level mit `SpecialEgg` und exakt dem Wert `true` bleiben erhalten. CampaignService behandelt nur exakt `true` als eingelösten Anspruch; ein fremder truthy Wert kann das einmalige Boss-Ei nicht unterdrücken.

V5-/V6-Variantenmigration, kombinierte Shiny-Zustände, V10-Enchants, V11-Dex-Einträge, Potionzustand und bestehende gültige Max-Level bleiben erhalten. Zweifache Migration und `cloneForPersistence` sind idempotent; der Persistence-Clone normalisiert eine nach dem Laden manipulierte Runtime-Kopie ohne das Liveprofil zu verändern.

## Lokale Verifikation

- Semantischer Code-Review nach zwei Fixrunden ohne verbleibenden Codeblocker.
- Gepinnte Pflicht-Toolchain erfolgreich geprüft.
- Python-Compile für Tools und Tests erfolgreich.
- Luau-Compile: **78/78** Runtime-Sources.
- Vollständige Luau-Suite: **356/356** in kanonischer und umgekehrter Reihenfolge.
- `verify_generated_place.py`: 78 Sources bytegenau, davon 76 ModuleScripts, 1 Script und 1 LocalScript.
- Unabhängiger QOF-23-Releaseverifier und SHA-Manifest erfolgreich.
- `git diff --check` erfolgreich.

## Testartefakt

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.117.269 | `b20778c38f4d68b1a959a85b0ca03a21fd334a2d743c164d65b344d69acd7d37` |
| `BATTLE_PETS_QOF-23_TEST.rbxl` | 394.233 | `b8a2d611beab73db67ee8b4fdb62b8d8e054f8b9ff91064bfb44a11a4eb2c40a` |
| `BATTLE_PETS_QOF-23_RBXLX.zip` | 224.298 | `9c2cad0b254339b273577f5e246d484d4afd77d40c8fa1e0e07d60d0a36a04f5` |
| `BATTLE_PETS_QOF-23_SHA256SUMS.txt` | 1.080 | `3aeb0f26c1f2cd4897a1e512904e8ace708c9535d644814e46d62a0a018a1278` |

Die RBXL beginnt mit der exakten binären Roblox-Signatur `<roblox!\x89\xff\r\n\x1a\n`.

## Verbindlicher Studio-Testplan

1. `BATTLE_PETS_QOF-23_TEST.rbxl` in Roblox Studio öffnen und **Play** starten. Erwartet: Welt und UI laden ohne rote Fehler im Output; vorhandene Pets, Währungen, Zonen und Progression erscheinen.
2. Mit einem Testkonto beitreten, dessen Profil bereits in einem älteren QOF-Build gespeichert wurde. Mindestens ein Pet, ein Quest-Upgrade, ein Mastery-Buff und Campaign-/Dex-Fortschritt sollten vorhanden sein. Erwartet: Der Join wird nicht abgewiesen und kein gültiger Fortschritt geht verloren.
3. Im **Server**-Command-Bar-Kontext während der Sitzung ausführen:
   ```lua
   local player = game:GetService("Players"):GetPlayers()[1]
   local data = require(game.ServerScriptService.Services.DataService).getPlayerData(player)
   print("QOF23_SCHEMA", data and data.schemaVersion)
   print("QOF23_PETS", data and #data.pets)
   ```
   Erwartet: `QOF23_SCHEMA 12`; Petanzahl entspricht dem Profil.
4. Quest- und Mastery-Fenster öffnen. Erwartet: gültige vorhandene Level und Max-Level werden korrekt angezeigt; keine Karte verursacht einen Nil-Index-/UI-Fehler.
5. Einen legitimen Questfortschritt auslösen und – falls Punkte vorhanden – einen Mastery-Level kaufen. Erwartet: genau ein gültiges Levelupdate; Kosten und Bonus entsprechen unverändert den Definitionen.
6. Einen Campaign-Boss mit bereits eingelöstem Boss-Ei wiederholen. Erwartet: kein zweites Ei. Einen noch nicht eingelösten Boss mit freiem Petplatz abschließen. Erwartet: genau ein Ei und nach Rejoin kein zweites.
7. Spiel verlassen, erneut beitreten und Schritt 3 wiederholen. Erwartet: Schema bleibt V12, gültige Pets/Varianten/Shiny/Enchants/Dex-/Quest-/Mastery-/Campaigndaten bleiben erhalten.
8. Optional Mobile-/Tablet-Smoke: Inventory, Quests, Mastery und Campaign öffnen. Erwartet: keine neue QOF-23-spezifische UI- oder Laufzeitstörung.

## Bekannte Grenze

Der echte DataStore-Rejoin und Roblox-Studio-Playtest konnten im Linux-Sandbox-Build nicht ausgeführt werden. Der Nutzer hat anschließend ausdrücklich `Weiter` geschrieben und damit die Fortsetzung zu QOF-24 freigegeben; ein separates positives Studio-Ergebnis wurde nicht gemeldet und wird deshalb nicht behauptet.
