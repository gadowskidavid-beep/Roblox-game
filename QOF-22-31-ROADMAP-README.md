# Battle Pets – QOF-22 bis QOF-31 Stabilisierung und Release

> **Fortsetzbarer Arbeitsauftrag für Kiro**
> Diese Datei ist gleichzeitig Roadmap, Produktvertrag, Fortschrittsprotokoll und Prompt für spätere Sessions. Eine neue Session soll diese Datei zuerst lesen, den Repository-Stand verifizieren und beim ersten noch nicht abgeschlossenen QOF fortfahren.

## 1. Ziel

QOF-01 bis QOF-21 haben das erweiterte Pet-, Hatch-, Potion-, Maschinen-, Enchant-, Dex- und Release-System aufgebaut. QOF-22 bis QOF-31 beheben die bei der Gesamtanalyse gefundenen Fehler und schließen die noch offenen Release-, Lifecycle-, Daten- und Studio-Abnahmen.

Die Arbeit ist erst abgeschlossen, wenn:

- der vollständige QOF-01–31-Stand auf `main` integriert ist,
- alle wirtschaftlichen und Inventartransaktionen all-or-nothing sind,
- keine neuere Potion-, Pet- oder Currency-Mutation durch einen Rollback überschrieben werden kann,
- Migrationen fehlerhafte alte Daten sicher normalisieren,
- die Release-Pipeline verpflichtend und reproduzierbar geprüft wird,
- und der Nutzer die abschließende Roblox-Studio-Matrix bestätigt hat.

## 2. Verbindliche Ausgangsbasis

Die vollständige QOF-01–21-Implementierung liegt auf:

- Remote-Branch: `origin/qof-20-21-pet-dex-release-pipeline`
- Baseline-Commit: `6f453131ea6d9cd9ae59321e476987107791f25e`

`main` stand bei Erstellung dieser Roadmap auf `b3fee6f519a6d3367381b09d74306fd6a08d69f9` und enthält die spätere QOF-Implementierung nicht vollständig.

### Pflichtprüfung vor jeder Fortsetzung

```bash
git status --short --branch
git rev-parse HEAD
git merge-base --is-ancestor 6f453131ea6d9cd9ae59321e476987107791f25e HEAD
```

Wenn der letzte Befehl fehlschlägt:

1. keine QOF-22+-Änderung auf dem falschen Stand implementieren,
2. keine uncommitteten Nutzeränderungen verwerfen,
3. den exakten Baseline-Commit `6f453131ea6d9cd9ae59321e476987107791f25e` lokal verfügbar machen,
4. einen neuen Arbeitsbranch **von dieser unveränderlichen SHA** erstellen – nicht von einem möglicherweise weiterbewegten Remote-Ref,
5. diese Roadmap als ersten Bootstrap-Commit in den neuen Branch übernehmen,
6. erst danach mit QOF-22 fortfahren.

Empfohlener Integrationsbranch:

```text
qof-22-31-stabilization-release
```

Der Bootstrap ist idempotent: Existiert der Branch bereits, wird er geprüft und nicht neu erzeugt. Fremde oder uncommittete Nutzeränderungen werden niemals überschrieben. Vor dem ersten Gameplay-Commit muss `git diff 6f453131ea6d9cd9ae59321e476987107791f25e..HEAD` ausschließlich die erwartete Roadmap-/Bootstrap-Änderung zeigen.

Die Roadmap muss von Git getrackt sein und aus `HEAD` gelesen werden können. Ist sie untracked, stammt sie nicht aus `HEAD` oder ist ihre Baseline unklar, stoppt die Session vor jeder Implementierung. Nie direkt auf `main` pushen. `main` wird erst in QOF-31 über einen geprüften Pull Request aktualisiert.

## 3. Unveränderliche Produktregeln

Diese Regeln dürfen nur nach einer ausdrücklichen neuen Entscheidung des Nutzers geändert werden.

### Pet-Varianten und Schaden

- Unterstützte Basisvarianten: `Normal`, `Golden`, `Rainbow`.
- Es gibt kein Mythic-System.
- Shiny ist ein unabhängiger Modifier und kann mit jeder Basisvariante kombiniert werden.
- Basis-Schadensmultiplikatoren:
  - Normal: ×1
  - Golden: ×2
  - Rainbow: ×5
  - Shiny zusätzlich: ×1,5
- Daraus folgen unter anderem Golden Shiny ×3 und Rainbow Shiny ×7,5.
- Kanonischer Kampfschaden darf Bruchteile enthalten; beispielsweise bleiben 3 × 1,5 = 4,5 erhalten.
- Es wird nicht pro Pet oder pro Multiplikator abgerundet. Falls ein Verbraucher zwingend Ganzzahlen benötigt, darf er erst nach der vollständigen Schadenssumme an seiner klar dokumentierten Systemgrenze runden.
- Gespeichertes `pet.damage` bleibt nur ein Kompatibilitäts-/Anzeige-Mirror und ist niemals Kampfauthorität.

### Hatch

- Ein Ei kann sechs Zustände liefern: Normal, Normal Shiny, Golden, Golden Shiny, Rainbow, Rainbow Shiny.
- RNG, Preise, Luck, Upgrade-Effekte, Varianten und Pet-Erstellung bleiben serverautoritativ.
- Shiny-Basischance: 0,01 % beziehungsweise 1:10.000, bevor gültige Multiplikatoren und Caps angewandt werden.
- Feste manuelle und automatische Batchgrößen sind ausschließlich `x1`, `x3`, `x9`; `x2`, `x5`, `x10` und `MAX` entfallen im neuen Vertrag vollständig.
- Diese am 28. August 2026 ausdrücklich vom Nutzer entschiedene Regel supersediert sowohl den historischen manuellen QOF-10-Vertrag `x1/x3/MAX` als auch QOF-18 Auto-Hatch V1 `x1/x2/x5/x10` und die frühere Fassung dieser Roadmap.
- Die Umstellung verwendet einen neuen versionierten Client-/Serververtrag. Alte und neue Rolling-Versionen müssen kontrolliert fail-closed reagieren; kein V1-Tier, historischer Fixed-/MAX-Request oder zusätzliches Feld darf als gültiger V2-Intent fehlinterpretiert werden.
- Paid Auto-Hatch behält mangels gegenteiliger Produktentscheidung vorerst 500 Diamonds, 600 Sekunden Zugang und drei Sekunden Batchintervall; der Kauf im Shop startet keine Session.
- Genau ein HUD-Icon steuert Auswahl, Start und Stop. Prompt- und Shop-Oberflächen dürfen keinen zweiten Start-/Stop-Einstieg besitzen.
- Der Server bindet jeden Start frisch an eine kanonische Station, hält Session/RNG/Preis/Inventar autoritativ und beendet vor dem nächsten Batch bei echter Positionsänderung oberhalb der dokumentierten Jitterschwelle.
- Auto-Hatch verbraucht keine Shiny-Potion-Charges, solange der Nutzer dies nicht ausdrücklich ändert.
- Vor QOF-28 sind nur noch zwei Produktdetails zu bestätigen: ob der Selector alle freigeschalteten Eier fern auswählbar macht oder ausschließlich die aktuell nahe Station, und wie bestehende x2/x5/x10-Entitlements nach x3/x9 migriert werden.

### Gold- und Rainbow-Maschinen

