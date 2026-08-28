# Paid Auto-Hatch: acht Vorfindings geschlossen, Same-Station-Reopen bleibt defekt

QOF-18 führt bezahlten, stationsgebundenen Auto-Hatch mit 500-Diamond-Kauf, absoluter 600-Sekunden-Expiry und globalem Drei-Sekunden-Scheduler ein. Alle acht Findings aus den beiden Vorreviews sind in ihrem ursprünglichen Korrektheitskern geschlossen: Persistenz, Stationsauthority, revisionsgebundenes Startfeedback, beide Joinpfade, Runtime-Fail-closed, manueller Authority-Fallback, Main-Rate-Limits und lokales Close-Ownership sind korrigiert. Die Abschlussprüfung findet jedoch eine neue **confirmed** Regression direkt hinter dem achten Fix: Nach Cancel, erfolgreichem manuellem Hatch oder Navigation wird die Session geschlossen, aber ein erneutes Auslösen desselben weiterhin aktiven Prompts bindet sie nicht wieder; Auto-Hatch bleibt dort bis zu PromptHidden/PromptShown ohne Ziel. In Economy, Scheduler, Tier-Verhalten, Lifecycle, Rolling-Vertrag und Artefaktparität wurde kein weiteres korrektheitsrelevantes Finding gefunden.

**Watch for:** **confirmed** — Close invalidiert die Session korrekt, doch Same-Station-Reopen übernimmt anschließend nur deren gelöschte `nil`-Felder statt die Stationscapability neu zu installieren.

**Verdict**: NEEDS_CHANGES

## High-level view

Bezahlte Zeit ist eine nicht stapelbare absolute Integer-Expiry; Kauf und Batchmutation besitzen atomare Rollback-Grenzen, und manuelle wie automatische Hatches hängen an derselben privaten Egg-Station-Authority. Die ersten sieben Vorfindings sind damit geschlossen; der achte Fix räumt außerdem Generation, Kauf-Token und Busy-Besitz beim Close auf.

**Confirmed:** Der Reopen-Pfad ist asymmetrisch. `PromptShown` und A→B installieren eine Capability, während `PromptTriggered` für denselben aktiven Prompt nur die bereits geschlossene Session in die UI projiziert. Nach Cancel sind Prompt, Station-ID, Token und Egg-Typ gelöscht, sodass die wieder geöffnete Auto-Hatch-Fläche kein Ziel erhält.

Scheduler und EggService bewahren One-in-flight, no-backlog/no-catch-up, atomare volle x1/x2/x5/x10-Batches, Tier-No-Fallback und Shiny-Charge-Erhalt. Join, Leave und Shutdown invalidieren transiente Sessions; Rolling-Flächen bleiben optional oder fail-closed, und die Place-Datei stimmt mit allen 72 Runtime-Sources bytegenau überein.

<details>
<summary>Issues (1)</summary>

1. **Same-Station-Reopen verliert die Capability** — **confirmed**: Cancel/Navigation schließen die Session, aber `PromptTriggered` bindet denselben weiterhin aktiven Prompt nicht neu und lässt Auto-Hatch bis zum Verlassen des Radius ohne Ziel. Den Same-Prompt-Zweig aus dem aktuellen Prompt erneut über `getAutoHatchStationData` und `AutoHatchClientSession.start` binden und den realen Close/Reopen-Routerpfad testen.

</details>

<details><summary>Details</summary>

## Expliziter Abschlussstatus der acht Vorfindings

Finding 1, fraktionale V9-Expiry — **GESCHLOSSEN, confirmed.** Schema und Live-Reconciliation verlangen finite Integer und setzen Fractionals, Expired und Werte außerhalb `now + 600` auf null (`src/ServerScriptService/Services/DataSchema.lua:405-422`, `src/ServerScriptService/Services/AutoHatchService.lua:89-104`).

Finding 2, unvollständiger Station-Property-Vertrag — **GESCHLOSSEN, confirmed.** Snapshot und Integritätsprüfung vergleichen jetzt Pedestal-Farbe/-Material sowie Shape, Farbe und Material des Interaction-Parts; die Tamper-Tests decken diese Eigenschaften ab (`src/ServerScriptService/Services/ZoneService.lua:114-177`, `:1603-1649`, `tests/MachineStation.spec.lua:508-522`).

Finding 3, Startfehler erreichen die UI nicht — **GESCHLOSSEN, confirmed.** `rejectedStartState` schreibt Aktion, Reason und Station-ID in einen revisionsgebundenen State; `UIController` rendert ihn nur für die lokal gebundene Station (`src/ServerScriptService/Services/AutoHatchService.lua:247-263`, `src/StarterPlayer/StarterPlayerScripts/UIController.lua:910-988`).

