# QOF-27 – Maschinen-Input-Staging vor RNG

Status: **Code-verifiziert – Studio-Test ausstehend**

QOF-27 ordnet den gemeinsamen Gold-/Rainbow-Maschinenpfad neu: Pet-Inputs werden erst nach erfolgreicher zentraler Profil-/Currency-Reservierung aus dem sichtbaren Inventar entfernt und erst danach wird gewürfelt. Ein normaler Chancen-Misserfolg verbraucht Inputs und Preis endgültig; ausschließlich technische Fehler vor dem Currency-PONR restaurieren den exakten Ausgangszustand.

## Kanonischer Vertrag

- Gold Machine bleibt in Zone 3, konvertiert Normal → Golden und kostet exakt 750 Diamonds.
- Rainbow Machine bleibt in Zone 6, konvertiert Golden → Rainbow und kostet exakt 2.500 Diamonds.
- Beide Maschinen verwenden denselben Transaktionskern und unverändert die Chancekurve 1–7 Inputs = 13/26/39/50/63/88/100 %.
- Zulässig sind ausschließlich 1–7 eigene, gleiche Species und gleiche Quellvariante; Favoriten, ausgerüstete, doppelte, sparse, fremde oder ungültige IDs werden vor Mutation abgewiesen.
- `PetService.prepareVariantConversion` validiert unter dem bereits gehaltenen Inventory-Lease und erzeugt nur Input-/Undo-Metadaten. Vor RNG existieren weder Output-GUID noch Output-Pet noch Dex-Schreibplan.
- `CurrencyService.beginSpendTransaction` registriert den zentralen `ProfileTransactionService`-Owner und die domain-first Settlement-Funktion, bevor ein Input entfernt wird. Dadurch kann Autosave keinen reversiblen Staging-Zustand persistieren.
- `PetService.stageVariantConversion` entfernt alle ausgewählten Inputs in absteigender Indexreihenfolge. Nicht ausgewählte Pets behalten dieselbe Tabellenidentität, Reihenfolge und Objektidentität.
- RNG läuft ausschließlich im Zustand `INPUTS_STAGED`. Nicht-finite Werte, falsche Typen oder Werte außerhalb 0…1 sind technische Fehler.
- Bei Erfolg wird erst nach RNG genau ein neues Output-Pet erzeugt und eingefügt. Shiny ist das OR aller Inputs; `enchantId` wird nicht übernommen; ausschließlich die Output-Dex-Keys werden geschrieben.
- Bei normalem Chancen-Misserfolg entstehen weder Output noch Dex-Schreibvorgang. Die gestagten Inputs bleiben verbraucht.
- Der Currency-Commit ist der eindeutige Point of No Return. Danach werden Transaktion und Wirtschaftsresultat vor jeder Benachrichtigung als terminal markiert.
- Jeder technische Pre-PONR-Fehler restauriert nur bei beweisbarer Ownership die ursprüngliche Pet-Tabelle, Reihenfolge, Referenzen und eigenen Dex-Writes, bevor die stille Currency-Reservierung aufgehoben wird. Ist Ownership nicht beweisbar, bleiben Profil-Owner, Inventory-Lease, Machine-Lock und aktiver Record retrybar erhalten.
- Fehler in post-PONR Hooks, Inventarreplikation, Questbenachrichtigung oder Lease-Freigabe können Inputs/Diamonds nicht zurückrollen und keine zweite RNG-/Wirtschaftstransaktion auslösen. Ein dauerhaftes Notification-Retry-Ledger ist nicht Teil dieses QOFs.

## Abgedeckte Regressionen

- Am RNG-Einstieg sind alle ausgewählten Inputs unsichtbar; Keeper behalten exakte Reihenfolge und Referenzen; Diamonds und Dex sind unverändert; Profil-Owner und Inventory-Lease sind aktiv.
- Strikte Reihenfolge für Gold/Rainbow und Erfolg/Misserfolg: `stageInputs → RNG → optional output/Dex → Currency-PONR → notifications`.
- Gewöhnlicher Gold- und Rainbow-Misserfolg verbraucht Inputs plus exakten Preis und schreibt keine Discovery.
- Ungültiges RNG: Throw, `nil`, String, NaN, `+∞`, `−∞`, kleiner 0 und größer 1.
- Technische Fehler nach partieller Input-Entfernung, vollständigem Input-Staging, Output-Insert, erstem Dex-Write und allen Dex-Writes.
- Exakte Restoration nicht benachbarter ausgewählter Pets mit unveränderter Tabellen-/Objektidentität.
- Direkte PetService-Zustandsübergänge `VALIDATED → INPUTS_STAGED → OUTCOME_STAGED`; doppelte oder falsche Übergänge scheitern.
- Echter zentraler Profil-Owner ist während RNG aktiv und blockiert damit die Save-Zulassung.
- Nicht beweisbare Restoration bleibt für Leave und Shutdown erhalten und settlet nach Wiederherstellung der erwarteten Ownership exakt.
- Post-PONR Hook-, Notification- und Lease-Release-Fehler behalten das wirtschaftliche Ergebnis; ein zweiter Versuch würfelt nicht erneut.
- Bestehende Chancen, Preise, Zone-/Station-Autorität, Shiny-OR, Enchant-Verlust, Gold-Quest, UI und Pet-Dex bleiben regressionsgedeckt.