- Gold Machine: Zone 3, Normal → Golden, 750 Diamonds.
- Rainbow Machine: Zone 6, Golden → Rainbow, 2.500 Diamonds.
- Zulässig sind 1–7 nicht favorisierte, nicht ausgerüstete Pets derselben Art und Eingangsvariante.
- Erfolgschancen für beide Maschinen:
  - 1 Pet: 13 %
  - 2 Pets: 26 %
  - 3 Pets: 39 %
  - 4 Pets: 50 %
  - 5 Pets: 63 %
  - 6 Pets: 88 %
  - 7 Pets: 100 %
- Alle ausgewählten Eingabe-Pets werden vor der Erfolgsauflösung atomar aus dem Inventar entfernt.
- Der Preis wird in derselben stillen Transaktion reserviert.
- Erst danach wird der Erfolg serverseitig gewürfelt.
- Ein normaler Misserfolg verbraucht Pets und Diamonds endgültig.
- Ein technischer Fehler stellt Pets, Diamonds und Dex exakt wieder her.
- Bei Erfolg ist das Ausgabe-Pet Shiny, wenn mindestens ein Eingabe-Pet Shiny war.
- Das Ausgabe-Pet ist neu und besitzt keinen Enchant.

### Persistenz und Wirtschaft

- Bestehende Pets, Favoriten, Ausrüstung, Zonen, Währungen, Fortschritt und Discoveries dürfen bei Migrationen nicht verloren gehen.
- Refunds verwenden keine Reward-/Bonuspfade.
- Composite Mutations verwenden stille Spend-Handles mit explizitem Commit/Rollback.
- Vor dem Commit darf kein falscher Currency-Zwischenstand an den Client repliziert werden.
- Rollback darf nur die Mutation der eigenen Transaktion zurücknehmen und niemals neuere fremde Mutationen überschreiben.

## 4. Arbeitsmodus für jede spätere Kiro-Session

Eine neue Session führt folgende Schritte aus:

1. Diese **getrackte** Datei vollständig lesen und prüfen, dass ihr Inhalt aus `HEAD` stammt.
2. `.kiro/steering/qof-test-debug-workflow.md` lesen und befolgen.
3. Dirty State, Branch, Upstream, `HEAD`, Baseline-Abstammung und Pflicht-Toolchain prüfen; fremde Änderungen bewahren.
4. In der Fortschrittstabelle immer das erste QOF wählen, dessen Status nicht `ABGESCHLOSSEN` ist.
5. Zustandsabhängig handeln:
   - `OFFEN`/`IN ARBEIT`: nur bei erfüllten Abhängigkeiten implementieren,
   - `BLOCKIERT`: ausschließlich den dokumentierten Blocker bearbeiten oder auf den Nutzer warten,
   - `CODE-VERIFIZIERT`/`STUDIO-TEST AUSSTEHEND`: keinen neuen Scope beginnen; den gebundenen Build testen, Feedback verarbeiten oder warten,
   - `STUDIO-BESTÄTIGT`: Evidenz, Commit und Dokumentation abschließen,
   - `ABGESCHLOSSEN`: erst dann zum nächsten Tabellenpunkt gehen.
6. Relevante Codepfade vor Änderungen vollständig untersuchen.
7. Implementieren, statisch prüfen, Regressionstests ausführen und semantisch reviewen.
8. Einen echten QOF-Testbuild mit der gelockten Pflicht-Toolchain erzeugen.
9. Status, nächste Aktion, Commit, Artefakt-SHA und Studio-Gate in dieser Datei aktualisieren.
10. Dem Nutzer Testschritte geben und auf dessen Studio-Ergebnis warten.
11. Das nächste QOF erst beginnen, wenn der Nutzer für **dieses QOF und diesen Build** ausdrücklich `Weiter` schreibt.

Keine Aufgabe wird nur aufgrund eines erfolgreichen Exitcodes als fertig markiert. Jede Abnahme muss gegen die konkreten Erfolgskriterien des QOF geprüft werden. Fehlt ein Pflichtwerkzeug, ist der Zustand `BLOCKIERT` und nicht `CODE-VERIFIZIERT`.

## 5. Statusdefinitionen

- `OFFEN`: noch nicht begonnen; nächste Aktion ist die Untersuchung/Implementierung dieses QOF.
- `IN ARBEIT`: Code oder Untersuchung läuft; nächste Aktion muss konkret in der Tabelle stehen.
- `CODE-VERIFIZIERT`: Implementierung und alle Pflichtprüfungen bestanden; nächste Aktion ist Testbuild/Studio-Gate, nicht das nächste QOF.
- `STUDIO-TEST AUSSTEHEND`: Test-RBXL und Testplan wurden übergeben; nur Feedback zum dokumentierten Build bearbeiten oder warten.
- `BLOCKIERT`: konkrete Entscheidung, Pflicht-Toolchain oder externe Freigabe fehlt; nur diesen Blocker bearbeiten.
- `STUDIO-BESTÄTIGT`: Nutzer hat die definierten Tests am dokumentierten Commit und Artefakt-SHA ohne Blocker bestätigt; Abschlussdokumentation steht noch aus.
- `ABGESCHLOSSEN`: Studio-Gate erfüllt oder ausdrücklich `n/a`, Dokumentation aktualisiert und Änderungen im vorgesehenen Branch committed.

## 6. Fortschritt

