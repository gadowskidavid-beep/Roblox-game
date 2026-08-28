# Paid Auto-Hatch: alle neun Reviewfindings geschlossen

QOF-18 ergänzt bezahltes, stationsgebundenes Auto-Hatch mit 500-Diamond-Kauf, absoluter 600-Sekunden-Expiry, vollen x1/x2/x5/x10-Coinbatches und einem globalen Drei-Sekunden-Scheduler. Der letzte Same-Station-Reopen-Defekt ist geschlossen: Nach Cancel oder Navigation installiert `PromptTriggered` die Capability desselben weiterhin aktiven Prompts erneut, während malformed Stationsdaten ohne lokales Ziel bleiben. Die acht früheren Findings bleiben geschlossen; in den angrenzenden Prompt-, In-flight-, Kauf-Token-, Busy-, Economy-, Authority-, Scheduler- und Lifecycle-Pfaden wurde kein neues korrektheitsrelevantes Finding gefunden. Die automatisierte Evidenz ist vollständig grün; Roblox-Engine-, DataStore- und echte Latenzgrenzen bleiben Teil der manuellen Abnahme.

**Watch for:** Keine offenen Codefindings. **confirmed** — der vollständige `Main.client.lua`-Prompt-Router und Roblox/DataStore-/Mehrclient-Verhalten werden nicht in einer echten Engine ausgeführt und bleiben als manuelle Abnahmegrenze gemäß Live-Matrix zu prüfen.

**Verdict**: APPROVED

## High-level view

Cancel, Navigation, PromptHidden und A→B-Wechsel schließen die lokale Client-Session und entziehen alten Requests sowie Käufen ihr Ownership. Ein erneutes Triggern desselben aktiven Prompts liest Station-ID, Token und Egg-Typ erneut und erzeugt eine neue Generation; malformed Capabilities bleiben ohne lokales Ziel.

Manuelle Hatches und Auto-Hatch hängen an derselben privaten Stationregistry. Start prüft zusätzlich Player, Character/HRP, Zone und Distanz; jeder Tick revalidiert Identität, Ancestry, Egg-Typ, Zone und Property-Snapshot, wobei nur die Distanz nach dem autorisierten Start bewusst übersprungen wird.

Bezahlte Zeit ist eine nicht stapelbare absolute Integer-Expiry mit stiller Debit-/Rollback-Grenze. Automatische Batches verwenden EggService zum vollen Preis, ohne Shiny-Charges oder Tier-Fallback.

Der Scheduler erlaubt pro Session höchstens einen Batch, keine Queue und kein Catch-up. Contract V1, monotone Revisionen, Generationen und optionale Client-Discovery halten Reordering, Lifecycle und Rolling-Deployment fail-closed; die Place-Datei stimmt mit allen 72 Runtime-Sources bytegenau überein.

<details>
<summary>Issues (0)</summary>

Keine offenen korrektheitsrelevanten Findings.

</details>

<details>
<summary>Details</summary>

## Same-Station-Reopen erneuert Capability und Ownership

Das Finding des dritten Reviews ist **GESCHLOSSEN, confirmed**. `closeHatchPurchaseDialog` invalidiert manuellen Hatch-Token, globalen Kauf-Token, `AutoHatchClientSession`, Busy und lokales Stationsziel, lässt aber den serverseitigen Auto-Hatch-Status unberührt. Bleibt der Roblox-Prompt sichtbar, erkennt der nächste `PromptTriggered` die geschlossene Session über `autoHatchSession.prompt ~= prompt`, liest die Capability mit `getAutoHatchStationData` neu, ruft `AutoHatchClientSession.start` auf und stellt erst danach das lokale Ziel wieder her (`src/StarterPlayer/StarterPlayerScripts/Main.client.lua`, `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua`).

