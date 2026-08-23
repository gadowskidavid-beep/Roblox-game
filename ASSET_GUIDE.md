# Eigene Assets für SHIFT//BREAK

Die Spiellogik erkennt deine Modelle über feste Namen und **CollectionService-Tags**. Dadurch bleiben deine Originalmodelle in `ServerStorage` unangetastet; für jede Runde wird eine Laufzeitkopie nach `Workspace/ShiftBreakRuntime` erzeugt.

## 1. Eigene Lobby

Erstelle in `ServerStorage` ein Model oder einen Folder namens:

```text
CustomLobby
```

Füge mindestens einen unsichtbaren oder sichtbaren `BasePart` als Spawnpunkt ein und gib ihm im Tag Editor den Tag:

```text
SB_LobbySpawn
```

Der Spieler erscheint vier Studs oberhalb dieses Parts. Ohne gültigen Spawn-Tag wird automatisch die prozedurale Lobby verwendet.

## 2. Eigene Arena

Erstelle in `ServerStorage` ein Model oder einen Folder namens:

```text
CustomArena
```

Die Arena ist gültig, wenn sie mindestens folgende getaggte `BasePart`-Objekte enthält:

| Tag | Minimum | Funktion |
|---|---:|---|
| `SB_PlayerSpawn` | 1 | Spawnpositionen der Spieler |
| `SB_EchoSpawn` | 1, empfohlen 20+ | mögliche Positionen der Sammelobjekte |
| `SB_EnemySpawn` | 1, empfohlen 6+ | mögliche Startpositionen der Schatten |
| `SB_DepositAnchor` | genau 1 | Anker; der ProximityPrompt wird automatisch angefügt |

Optionale Phasentags:

| Tag | Wirkung |
|---|---|
| `SB_StableOnly` | Part ist nur in der stabilen Dimension sichtbar, berührbar und kollidierbar |
| `SB_FracturedOnly` | Part ist nur in der gebrochenen Dimension sichtbar, berührbar und kollidierbar |

### Empfohlener Aufbau

```text
ServerStorage
└── CustomArena
    ├── Geometry
    │   ├── StaticArchitecture
    │   ├── StableBridgeParts      [SB_StableOnly je BasePart]
    │   └── FracturedBridgeParts   [SB_FracturedOnly je BasePart]
    ├── Markers
    │   ├── PlayerSpawns           [SB_PlayerSpawn]
    │   ├── EchoSpawns             [SB_EchoSpawn]
    │   └── EnemySpawns            [SB_EnemySpawn]
    └── AnchorHitbox                [SB_DepositAnchor]
```

Marker sollten `Anchored = true`, `Transparency = 1`, `CanCollide = false`, `CanTouch = false` und `CanQuery = false` verwenden. Der Code liest nur ihre Position.

**Wichtig:** Tags für Phasenwechsel gehören auf jeden betroffenen `BasePart`, nicht nur auf dessen Model. Ursprüngliche Transparenz sowie `CanCollide`/`CanTouch` werden gespeichert und in der richtigen Phase wiederhergestellt.

Die Absturzhöhe liegt automatisch 60 Studs unter dem getaggten Anker. Baue daher keine vorgesehenen Laufwege tiefer als diese Ebene.

## 3. Eigenes Echo-Modell

Erstelle optional:

```text
ServerStorage
└── ShiftBreakAssets
    └── Echo
```

`Echo` darf ein einzelner `BasePart` oder ein `Model` sein. Bei einem Model benötigt es:

1. bevorzugt einen `BasePart` namens `Hitbox`, oder
2. eine gesetzte `PrimaryPart`, oder
3. mindestens irgendeinen `BasePart` als Fallback.

Der gewählte Part erkennt Berührungen. Alle Teile des Echo-Modells werden zur Laufzeit verankert und nicht kollidierbar gemacht. Position, Highlight und optional fehlendes Licht übernimmt das Spiel. Eigene Partikel und Lichter im Template bleiben erhalten.

## 4. Eigenes Schatten-Modell

Erstelle optional:

```text
ServerStorage
└── ShiftBreakAssets
    └── Shade
```

`Shade` darf ein `Model` oder einzelner `BasePart` sein. Ein Model braucht bevorzugt:

1. eine gesetzte `PrimaryPart`, oder
2. einen `BasePart` namens `Core`, oder
3. mindestens irgendeinen `BasePart` als Fallback.

Alle Parts werden serverseitig verankert und durch `Model:PivotTo()` bewegt. Ein `Humanoid`, eigene Kollisionslogik oder KI-Scripts sind nicht nötig. Die lokale Vorderseite sollte in Roblox-Richtung **−Z** zeigen, damit das Modell sein Ziel ansieht.

Die Farbe des Core-Parts wird während einer Betäubung kurz cyan und danach auf seine ursprüngliche Farbe zurückgesetzt. Wenn das bei deinem Material nicht erwünscht ist, nutze einen kleinen unsichtbaren `Core` als PrimaryPart und baue die sichtbare Geometrie darum.

## 5. Anker gestalten

`SB_DepositAnchor` muss auf einem `BasePart` liegen, weil der Server dort einen `ProximityPrompt` erstellt. Zwei gute Varianten:

- Tag direkt auf dem sichtbaren Kern-Part.
- Unsichtbaren `AnchorHitbox` taggen und das sichtbare Modell darum bauen.

Der getaggte Part wechselt als unmittelbares Feedback seine Farbe. Eigene Lichter, Partikel und Animationen dürfen als Kinder des Parts oder benachbarte Objekte existieren.

## 6. Regeln für robuste Modelle

- Arena- und Lobby-Geometrie sowie optionale Templates müssen `Archivable = true` besitzen.
- Arena- und Lobby-Geometrie sollte vor dem Klonen bereits `Anchored = true` sein.
- Verwende eindeutige Tags; mehr als ein `SB_DepositAnchor` führt dazu, dass der zuletzt gefundene genutzt wird.
- Lege in `CustomArena` keine eigenen Ordner namens `Echoes` oder `Shades` an; diese erzeugt das Spiel.
- Packe keine notwendigen Daten ausschließlich in LocalScripts innerhalb von `ServerStorage`; sie laufen dort nicht.
- Teste beide Phasen und achte darauf, dass Spieler nicht durch einen Phasenwechsel dauerhaft eingeschlossen werden.
- Plane sichere Standflächen an mehreren Spieler-Spawns ein.
- Verteile Echo- und Gegner-Marker über alle tatsächlich erreichbaren Bereiche.

## 7. Fehlerdiagnose

In der Roblox-Output-Konsole erscheinen verständliche Warnungen:

- fehlende Arena-Tags → prozedurale Arena wird geladen
- fehlender Lobby-Spawn → prozedurale Lobby wird geladen
- Echo ohne Hitbox/BasePart → prozedurales Echo wird verwendet
- Shade ohne PrimaryPart/Core → prozeduraler Schatten wird verwendet

So bleibt das Spiel auch während des Modellierens jederzeit startbar.