| QOF | Paket | Status | Abhängigkeit | Nächste Aktion | Studio-Gate | Evidenz: Commit / Artefakt-SHA / CI |
|---|---|---|---|---|---|---|
| QOF-22 | Baseline und Pflicht-Toolchain | ABGESCHLOSSEN | QOF-21 | auf ausdrückliches `Weiter` für QOF-23 warten | n/a | Implementierung: `8e5a37c6b8560d7f87a2f1943aad5cd7862299d5`; Fresh-QOF-21-RBXL: `9f7c7653b982a564da415b3ba3bb8e48370a559d9e3c1552df2403d57daccaaf`; Lock: `dfcc08b6bc1c5ef8333513a1130bd050d84a51e19c8eb1f4288263d5659600c1`; Tests 345/345 normal + reverse; Compile 77/77 |
| QOF-23 | DataSchema V12 und hostile Save-Normalisierung | ABGESCHLOSSEN | QOF-22 | QOF-24 durch ausdrückliches `Weiter` freigegeben | nicht separat bestätigt; Nutzer hat Fortsetzung ausdrücklich freigegeben | Implementierung: `21fdf0e2dbcc1607d814bb9d6f7d0986abec2d1c`; RBXL: `b8a2d611beab73db67ee8b4fdb62b8d8e054f8b9ff91064bfb44a11a4eb2c40a`; Manifest: `3aeb0f26c1f2cd4897a1e512904e8ace708c9535d644814e46d62a0a018a1278`; Tests 356/356 normal + reverse; Compile 78/78; Abschluss durch Nutzer-`Weiter` ohne separat gemeldetes Studioergebnis |
| QOF-24 | Kanonische Schadenspräzision | ABGESCHLOSSEN | QOF-23 | QOF-25 durch ausdrückliches `Weiter` freigegeben | nicht separat bestätigt; Nutzer hat Fortsetzung ausdrücklich freigegeben | Implementierung: `52a335690d56a236016194065e5fa8138457e6ef`; RBXL: `68ec212191c21d9d2f524bada14e20eef2505c3ff5848e22c35a5ba6dd5f33bb`; Manifest: `bd12420d1989dd4a184e0ecc6ae90340666b52b56aa79955075120a8126e3b1c`; Tests 366/366 normal + reverse; Compile 78/78; Abschluss durch Nutzer-`Weiter` ohne separat gemeldetes Studioergebnis |
| QOF-25 | Zentrale atomare Profil-/Currency-Transaktionen | ABGESCHLOSSEN | QOF-24 | QOF-26 durch ausdrückliches `Weiter` freigegeben | nicht separat bestätigt; Nutzer hat Fortsetzung ausdrücklich freigegeben | Implementierungscommit: `b25979fb0ce38250a9c6079a535a35e1dfe6d093`; RBXL: `2df665a6baa4b0b335abad48f3c1dbe7d58884e07eeb57c462e0083617143286`; Manifest: `c523966008de7a15fa60f88b3622b9bc0615a65acd0c5a38ce5a86a8444146dc`; Tests 399/399 normal + reverse; Compile 79/79; Abschluss durch Nutzer-`Weiter` ohne separat gemeldetes Studioergebnis |
| QOF-26 | Potion-Concurrency und Lifecycle | ABGESCHLOSSEN | QOF-25 | QOF-27 durch ausdrückliches `Weiter` freigegeben | nicht separat bestätigt; Nutzer hat Fortsetzung ausdrücklich freigegeben | Implementierungscommit: `5df4944`; RBXL: `2df33d0b3bd136e4030c2583fabdd4b8f731b3224e47abf103e47dd8f7770db1`; Manifest: `78f94977ea444650141295a70dfbcdbb62c9104d2a6ca25957f42f475080747e`; Tests 409/409 normal + reverse; Compile 79/79; semantischer Review APPROVED; Abschluss durch Nutzer-`Weiter` ohne separat gemeldetes Studioergebnis |
| QOF-27 | Maschinenreihenfolge und Rollback-Invarianten | IN ARBEIT | QOF-25 | bestehende MachineService-Reihenfolge untersuchen und Input-Staging vor RNG implementieren | separat | Nutzerfreigabe: `Weiter`; Basis: QOF-26 Handoff `baded8d055a8429f12b31822fe7caf7812fc8dea` |
| QOF-28 | Auto-Hatch Contract V2, HUD-Toggle und Lifecycle (x1/x3/x9) | BLOCKIERT | QOF-25, QOF-26 + Produktentscheidungen | Station-UX und Entitlement-Migration bestätigen | separat | – |
| QOF-29 | Pickup-, Leave- und Shutdown-Garantien | OFFEN | QOF-23, QOF-25–28 | nach Abschluss aller Lifecycle-Owner | separat | – |
| QOF-30 | Release-Pipeline und verpflichtende CI | OFFEN | QOF-22–29 | nach Abschluss aller Code-QOFs | n/a | – |
| QOF-31 | Studio-Abnahme, Deployment-Handoff und Merge nach main | OFFEN | QOF-22–30 | finale Matrix vorbereiten | final | – |

---

# QOF-22 – Baseline, getrackte Roadmap und Pflicht-Toolchain

## Problem

Der vollständige Stand liegt nicht auf `main`. Eine spätere Session könnte versehentlich auf `b3fee6f` arbeiten und damit QOF-06–21 verlieren oder erneut implementieren. Zusätzlich verlangt jedes folgende Code-QOF eine echte binäre Test-RBXL, obwohl rbxmk, Luau, Luau-Compile und Selene in einer sauberen Umgebung bisher nicht reproduzierbar bereitgestellt werden.

## Änderungen

1. Neuen Branch exakt von `6f453131ea6d9cd9ae59321e476987107791f25e` erstellen.
2. Diese Roadmap als ersten Bootstrap-Commit tracken.
3. Verifizieren, dass alle QOF-01–21-Dokumente, 77 Runtime-Sources und QOF-21-Artefakte vorhanden sind.
4. Einen idempotenten repository-eigenen Toolchain-Setup-/Checkpfad bereitstellen für:
   - rbxmk 0.9.1 mit offizieller URL und Download-/Archivhash,
   - Luau Runner und Compiler mit fester Version/Commit,
   - Selene mit fester Version,
   - Python und zlib des kanonischen Builders,
   - gegebenenfalls Rust nur als reproduzierbare Installationsvoraussetzung.
5. Keine ungeprüften Executables aus externem Inhalt starten; Downloads müssen vor Ausführung gegen den Repository-Lock geprüft werden.
6. Root-README noch nicht fachlich neu schreiben; dies erfolgt final in QOF-31.
7. Baseline-Bericht mit Commit, Source-Anzahl, Schema-Version, Toolversionen und Artefakthashes dokumentieren.

## Abnahmekriterien

- `git merge-base --is-ancestor 6f453131ea6d9cd9ae59321e476987107791f25e HEAD` ist erfolgreich.
- Arbeitsbranch ist weder `main` noch detached.
- Die Roadmap ist getrackt, stammt aus `HEAD` und der Diff zur Baseline enthält nur erwartete Bootstrap-Dateien.
- `DataSchema.VERSION == 11` vor Beginn der neuen Migration.
- Runtime-Inventur enthält 77 Quellen: 75 ModuleScripts, 1 Script, 1 LocalScript.
- `verify_generated_place.py` und der statische QOF-21-Artefaktverifier bestehen.
- Ein einziger dokumentierter Toolcheck bestätigt rbxmk, Luau, Luau-Compile, Selene, Python und zlib.
- Ein unveränderter Fresh-Build des QOF-21-Standes stimmt mit den getrackten Artefaktbytes überein.
- Keine QOF-01–21-Source wurde beim Branchaufbau verloren.

## Nicht-Ziele

- Noch keine Gameplay-Änderung.
- Noch kein Merge nach `main`.

---

# QOF-23 – DataSchema V12 und hostile Save-Normalisierung

## Problem

`DataSchema` normalisiert `upgrades` und `masteryBuffs` bislang nur als Tabellen. Alte, beschädigte oder administrativ manipulierte Level können außerhalb gültiger Grenzen liegen. Verbraucher wie `UpgradeService` können anschließend ungültige Leveltabellen indexieren.

## Änderungen

1. Schema von V11 auf V12 erhöhen.
2. Quest-Upgrades ausschließlich gegen bekannte `QuestData`-Definitionen normalisieren; das Maximum wird aus der tatsächlichen Leveldefinition abgeleitet.
3. Mastery-Buffs ausschließlich gegen bekannte `MasteryData`-Definitionen normalisieren; gültiges Maximum ist die kleinste konsistente Grenze aus `maxLevel`, Kosten- und Bonustabellen.
4. Werte müssen endlich, ganzzahlig und innerhalb `0..maxLevel` sein.
5. Unbekannte Progressions-IDs werden aus dem kanonischen Runtime-State entfernt. Sie dürfen keine Wirkung besitzen; es gibt keinen offenen alternativen Legacy-Pfad.
6. Alle öffentlichen Bonusresolver validieren unmittelbar vor einem Tabellenindex erneut und liefern bei ungültigen Runtime-Werten einen neutralen Fallback. Load-Normalisierung allein genügt nicht.
7. Sparse Arrays für `pets`, `equippedPets`, `unlockedZones` und `campaignProgress` werden über sortierte positive Ganzzahlkeys deterministisch rekonstruiert, statt nach dem ersten Loch abzubrechen. Gültige spätere Einträge bleiben erhalten; Duplikate werden nach dokumentierter First-valid-Regel entfernt.
8. Alle später indexierten Progressionsfelder auf dieselbe hostile-input-Strategie prüfen.
9. Migration muss idempotent sein und gültige alte Saves unverändert erhalten.
10. `cloneForPersistence` muss dieselbe Normalisierung verwenden.

