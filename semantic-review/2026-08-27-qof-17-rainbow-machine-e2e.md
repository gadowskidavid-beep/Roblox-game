# Rainbow Machine als zweite serverautoritär gebundene Konvertierungsstation

QOF-17 aktiviert die `RainbowMachine` in Zone 6 neben der bestehenden Gold Machine und führt Golden→Rainbow-Konvertierungen für 2.500 Diamonds über denselben atomaren `UseMachine`-Transaktionspfad aus. Station, UI und Transaktion werden über kanonische Machine-Definitionen parametrisiert, statt einen zweiten Mutationseinstieg anzulegen. Die private Weltinstanz und die clientseitige Session-Generation binden jeden Request an die konkrete Station. Die regenerierte Place-Datei enthält alle 70 Runtime-Quellen bytegenau.

Watch for: Keine blockierenden oder korrektheitsrelevanten Findings; besonders geprüft wurden Rainbow-Zone/-Ökonomie, Shiny-OR, Verlust bei Business-Failure, technische Rollbacks, Quest-Isolation, Stationsautorität, Session-Generationen und unveränderte allgemeine Duplicate-Selection-Semantik.

**Verdict**: APPROVED

## High-level view

`RainbowMachine` ist in Zone 6 freigeschaltet, akzeptiert ausschließlich Golden-Basisvarianten, erzeugt Rainbow und kostet 2.500 Diamonds. Beide Maschinen teilen die 1–7-Input-Kurve 13/26/39/50/63/88/100 Prozent und bleiben einzeln sowie global abschaltbar.

`MachineService` führt Gold und Rainbow durch denselben gelockten Transaktionspfad. Der gemeinsame Pet-Primitive schützt Favorite/Equipped, verlangt eine Spezies und die exakte Eingangsvariante, propagiert Shiny als OR und setzt Pet-Inventar, Discovery und Diamond-Debit bei technischen Fehlern vollständig zurück; ein normaler Fehlwurf verbraucht dagegen Preis und Inputs verbindlich.

`ZoneService` erzeugt genau eine Gold-Station in Zone 3 und eine Rainbow-Station in Zone 6. Eigene GUIDs und private Registry-Einträge binden Model, Anchor, Prompt, Zone, Unlock und 12-Stud-Distanz an exakte Serverinstanzen; kopierte Namen, Tokens oder Stationen begründen keine Autorität.

Der Client routet beide IDs durch dieselbe `UseMachine`-Capability. Generationen entwerten geschlossene oder ersetzte Sessions und verspätete Antworten; die UI filtert dynamisch nach Normal oder Golden und zeigt Ziel, Preis, Chance und Verlustbedingungen.

Duplicate Selection erhält außerhalb aktiver Machine-Sessions die QOF-16-Semantik: Favoriten bleiben geschützt, Equipped-Pets bleiben für allgemeines Multi-Select/Delete auswählbar, und Keeper-Wahl sowie Gruppierung bleiben unverändert.

<details>
<summary>Issues (0)</summary>

Keine Findings.

</details>

<details>
<summary>Details</summary>

## Eine kanonische Definition steuert Ökonomie und Präsentation

`BalanceConfig.Machines.Rainbow` bindet `RainbowMachine`, Zone 6, `Golden` als Quelle, `Rainbow` als Ziel und 2.500 Diamonds. Dieselbe Chance-Tabelle steuert Server-Roll und UI-Anzeige; Startup-Validierung und Tests fixieren IDs, Zonen, Varianten, Preise, Input-Grenzen und alle sieben Wahrscheinlichkeiten.

Die UI bezieht Eingangsvariante und Preis aus der Balance-Definition. Gold-Sessions zeigen Normal-Basispets und Golden/750, Rainbow-Sessions Golden-Basispets einschließlich Shiny Golden und Rainbow/2.500. Vor Bestätigung wird die aktuelle Auswahl aus dem replizierten Inventar rekonstruiert und erneut auf 1–7 gleiche Spezies, Favorite, Equipped und Eingangsvariante geprüft; der Dialog nennt Chance und vollständigen Verlust bei einem Fehlwurf.

## Business-Failure und technischer Fehler bleiben getrennt

`MachineService.resolveMachine` kopiert Gate, ID, Zone, Varianten und Kosten vor Weltvalidierung oder Mutation in einen privaten Snapshot. `PetService.prepareVariantConversion` reserviert Pet-Objekte und Inventar-/Discovery-Snapshots, bevor der exakte Diamond-Betrag still vorgemerkt wird. Erst der Currency-Commit macht die Transaktion endgültig.

Ein Roll oberhalb der Chance entfernt alle Inputs, erzeugt keinen Output und committed den vollen Preis als `success = false`. Exceptions, ungültiges RNG, fehlgeschlagene Pet-Mutation oder fehlgeschlagener Currency-Commit stellen dagegen Pet-Array samt Identität und Reihenfolge, transaktionseigene Discovery-Änderungen und Währungs-Debit wieder her. Die adversarialen Shared-Path-Tests werden durch einen Rainbow-Fehler nach Pet-Mutation ergänzt.

`prepareVariantConversion` bildet `anyShiny` als OR über alle Inputs: mindestens ein Shiny Golden erzeugt genau ein Shiny Rainbow, ohne Stapelwirkung. Favorite und beide Equipped-Repräsentationen werden bei Vorbereitung und unmittelbar vor Mutation abgewiesen.

## Gold-Quest bleibt von Rainbow isoliert

`goldenPetsConverted` wird erst nach erfolgreichem Currency-Commit und nur bei `success and machineType == "Gold"` erhöht. Rainbow-Success, Rainbow-Failure, Admission-Rejection und technischer Rollback erreichen den Hook nicht; alle drei Rainbow-Ergebnisarten werden mit unverändertem Quest-Zähler geprüft.