## Lokale Verifikation

- Gepinnte Pflicht-Toolchain erfolgreich geprüft (`rbxmk 0.9.1`, Luau/Compiler `0.735`, Toolchain-Lock `dfcc08b6bc1c5ef8333513a1130bd050d84a51e19c8eb1f4288263d5659600c1`).
- Vollständige Luau-Suite: **417/417** in kanonischer und umgekehrter Reihenfolge.
- Luau-Compile: **79/79** Runtime-Sources.
- Python-Compile für Tools und Tests erfolgreich.
- `verify_generated_place.py`: 79 Sources bytegenau, davon 77 ModuleScripts, 1 Script und 1 LocalScript.
- Unabhängiger semantischer Review: **APPROVED**; die nicht-blockierenden Dokumentationsformulierungen wurden auf die tatsächlich implementierten Garantien begrenzt.
- Unabhängiger Fresh-Build, RBXL-Signatur, kanonisches ZIP, Provenienz und SHA-Manifest erfolgreich.
- `git diff --check` erfolgreich.

## Testartefakt

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.167.422 | `2fbefc790e13577d2cb17b34c7d2f1db20587f71b65c7ce73cc3bcefc0604bdb` |
| `BATTLE_PETS_QOF-27_TEST.rbxl` | 412.002 | `cf21636b78b8b9cf589969baf824bce9d1adede30a71a0b648fa17963d3ba88e` |
| `BATTLE_PETS_QOF-27_RBXLX.zip` | 234.599 | `4e5a8e90b6b19475f9ebbdc33043cdee79688cce0eeb142cc174c897f93b768c` |
| `BATTLE_PETS_QOF-27_SHA256SUMS.txt` | 1.080 | `35f33e5910930a7ba38261ee5f5500993b2950d745fd4c3c7737b6bf5238189b` |

Die RBXL beginnt mit der exakten binären Roblox-Signatur `<roblox!\x89\xff\r\n\x1a\n`.

## Verbindlicher Studio-Testplan

1. `BATTLE_PETS_QOF-27_TEST.rbxl` in Roblox Studio öffnen und **Play** starten. Erwartet: Welt, Zonen, Pet-Inventar, Gold-/Rainbow-Stationen und UI laden ohne rote Server-/Clientfehler; bestehende Währungen, Pets, Dex und Enchants erscheinen unverändert.
2. In der **Server**-Command-Bar den Reihenfolge-Trace aktivieren:
   ```lua
   local Players = game:GetService("Players")
   local S = game.ServerScriptService.Services
   local Machine = require(S.MachineService)
   local Data = require(S.DataService)
   local p = Players:GetPlayers()[1]
   Machine.setTransactionHook(function(stage, context)
       local d = Data.getPlayerData(p)
       if stage == "afterInputStaging" then
           print("QOF27_STAGED_BEFORE_RNG", #d.pets, d.diamonds,
               context.prepared.phase,
               context.prepared.outputPet == nil,
               context.prepared.discoveryKeys == nil)
       elseif stage == "afterOutcomeStaging" then
           print("QOF27_OUTCOME_STAGED", context.success,
               context.prepared.phase, #d.pets, d.diamonds)
       elseif stage == "afterCurrencyCommit" then
           print("QOF27_PONR", context.success, #d.pets, d.diamonds)
       end
   end)
   Machine.setRandomSource(function() return 1 end)
   ```
   Danach an der Gold Machine **2–6** passende Normal-Pets auswählen (nicht 7, da sieben 100 % garantieren). Erwartet: Trace-Reihenfolge `QOF27_STAGED_BEFORE_RNG` vor Outcome/PONR; beim ersten Trace sind Output und Discovery-Plan `nil`, Diamonds noch unverändert und Inputs bereits aus dem Inventar entfernt. Ergebnis ist normaler Misserfolg: alle Inputs bleiben weg, exakt 750 Diamonds weg, kein Output und keine neue Output-Dex-Discovery.
3. Gold-Erfolg erzwingen:
   ```lua
   local Machine = require(game.ServerScriptService.Services.MachineService)
   Machine.setRandomSource(function() return 0 end)
   ```
   Mindestens zwei gleiche Normal-Pets konvertieren, davon möglichst eines Shiny und eines mit Enchant. Erwartet: genau ein neues Golden-Pet, Shiny wenn irgendein Input Shiny war, kein `enchantId`, exakt 750 Diamonds Kosten, nur Output-Dex neu und Trace `staged → outcome → PONR`.