## Pflichtfälle

- `NaN`, `math.huge`, negative Werte, Strings, Tabellen und Funktionen.
- Extrem hohe Level und nach dem Laden erneut manipulierte Runtime-Level.
- Unbekannte Progressions-IDs.
- Sparse Pet-, Equipped-, Zone- und Campaign-Arrays mit gültigen Einträgen hinter Löchern.
- Doppelte Pet-IDs, Equipped-IDs und Zahlenwerte sowie deterministische Reihenfolge.
- Gültige Max-Level-Werte.
- V5/V6/V10/V11-artige Saves.
- Pets mit kombinierten Varianten, Enchants und Dex-Einträgen.

## Abnahmekriterien

- Kein öffentlicher Bonus-, Movement-, Hatch- oder Damage-Pfad kann wegen eines ungültigen Save-Levels einen Nil-Index-Fehler auslösen.
- Gültiger Fortschritt bleibt erhalten.
- Zweifache Migration liefert dasselbe Ergebnis wie einmalige Migration.
- Schema- und DataService-Regressionen bestehen.
- Studio-Rejoin mit einem migrierten Testprofil ist bestätigt.

---

# QOF-24 – Kanonische Schadenspräzision

## Problem

Der kanonische Variantenschaden ist korrekt, aber `PetService.getPetDamage` rundet derzeit nach einzelnen späteren Multiplikatoren ab. Dadurch kann ein kleiner Shiny-, Strong- oder Shop-Effekt teilweise verschwinden.

## Änderungen

1. Basiswert aus Pet-Art, Basisvariante und Shiny bestimmen.
2. Enchant-, Quest-/Upgrade-, Shop- und weitere gültige Multiplikatoren als endliche positive Faktoren sammeln.
3. Alle Multiplikatoren auf den ungerundeten Zwischenwert anwenden.
4. `PetService.getPetDamage` gibt den vollständigen endlichen Bruchwert zurück; es findet keine Rundung pro Faktor oder pro Pet statt.
5. Mehrere Pet-Schäden werden ungerundet summiert. Nur ein Verbraucher, der technisch zwingend Ganzzahlen benötigt, darf einmal nach der Gesamtsumme an seiner dokumentierten Grenze runden.
6. Replizierten `pet.damage`-Mirror weiterhin nicht als Autorität verwenden.
7. UI-Anzeigen dürfen separat formatiert werden, aber die Serverberechnung nicht beeinflussen.

## Abnahmekriterien

- Normal, Golden, Rainbow und alle Shiny-Kombinationen liefern exakt die erwarteten Basismultiplikatoren.
- Strong I–III und Shop-Multiplikatoren werden nicht zwischenzeitig weggefloor’t.
- Ein Pet mit 4,5 Schaden bleibt 4,5; zwei solche Pets ergeben vor Zielanwendung exakt 9 und nicht 8.
- Bruchwerte, Overkill sowie gültige Faktoren zwischen 0 und 1 sind ausdrücklich getestet.
- Nicht endliche oder negative Faktoren werden neutralisiert oder fail-closed behandelt.
- Kampfschaden wird serverseitig berechnet.
- Bestehende Campaign-/Pet-Damage-Regressionen bestehen.

---

# QOF-25 – Zentrale atomare Profil- und Currency-Transaktionen

## Problem

Nicht alle Composite Purchases verwenden denselben stillen Spend-Handle. Besonders Upgrade-Tree und Hatch können Debit und späteren Refund getrennt replizieren; Upgrade-Tree kann bei einem zweiten Profilfehler einen Debit nicht sicher zurückstellen. Zusätzlich mutieren stille Handles aktuell das Liveprofil: Ein unabhängiger Autosave könnte einen Zwischenstand mit reservierter Currency oder vorübergehend entfernten Pets persistieren. Service-lokale Locks serialisieren verschiedene Economy-Services nicht zuverlässig gegeneinander.

## Änderungen

1. Einen zentralen per-profile Transaction-/Admission-Owner mit einem gemeinsamen Vertrag einführen: `begin`, `closeAdmission`, `hasPending`, idempotentes `settlePlayer`, `commit` und retrybares `rollback`.
2. Jede Composite-Mutation registriert ihren Owner **vor** der ersten Liveprofilmutation.
3. Autosave, Leave-Save und Shutdown-Save dürfen kein Profil snapshotten, solange ein registrierter Owner unresolved ist; sie warten auf Settlement oder halten das Profil fail-closed.
4. Parallel laufende Currency-Spends, Rewards und Composite Mutations verschiedener Services werden pro Profil serialisiert oder über Reservations geführt, die den Livezustand bis Commit nicht verändern.
5. Upgrade-Tree auf `beginSpendTransaction`, `commitSpendTransaction` und `rollbackSpendTransaction` umstellen.
6. Egg-/Multi-Hatch ebenfalls auf den stillen Handle und den zentralen Owner umstellen.
7. Alle Composite Purchases inventarisieren: Shop, Potion-Upgrades, Maschinen, Auto-Hatch-Zugang, Enchanting, Upgrade-Tree und Hatch.
8. Einheitliche Invariante erzwingen:
   - Owner registrieren und vorbereiten,
   - still reservieren,
   - Profil-/Inventarmutation durchführen,
   - vollständigen DTO bauen,
   - einmal committen und erst dann replizieren,
   - Owner erst nach abgeschlossenem Commit/Rollback freigeben.
9. Fehlgeschlagene Rollbacks behalten Handle und Owner für Lifecycle-Retry.
10. Kein Refund darf Mastery-, Quest-, Potion- oder Shop-Boni anwenden.
11. Post-PONR-Benachrichtigungsfehler dürfen keine abgeschlossene Transaktion zurückrollen.

## Abnahmekriterien

- Vor Commit wird keine Currency-Aktualisierung gesendet.
- Technischer Fehler erzeugt keinen sichtbaren Debit/Refund-Flicker.
- Autosave exakt nach Spend, nach Profil-/Pet-/Entitlement-Mutation und unmittelbar vor Currency-Commit speichert niemals einen Zwischenstand.
- Leave und BindToClose werden getrennt gegen dieselben Fault-Stages geprüft.
- Fault Injection nach Spend, Mutation und DTO-Bau stellt exakt den vorherigen Zustand wieder her.
- Rollback-Fehler bleibt retrybar und blockiert jedes sichere Snapshot/Save bis zum Settlement.
- Parallelversuche aus zwei unterschiedlichen Services können sich weder gegenseitig committen noch replizieren.
- Doppelaufrufe und parallele Käufe werden pro Spieler abgewiesen oder serialisiert.

---

# QOF-26 – Potion-Concurrency und Lifecycle

## Problem

Eine Shiny-Charge-Reservierung teilt nicht denselben Mutationsschutz wie manuelles Trinken oder Auto-Drink. Ein Hatch kann Charges reservieren, während parallel eine Shiny Potion konsumiert wird; ein späterer Hatch-Rollback kann dann den neueren Zustand überschreiben und die konsumierte Potionwirkung verlieren. Shop und Potion haben außerdem noch keinen vollständigen Shutdown-Owner.

## Änderungen