Inventar-Replikation und Quest-Notification liegen hinter dem Commit und sind geschützt. Ein Notification-Fehler macht eine abgeschlossene wirtschaftliche Transaktion weder retrybar noch teilweise rückgängig.

## Zwei private Stationsidentitäten statt replizierter Namensautorität

Der gemeinsame Builder erzeugt je ein Model in `Zone_3` und `Zone_6`. Eindeutige GUIDs und Registry-Einträge halten die konkreten `Zones`-/Zone-/Model-/Anchor-/Prompt-Instanzen sowie erwartete Attribute, Form, Größe, CFrame, Farbe, Material, Collision- und Prompt-Eigenschaften.

Jeder Request muss Machine-ID und GUID desselben Eintrags treffen. Die Validierung verlangt echten Player, freigeschaltete Zone, descendant `HumanoidRootPart`, maximal 12 Studs Abstand und unveränderte Instanz-/Property-Beziehungen. Konkurrierende Models mit kopierter ID, Token oder Name sowie zusätzliche Prompts werden abgewiesen; Tests decken Clone-, Token-Swap-, Property-, Parent-, Unlock-, Distanz-, Character- und HRP-Manipulation für beide Stationen ab.

Der Validator wird erst nach beiden Builds über `MachineAuthorityBootstrap` installiert. Ein Build-Fehler lässt `MachineService` ohne Weltvalidator und damit fail-closed.

## Generische Capability und generationengebundene UI

`MachineClientSession` akzeptiert ausschließlich `GoldMachine` und `RainbowMachine`, begrenzt Tokens und löscht bei ungültigem Start alte Autorität. Eine Antwort darf die UI nur verändern, wenn Generation, Prompt, Machine-ID, Token und In-Flight-Status noch zum gestarteten Request gehören.

Der zentrale Prompt-Router ersetzt auch beim erneuten Triggern derselben Station zuerst die bestehende Session. Stationswechsel, PromptHidden, Inventory-Close, Navigation und Overlay-Cancel schließen Session, Selection und Overlay; ein laufender Request blockiert Duplikate. Request-/Admission-Fehler reaktivieren Retry und Cancel, terminale Ergebnisse leeren die Auswahl, und Delayed Cleanup zerstört nur sein eigenes Overlay.

`UseMachine` bleibt der einzige öffentliche Mutationseinstieg. `ConvertToGoldenPet` bleibt für Rolling Clients discoverable, antwortet aber ausschließlich mit der mutationfreien Kompatibilitätsablehnung; der Client referenziert das Legacy-Remote nicht.

## Duplicate Selection behält außerhalb der Station QOF-16-Semantik

Machine-spezifische Bedingungen in `_selectDuplicatePets`, `_buildPetDisplayList`, `updatePetInventory` und der Card-Selektion greifen nur mit aktiver Machine-Definition. Dann werden falsche Basisvarianten ausgefiltert und Favorite/Equipped weder gezählt noch ausgewählt.

Ohne Session ist `machineInputVariant == nil`: Das gesamte Inventar wird wie zuvor gruppiert, Favorite-Pets können die Keeper-Wahl beeinflussen, werden aber nicht ausgewählt, und Equipped-Pets erhalten keine neue Sperre. Damage-/Variant-/ID-Tiebreaker und das Ersetzen der Selection-Map sind gegenüber QOF-16 unverändert.

## Ausgeführte Regression und Place-Parität

Die Suite endet mit 236/236 Lua-Tests. Alle 90 Lua/Luau-Dateien kompilieren; `tests/verify_generated_place.py` bestätigt 70/70 bytegenaue Runtime-Quellen und unveränderte Script-Anzahlen in `BATTLE_PETS.rbxlx`. Beide Python-Dateien parsen, und `git diff --check` meldet keine Fehler.

</details>

<details>
<summary>File map</summary>

- `src/ReplicatedStorage/Shared/BalanceConfig.lua` — aktiviert und validiert die Rainbow-Definition.
- `src/ReplicatedStorage/Shared/MachineClientSession.lua` — erweitert generationengebundene Sessions auf Gold und Rainbow.
- `src/ServerScriptService/Services/MachineService.lua` — teilt Snapshot-/Transaktionspfad und isoliert den Gold-Quest-Hook.
- `src/ServerScriptService/Services/ZoneService.lua` — baut und validiert zwei GUID-/instanzgebundene Stationen.
- `src/StarterPlayer/StarterPlayerScripts/Main.client.lua` — routet beide Stationen über `UseMachine`.
- `src/StarterPlayer/StarterPlayerScripts/UIController.lua` — parametrisiert Auswahl, Bestätigung, Ergebnis und Lifecycle.
- `tests/BalanceConfig.spec.lua` — erwartet beide aktiven Gates.
- `tests/MachineService.spec.lua` — ergänzt Rainbow-Ökonomie, Outcomes, Shiny, Rollback und Quest-Isolation.
- `tests/MachineStation.spec.lua` — prüft beide Stationen und adversariale Integrität.
- `tests/MachineClient.spec.lua` — prüft generisches Routing und Session-Generationen.
- `tests/verify_generated_place.py` — aktualisiert QOF-17-Verträge und Source-Parität.
- `BATTLE_PETS.rbxlx` — regeneriertes Place-Artefakt mit aktuellen Runtime-Quellen.
- `README.md` — dokumentiert beide aktiven Maschinen und Verifikation.
- `docs/QOF-17-rainbow-machine-e2e.md` — untracked End-to-End-Vertrag und Checks.

Full diff: `git diff origin/qof-16-gold-machine-e2e`; zusätzlich `docs/QOF-17-rainbow-machine-e2e.md` als untracked Datei.

</details>
