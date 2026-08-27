# QOF-07 – Serverautoritäre Tree-Entitlements

**Status:** Code-verifiziert – Studio-Test ausstehend
**Testbuild:** `BATTLE_PETS_QOF-07_TEST.rbxl`
**Schema:** V6 bleibt unverändert

## Ziel

QOF-07 macht den freigegebenen Teil des bestehenden Upgrade Trees gameplay-wirksam. Kauf, Währung, Voraussetzungen und Effekte werden ausschließlich auf dem Server aus kanonischer Konfiguration und der persistenten Boolean-Map `upgradeTreePurchases` bestimmt.

Aktiviert werden:

- Egg Quality I/II
- je drei direkte Gold-, Rainbow- und Shiny-Chance-Stufen
- kanonische Coin- und Diamond-Käufe
- serverseitige Entitlement-Abfrage für den Single-Egg-Hatch

Multi-Open, Core Upgrades und alle übrigen Legacy-Nodes bleiben dormant.

## Save-kompatible IDs und Grandfathering

Vorhandene IDs werden nicht umbenannt. Bereits gekaufte vollständige Ketten erhalten ihre neue Wirkung automatisch und werden nicht erneut berechnet oder belastet.

| Persistente ID | QOF-07-Wirkung | Kosten |
|---|---|---:|
| `Eggs I` | Egg Quality ×1,25 | 5.000 Coins |
| `Eggs II` | Egg Quality ×1,60 gesamt | 50.000 Coins |
| `epicLuck1` | Gold Chance ×1,25 | 500 Diamonds |
| `epicLuck2` | Gold Chance ×1,50 gesamt | 1.500 Diamonds |
| `epicLuck3` | Gold Chance ×2 gesamt | 5.000 Diamonds |
| `legendLuck1` | Rainbow Chance ×1,25 | 1.500 Diamonds |
| `legendLuck2` | Rainbow Chance ×1,50 gesamt | 5.000 Diamonds |
| `legendLuck3` | Rainbow Chance ×2 gesamt | 15.000 Diamonds |
| `rerollLuck1` | Shiny Chance ×1,25 | 5.000 Diamonds |
| `rerollLuck2` | Shiny Chance ×1,50 gesamt | 15.000 Diamonds |
| `rerollLuck3` | Shiny Chance ×2 gesamt | 50.000 Diamonds |

Stufen kumulieren nicht miteinander. Es gilt die höchste vollständig und zusammenhängend gekaufte Stufe. Übersprungene oder unbekannte IDs erzeugen keinen Effekt.

## Hatch-Formeln

Allgemeines Luck bleibt die multiplikative Kombination aus `LuckyEggs`, `BetterLuck` und dem bestehenden Shop-/Potion-Luck.

```text
speciesMultiplier = min(generalLuck × highestEggQuality, 10)
goldChance = min(1% × generalLuck × highestGoldStage, 5%)
rainbowChance = min(0.1% × generalLuck × highestRainbowStage, 0.5%)
shinyChance = min(0.01% × generalLuck × highestShinyStage, 0.1%)
```

Egg Quality verändert ausschließlich die Gewichte nicht-gewöhnlicher Spezies. Es verändert keine Variantenchance. Jede direkte Variantenstufe beeinflusst nur ihren eigenen Roll-Anteil. Gold und Rainbow bleiben kategorisch exklusiv; Shiny bleibt unabhängig und mit jeder Basisvariante kombinierbar.

## Kauf- und Currency-Sicherheit

- Der Client sendet nur eine Upgrade-ID.
- Der Server bestimmt Verfügbarkeit, Currency, Preis und Voraussetzungen.
- Coins und Diamonds laufen über dieselbe validierte Spend-API.
- Es werden nur positive, endliche Ganzzahlbeträge und bekannte Währungen akzeptiert.
- Ein per-player Lock verhindert parallele Tree-Käufe.
- Debit und Entitlement sind rollback-gesichert; Fehler nach dem Debit stellen Currency und vorherigen Kaufstatus wieder her.
- Tree-State liefert Coins, Diamonds, Purchased-Map, verfügbare IDs und eine read-only Entitlement-Zusammenfassung.
- Reward-Boni gelten nur für verdiente Währung. Hatch-Refunds nutzen eine rohe 1:1-Gutschrift und können nicht durch Quest-/Mastery-Boni vergrößert werden.

## Client und Mobile

Der bestehende Vide-Renderer und `upgradeTree.lua` bleiben unverändert. Der Adapter ergänzt:

- synchronen Coin-/Diamond-State
- Diamond-Anzeige mit Roblox' integrierter Gem-Textur ([Roblox Developer Forum](https://devforum.roblox.com/t/diamond-badge-with-roblox-plus/4608580))
- sichtbare Erfolgs-, Ablehnungs- und Transportfehler
- globalen In-flight-Schutz gegen Doppelklicks
- einen 72×72-Pixel-Tree-Button für Touch und Desktop
- cleanup-sicheres Remounting beim Button-Öffnen; Q bleibt als Desktop-Shortcut erhalten

Content was rephrased for compliance with licensing restrictions.

Nicht verfügbare Nodes sind als `Coming Soon` beziehungsweise `Later` beschriftet. Ein Tap zeigt lokales Feedback und sendet keinen Kaufrequest.

## Bewusst verschoben

- `Eggs III–V`: Multi-Open 2/5/10 und atomarer Batch-Pfad in QOF-08
- Batch-DTO, Ergebnis-Grid, Auto-Hatch-Batch und Prompt-Router in QOF-08/09
- Speed, Storage, Magnet, Double Luck und Pet Equip Slots bis zu ihrem Besitzer-QOF
- Potions, Maschinen, Enchanting und sechs kombinierte Pet-Dex-Kategorien bis zu ihren späteren QOFs
- keine Änderung an `upgradeTree.lua` oder Vide

Bereits persistierte spätere oder Legacy-IDs bleiben erhalten, sind aber weder neu kaufbar noch gameplay-wirksam.

## Rollout

QOF-06- und ältere Server sollten vor Produktion vollständig gedraint werden. Andernfalls können Tree-Käufe und Hatch-Wirkungen während des Rollouts serverabhängig sein. Es gibt keinen Schema-Bump; die vorhandene V6-Map bleibt die Persistenzautorität.

## Verifikation

- 84 Pure-/Regressionstests für Balance, Currency, Tree-Käufe, Rollback, Entitlements, Hatch-Math, PetService, EggService, Schema und Presentation
- Fault-Injection direkt nach Debit und nach Entitlement-Mutation
- Coin-/Diamond-Kosten, Voraussetzungen, Doppelkauf, fehlende Mittel und blockierte Legacy-/Multi-Open-Nodes
- Grandfathering vollständiger Ketten sowie Schutz gegen unbekannte und übersprungene IDs
- Luau-Compile der geänderten Runtime- und Testdateien
- Python-/JSON-/XML-Prüfung und Generator-/Place-Source-Parität
- erwartete Place-Hierarchie: 61 ModuleScripts, 1 Script, 1 LocalScript
- binäre RBXL-Signatur- und Source-Roundtrip-Prüfung
- semantischer Review, `git diff --check`, unverändertes `upgradeTree.lua` und unverändertes Vide-Paket

Roblox-Studio-Laufzeit-, Touch-, Safe-Area-, visuelle Tree- und statistische Odds-Tests bleiben bis zum Nutzerfeedback ausstehend.