1. Einen gemeinsamen exklusiven per-player Potion-Lease einführen.
2. Shiny-Reservation, manuelles Trinken, Auto-Drink, Potion-Upgrades, Selection-Änderungen und Cleanup über dieselbe Autorität koordinieren.
3. Eine Hatch-Reservation hält den Lease bis Charge-Commit oder -Rollback. Paralleles Trinken, Auto-Drink oder Upgrade liefert deterministisch `BUSY` und mutiert nichts.
4. Rollback darf keine vollständige veraltete Snapshot-Tabelle zurückschreiben; er restauriert ausschließlich die vom Handle reservierte Charge-Menge unter demselben Lease.
5. Potion- und Shop-Admission beim Shutdown schließen.
6. Aktive Shop-/Potion-Transaktionen in der zentralen QOF-25-Registry als retrybare Lifecycle-Owner registrieren.
7. Leave darf Locks nicht einfach löschen, solange eine unresolved Transaktion existiert.
8. Offline-Timer bleiben absolute Zeitwerte; Auto-Drink simuliert keine Offline-Schleife.

## Pflicht-Race-Test

1. Profil besitzt 5 Shiny-Charges und mindestens eine Shiny Potion.
2. Hatch reserviert 3 Charges und hält den Potion-Lease.
3. Paralleles manuelles Trinken und Auto-Drink werden mit `BUSY` abgewiesen; Inventar und verbleibende 2 Charges ändern sich nicht weiter.
4. Hatch schlägt technisch fehl und rollt seine Reservation zurück.
5. Endzustand ist exakt 5 Charges und dieselbe Anzahl Shiny Potions.
6. Derselbe Ablauf wird an den Grenzen 29 und 30 Charges geprüft; kein Clamp darf eine Ressource vernichten oder duplizieren.

## Abnahmekriterien

- Potion-Inventar und Charges sind bei jedem Race exakt konserviert.
- Kein Rollback überschreibt eine neuere Potion-Mutation.
- Shutdown/Leave wartet auf Settlement oder behält einen retrybaren Owner.
- Luck, Mega Luck, Speed, Coin Boost, Duration, Slots und Auto-Drink regressieren nicht.

---

# QOF-27 – Maschinenreihenfolge und Rollback-Invarianten

## Problem

Der bisherige Maschinenpfad würfelt vor dem tatsächlichen Entfernen der Eingabe-Pets. Der verbindliche Produktvertrag verlangt: Inputs und Preis atomar reservieren/entfernen, danach Erfolg würfeln, Business-Failure committen, technische Fehler exakt zurückrollen.

## Änderungen

1. Pet-Auswahl und Snapshots unter Inventory-Lease validieren.
2. Zentralen Profil-Owner registrieren und Currency still reservieren.
3. Eingabe-Pets vor dem RNG aus dem sichtbaren Inventar in transaktionseigenes Staging verschieben. Vor dem RNG werden nur Dex-Snapshot und Undo-Metadaten vorbereitet; noch keine Output-Discovery geschrieben.
4. Erst danach RNG ausführen.
5. Erfolg:
   - Ausgabe-Pet einfügen,
   - ausschließlich jetzt Output-Dex schreiben,
   - Shiny als OR der Eingaben übernehmen,
   - keinen Enchant übernehmen.
6. Normaler Misserfolg:
   - kein Ausgabe-Pet,
   - keinerlei neue Dex-Discovery,
   - gestagte Eingaben bleiben entfernt.
7. Danach Currency-Commit als eindeutigen Point of No Return (PONR) ausführen.
8. Technischer Fehler oder ungültiges RNG **vor dem PONR** restauriert ursprüngliche Pet-Reihenfolge, Pet-Objektidentität, Diamonds, eigene Dex-Writes, Lease und Locks exakt oder hält den Owner retrybar.
9. Fehler bei Benachrichtigungen **nach dem PONR** werden geloggt/retrybar repliziert, dürfen die abgeschlossene Business-Transaktion aber nicht zurückrollen.
10. Private Zone-/Station-Autorität und Remote-Validierung unverändert beibehalten.

## Abnahmekriterien

- Ein Testhook beweist die Reihenfolge `input staging/removal → RNG → optional output/Dex → currency PONR`.
- Die Chancekurve bleibt exakt 13/26/39/50/63/88/100 %.
- Gold und Rainbow benutzen denselben Transaktionskern.
- Business-Failure verbraucht Inputs und Preis und schreibt keine Discovery.
- Technischer Pre-PONR-Failure verbraucht nichts; post-PONR-Notificationfehler erzeugt keinen Client-Retry derselben Conversion.
- Autosave während des Stagings kann keinen petlosen oder still debitierten Zwischenzustand persistieren.
- Gemischte Shiny-Inputs erzeugen bei Erfolg ein Shiny-Output.
- Favorisierte, ausgerüstete, doppelte, sparse, fremde oder falsche Pets werden vor Mutation abgewiesen.

---

# QOF-28 – Auto-Hatch Contract V2, HUD-Toggle und Lifecycle

## Problem

QOF-18 ist promptgebunden, verwendet persistierte `1/2/5/10`-Tiers und prüft die Stationsdistanz nur beim Start. Dadurch passt es weder zum gewünschten einzigen HUD-Toggle noch zum ausschließlichen `1/3/9`-Vertrag und zum serverautoritativen Bewegungsabbruch. Außerdem hält der Kauf des Paid-Auto-Hatch-Zugangs noch keinen retrybaren Shutdown-Owner.

## Verbindlicher Scope

1. QOF-18 Contract V1 und den manuellen QOF-10-Intent durch einen strikt versionierten Contract V2 ersetzen; V1, `Fixed`, `MAX`, rohe Counts, Zusatzkeys und Mischverträge fail-closed ohne Mutation behandeln.
2. Ausschließlich feste Batchgrößen `1`, `3`, `9` in Shared Config, DataSchema, Upgrade-Entitlements, Server, Client, UI und Tests verwenden. `2/5/10/MAX` werden nicht nur versteckt, sondern aus dem aktiven Request-/Responsevertrag entfernt.
3. Vor Implementierung die noch offene Migrationsentscheidung dokumentieren: Zuordnung bestehender x2/x5/x10-Freischaltungen zu x3/x9 inklusive Besitzstand und ohne stillen Wertverlust. Ohne Nutzerentscheidung bleibt QOF-28 `BLOCKIERT`.
4. Genau ein Auto-Hatch-Icon im permanenten HUD erzeugen: AUS neutral, AN grün mit begrenzter Pulse-Animation; Klick AUS öffnet Auswahl, Klick AN stoppt unmittelbar. Alte Prompt-Controls und jeder Shop-Startbutton entfallen.
5. Selector zeigt nur serverseitig angebotene, freigeschaltete und aktuell bezahlbare Eier. Preis je `1/3/9` kommt aus einem revisionierten Server-Quote und wird vor Start sowie vor jedem Batch neu validiert.
6. Vor Implementierung die Stations-UX bestätigen: entweder nur die aktuell nahe kanonische Station ist auswählbar oder ein klar definierter sicherer Weltfluss bringt den Spieler zur gewählten Station. Ein frei erfundener Remote-Hatch von beliebiger Position ist verboten.
7. Startintent bindet eine frische generationgebundene, kurzlebige Stationsauswahl. Jeder Neustart – auch nach Cancel, Bewegung oder derselben Station – erhält eine neue Sessiongeneration; alte Responses/Callbacks dürfen sie nicht übernehmen.
8. Server speichert die echte `HumanoidRootPart`-Startposition und beendet die Session bei mehr als 2,5 Studs Distanz. Kamera/Zoom zählen nicht. Character-Wechsel, Zone-/Stationswechsel, Teleport, Leave und Shutdown stoppen ebenfalls. Mikro-Jitter bis 2,5 Studs stoppt nicht.
9. Höchstens ein Batch ist in-flight; kein Catch-up. Vor jedem weiteren Drei-Sekunden-Tick werden Generation, Zugang, Station, Zone, Character, Distanz, Entitlement, Preis, Coins und Storage neu geprüft.
10. Batchausführung verwendet unverändert den QOF-25-Profil-/Currency-Owner, den QOF-26-Charge-Lease und `prepareHatchBatch → commit`; RNG und Rewards bleiben ausschließlich serverseitig. Auto-Hatch verbraucht weiterhin keine Shiny-Charges.
11. Bereits committeter Batch bleibt bei Stop/Bewegung erhalten; es startet nur kein weiterer. Erfolgreiche Batches verwenden weiter `EggHatchStart/Result` und die gemeinsame begrenzte Cinematic-FIFO ohne Bestätigungsdialog.
12. Fehlercodes werden stabil, revisioniert und rate-limited veröffentlicht. Unbekannte interne Fehlermeldungen werden nicht roh angezeigt; die separate vollständige Lokalisierung bleibt Backlog.
13. Zugangskauf erhält Admission-Gate, aktiven Transaction-Record und Shutdown-/Leave-Settlement. Mangels gegenteiliger Entscheidung bleiben Preis 500 Diamonds, Dauer 600 Sekunden und Batchintervall drei Sekunden unverändert; Kauf ist nur im Shop, Start/Stop nur über das HUD-Icon.
14. Auto-Hatch-Clientcode als eigenes Featuremodul aus dem `UIController`-Monolithen lösen; keine zusätzlichen Heartbeat-/Prompt-Verbindungen bei erneutem Öffnen.