`PromptShown`, direkte Trigger ohne vorheriges `PromptShown`, A→B und `PromptHidden` besitzen dieselbe Ownership-Grenze. Fehlende oder unbounded IDs/Tokens sowie ein abweichender Egg-Typ lassen die Auto-Hatch-Fläche ohne Ziel; die private Serverregistry wird unabhängig davon erneut geprüft. Alte Action-Completions müssen Generation, Prompt, Station-ID, Token, Egg-Typ und aktuelles In-flight-Besitzrecht treffen und können weder eine wieder geöffnete Session übernehmen noch den Busy-Zustand einer neueren Aktion löschen. Der Kaufpfad besitzt mit `autoHatchGlobalToken` dieselbe Schutzwirkung; autoritative Events dürfen einen bereits committed Kauf weiterhin global darstellen.

## Alle acht früheren Findings bleiben geschlossen

Fraktionale V9-Expiry und der unvollständige Stationssnapshot sind **GESCHLOSSEN, confirmed**: Schema und Live-Reconciliation akzeptieren nur finite Integer im Live-Fenster, und die zuvor fehlenden Pedestal-/Interaction-Part-Eigenschaften werden vor Start und Tick geprüft.

Verlorenes Startfeedback und der fehlende Bootstrap bereits verbundener Spieler sind **GESCHLOSSEN, confirmed**: Startablehnungen einschließlich `RATE_LIMITED` laufen revisions- und stationsgebunden bis zur UI, und beide Joinpfade initialisieren Auto-Hatch nach erfolgreichem Profile-Load.

Irreführende Runtime-Verfügbarkeit und manueller Legacy-Authority-Fallback sind **GESCHLOSSEN, confirmed**: Availability verlangt vollständige Dependencies plus laufenden Scheduler; ohne private Authority lehnt EggService manuelle Quotes und Käufe mutationsfrei ab.

Das ursprüngliche Close-/Reopen-Ownership-Finding ist **GESCHLOSSEN, confirmed**: Cancel und Navigation invalidieren Generation, Busy und Kauf-Token. Der Same-Station-Fix vervollständigt diese Grenze durch eine frische Capability beim nächsten Trigger.

## Authority, Economy und Scheduler

`ZoneService` veröffentlicht die Egg-Authority erst nach erfolgreichem World-Build. Acht private Records binden bounded IDs und pro Server eindeutige GUID-Tokens an exakte Instanzen und kanonische Properties; Clone-, Duplicate-ID-, Token-Swap-, Reparenting-, Prompt- und Property-Tampering werden fail-closed abgelehnt. Die fünf RemoteFunctions akzeptieren nur exakte plain Contract-V1-Tabellen; Main begrenzt Cooldown/Burst, AutoHatchService validiert erneut, und Legacy-Flächen bleiben discoverable, aber mutationsfrei.

Der Kauf setzt nach einem stillen exakten 500-Diamond-Debit `now + 600`; aktives Access wird nicht gestapelt. Technische Fehler vor Commit stellen Expiry und Diamondbetrag wieder her. Ein Tick führt den vollständigen ausgewählten Tier über `EggService.purchaseAndHatch` mit voller Coinzahlung und `consumeShinyCharges = false` aus. Gültige x2/x5/x10 bleiben bei Entitlement-Verlust gespeichert und pausieren, statt kleiner ausgeführt zu werden.

Der erste Batch ist erst am nächsten regulären Tick fällig. In-flight-Ticks werden übersprungen; Stall und Pause erzeugen weder Queue noch Catch-up. Stop, Targetwechsel und Leave verhindern per Generation die Wiederbelebung alter Sessions, während bereits atomar zugelassene EggService-Arbeit fertig werden darf. Bei `now >= expiresAt` startet kein neuer Batch; Scheduler-Crash deaktiviert die Runtime fail-closed.

## Lifecycle, Evidenz und manuelle Grenzen

Join und Bereits-verbunden-Bootstrap verwenden dieselbe Reconciliation; aktive Restzeit erscheint nach Rejoin als `REJOIN_REQUIRES_STATION`. Leave invalidiert vor Egg-/Data-Cleanup, Shutdown stoppt den Scheduler vor dem finalen Save-Hook, und monotone DTO-Revisionen schützen Action-Response/Event/GET-Reordering. Committed Batches bleiben auf dem vorhandenen `EggHatchStart`-/`EggHatchResult`- und EffectsController-FIFO-Pfad.

