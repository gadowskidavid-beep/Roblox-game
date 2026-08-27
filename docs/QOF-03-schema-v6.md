# QOF-03 – Schema V6 und sichere Kompatibilitätsmigration

**Status:** Code-verifiziert – Studio-Test ausstehend
**Testbuild:** `BATTLE_PETS_QOF-03_TEST.rbxl`
**DataStore:** unverändert `BattlePets_v1`

## Ziel

QOF-03 bereitet persistente Spielerdaten für die späteren Varianten-, Potion- und Maschinen-QOFs vor, ohne deren Gameplay zu aktivieren. Bestehende Saves werden beim Laden unter dem vorhandenen Session-Lock idempotent von V5 auf V6 migriert.

## V6-Datenvertrag

Jedes Pet besitzt künftig:

```text
variant = "Normal" | "Golden" | "Rainbow"
shiny = boolean
golden = (variant == "Golden") -- temporärer Kompatibilitätsspiegel
```

Legacy-Migration:

- `golden=true` oder `variant="Golden"` → Golden
- `variant="Rainbow"` → Rainbow
- `variant="Shiny"` → Normal plus `shiny=true`
- fehlende/ungültige Varianten → Normal
- ein vorhandenes `shiny=true` wird unabhängig von der alten Schema-Versionsnummer bewahrt

Pet-ID, Species, Name, gebackener Schaden, Favorite, Equipped und Inventarreihenfolge gültiger eindeutiger Pets bleiben erhalten. Aktuelle x3-Shiny-/x5-Rainbow-Schäden werden in QOF-03 nicht neu berechnet; die neue x1,5-Shiny-Formel gehört zu QOF-04.

## Vorbereitete, deaktivierte Potion-Daten

Neue Profile enthalten:

```text
potionInventory[potionId] = integer
activeBuffs[buffType] = unixExpiry | { charges = integer }
potionUpgrades = { slots, durationLevel, autoDrink }
```

Sicherheitsgrenzen:

- nur Potion-IDs aus `BalanceConfig.Potions.Catalog`
- maximal 999 Items pro Potion
- maximal 30 Shiny-Charges
- gespeicherte Timer maximal 30 Tage in der Zukunft
- NaN, Infinity, unbekannte Keys, negative Mengen und abgelaufene Timer werden entfernt
- Slots 2–5, Duration-Level 0–4, Auto-Drink strikt Boolean

Diese Felder sind nur vorbereitet. Der bisherige Shop und seine Session-Buffs bleiben unverändert; `Potions.RuntimeEnabled` bleibt `false`.

## Laufzeitkompatibilität

- One-Egg-Hatch, Kosten, zwei Legacy-Rolls, Luck-Quellen, Namen und x3/x5-Schaden bleiben unverändert.
- Hatch-Ausgaben werden V6-konform gespeichert und weiterhin als vier aktuelle UI-Kategorien dargestellt.
- Golden-Konvertierung behält 1–7 Inputs, 13/26/39/50/63/88/100 %, No-Cost und Consume-on-Failure.
- Golden-Konvertierung schützt Favorite, Equipped, Golden, Rainbow und nun auch kanonische `shiny=true` Pets.
- Alte Discovery-Keys und alle `upgradeTreePurchases` bleiben erhalten.
- Keine Remotes und keine Balance-Runtime-Gates wurden verändert.
- `upgradeTree.lua` und Vide bleiben unverändert.

## Verbindliche Produktions-Rollout-Regel

V6 schreibt Shiny korrekt als `variant="Normal", shiny=true`. Ein bereits laufender V5-Server kennt das Boolean-Feld nicht und könnte dieses Pet trotz verlustfreier Speicherung als normales Pet behandeln. Das lässt sich durch neue Dateien nicht rückwirkend in einem alten Serverprozess beheben.

**Vor einer Produktionseinführung müssen deshalb alle V5-Server geschlossen beziehungsweise über Roblox „Shut Down All Servers“ entleert werden. Erst danach darf die V6-Version veröffentlicht werden.** Der QOF-03-Testbuild darf unabhängig davon lokal/in einer getrennten Testumgebung geprüft werden. Ein gemischter V5/V6-Produktionsbetrieb ist nicht freigegeben.

## Verifikation

- Luau-Compile für alle geänderten Luau-Dateien
- 42/42 Balance- und Schema-Tests
- V5→V6-Matrix und wiederholte Migration
- V6→V5-Versionsstempel→V6-Shiny-Persistenz
- hostile/ungültige Potion-Daten, Mengen- und Timer-Caps
- generierte Place-Source-Parität für alle geänderten Module/Controller
- 58 ModuleScripts, 1 Script, 1 LocalScript
- keine Änderungen an `upgradeTree.lua` oder Vide

Roblox-Studio- und DataStore-Laufzeittests bleiben bis zum Nutzerfeedback ausstehend. QOF-04 beginnt erst nach der Nachricht `Weiter`.