## Abnahmekriterien

- Genau ein Icon startet/stoppt; Shop und Egg-Prompt besitzen keinen zweiten Sessioneinstieg.
- Aktiver Vertrag akzeptiert ausschließlich x1/x3/x9; V1, x2/x5/x10, `MAX`, historische Fixed-x3-Form und Mischpayloads mutieren nichts.
- Jeder Start verwendet eine neue Generation und Stationsbindung; Cancel/Stop/Bewegung plus Neustart an derselben Station funktioniert.
- Serverbewegung über 2,5 Studs, Zone-/Stationwechsel, Respawn, Leave und Shutdown stoppen vor dem nächsten Batch; Kamera, Zoom und Jitter bis 2,5 Studs nicht.
- Ein Batch ist wirtschaftlich und im Inventar vollständig atomar; kein transienter Currency-Flicker und keine Client-RNG-/Rewardautorität.
- Zugangskauf endet atomar entweder in `(Diamonds unverändert, alter Expiry)` oder `(Diamonds − 500, expiresAt = now + 600)`.
- Kein Requestspam: ein serverseitiger Scheduler besitzt das Intervall, maximal einen in-flight Batch und revisioniertes Rate-Limit-Feedback.
- Bereits committete Ergebnisse werden bei Stop nicht zurückgenommen; stale Callbacks können keine neue Session wiederbeleben.
- Unbekannte Serverfehler erscheinen als generischer spielerfreundlicher Text, nie als `Invalid player`, `No player data` oder interner Fehlerstring.
- Desktop, Mobile, reale Bewegung/Physik, Latenz, Rejoin und Same-Station-Reopen sind im gebundenen Studio-Build manuell bestätigt.

## Nicht-Ziele

- Kein Skill Tree.
- Keine allgemeine deutsche Lokalisierung.
- Kein Inventory-Tab-Neubau; dieser folgt in der separaten QOF-32+-Roadmap.

---

# QOF-29 – Pickup-, Leave- und Shutdown-Garantien

## Problem

Ablauf und geordnetes Leave besitzen Retry-Logik, aber die bisherige Formulierung „Pickups gehen nie verloren“ ist für einen harten Prozessabbruch zu absolut. Pickup-Records sind transient und besitzen keine stärkere Haltbarkeit als der noch nicht gespeicherte Profilzustand.

## Änderungen

1. Garantie exakt definieren:
   - at-most-once innerhalb eines laufenden Servers,
   - Retry bei temporärem Creditfehler,
   - eventual exactly-once nur unter der Annahme, dass Profilzugriff, Credit und geordneter Save vor Prozessverlust gelingen,
   - Settlement vor geordnetem Leave/Shutdown,
   - keine absolute Garantie bei sofortigem Prozessverlust vor DataStore-Persistenz.
2. In dieser Roadmap wird **kein persistentes Pickup-Ledger** in V12 eingeführt. Ein solches Ledger wäre ein separates zukünftiges Schema-V13-QOF mit eigener Performance-/DataStore-Entscheidung.
3. Dokumentation und UI-Texte auf die reale Garantie begrenzen.
4. Leave-/Shutdown-Reihenfolge mit der zentralen QOF-25-Registry sowie Egg, Machine, Enchanting, Potion, Shop und Auto-Hatch gemeinsam prüfen.
5. ZoneService-Handoffs von zerstörten Objekten bis Pickup integrieren testen.
6. Der vorhandene direkte exakte Credit-Fallback bei fehlgeschlagener Pickup-Erzeugung bleibt verpflichtend und darf Boni nicht doppelt anwenden.

## Abnahmekriterien

- Claim ist owner- und range-validiert und at-most-once.
- Ablaufcredit wird bei temporärem Fehler erneut versucht und nicht verworfen.
- Eventual exactly-once ist für geordnete, erfolgreich gespeicherte Serverpfade belegt und nicht für einen harten Prozessabbruch behauptet.
- Pending Limit settlet zuerst den ältesten Record oder lehnt den neuen Drop ab.
- Geordnetes Leave speichert erst nach erfolgreichem Settlement aller zentral registrierten Owner.
- Ein echter ZoneService-Integrationstest deckt Coins, Diamonds, Pickup-Erzeugung und direkten Fallback-Credit ab.
- README verspricht keine technisch unmögliche Hard-Crash-Garantie.

---

# QOF-30 – Release-Pipeline und verpflichtende CI

## Problem

Die QOF-21-Pipeline ist stark, aber nicht vollständig CI-erzwungen. Der statische Artefaktverifier prüft eine RBXL ohne Fresh-Build nur über Magic und Hashmanifest. Tool-Bootstrap, Python/zlib-Umgebung und Cross-Host-Reproduzierbarkeit sind nicht vollständig gepinnt.

## Änderungen

1. GitHub Actions muss verpflichtend ausführen:
   - Selene,
   - Luau-Tests ohne `continue-on-error`,
   - Luau-Compile aller Runtime-Sources,
   - Runtime-Inventur,
   - RBXLX-Generator-Parität,
   - `verify_generated_place.py`,
   - QOF-Release-Fresh-Build mit gelocktem rbxmk,
   - `verify_release_artifacts.py --fresh-build`.
