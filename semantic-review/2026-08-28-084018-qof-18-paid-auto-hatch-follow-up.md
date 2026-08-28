# Paid Auto-Hatch Follow-up: Kernfixes geschlossen, Failure-Grenzen noch offen

QOF-18 implementiert den bezahlten, stationsgebundenen Auto-Hatch-Pfad mit absoluter 600-Sekunden-Expiry, atomaren EggService-Batches und einem globalen Drei-Sekunden-Scheduler. Die fünf Findings des ersten Reviews sind geschlossen: fraktionale Expiries fallen auf null, die fehlenden Stationseigenschaften werden geprüft, normale Startablehnungen werden revisionsgebunden dargestellt, beide Joinpfade initialisieren den Dienst, und Runtime-Verfügbarkeit hängt an Authority plus Scheduler. Scheduler-Crash nach erfolgreichem Spawn und Busy-Cleanup beim direkten Station-A→B-Wechsel sind ebenfalls umgesetzt. Vor dem Shipping verbleiben drei korrektheitsrelevante Failure-Grenzen.

**Watch for:** **confirmed** — ein Authority-Bootstrapfehler lässt manuelle Hatches auf den alten replizierten Stationsscan zurückfallen; **confirmed** — `RATE_LIMITED`-Startablehnungen umgehen das revisionsgebundene `actionFeedback` und bleiben unsichtbar; **confirmed** — Cancel/Navigation schließen die Oberfläche, invalidieren aber weder die Auto-Hatch-Requestgeneration noch deren Busy-Besitz.

**Verdict**: NEEDS_CHANGES

## High-level view

V9 akzeptiert nur finite Integer im Live-Fenster, der Kauf setzt exakt `now + 600`, und automatische Batches verwenden den vollständigen Coin-/Inventory-Commit ohne Shiny-Charges oder Tier-Fallback.

Die private Egg-Station-Registry prüft im erfolgreichen Bootstrap konkrete Instanzen, Tokens, Zonen, Distanzen und die zuvor fehlenden Pedestal-/Interaction-Part-Eigenschaften. **Confirmed:** Schlägt `ZoneService.init` nach dem Erzeugen von Egg-Parts fehl, erhält `EggService` keine Authority und verwendet für manuelle Quotes und Käufe wieder den Legacy-Scan statt fail-closed abzulehnen.

Der Scheduler lässt höchstens einen Batch pro Session zu, erzeugt keine Queue oder Catch-up-Arbeit und deaktiviert die Runtime nach einem späteren Loop-Crash. Stop, Leave, Rejoin, Expiry und Generationen verhindern das Wiederbeleben alter Sessions.

Revisionsgebundenes `actionFeedback` ist für `ACCESS_REQUIRED`, Authority- und Stationsablehnungen gegen GET/Event/Action-Response-Reordering stabil. **Confirmed:** Das vorgeschaltete Main-Rate-Limit liefert einen alten DTO ohne Feedbackrevision, während der Client den separaten Reason verwirft; ein schneller zweiter Start, insbesondere nach A→B, endet ohne sichtbaren `RATE_LIMITED`-Hinweis.

Der direkte A→B-Promptwechsel und `PromptHidden` schließen die Client-Session und räumen Busy-State auf. **Confirmed:** Der gemeinsame Cancel-/Navigationspfad löscht nur die lokale Stationsdarstellung; ein laufender Request bleibt generation-gültig und Busy bleibt beim Schließen/Reopen bestehen.

Erneut ausgeführt wurden 261/261 Lua-Tests, 72/72 bytegenaue Place-Sources, die Prüfung auf 70 ModuleScripts plus je ein Script/LocalScript, 1.017.638 Bytes, `git diff --check` und SHA-256 `17829139d93c6d02c55013b3b16fd9bcf75a313ec4228a8d2f537ec0331f3014`. Die angegebenen 94/94 Compiles, Python 2/2 und Generatorwerte stimmen damit überein; die drei verbleibenden Pfade werden nicht end-to-end getestet.

<details>
<summary>Issues (3)</summary>