Finding 4, bereits verbundene Spieler werden nicht initialisiert — **GESCHLOSSEN, confirmed.** `PlayerAdded` und `Players:GetPlayers()` rufen nach dem Profile-Load `AutoHatchService.onPlayerAdded` auf (`src/ServerScriptService/Main.server.lua:790-794`, `:935-946`).

Finding 5, Authority-/Scheduler-Ausfall wird als aktiv beworben — **GESCHLOSSEN, confirmed.** Runtime-Verfügbarkeit verlangt vollständige Dependencies und `_started`; Startfehler und spätere Loop-Crashes deaktivieren und publizieren die Runtime fail-closed (`src/ServerScriptService/Services/AutoHatchService.lua:69-87`, `:553-605`).

Finding 6, manueller Hatch fällt auf den Legacy-Stationsscan zurück — **GESCHLOSSEN, confirmed.** `defaultStationValidator` ist entfernt; ohne private `validateManual`-Authority lehnen Quote und Kauf mutationsfrei ab (`src/ServerScriptService/Services/EggService.lua:69-75`, `:192-202`, `tests/EggService.spec.lua:328-343`).

Finding 7, Main-Rate-Limit umgeht kanonisches Startfeedback — **GESCHLOSSEN, confirmed.** `StartAutoHatch` leitet `RATE_LIMITED` über `AutoHatchService.rejectStart` in denselben revisions- und stationsgebundenen Feedbackpfad (`src/ServerScriptService/Main.server.lua:382-388`, `src/ServerScriptService/Services/AutoHatchService.lua:281-287`, `tests/AutoHatchService.spec.lua:285-304`).

Finding 8, Cancel/Navigation behalten Request- und Busy-Besitz — **GESCHLOSSEN im ursprünglichen Kern, confirmed.** Der gemeinsame Close erhöht beide Kauf-/Hatch-Tokens, schließt `AutoHatchClientSession`, löscht Busy und entfernt das lokale Ziel; Navigation einer offenen Hatch-Oberfläche nutzt diesen Callback (`src/StarterPlayer/StarterPlayerScripts/Main.client.lua:419-431`, `src/StarterPlayer/StarterPlayerScripts/UIController.lua:5368-5378`). Der nachfolgende Reopen-Defekt ist das neue Finding dieses Passes.

## Same-Station-Reopen verliert die Auto-Hatch-Capability

**P1 · confirmed.** `closeHatchPurchaseDialog` ruft `AutoHatchClientSession.close` auf, das Generation, Prompt, Station-ID, Token und Egg-Typ invalidiert (`src/StarterPlayer/StarterPlayerScripts/Main.client.lua:419-431`, `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua:23-32`). `activeEggPrompt` bleibt bei Cancel, erfolgreichem manuellem Hatch und Navigation bestehen, solange der Roblox-Prompt sichtbar ist.

Beim erneuten E auf derselben Station gilt deshalb `activeEggPrompt == prompt`. `PromptTriggered` nimmt den `elseif autoHatchSession`-Zweig und übergibt nur `autoHatchSession.eggType` und `.stationId` an die UI; beide sind nach Close `nil` (`src/StarterPlayer/StarterPlayerScripts/Main.client.lua:759-778`). Anders als `PromptShown` oder A→B liest dieser Zweig die Capability nicht neu und ruft `AutoHatchClientSession.start` nicht auf.

```text
PromptShown(A)      -> Session.start(A) -> Ziel A
Cancel/Navigation   -> Session.close()  -> prompt/id/token/type = nil
PromptTriggered(A)  -> same-prompt      -> setLocalStation(nil, nil)
```

Auto-Hatch funktioniert danach erst wieder, wenn der Spieler den Radius verlässt und ein neues `PromptShown` erzeugt. Der Same-Prompt-Zweig muss eine geschlossene oder abweichend gebundene Session aus dem aktuellen Prompt neu installieren. Ein Produktionspfad-Test sollte `PromptShown(A) → Request in flight → Cancel/Navigation → PromptTriggered(A)` ausführen, die alte Completion ablehnen und sofort eine neue Aktion mit A-ID/A-Token zulassen. Der Pure-Session-Test startet beim Reopen selbst `Session.start` und überspringt damit den defekten Router (`tests/AutoHatchClient.spec.lua:15-34`).

## Geprüfte Economy-, Scheduler- und Lifecycle-Grenzen

Kauf und Persistenz halten 500 Diamonds, exakt 600 Sekunden, kein Stacking und fail-closed Integer-Expiry. Der stille Debit wird erst nach Expiry-Mutation und DTO-Aufbau committed; technische Fehler stellen Expiry und Rohbetrag wieder her. Start und Tick prüfen private Instanzen, GUID, Zone, Egg-Typ und physischen Snapshot; nur die Distanz wird nach autorisiertem Start serverseitig ausgelassen, und manuelle Pfade besitzen keinen Legacy-Fallback.