2. Den in QOF-22 eingeführten Toolbootstrap in CI verwenden; Actions, Container und Werkzeuge per Commit-SHA, Image-Digest oder exakter Version pinnen.
3. Kanonischen Linux-amd64-Builder als Container inklusive Python- und zlib-Version festschreiben.
4. `PYTHONDONTWRITEBYTECODE=1` in Check-/CI-Pfaden setzen.
5. Place-Verifier auf eine kanonische Map `Roblox-Hierarchie → Scriptklasse → Sourcepfad → Bytes` umstellen, nicht nur globale Namen/Counts.
6. Negative Manipulationsfixtures müssen fehlschlagen: Source in falschem Service, getauschte Scriptklassen bei gleichen Counts, vertauschte gleichnamige Main-Scripts, doppelter Root-Service und unerwartetes Runtime-Script.
7. Fresh-Build muss RBXL semantisch und bytegenau an den erzeugten RBXLX-Stand binden.
8. Provenienz pinnt Source-Tree, unabhängige Verifier und einen artefaktfreien Source-Commit beziehungsweise wird zweistufig als `Source-Commit → CI-Artefakt/Release` erzeugt; keine zirkuläre Manifest-Selbstauthentisierung behaupten.
9. Multi-File-Publish weiterhin manifest-last und fail-closed halten; Crash-Atomicity-Grenzen dokumentieren.
10. Keine Behauptung von Cross-OS-Bytegleichheit; kanonischer Host bleibt explizit gelockt.
11. Stabile CI-Jobnamen definieren und als Required Checks in Branch Protection/GitHub Ruleset für `main` konfigurieren; ist diese externe Einstellung nicht automatisierbar, bleibt QOF-30 bis zur Nutzerbestätigung `BLOCKIERT`.

## Abnahmekriterien

- Ein PR kann nicht grün werden, wenn Tests, Compile, Source-Parität oder Fresh-Build fehlen.
- Branch Protection/Ruleset verlangt die dokumentierten stabilen CI-Jobs vor Merge nach `main`.
- Zwei saubere Builds im kanonischen Container liefern dieselben vier Artefaktbytes.
- RBXLX enthält alle Runtime-Sources in der richtigen Hierarchie und Klasse; alle negativen Manipulationsfixtures werden erkannt.
- RBXL → RBXLX → RBXL liefert identische Binärbytes.
- ZIP enthält genau die erwartete Root-RBXLX mit kanonischen Metadaten.
- Manifest und getrackte Artefakte stimmen mit einem Fresh-Build überein.

---

# QOF-31 – Studio-Abnahme, Deployment-Handoff und Merge nach main

## Problem

Statische und Pure-Luau-Prüfungen ersetzen keine Roblox-Engine-, DataStore-, Mobile-, Kamera-, Prompt- oder Multiplayer-Abnahme. Außerdem beschreibt das aktuelle Root-README den finalen Varianten- und Services-Stand nicht korrekt.

## Änderungen

1. Root-README auf den tatsächlichen QOF-31-Stand aktualisieren.
2. Alte falsche Aussage „Golden (Shiny)“ durch getrennte Basisvariante und Shiny-Modifier ersetzen.
3. Schema V12, sechs Pet-Zustände, Maschinen, Potions, Auto-Hatch, Enchants, Dex und Releasebefehle dokumentieren.
4. Historische Studio-Schulden aus QOF-01–21 in einer Matrix `QOF → Testfall → Fixture → Evidenz` abbilden.
5. Versionierte Testprofile und kontrollierte Testbuild-Fixtures für RNG, Fault-Stages und Transaktionspausen bereitstellen; Testhooks sind in Production fail-closed/deaktiviert.
6. Vollständige Test-RBXL aus dem finalen Source-Stand erzeugen.
7. Studio-Matrix auf Desktop und Mobile durchführen.
8. Mindestens einen Multiplayer-Test mit zwei Spielern durchführen.
9. Alte Testprofile für Migration/Rejoin verwenden.
10. Finale Änderungen per Pull Request gegen `main` reviewen.
11. Erst nach grüner Required-CI und buildgebundener Nutzerbestätigung mergen.
12. Immutable Git-Tag und GitHub Release mit den verifizierten Artefakten erstellen.
13. Roblox-Publish bleibt ein externes Credential-/Nutzer-Gate: Ziel-Universe/Place, Canary-/Smoke-Test, Beobachtungsfenster und Rollback auf die vorige Place-Version dokumentieren.
14. Für Schema V12 ausdrücklich dokumentieren, welche Migrationen rückwärtskompatibel und welche nach einem Production-Save nicht sicher rückrollbar sind.

## Verbindliche Studio-Matrix

1. **Migration/Rejoin**
   - altes Profil laden,
   - Pets/Favoriten/Equip/Zonen/Währungen vergleichen,
   - verlassen und erneut beitreten.
2. **Varianten/Schaden**
   - alle sechs Zustände anzeigen,
   - Golden/Rainbow/Shiny-Schaden prüfen,
   - Strong-/Shop-Kombinationen prüfen.
3. **Hatch**
   - x1/x2/x5/x10 und MAX,
   - zu wenig Coins,
   - fast volles Inventar,
   - Skip und seltene Cinematic.
4. **Potions**
   - alle fünf Arten,
   - Slots/Duration/Auto-Drink,
   - Shiny-Charges mit absichtlich fehlgeschlagenem Hatch.
5. **Maschinen**
   - Zone 3 und 6,
   - 1 und 7 Inputs,
   - Erfolg und Misserfolg,
   - Shiny-Mix,
   - Favorit/Equipped-Ablehnung.
6. **Auto-Hatch**
   - Kauf, Start, Pause, Batchwechsel, Rejoin, Ablauf.
7. **Enchanting**
   - erster Enchant und Reroll,
   - Strong/Agile-Wirkung,
   - stale Details und zu wenig Diamonds.
8. **Pet Dex**
   - 96 Karten,
   - sofortiges Hatch- und Machine-Update,
   - Reopen/Rejoin.
9. **Pickups/Movement**
   - Speed, Magnet, Claim-Grenze, Ablauf, Leave.
10. **Lifecycle**
    - Leave **und** BindToClose/Studio-Stop getrennt während Hatch, Maschine, Potion, Shop, Auto-Hatch-Kauf und Enchant,
    - kontrollierte Fault-Stages vor und nach dem jeweiligen PONR,
    - kein Save eines Zwischenzustands.
11. **Geräte/UI**
    - Desktop, Mobile und Tablet,
    - x10-Hatch-Lesbarkeit,
    - Prompt-Distanz,
    - Kamera-/FOV-Restore.
12. **Release-Artefakte**
    - RBXL in Studio öffnen,
    - Play-Smoke-Test,
    - keine fehlenden Services/Remotes/Sources.

## Abnahmekriterien

- Alle QOF-22–30 sind `ABGESCHLOSSEN`; `CODE-VERIFIZIERT` allein genügt nicht.
- Jeder Studio-Test ist an exakten Commit, Artefakt-SHA, Studio-Version, Gerät, Spielerzahl, Fixture, erwarteten/tatsächlichen Zustand, Tester und Datum gebunden.
- Datenverlust-, Economy-, Migration-, Lifecycle-, Crash- oder Releasefehler blockieren QOF-31 zwingend und dürfen nicht nur als spätere QOFs notiert werden.
- Nicht blockierende UX-Abweichungen dürfen nur mit ausdrücklicher Nutzerfreigabe als Folge-QOF erfasst werden.
- Pflicht-CI und Required Checks sind grün.
- Finaler Fresh-Build stimmt mit den veröffentlichten Bytes überein.
- Pull Request enthält keine temporären Converter, Downloads, Logs oder Secrets.
- `main` enthält nach Merge den vollständigen QOF-01–31-Stand.
- Tag/GitHub Release referenzieren denselben Commit und dieselben Artefakthashes.
- Roblox-Publish, Canary, Monitoring und Rollback bleiben dokumentiert und warten gegebenenfalls als externes Gate auf den Nutzer.