1. **Privater Authority-Bootstrap fällt manuell offen** — **confirmed**: Bei partiellem World-Build nutzt `EggService` wieder den Legacy-Stationsscan. Fehlende private Authority muss auch manuelle Quotes/Käufe mutationsfrei ablehnen; ein Post-Egg-Spawn-Bootstraptest ist erforderlich.
2. **Rate-limitierte Starts verlieren Feedback** — **confirmed**: Main gibt `RATE_LIMITED` ohne neue Feedbackrevision zurück, und der Client verwirft den separaten Reason. Die Ablehnung revisions- und stationsgebunden publizieren oder generation-sicher lokal übernehmen und den Main→UI-Pfad testen.
3. **Close/Reopen behält Request- und Busy-Besitz** — **confirmed**: Cancel und Navigation schließen weder `AutoHatchClientSession` noch den Busy-State. Den gemeinsamen Close-Pfad wie A→B invalidieren und einen in-flight Cancel/Navigation/Reopen-Test ergänzen.

</details>

<details>
<summary>Details</summary>

## EggService fällt bei fehlender privater Authority auf den Legacy-Scan zurück

**P1 · confirmed.** `src/ServerScriptService/Main.server.lua:253-262` installiert `EggService.setStationAuthority(eggStationAuthority)` nur nach vollständig erfolgreichem `ZoneService.init`. Bei einem späteren World-Build-Fehler bleibt `EggService._stationValidator` nil; `isNearStation` fällt in `src/ServerScriptService/Services/EggService.lua:222-226` auf `defaultStationValidator` zurück. Dieser prüft replizierte `EggModel`-/Tag-/Prompt-Strukturen und Distanz, aber nicht die private Registry-Identität oder deren vollständigen Integritäts-Snapshot.

`ZoneService.init` erzeugt Egg-Stationen vor weiteren World-, Maschinen- und Authority-Schritten. Ein Fehler nach `_spawnEggStations()` kann deshalb serverseitige Parts hinterlassen, die der Fallback für manuelle Quotes und `HatchEgg` akzeptiert, obwohl Auto-Hatch unavailable ist. Das widerspricht dem Vertrag in `docs/QOF-18-paid-auto-hatch.md`, nach dem manuelle Hatches dieselbe Registry verwenden.

Fehlende Authority muss auch den manuellen Stationspfad explizit verweigern; der Legacy-Scanner darf nicht der QOF-18-Ausfallpfad sein. Ein Bootstrap-Test muss einen Fehler nach Egg-Spawn injizieren und mutationsfreie Quote-/Kaufablehnung bestätigen.

## Main-Rate-Limits umgehen das kanonische Start-Feedback

**P1 · confirmed.** `AutoHatchService.rejectedStartState` erhöht für Service-Ablehnungen die Revision und publiziert `{ action = "START", reason, stationId }`. Dadurch bleibt das Feedback bei vertauschter GET-, Event- und Action-Response-Reihenfolge kanonisch.

`src/ServerScriptService/Main.server.lua:383-385` beendet `StartAutoHatch` bei Cooldown/Burst-Limit vorher mit `false, "RATE_LIMITED", AutoHatchService.getState(player)`. Der DTO hat keine neue Revision und kein `actionFeedback`. `finishAutoAction` in `src/StarterPlayer/StarterPlayerScripts/Main.client.lua:540-550` ignoriert den separaten `reason`; derselbe Revisionsstand wird abgelehnt und ein GET-Refresh kann ihn nicht sichtbar machen. Der Text in `src/StarterPlayer/StarterPlayerScripts/UIController.lua:881` ist damit unerreichbar.

Ein schneller Start an Station B nach dem bereinigten A→B-Wechsel kann in die 350-ms-Sperre des Starts an A laufen und still scheitern. Das Limit muss eine kanonische Startablehnung publizieren oder der Client den Reason generation- und stationsgebunden übernehmen. Der Test braucht den vollständigen Main→Client-Pfad.

## Cancel und Navigation invalidieren Auto-Hatch-Requests nicht

