# QOF-05 – Kanonische Pet-Varianten-Präsentation

**Status:** Code-verifiziert – Studio-Test ausstehend  
**Testbuild:** `BATTLE_PETS_QOF-05_TEST.rbxl`  
**Schema:** V6 bleibt unverändert

## Ziel

QOF-05 ergänzt eine rein clientseitige, kombinierbare Präsentationsschicht für alle sechs kanonischen Zustände:

| Persistierte Basisvariante | Shiny | Anzeige |
|---|---:|---|
| Normal | nein | Normal |
| Normal | ja | Normal Shiny |
| Golden | nein | Gold |
| Golden | ja | Gold Shiny |
| Rainbow | nein | Rainbow |
| Rainbow | ja | Rainbow Shiny |

`Golden` bleibt der interne kanonische Wert; in sichtbaren englischen Labels wird `Gold` verwendet. Shiny ist eine unabhängige Ebene und kann mit jeder Basisvariante kombiniert werden.

## Gemeinsame Presentation Source of Truth

`PetVariantPresentation` ist ein reines Shared-Modul. Es liefert normalisierte Basisvariante, unabhängigen Shiny-Status, kanonischen Pet-Namen, kombiniertes Variantenlabel, vollständigen Anzeigenamen, stabilen Visual-Key und RGB-Farbtokens.

Das Modul erzeugt keine Instances, nutzt keinen Zufall, mutiert keine Eingaben, persistiert nichts und beeinflusst weder Schaden noch Chancen, Währung oder Maschinenberechtigungen.

## Ausgerüstete Pets

- Normal behält den bestehenden Seltenheitsstil.
- Gold nutzt den bestehenden Neon-/Gold-Look mit größenkorrektem Ground-Snapping.
- Rainbow erhält einen langsam animierten Spektrum-Look für Körper, Licht, Nametag und vorhandene Orbit-Partikel.
- Shiny ergänzt unabhängig davon ein weiß/cyanfarbenes Highlight, begrenzte Sparkles und ein kleines Zusatzlicht.
- Nametags zeigen den vollständigen Pet-Namen sowie `Variantenlabel • Seltenheit`.
- Änderungen des Visual-Keys werden an bestehenden Modellen idempotent angewendet, ohne Angriffs- oder Follow-State zurückzusetzen.
- Alle Effekt-Instances liegen unter dem Pet-Modell und werden mit ihm zerstört.

Die Animation verwendet ausschließlich den bereits vorhandenen `PetController:update`-Loop. Es entstehen keine RenderStepped-/Heartbeat-Verbindungen pro Pet. Körper, Lichter, Highlight und Partikel werden gecacht; für Variantenanimationen gibt es keine per-frame Descendant-Suche.

## Bestehende UI

- Inventarkarten zeigen vollständige kombinierte Namen und Labels.
- Gold/Rainbow und Shiny werden als zusammengesetzte Farbe-/Rahmenebenen dargestellt.
- Discovery-Toasts, der kurze Hatch-Toast, der bestehende Single-Hatch-Reveal und World-Nametags verwenden dieselbe Auflösung.
- Ein Inventar-Snapshot aktualisiert auch bereits ausgerüstete lokale Visualdaten, falls sich deren Visual-Key ändert.

Die bestehende Vier-Kategorien-Filterung (`Normal`, `Golden`, `Shiny`, `Rainbow`) und der Legacy-Pet-Index bleiben absichtlich kompatibel. Kombinierte Shiny-Zustände erscheinen bis zur späteren Index-Migration weiterhin in der Kategorie `Shiny`, werden dort aber korrekt als `Gold Shiny` beziehungsweise `Rainbow Shiny` beschriftet.

## Bewusst unverändert

- Kein Server-, Schema-, Save-, Damage-, Economy- oder Remote-Change.
- Keine Aktivierung der Ziel-Hatchchancen Gold 1 %, Rainbow 0,1 % oder Shiny 0,01 %.
- Kein Multi-Open und keine Batch-/Cinematic-Hatch-Neugestaltung.
- Keine sechsfachen Discovery-Keys oder Pet-Dex-Migration.
- Keine all-player Pet-Replikation; `workspace.ClientPets` bleibt owner-local.
- Maschinen, Potions, Enchanting, Upgrade Tree und Vide bleiben unverändert.

## Produktionshinweis

Die QOF-04-Regel bleibt bestehen: Vor einer Produktionseinführung müssen alle QOF-03- und älteren Server vollständig beendet werden. QOF-05 ändert die serverseitige Mischversionssicherheit nicht.

## Verifikation

- Pure Tests für alle sechs Kombinationen, Legacy-Werte, ungültige Daten, unbekannte Pets, stabile Keys und Eingabe-Nichtmutation
- Luau-Compile der geänderten Lua-Dateien
- vollständige Balance-, Schema-, Varianten- und PetService-Regression
- Generator-/Place-Source-Parität: 60 ModuleScripts, 1 Script, 1 LocalScript
- binäre RBXL-Signaturprüfung
- semantischer Review und Diff-Prüfung
- `upgradeTree.lua` und Vide ohne Änderungen

Roblox-Studio-Laufzeit-, Visual- und Mobile-Tests bleiben bis zum Nutzerfeedback ausstehend.
