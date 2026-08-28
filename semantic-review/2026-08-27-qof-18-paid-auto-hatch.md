# Bezahltes, stationsgebundenes Auto-Hatch mit absoluter Laufzeit

QOF-18 führt einen separaten, serverautoritativen Auto-Hatch-Dienst mit 500-Diamond-Kauf, absoluter 600-Sekunden-Expiry, konkreter Egg-Station und einem globalen Drei-Sekunden-Scheduler ein. Automatische Batches laufen über den bestehenden atomaren EggService-Pfad, bezahlen den vollen Coinpreis und verbrauchen keine Shiny-Charges; der persistierte Tier bleibt auf x1/x2/x5/x10 beschränkt und fällt bei Entitlement-Verlust nicht auf eine kleinere Größe zurück. Die V1-Remotes, serverseitigen Revisionen, Client-Generationen und der deaktivierte Legacy-Shop-Loop bilden eine klare Rolling-Deployment-Grenze. Vor dem Shipping bleiben fünf **confirmed** korrektheitsrelevante Lücken in Persistenzvalidierung, Station-Integrität, Fehlerdarstellung und Lifecycle-Wiring.

**Watch for:** **confirmed** — fraktionale Expiries werden entgegen dem V9-Vertrag akzeptiert; **confirmed** — nicht alle kanonischen Stationseigenschaften werden validiert; **confirmed** — Startfehler verschwinden vor der UI; **confirmed** — bereits verbundene Spieler umgehen die Auto-Hatch-Rejoin-Initialisierung; **confirmed** — ein fehlgeschlagener Authority-Bootstrap wird im DTO trotzdem als runtime-enabled beworben.

**Verdict**: NEEDS_CHANGES

## High-level view

Der Kaufpfad verwendet den stillen `CurrencyService.beginSpendTransaction`-Debit, baut die vollständige Zustandsantwort vor dem Commit und stellt Expiry sowie Balance bei technischen Fehlern wieder her. Aktiver Wiederkauf wird vor dem Debit abgelehnt, und die absolute `os.time()`-Expiry zählt Offline-Zeit. **Confirmed:** Die Schema-Normalisierung verletzt ihre Integer-Grenze, weil sie Bruchteile abrundet statt sie fail-closed auf null zu setzen.

`ZoneService` bindet jede der acht Stationen an eine stabile ID, einen pro Server eindeutigen GUID-Token und private Instance-Referenzen; Clone-, Token-, Ancestry-, Zone- und Distanzprüfungen sind vorhanden. **Confirmed:** Die Integritätsprüfung deckt den zugesagten Property-Vertrag nicht vollständig ab: Pedestal-Farbe/-Material sowie Shape/Material/Color des Interaction-Parts können verändert werden, ohne die Station ungültig zu machen.

Der Scheduler startet den ersten Batch erst am nächsten regulären Tick, lässt pro Spieler höchstens einen Batch gleichzeitig zu und erzeugt weder Queue noch Catch-up. Stop, Leave, Target-Wechsel und Expiry invalidieren Generationen; jeder zugelassene Batch nutzt den bestehenden EggService-Lock, den vollen Batchpreis und `consumeShinyCharges = false`. Ressourcen- und Entitlement-Pausen werden am nächsten regulären Tick neu geprüft, ohne den gespeicherten Tier zu verkleinern.

Die V1-Oberfläche validiert exakte Request-Shapes und erzeugt neue DTOs mit monotonen Revisionen und unabhängigen Tabellen. **Confirmed:** Startfehler wie `TOO_FAR` oder `ZONE_LOCKED` werden nur als separates Remote-Ergebnis geliefert, während der Client ausschließlich `state.pauseReason` rendert und das Ergebnisfeld ignoriert.

Normale Joins initialisieren Auto-Hatch nach erfolgreichem Profile-Load, Leave und Shutdown räumen transienten Target-State vor Egg/Data-Cleanup auf. **Confirmed:** Der Bootstrap-Pfad für Spieler, die beim Scriptstart bereits verbunden sind, lässt `AutoHatchService.onPlayerAdded` aus; außerdem basiert `runtimeEnabled` nur auf Config-Gates und nicht auf erfolgreicher Authority-/Scheduler-Initialisierung.

