# SHIFT//BREAK

Ein vollständiges, assetfreies Roblox-Spiel in Luau. **1–8 Spieler** bergen Echos aus einer instabilen Dimension. Alle 22 Sekunden kippt die Realität: Wege ändern sich, der Anker fällt aus und jagende Schatten erscheinen. Nach drei Wellen bleibt entweder eine versiegelte Realität – oder ein weiterer Versuch mit permanenten Upgrades.

Das Projekt läuft sofort mit prozeduralen Platzhaltern. Eigene Modelle können später ohne Änderung der Spiellogik eingesetzt werden; siehe [`ASSET_GUIDE.md`](ASSET_GUIDE.md).

## Enthalten

- kompletter Loop: Warten → Intermission → drei Wellen → Sieg/Niederlage → Neustart
- serverautoritatives Sammeln, Einzahlen, Sprinten, Puls, Schaden, Belohnungen und Upgrades
- prozedurale Lobby und Arena als sofort spielbare Fallbacks
- Wechsel zwischen **STABIL** und **GEBROCHEN** mit anderen Brücken, Lichtstimmung und Gefahren
- schwebende Gegner-KI mit Skalierung pro Welle
- drei persistente Upgrades: Tragfähigkeit, Tempo und Puls-Cooldown
- DataStore-Speicherung mit sicherem Sitzungsfallback, wenn Studio-API-Zugriff deaktiviert ist
- vollständig per Code erzeugtes HUD, Intro, Meldungen und Shop
- Tastatur, Gamepad und Touchsteuerung
- Schnittstellen für eigene Lobby-, Arena-, Echo- und Schattenmodelle
- keine externen Pakete, Plugins, Bilder, Sounds oder bezahlten Assets

## Spielziel

1. Berühre gelbe **Echos**, um sie in deiner Tasche zu sammeln.
2. Kehre in der **stabilen Phase** zum gelben Riss-Anker zurück und halte **E**.
3. In der **gebrochenen Phase** ist der Anker offline. Wege wechseln und Schatten greifen an.
4. Nutze den **Riss-Puls**, um Gegner in der Nähe vier Sekunden zu betäuben.
5. Erfülle die Teamquote in allen drei Wellen. Eingezahlte Echos und Wellen geben Flux für permanente Upgrades.

Getragene Echos gehen beim Tod verloren; bereits eingezahlte Echos und Flux bleiben erhalten.

## Steuerung

| Aktion | Tastatur | Gamepad | Mobil |
|---|---|---|---|
| Bewegen | WASD | linker Stick | virtueller Stick |
| Sprint | Shift halten | L3 halten | SPRINT-Schaltfläche |
| Riss-Puls | Q | R2 | PULS-Schaltfläche |
| Echos übertragen | E am Anker | X | ProximityPrompt |

## Installation mit Rojo

Voraussetzungen: [Roblox Studio](https://create.roblox.com/) und Rojo 7.

```bash
cd shift-break
rojo build default.project.json -o SHIFT_BREAK.rbxlx
```

Öffne anschließend `SHIFT_BREAK.rbxlx` in Roblox Studio und starte **Test → Play**. Alternativ kannst du `rojo serve` nutzen und `default.project.json` über das Rojo-Studio-Plugin synchronisieren.

### Ohne Rojo

Lege die Dateien anhand ihrer Pfade manuell als Scripts/ModuleScripts an:

- `src/ReplicatedStorage/Shared/*` → `ReplicatedStorage/Shared`
- `src/ServerScriptService/Server/*` → `ServerScriptService/Server`
- `src/StarterPlayer/StarterPlayerScripts/Client/*` → `StarterPlayer/StarterPlayerScripts/Client`

Dateien mit `.server.lua` werden zu **Scripts**, `.client.lua` zu **LocalScripts**, alle übrigen `.lua` zu **ModuleScripts**. Entferne dabei nur die Dateiendung; `Main.server.lua` heißt in Studio beispielsweise `Main`.

## DataStore in Studio

Ohne API-Zugriff ist das Spiel trotzdem vollständig testbar; Profile gelten dann nur für die laufende Serversitzung und die Output-Konsole zeigt eine Warnung. Für persistente Daten:

1. Experience veröffentlichen.
2. **Game Settings → Security → Enable Studio Access to API Services** aktivieren.
3. Nur in einer Test-Experience aktivieren, wenn du Produktionsdaten nicht mit Studio verändern willst.

Verwendeter Store: `ShiftBreakProfiles_v1`. Gespeichert werden nur `Flux`, `Wins` und die drei Upgrade-Stufen.

## Balancing

Alle relevanten Werte stehen zentral in [`src/ReplicatedStorage/Shared/Config.lua`](src/ReplicatedStorage/Shared/Config.lua):

- Rundendauer und Phasenintervall
- Teamquoten und Skalierung pro Spieler/Welle
- Ausdauer, Sprinttempo, Pulsradius und Cooldown
- Gegneranzahl, Tempo und Schaden
- Belohnungen, Upgrade-Kosten und Upgrade-Boni
- Farben und CollectionService-Tags

Für einen ersten Solotest empfiehlt sich die vorhandene Konfiguration. Das erste Ziel beträgt 19 Echos und jede Welle dauert maximal 70 Sekunden.

## Projektstruktur

```text
shift-break/
├── default.project.json
├── README.md
├── ASSET_GUIDE.md
└── src/
    ├── ReplicatedStorage/Shared/
    │   └── Config.lua
    ├── ServerScriptService/Server/
    │   ├── Main.server.lua
    │   └── Services/
    │       ├── ArenaService.lua
    │       ├── DataService.lua
    │       ├── EnemyService.lua
    │       └── GameService.lua
    └── StarterPlayer/StarterPlayerScripts/Client/
        ├── Main.client.lua
        ├── UIController.lua
        └── EffectsController.lua
```

## Architektur und Sicherheit

Der Client stellt Eingaben, UI und rein visuelle Effekte bereit. Der Server prüft und entscheidet über:

- Kapazität und Aufnahme jedes Echos
- Einzahlungen und Teamfortschritt
- Puls-Cooldown und Reichweite
- Sprinttempo und Ausdauer
- Käufe, Preise und Profildaten
- Gegnerschaden, Belohnungen und Siege

Remote-Aufrufe allein können daher weder Flux erzeugen noch Upgrade-Kosten umgehen. Für ein öffentliches Release sollten trotzdem Roblox-Analytics, zusätzliche Rate-Limits und Playtests mit hoher Latenz ergänzt werden.

## Schnelltest-Checkliste

1. Play starten; Intro schließen.
2. 15 Sekunden Intermission abwarten.
3. Gelbe Echos berühren und am Anker mit E einzahlen.
4. Einen Phasenwechsel abwarten; Brückenfarbe und Atmosphäre müssen wechseln.
5. Schatten mit Q betäuben und Schaden/Respawn prüfen.
6. Nach einer Runde im Shop ein Upgrade kaufen.
7. Server neu starten und – bei aktiviertem API-Zugriff – gespeicherten Flux prüfen.

Viel Spaß beim Modellieren. Die Platzhalter sind absichtlich klar und minimal, damit deine visuelle Richtung das Spiel definiert.