---

## 7. Verbindliche Prüfungen pro Code-QOF

Die in QOF-22 gelockte Pflicht-Toolchain muss für jedes Code-QOF verfügbar sein. Fehlt ein Pflichtwerkzeug, ist das QOF `BLOCKIERT`; fehlende Prüfungen dürfen nicht als bestanden oder code-verifiziert gelten.

```bash
git diff --check
selene src/
luau tests/run_tests.lua
# luau-compile über jede von runtime_inventory.py gelistete Runtime-Source
```

Python-Tools werden ohne Repository-Bytecode zu erzeugen geprüft:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  tools/runtime_inventory.py \
  tools/generate_rbxlx.py \
  tools/build_release.py \
  tests/verify_generated_place.py \
  tests/verify_release_artifacts.py
```

Place- und Buildprüfung:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/generate_rbxlx.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_generated_place.py BATTLE_PETS.rbxlx

ARTIFACT_DIR="$(mktemp -d)"
PYTHONDONTWRITEBYTECODE=1 python3 tools/build_release.py \
  --qof <XX> --rbxmk "$RBXMK" --output-dir "$ARTIFACT_DIR"
PYTHONDONTWRITEBYTECODE=1 python3 tests/verify_release_artifacts.py \
  --qof <XX> --artifact-dir "$ARTIFACT_DIR" --fresh-build --rbxmk "$RBXMK"
```

### Zwischenartefakt-Policy

- QOF-23 bis QOF-29 erzeugen den vollständigen Vier-Dateien-Satz in einem temporären Verzeichnis, damit Fresh-Build und Roundtrip prüfbar sind.
- Als dauerhaftes Testartefakt wird für diese Zwischen-QOFs mindestens `BATTLE_PETS_QOF-XX_TEST.rbxl` beziehungsweise eine `_vN`-Korrekturrunde veröffentlicht; Commit, Dateigröße und SHA-256 werden in der Fortschrittstabelle festgehalten.
- Temporäre XML-/ZIP-/Manifest-Sätze werden nicht ungeprüft ins Repository übernommen.
- QOF-30 und QOF-31 veröffentlichen den vollständigen kanonischen Vier-Dateien-Release-Satz.
- Das Manifest hasht die drei Nutzartefakte; seine Vertrauensbasis ist der getrackte Source-/CI-Commit, nicht eine behauptete Selbstsignatur.

## 8. Ergebnisformat nach jedem QOF

Die Abschlussantwort verwendet diese Reihenfolge:

1. Exakter Status gemäß Abschnitt 5 und konkrete nächste Aktion.
2. QOF und Buildversion.
3. Git-Commit, Branch und Upstream.
4. Download-Link zur echten Test-RBXL.
5. Artefaktgröße und SHA-256; bei Release-QOFs alle vier Artefakte.
6. Geänderte Dateien und Verhalten.
7. Ausgeführte Pflichtprüfungen mit Ergebnis und CI-Run.
8. Nicht ausführbare Prüfungen als Blocker, nicht als stilles PASS.
9. Nummerierter Studio-Testplan mit erwarteten Ergebnissen.
10. Bekannte Grenzen.
11. Konkrete Feedbackfragen.
12. Hinweis: Nur ein auf QOF und Build bezogenes `Weiter` startet nach `ABGESCHLOSSEN` das nächste QOF.

## 9. Bugreport-Format

```text
QOF/Build:
Gerät: PC / Mobile / Tablet
Spielerzahl:
Aktion:
Erwartet:
Tatsächlich:
Reproduzierbar: immer / manchmal / einmal
Studio Output/Fehler:
Screenshot oder Video:
```

## 10. Prompt für eine neue Kiro-Session

Der Nutzer kann in einer neuen Session folgenden kurzen Prompt verwenden:

```text
Arbeite im Battle-Pets-Repository auf dem getrackten Integrationsbranch. Lies die
getrackte QOF-22-31-ROADMAP-README.md und .kiro/steering/qof-test-debug-workflow.md
vollständig; ändere zunächst nichts. Prüfe Dirty State, Branch/Upstream, HEAD und
dass 6f453131ea6d9cd9ae59321e476987107791f25e Vorfahr ist; bewahre fremde
Änderungen. Stoppe, wenn die Roadmap untracked ist, nicht aus HEAD stammt oder die
Pflicht-Toolchain für das nächste Gate fehlt. Wähle das erste nicht
ABGESCHLOSSENE QOF in Tabellenreihenfolge und führe nur die für seinen Status
angegebene nächste Aktion aus. Überspringe BLOCKIERT, CODE-VERIFIZIERT,
STUDIO-TEST AUSSTEHEND oder STUDIO-BESTÄTIGT nicht. Verifiziere Evidenz gegen
Commit, Artefakt-SHA und CI-Run. Implementiere nur bei OFFEN/IN ARBEIT und
erfüllten Abhängigkeiten. Aktualisiere Roadmap, nächste Aktion und Evidenz. Ein
neues QOF beginnt nur nach einem für dieses QOF und diesen Build dokumentierten
„Weiter“; Studio-, Branch-Protection- und Publish-Gates bleiben extern.
```

## 11. Bekannte Ausgangsbefunde, die nicht verloren gehen dürfen

Diese Punkte wurden vor QOF-22 bereits bestätigt und müssen durch die Roadmap behoben oder bewusst verifiziert werden:

- Vollständige Implementierung nicht auf `main`; Roadmap muss auf der exakten Baseline getrackt werden.
- `upgrades` und `masteryBuffs` nicht ausreichend hostile-normalisiert; sparse Arrays können gültige spätere Einträge verlieren.
- Zwischenrundung im Pet-Schaden widerspricht der Bruchteilregel.
- Upgrade-Tree und Hatch verwenden nicht überall stille Currency-Handles.
- Autosave kann ohne zentralen Profil-Owner theoretisch eine laufende stille Composite-Mutation snapshotten.
- Shiny-Charge-Reservation kann neuere Potion-Mutationen überschreiben.
- Shop/Potion besitzen keine vollständigen Shutdown-Owner.
- Maschinen würfeln vor dem Entfernen der Inputs.
- Auto-Hatch-Zugangskauf besitzt keinen retrybaren Shutdown-Transaction-Record.
- Historische Hatchverträge `x1/x3/MAX` (manuell) und `x1/x2/x5/x10` (Auto V1) werden bewusst durch Contract V2 mit ausschließlich `x1/x3/x9` ersetzt; Station-UX und Besitzstandsmigration der alten Tiers sind vor QOF-28 noch zu entscheiden.
- Pickup-Hard-Crash-Garantie war zu absolut formuliert.
- QOF-21-Fresh-Build ist nicht verpflichtend in CI; Place-Parität ist noch nicht fest an Hierarchie und Scriptklasse gebunden.
- Luau-Tests sind in der bisherigen CI optional; Pflicht-Toolchain-Bootstrap fehlt.
- Rendering, Kamera, Mobile, DataStore, Leave/BindToClose und Multiplayer sind nicht vollständig automatisiert abgenommen.

Diese Liste darf erst gekürzt werden, wenn der jeweilige Punkt durch Code, Tests und – falls nötig – Studio-Evidenz abgeschlossen ist.