Die generierte Place-Datei enthält alle 72 Runtime-Sources bytegenau. Die ausgeführten Prüfungen sind grün: 257/257 Lua-Tests, 94/94 Luau-Compiles, 72/72 Place-Parität, beide Python-Dateien kompilieren und `git diff --check` meldet keine Fehler; die Tests kodifizieren oder übersehen die fünf Findings.

<details>
<summary>Issues (5)</summary>

1. **P1 · Fraktionale V9-Expiry wird gültig** — **confirmed**: `math.floor` macht beispielsweise `1600.9` zu einer gültigen Expiry. Vor dem Bounds-Check `value % 1 == 0` verlangen und den Test auf Normalisierung zu `0` ändern.
2. **P1 · Station-Property-Vertrag ist unvollständig** — **confirmed**: Pedestal-Farbe/-Material und Shape/Material/Color des Interaction-Parts fehlen im privaten Snapshot und in der Integritätsprüfung. Diese Eigenschaften mitspeichern, bei jedem Start/Tick vergleichen und Tamper-Tests ergänzen.
3. **P1 · Stabile Startfehler erreichen die UI nicht** — **confirmed**: `StartAutoHatch` gibt den Reason separat zurück, der Client verwirft ihn und rendert nur den unveränderten DTO-Reason. Den validen Aktionsfehler revisionsgesichert in den autoritativen State publizieren oder generation-gebunden als lokales Feedback übernehmen.
4. **P1 · Bereits verbundene Spieler werden nicht initialisiert** — **confirmed**: Der `Players:GetPlayers()`-Bootstrap ruft Potion- und Movement-, aber nicht Auto-Hatch-Initialisierung auf. Nach dem Profile-Load denselben `AutoHatchService.onPlayerAdded(player)`-Aufruf wie im normalen Joinpfad ausführen und testen.
5. **P2 · Authority-Ausfall wird als aktiv beworben** — **confirmed**: Bei fehlender Egg-Authority startet der Dienst nicht, `getState().runtimeEnabled` bleibt wegen der reinen Config-Prüfung dennoch `true`. Verfügbarkeit an erfolgreiche Initialisierung/Start koppeln und Kauf/State explizit fail-closed als unavailable ausgeben.

</details>

<details>
<summary>Details</summary>

## V9 akzeptiert nicht-kanonische bezahlte Expiries

**P1 · confirmed.** `DataSchema.normalizeAutoHatchExpiry` rundet in `src/ServerScriptService/Services/DataSchema.lua:412` jeden endlichen Wert mit `math.floor` ab und prüft erst danach das Live-Fenster. Damit wird ein korrupter Wert wie `1600.9` bei `now = 1000` als gültige absolute Expiry `1600` geladen, obwohl der Persistenzvertrag ausschließlich finite Integer zulässt. Der neue Test in `tests/DataSchema.spec.lua:731-734` bestätigt das falsche Verhalten und bezeichnet es zugleich als „canonical integer“.

Vor jeder Abrundung muss `value % 1 ~= 0` zu `0` normalisieren; derselbe Integer-Check sollte auch in der Live-Reconciliation von `AutoHatchService` gelten, damit nach dem Load korrumpierte Werte nicht repariert statt verworfen werden. Der Testfall `1600.9` muss anschließend `0` erwarten.

## Private Station-Authority lässt Property-Tampering teilweise zu

**P1 · confirmed.** In `src/ServerScriptService/Services/ZoneService.lua:124-130` werden am Pedestal Name, Shape, Anchored, CanCollide, Size und CFrame geprüft; die beim Spawn gesetzten Werte `Color` und `Material` fehlen. Für den Interaction-Part vergleichen `ZoneService.lua:164-170` Name, Anchored, CanCollide, Transparency, Size und CFrame, aber nicht Shape, Material oder Color. Entsprechend speichert der Record in `ZoneService.lua:1609-1628` dafür keine kanonischen Werte.