4. Rainbow-Pfade prüfen. Zuerst mit `return 1` zwei bis sechs gleiche Golden-Pets verwenden: normaler Misserfolg verbraucht alle Inputs und exakt 2.500 Diamonds ohne Output/Dex. Danach mit `return 0` erneut testen: genau ein Rainbow-Output, Shiny-OR erhalten, kein Enchant, exakt 2.500 Diamonds.
5. Technischen RNG-Fehler prüfen:
   ```lua
   local Machine = require(game.ServerScriptService.Services.MachineService)
   Machine.setRandomSource(function() return 0/0 end)
   ```
   Zwei nicht benachbarte passende Pets im Inventar auswählen. Erwartet: Conversion wird sicher abgelehnt; beide Pets erscheinen in ursprünglicher Reihenfolge mit identischen Daten/Enchant-/Shiny-Werten wieder; Diamonds und Dex bleiben exakt unverändert; ein unmittelbar folgender gültiger Versuch ist nicht dauerhaft blockiert.
6. Post-PONR-Terminalität prüfen:
   ```lua
   local Machine = require(game.ServerScriptService.Services.MachineService)
   Machine.setRandomSource(function() return 0 end)
   Machine.setTransactionHook(function(stage)
       if stage == "afterCurrencyCommit" then
           error("QOF27 injected post-PONR notification seam")
       end
   end)
   ```
   Einen Gold-Erfolg ausführen. Erwartet: trotz injiziertem Fehler genau ein Output und genau 750 Diamonds Kosten; keine Restoration und kein zweiter RNG-Lauf. Danach Hook entfernen.
7. Testseams zurücksetzen:
   ```lua
   local Machine = require(game.ServerScriptService.Services.MachineService)
   Machine.setRandomSource(math.random)
   Machine.setTransactionHook(nil)
   ```
   Anschließend normale Gold- und Rainbow-Conversions ohne Forcing ausführen. Erwartet: Chanceanzeige 13/26/39/50/63/88/100 % passt zur Auswahl; sieben Inputs garantieren Erfolg; Favoriten, ausgerüstete und gemischte Species/Varianten werden vor Kosten und RNG abgewiesen.
8. Inventar- und Dex-UI nach mehreren Erfolgen und normalen Misserfolgen schließen/öffnen. Erwartet: keine Ghost-Pets, kein doppeltes Output, keine Discovery auf Misserfolg; Golden/Rainbow/Shiny-Präsentation und Schadenswerte bleiben korrekt.
9. Einen erfolgreichen und einen fehlgeschlagenen Maschinenversuch durchführen, danach verlassen und neu beitreten. Erwartet: nur terminale Ergebnisse persistieren; kein gestagtes Zwischeninventar, kein still reservierter Preis, keine wiederauftauchenden verbrauchten Inputs.
10. Mit zwei Spielern sowie Desktop- und Mobile-Emulation einen Smoke-Test durchführen. Erwartet: Machine-Locks sind pro Spieler isoliert; Zonen-/Distanz-/Stationsautorität, Auswahl-UI, Ergebnisanzeige, Pet-Dex, Enchanting, Hatching, Shop und Potions regressieren nicht.

## Bekannte Grenzen

Der echte Roblox-Studio-Playtest, DataStore-Rejoin, Netzwerk-/Physikpfad und ein harter Prozessabbruch können im Linux-Sandbox-Build nicht ausgeführt werden; das Studio-Gate bleibt daher ausdrücklich offen. Die Save-/Lifecycle-Evidenz kombiniert den realen zentralen Profil-Owner mit Machine-Leave-/Shutdown-Faulttests, ist aber kein vollständiger Roblox-DataStore-End-to-End-Test. Post-PONR-Benachrichtigungen sind geschützt, besitzen jedoch kein dauerhaftes Retry-Ledger. QOF-27 fügt außerdem kein allgemeines Request-ID-/Receipt-Ledger ein.

QOF-28 (Auto-Hatch Contract V2, HUD und x1/x3/x9) bleibt wegen offener Produktentscheidungen blockiert und wird durch diesen Handoff nicht gestartet.

## Offenes Feedback

Bitte nach dem Studio-Test melden:

1. Zeigt der Trace bei Gold und Rainbow tatsächlich `Inputs entfernt → RNG/Outcome → Currency-PONR` mit unveränderten Diamonds vor dem PONR?
2. Verbraucht ein normaler Chancen-Misserfolg sämtliche ausgewählten Inputs und den exakten Preis, ohne Output oder neue Dex-Discovery?
3. Restauriert das ungültige RNG alle ausgewählten Pets in exakt derselben Reihenfolge und mit unveränderten Shiny-/Enchant-Daten sowie unveränderten Diamonds?
4. Erzeugt Erfolg genau ein unenchanted Output, übernimmt Shiny als OR und aktualisiert ausschließlich die passende Output-Dex-Discovery?
5. Bleiben post-PONR Fehler wirtschaftlich terminal, und persistieren nach Rejoin ausschließlich vollständige Endzustände?
6. Gibt es rote Server-/Clientfehler oder Regressionen bei Machine-UI, Pet-Dex, Enchanting, Hatching, Shop oder Potions?

Status bleibt bis zu dieser Rückmeldung **Code-verifiziert – Studio-Test ausstehend**.