Erneut bestätigt wurden 263/263 Lua-Tests, 94/94 Luau-Compiles, Python-Compile 2/2 und `git diff --check origin/qof-17-rainbow-machine-e2e`. Der Place-Verifier bestätigt 72/72 bytegenaue Runtime-Sources und 70 ModuleScripts + 1 Script + 1 LocalScript. `BATTLE_PETS.rbxlx` enthält 135 Items, ist 1.018.039 Bytes groß und hat SHA-256 `e4bf01099a4d0ad101f9e38c09a54cf11df6b5da51993d3c3003b70c76766e50`.

Die verbleibende manuelle Matrix ist **confirmed** eine Engine-/Infrastruktur-Abnahmegrenze, kein Codefinding: DataStore-Offlinezeit und Korruptionsinjektion, 10/10,001-Stud-Distanzen, Character-/HRP- und Instance-Tampering, die echte Same-Station-`PromptShown → in-flight → Cancel/Navigation → PromptTriggered`-Folge, Scheduler-Hitches, Mehrclient-/Manual-Hatch-Konkurrenz, Coin-/Kapazitätsgrenzen aller Tiers, Shiny-Charge-Erhalt, Exact-Expiry-Race, Cinematic-FIFO, Rolling Server/Client, Leave während in-flight, Servertransfer und `BindToClose`. `docs/QOF-18-paid-auto-hatch.md` hält diese Live-Matrix fest.

</details>

<details>
<summary>File map</summary>

- `src/ReplicatedStorage/Shared/BalanceConfig.lua` — Preis, Laufzeit, Intervall und Contract V1.
- `src/ReplicatedStorage/Shared/ShopData.lua` — Auto-Hatch-Katalog und Präsentation.
- `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua` — Promptgeneration, Requestbesitz und Revisionen.
- `src/ServerScriptService/Services/AutoHatchService.lua` — Kauf, Expiry, Sessions, Feedback, Scheduler und Lifecycle.
- `src/ServerScriptService/Services/DataSchema.lua` — V9-Migration und absolute Expiry.
- `src/ServerScriptService/Services/DataService.lua` — Clientprojektion der Expiry.
- `src/ServerScriptService/Services/EggService.lua` — private Authority, Tier-No-Fallback und atomare Batches.
- `src/ServerScriptService/Services/ShopService.lua` — dauerhaft deaktivierter Legacy-Loop.
- `src/ServerScriptService/Services/ZoneService.lua` — private konkrete Egg-Station-Registry.
- `src/ServerScriptService/Main.server.lua` — Remotes, Rate-Limits, Bootstrap, Leave und Shutdown.
- `src/StarterPlayer/StarterPlayerScripts/Main.client.lua` — Prompt-, Capability- und Close/Reopen-Routing.
- `src/StarterPlayer/StarterPlayerScripts/UIController.lua` — Shopkarte, Stationcontrols, Countdown und Reasons.
- `tests/BalanceConfig.spec.lua`, `DataSchema.spec.lua`, `EggService.spec.lua`, `MachineStation.spec.lua`, `ShopService.spec.lua` — Economy-, Persistenz-, Batch-, Authority- und Legacy-Evidenz.
- `tests/AutoHatchService.spec.lua`, `AutoHatchClient.spec.lua`, `run_tests.lua` — Service-, Scheduler-, Client- und Testregistrierung.
- `tools/generate_rbxlx.py`, `tests/verify_generated_place.py`, `BATTLE_PETS.rbxlx` — Runtime-Manifest und bytegenaue Place-Parität.
- `README.md`, `docs/QOF-18-paid-auto-hatch.md` — Architektur-, Produkt- und Live-Testvertrag.
- Die drei vorhandenen Dateien unter `semantic-review/` — untracked Reviewhistorie, kein ausführbarer Produktcode.

Vollständiger Working-Tree-Diff: `git diff origin/qof-17-rainbow-machine-e2e` plus `git ls-files --others --exclude-standard` für untracked Source-, Test-, Dokumentations- und Reviewdateien.

</details>