Der Snapshot sollte alle kanonischen physischen Eigenschaften der drei Parts aufnehmen und `validateEggRecordIntegrity` exakt dagegen prüfen. `MachineStation.spec.lua` braucht Tamper-Tests für Pedestal-Material/-Farbe und Interaction-Part-Shape/-Material/-Farbe, damit der zugesagte Property-Vertrag vollständig fail-closed ist.

## Startfehler verlieren ihren stabilen Pause-Code vor der Darstellung

**P1 · confirmed.** `AutoHatchService.startSession` gibt fehlenden Zugang und Authority-/Stationsfehler in `src/ServerScriptService/Services/AutoHatchService.lua:336-348` als zweites Remote-Ergebnis zurück, ohne `_stoppedReasons` zu setzen, eine Revision zu erhöhen oder einen DTO mit diesem `pauseReason` zu publizieren. `finishAutoAction` in `src/StarterPlayer/StarterPlayerScripts/Main.client.lua:538-548` nimmt `reason` entgegen, verwendet ihn aber nicht: Es rendert `state` und lädt bei Fehlern erneut denselben unveränderten Zustand.

`UIController` lokalisiert ausschließlich `state.pauseReason` (`src/StarterPlayer/StarterPlayerScripts/UIController.lua:867-880, 970`). Dadurch bleiben `TOO_FAR`, `CHARACTER_UNAVAILABLE`, `ZONE_LOCKED`, `STATION_INVALID` und `ACCESS_REQUIRED` trotz vorhandener Texte unsichtbar. Für semantisch valide, aber abgelehnte Aktionen sollte der Server den Reason in einen revisionsgesicherten State übernehmen und publizieren; alternativ braucht der Client generation-gebundenes, beim Promptwechsel invalidiertes Aktionsfeedback. Ein Test muss einen realen Startfehler durch Remote-Antwort bis zum sichtbaren Text verfolgen.

## Scriptstart-Spieler überspringen die Rejoin-Reconciliation

**P1 · confirmed.** Der normale `PlayerAdded`-Pfad ruft nach dem Profile-Load `PotionService.onPlayerAdded`, `AutoHatchService.onPlayerAdded` und danach Movement auf (`src/ServerScriptService/Main.server.lua:790-794`). Im Bootstrap für bereits verbundene Spieler folgt auf den Load direkt Potion und Movement (`Main.server.lua:935-945`); Auto-Hatch fehlt.

Ein solcher Spieler erhält weder eine initiale Generation/Revision noch `_rejoinRequired = true` für noch aktive persistierte Zeit. `GetAutoHatchState` zeigt dann `STOPPED` ohne `REJOIN_REQUIRES_STATION`. Der Bootstrap muss denselben Auto-Hatch-Hook in derselben Reihenfolge ausführen; ein Lifecycle-Test sollte beide Eintrittspfade auf identische Initialzustände prüfen.

## Fehlende Egg-Authority deaktiviert Verhalten, aber nicht die Präsentation

**P2 · confirmed.** `Main.server.lua:253-262` initialisiert und startet Auto-Hatch nur, wenn `ZoneService` beide Authority-Funktionen liefert. Schlägt World-/Authority-Initialisierung fehl, bleiben Dependencies und Scheduler inaktiv. `runtimeEnabled` in `src/ServerScriptService/Services/AutoHatchService.lua:189-190` prüft dagegen ausschließlich die Config-Gates und bleibt `true`; der Shop kann einen kaufbaren Dienst anzeigen, dessen Kauf nur mit `TECHNICAL_ERROR` und dessen Start mit `STATION_AUTHORITY_UNAVAILABLE` endet.

Der State sollte Verfügbarkeit nur melden, wenn Dependencies installiert und der Scheduler erfolgreich gestartet sind. Der Kaufpfad sollte dieselbe Prüfung vor dem Transaktionszugriff verwenden und einen stabilen unavailable Reason liefern. Ein Initialisierungsfehler-Test sollte `runtimeEnabled = false`, mutationsfreie Ablehnung und deaktivierte UI-Flächen bestätigen.

