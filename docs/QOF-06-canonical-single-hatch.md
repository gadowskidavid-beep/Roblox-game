# QOF-06 – Kanonischer Single-Egg-Hatch

**Status:** Code-verifiziert – Studio-Test ausstehend
**Testbuild:** `BATTLE_PETS_QOF-06_TEST.rbxl`
**Schema:** V6 bleibt unverändert

## Ziel

QOF-06 aktiviert die kanonischen direkten Varianten-Ergebnisse im bestehenden serverautoritären Single-Egg-Pfad. Der Server bestimmt Spezies, Basisvariante und Shiny-Status; der Client stellt nur das bestätigte Ergebnis dar.

Pro Ei werden genau drei serverseitige Zufallswerte verwendet:

1. Spezies aus dem bestehenden gewichteten Egg-Pool
2. gemeinsame kategorische Basisvariante
3. unabhängiger Shiny-Status

Damit sind alle sechs V6-Zustände direkt hatchbar:

| Basisvariante | Shiny | Persistierte Felder | Basisschaden |
|---|---:|---|---:|
| Normal | nein | `variant = "Normal"`, `shiny = false` | ×1 |
| Normal | ja | `variant = "Normal"`, `shiny = true` | ×1,5 |
| Golden | nein | `variant = "Golden"`, `shiny = false` | ×2 |
| Golden | ja | `variant = "Golden"`, `shiny = true` | ×3 |
| Rainbow | nein | `variant = "Rainbow"`, `shiny = false` | ×5 |
| Rainbow | ja | `variant = "Rainbow"`, `shiny = true` | ×7,5 |

## Wahrscheinlichkeitsmodell

Ohne Luck gelten pro Ei exakt:

- Rainbow: 0,1 %
- Golden: 1 %
- Normal: 98,9 %
- Shiny unabhängig von der Basisvariante: 0,01 %

Rainbow belegt den ersten Abschnitt des gemeinsamen Basisvarianten-Rolls, Golden den direkt folgenden vollständigen 1-%-Abschnitt. Gold und Rainbow können dadurch nicht gleichzeitig auftreten. Shiny wird separat gerollt und kann auf Normal, Golden oder Rainbow liegen.

Ungültige, nicht endliche oder außerhalb von `[0, 1)` liegende Rollwerte werden defensiv als Normal beziehungsweise nicht Shiny behandelt.

## Luck und Caps

Die bereits aktiven serverseitigen Quellen werden einmal pro Ei multiplikativ kombiniert:

- `LuckyEggs`
- `BetterLuck`
- bestehender Lucky-Potion-/Shop-Luck-Multiplikator

Fehlende, ungültige oder sub-neutrale Multiplikatoren (`≤ 1`) gelten neutral als ×1. Die Gesamtwirkung wird vor der Verwendung begrenzt:

| Wirkung | Cap |
|---|---:|
| seltenere Spezies | ×10 |
| Golden | 5 % |
| Rainbow | 0,5 % |
| Shiny | 0,1 % |

Die für QOF-07 vorgesehenen Upgrade-Tree-Entitlements und Direct-Variant-Upgrades werden in QOF-06 noch nicht ausgewertet.

## Serverautorität und Datenvertrag

- Der bestehende Single-Egg-Remote-, Kosten-, Zonen-, Inventar-, Quest- und Animationspfad bleibt erhalten.
- Chancen und Resultate werden ausschließlich auf dem Server bestimmt.
- Der Server erzeugt kanonische V6-Felder `variant` und `shiny` sowie den kompatiblen `golden`-Spiegel.
- Name und Schaden werden aus den gemeinsamen kanonischen Modulen abgeleitet; vom Client gelieferte Damage- oder Variantenwerte werden nicht vertraut.
- Es gibt keinen Schema-Bump, keinen neuen Remote und kein Batch-DTO.

## Presentation und Discovery

Die QOF-05-Präsentationsschicht kann alle sechs Resultate bereits kombinieren. Deshalb benötigt QOF-06 keine neue Client-Source. Namen, Labels, Inventarkarten, Hatch-Reveal, Discovery-UI und ausgerüstete Pet-Visuals lösen `variant + shiny` gemeinsam auf.

Bis zur späteren Pet-Dex-Migration bleiben die vier Legacy-Discovery-Keys:

- Normal → `<petId>`
- Golden → `Golden_<petId>`
- Rainbow → `Rainbow_<petId>`
- jedes Shiny-Ergebnis → `Shiny_<petId>`

Gold Shiny und Rainbow Shiny werden korrekt angezeigt, teilen für „neu entdeckt“ aber absichtlich den bisherigen Shiny-Key mit Normal Shiny.

## Bewusst verschoben

- QOF-07: Upgrade-Tree-Entitlements, Tree Currency und direkte Chance-Upgrades
- QOF-08/09: atomarer Multi-Open-/Batch-Pfad, Prompt-Router und Hatch-Cinematic-Ausbau
- spätere QOFs: Potions, Gold-/Rainbow-Maschinen, Enchanting und sechs kombinierte Pet-Dex-Kategorien
- kein neues 3D-/Viewport-Pet-Modell im bestehenden Single-Hatch-Reveal

## Rollout

Die QOF-04-Produktionsregel bleibt verbindlich: QOF-03- und ältere Server müssen vor dem Rollout vollständig beendet werden. Zusätzlich sollten QOF-05-Server gedraint werden, damit direkte Hatch-Odds während des Rollouts nicht zwischen alten und neuen Servern variieren.

## Verifikation

- 68 Pure-/Regressionstests für Balance, Hatch-Math, Varianten, Presentation, Schema, PetService und den bezahlten EggService-Pfad
- exakte Boundary-Tests für Golden, Rainbow und Shiny sowie alle sechs Kombinationen
- Luck-Quellen, Species-/Chance-Caps und Legacy-Discovery-Projektion geprüft
- Luau-Compile der geänderten Runtime- und Testdateien
- Python-Syntax, XML-Parsing und Generator-/Place-Source-Parität
- erwartete Place-Hierarchie: 61 ModuleScripts, 1 Script, 1 LocalScript
- binäre RBXL-Signatur- und Source-Roundtrip-Prüfung
- semantischer Review, `git diff --check`, unverändertes `upgradeTree.lua` und unverändertes Vide-Paket

Roblox-Studio-Laufzeit-, Visual-, Odds-Smoke- und Mobile-Tests bleiben bis zum Nutzerfeedback ausstehend.