Auto-Hatch verwendet den bestehenden atomaren `EggService.purchaseAndHatch`-Commit mit vollem Tier und Coinpreis. Kapazität, Entitlement, Hatch-Lock, Pet-/Currency-Rollback und Events bleiben Batch-atomar; `consumeShinyCharges = false` erhält Shiny-Charges. Gültige x2/x5/x10 bleiben bei Entitlement-Verlust gespeichert und pausieren statt kleiner auszuführen.

Der Scheduler lässt höchstens einen Batch pro Session zu, verwirft Ticks während in-flight und erzeugt nach Stall oder Pause weder Queue noch Catch-up. Beide Joinpfade setzen aktive Restzeit auf `REJOIN_REQUIRES_STATION`; Leave invalidiert vor Egg-/Data-Cleanup, Shutdown stoppt den Scheduler vor dem finalen Save-Hook. Neue Clients entdecken QOF-18 optional, während `SetHatchBatchSize`, `PurchaseShopItem("AutoHatch")` und `ShopService._processAutoHatch` mutationsfrei bleiben.

## Automatisierte Evidenz und manuelle Abnahmegrenzen

Bestätigt sind 263/263 Lua-Tests, 94/94 Luau-Compiles, Python 2/2, `git diff --check`, 72/72 bytegenaue Runtime-Sources und 70 ModuleScripts + 1 Script + 1 LocalScript. `BATTLE_PETS.rbxlx` hat 1.017.486 Bytes und SHA-256 `d3f128d59fe965cd65133b781b7129098800c84673b0b68fb698c1193107039b`. Der Routerfehler bleibt grün, weil der Clienttest beim Reopen `Session.start` direkt aufruft und `Main.client.lua` sonst nur über Source-Strings prüft.

Manuell bleiben DataStore-Offlinezeit und Korruptionsinjektion, 10/10.001-Stud-Live-Distanzen, Character/HRP und Instance-Tampering, Scheduler-Hitches, Mehrclient-/Manual-Hatch-Konkurrenz, Coin-/Kapazitätsgrenzen aller Tiers, Shiny-Charge-Erhalt, Expiry-Race, Cinematic-FIFO, Rolling Server/Client, Leave während in-flight, Servertransfer und BindToClose. `docs/QOF-18-paid-auto-hatch.md:83-106` beschreibt diese Matrix; das Blocking-Finding liegt im deterministischen Client-Router und benötigt keine Live-Annahme.

</details>

<details>
<summary>File map</summary>

- `src/ServerScriptService/Services/AutoHatchService.lua` — Kauf, Expiry, Feedback, Sessiongenerationen und Scheduler.
- `src/ServerScriptService/Services/EggService.lua` — fail-closed Authority, Tier-Persistenz und atomare Batches.
- `src/ServerScriptService/Services/ZoneService.lua` — private Egg-Station-Registry und Integrität.
- `src/ServerScriptService/Main.server.lua` — Bootstrap, V1-Remotes, Rate-Limits und Lifecycle.
- `src/ReplicatedStorage/Shared/AutoHatchClientSession.lua` — Promptgeneration, Requestbesitz und Revisionen.
- `src/StarterPlayer/StarterPlayerScripts/Main.client.lua` — Rolling-Remotes, Close-Invaliderung und defekter Same-Prompt-Reopen.
- `src/StarterPlayer/StarterPlayerScripts/UIController.lua` — Hatch-Dialog, Auto-Hatch-Controls, Feedback und Navigation-Cancel.
- `src/ServerScriptService/Services/DataSchema.lua` / `DataService.lua` — V9-Expiry und Persistenz/Shutdown.
- `src/ReplicatedStorage/Shared/BalanceConfig.lua` / `ShopData.lua` — Economy und Shoppräsentation.
- `src/ServerScriptService/Services/ShopService.lua` — deaktivierter Legacy-Loop.
- `tests/AutoHatchService.spec.lua`, `AutoHatchClient.spec.lua`, `EggService.spec.lua`, `MachineStation.spec.lua` — Service-, Client-, Batch- und Authority-Evidenz.
- `tools/generate_rbxlx.py`, `tests/verify_generated_place.py`, `BATTLE_PETS.rbxlx` — Manifest und Place-Parität.
- `docs/QOF-18-paid-auto-hatch.md`, `README.md` — Vertrag und manuelle Live-Matrix.

Vollständiger Produktdiff: `git diff origin/qof-17-rainbow-machine-e2e` plus `git ls-files --others --exclude-standard`; `semantic-review/` enthält nur Reviewartefakte.

</details>