## Nicht abgedeckte Fehlerpfade

**Confirmed:** Nicht getestet sind die Ablehnung fraktionaler Expiries, die vollständige physische Property-Matrix der Station, sichtbares Feedback für abgelehnte Start-Aktionen, der bereits-verbunden-Bootstrap und der DTO/UI-Zustand nach Authority-Initialisierungsfehler. Diese Lücken erklären, warum 257/257 Lua-Tests, 94/94 Compiles, 72/72 Source-Parität, Python 2/2 und `diff --check` trotz der Findings grün bleiben.

</details>

<details>
<summary>File map</summary>

- `src/ReplicatedStorage/Shared/BalanceConfig.lua` — aktiviert und definiert Preis, Laufzeit, Intervall und V1-Vertrag.
- `src/ReplicatedStorage/Shared/ShopData.lua` — ergänzt Auto-Hatch-Katalog- und Präsentationsdaten.
- `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua` — kapselt Prompt-Generation, In-flight-Besitz und Revisionen.
- `src/ServerScriptService/Services/AutoHatchService.lua` — besitzt Kauf, DTOs, Sessions, Scheduler und Lifecycle.
- `src/ServerScriptService/Services/DataSchema.lua` — migriert auf V9 und persistiert die absolute Expiry.
- `src/ServerScriptService/Services/DataService.lua` — projiziert die Expiry zum Client.
- `src/ServerScriptService/Services/EggService.lua` — bewahrt persistierte Tiers und stellt Station-Authority bereit.
- `src/ServerScriptService/Services/ShopService.lua` — deaktiviert den Legacy-Scheduler und hält Kompatibilität fail-closed.
- `src/ServerScriptService/Services/ZoneService.lua` — erzeugt die private konkrete Egg-Station-Registry.
- `src/ServerScriptService/Main.server.lua` — verdrahtet Service, Remotes, Rate Limits, Join/Leave und Shutdown.
- `src/StarterPlayer/StarterPlayerScripts/Main.client.lua` — entdeckt optionale Remotes und bindet Station-Aktionen generation-sicher.
- `src/StarterPlayer/StarterPlayerScripts/UIController.lua` — ergänzt Shopkarte, Station-Controls, Countdown und Reason-Texte.
- `tests/BalanceConfig.spec.lua` — verifiziert die kanonische Economy-Konfiguration.
- `tests/DataSchema.spec.lua` — testet V9-Migration, Offline-Zeit und Expiry-Bounds.
- `tests/EggService.spec.lua` — testet No-fallback-Tiers und server-driven Shiny-Verhalten.
- `tests/MachineStation.spec.lua` — erweitert World-Authority-Tests um Egg-Stationen.
- `tests/ShopService.spec.lua` — verifiziert Katalog und fail-closed Legacy-Pfade.
- `tests/AutoHatchService.spec.lua` — deckt Kauf, Scheduler, Pausen und Lifecycle ab.
- `tests/AutoHatchClient.spec.lua` — deckt Client-Generationen, Revisionen und Rolling-Discovery ab.
- `tests/run_tests.lua` — registriert die neuen Specs.
- `tools/generate_rbxlx.py` — nimmt beide neuen Runtime-Module in die Place auf.
- `tests/verify_generated_place.py` — erwartet und verifiziert 72 Runtime-Sources und QOF-18-Wiring.
- `BATTLE_PETS.rbxlx` — regenerierte Place mit bytegenauen QOF-18-Sources.
- `README.md` — dokumentiert Feature, Architektur und Verifikation.
- `docs/QOF-18-paid-auto-hatch.md` — beschreibt Produkt-, Sicherheits-, Scheduler- und Live-Testvertrag.

Vollständiger Diff: `git diff origin/qof-17-rainbow-machine-e2e` plus `git ls-files --others --exclude-standard` für die fünf untracked Dateien.

</details>