**P1 · confirmed.** `closeHatchPurchaseDialog` in `src/StarterPlayer/StarterPlayerScripts/Main.client.lua:417-423` erhöht nur den manuellen Hatch-Token, schließt das Fenster und löscht die lokale Station. Anders als A→B (`Main.client.lua:688-692`) und `PromptHidden` (`Main.client.lua:719-723`) ruft er weder `AutoHatchClientSession.close` noch `setAutoHatchActionInFlight(nil)` auf.

Cancel, Navigation und ein erfolgreicher manueller Hatch verwenden diesen Pfad. Ein gesendeter Auto-Hatch-Request behält seine Generation, seine Completion wird nach dem Schließen akzeptiert, und Busy bleibt bis zur Antwort bestehen. Wird dieselbe Promptoberfläche vorher wieder geöffnet, kann die alte Response wieder stationsgebundenes Feedback rendern.

Der gemeinsame Close-Pfad muss Sessiongeneration und Busy-UI wie A→B invalidieren, ohne serverseitig Stop auszulösen. Ein integrierter Start-in-flight → Cancel/Navigation → Reopen-Test muss alte Completions abweisen.

## Nicht automatisierte Grenzen

Nicht getestet sind der partielle World-Build mit vorhandenen Eggs aber fehlender Authority, die Main-Rate-Limit-Ablehnung bis zum sichtbaren Text und der reale Dialog-Close-/Navigation-Pfad mit in-flight Request. Die Clienttests prüfen dafür nur das pure Session-Modul und Source-Strings.

Manuell bleiben DataStore-Offlinezeit und Korruptionsinjektion, Live-Distanzen und serverseitiges Station-Tampering, Scheduler-Hitches, Mehrclient-/Manual-Hatch-Konkurrenz, Economy-/Kapazitätsgrenzen, Shiny-Charge-Erhalt, Expiry-Race, Cinematic-FIFO, Rolling Deployment sowie Leave/Shutdown/Transfer unter echter Roblox-Latenz.

</details>

<details>
<summary>File map</summary>

- `src/ServerScriptService/Services/AutoHatchService.lua` — Kauf, Expiry, Sessions, Feedback, Revisionen und Scheduler-Fail-closed.
- `src/ServerScriptService/Services/ZoneService.lua` — private Egg-Station-Registry und Property-Snapshot.
- `src/ServerScriptService/Services/EggService.lua` — Tiers ohne Fallback, atomare Batches und manueller Authority-/Legacy-Fallback.
- `src/ServerScriptService/Main.server.lua` — Bootstrap, V1-Remotes, Rate-Limits und Player-Lifecycle.
- `src/ServerScriptService/Services/DataSchema.lua` — V9-Integer-Expiry und fail-closed Live-Fenster.
- `src/ReplicatedStorage/Shared/BalanceConfig.lua` / `ShopData.lua` — Economy-, Intervall-, Contract- und Shopdaten.
- `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua` — Promptgeneration, in-flight Ownership und Revisionannahme.
- `src/StarterPlayer/StarterPlayerScripts/Main.client.lua` — Rolling-Remotes, Actionrouting und Prompt-/Close-Lifecycle.
- `src/StarterPlayer/StarterPlayerScripts/UIController.lua` — Shop-/Stationscontrols, Countdown und Reason-Darstellung.
- `tests/AutoHatchService.spec.lua` / `AutoHatchClient.spec.lua` / `tests/MachineStation.spec.lua` — Service-, Scheduler-, Client-Session- und Stationstests.
- `tools/generate_rbxlx.py`, `tests/verify_generated_place.py`, `BATTLE_PETS.rbxlx` — Runtime-Manifest, Parität und Place-Artefakt.
- `docs/QOF-18-paid-auto-hatch.md` / `README.md` — Produkt-, Sicherheits-, Rolling- und Live-Testvertrag.

Vollständiger Produktdiff: `git diff origin/qof-17-rainbow-machine-e2e` plus `git ls-files --others --exclude-standard`; `semantic-review/` enthält nur Reviewartefakte.

</details>
