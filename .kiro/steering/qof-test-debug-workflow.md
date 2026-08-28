---
inclusion: always
---

# QOF Test- und Debugging-Workflow

Diese Regel gilt für alle QOF-Arbeitspakete im Battle-Pets-Repository.

## Freigabegesteuerte Umsetzung

- Es wird immer nur das aktuell freigegebene QOF-Paket bearbeitet.
- Das nächste QOF beginnt erst, wenn der Nutzer ausdrücklich `Weiter` schreibt.
- Vor einer Implementierung werden echte fachliche Unklarheiten gezielt gefragt; bereits entschiedene Regeln werden nicht erneut abgefragt.
- Bugs des aktuellen QOF werden vor dem nächsten QOF behoben und mit einem neuen Test-Build erneut bereitgestellt.

## Verbindliches Ergebnis jedes implementierten QOF

Nach jedem QOF mit Codeänderungen müssen folgende Ergebnisse geliefert werden:

1. Eine aus dem aktuellen Source-Stand erzeugte, echte binäre Roblox-Place-Datei:
   - Dateiname: `BATTLE_PETS_QOF-XX_TEST.rbxl`
   - bei Korrekturrunden: `BATTLE_PETS_QOF-XX_TEST_v2.rbxl`, `v3` usw.
   - die Datei muss die binäre Roblox-Signatur besitzen und vor der Übergabe geprüft werden.
2. Ein direkter GitHub-Download-Link zur Test-RBXL.
3. Eine kompakte Änderungsübersicht: Was ist neu, was wurde bewusst noch nicht umgesetzt?
4. Ein nummerierter Studio-Testplan mit konkreten Aktionen und erwarteten Ergebnissen.
5. Ein Regressionstest für bereits funktionierende Kernpfade, die vom QOF berührt werden.
6. Eine Liste bekannter Einschränkungen oder Punkte, die ohne Roblox Studio nicht lokal verifiziert werden konnten.
7. Gezielte Fragen zu beobachteten Bugs, Bediengefühl, Animation, Timing, Mobile/Desktop und noch offenen Produktentscheidungen.

Ein QOF darf nicht als vollständig spielgetestet bezeichnet werden, solange der Nutzer den Studio-Test nicht bestätigt hat. Es muss zwischen diesen Zuständen unterschieden werden:

- `Code-verifiziert`: statische Prüfungen, Generator, Daten-/Hierarchy-Prüfung und semantischer Review bestanden.
- `Studio-Test ausstehend`: RBXL wurde bereitgestellt, Nutzerfeedback fehlt.
- `Studio-bestätigt`: Nutzer hat die Testfälle ausgeführt und keine Blocker gemeldet.

## Qualitäts- und Performance-Anforderungen

Jede Implementierung muss professionell, sauber und flüssig sein:

- Server ist autoritativ für Preise, Chancen, Währung, Inventar, Pet-Eigentum und Resultate.
- Remotes erhalten Typ-, Bereichs-, Mengen-, Cooldown- und Burst-Prüfungen.
- Currency-/Inventartransaktionen sind all-or-nothing; keine Teilzustände oder Bonus-Refunds.
- Serverseitige Gameplay-Pfade enthalten keine unnötigen Animations-Waits.
- Animationen laufen clientseitig, blockieren die Steuerung nicht unnötig und besitzen Cleanup-/Cancellation-Logik.
- Event-Verbindungen und Heartbeat-Loops dürfen sich bei erneutem Öffnen nicht duplizieren.
- UI wird für Desktop und Mobile geprüft; zehnfache Hatch-Ergebnisse müssen lesbar bleiben.
- Partikel, Tweens und Sounds werden begrenzt, wiederverwendet oder zuverlässig zerstört.
- Bestehende Spielstände werden migriert und nie stillschweigend verworfen.
- `upgradeTree.lua` und Vide bleiben unverändert, solange der Nutzer keine ausdrückliche Ausnahme freigibt.
- Source of truth bleibt `src/`; generierte `.rbxlx`/`.rbxl` müssen zum Source-Stand passen.

## Prüfungen vor jedem Test-Build

Soweit im Sandbox-Umfeld möglich:

1. Relevante Dateien erneut lesen und Erfolgskriterien gegen das QOF prüfen.
2. JSON/XML/Python-Syntax und vorhandene Luau-/Selene-Prüfungen ausführen.
3. `git diff --check` für selbst geschriebene Dateien ausführen.
4. `BATTLE_PETS.rbxlx` neu generieren.
5. Erwartete Services, Controller, Remotes, Shared-Module und Sources im Place prüfen.
6. Binäre Test-RBXL aus dem geprüften RBXLX erzeugen.
7. Dateigröße und `<roblox!`-Signatur prüfen.
8. Semantischen Review für Sicherheits-, Migrations- und Laufzeitfehler durchführen.
9. Nur Produktdateien committen; temporäre Converter und Downloads entfernen.
10. Auf einen QOF-spezifischen Branch/Commit pushen und Download-Link verifizieren.

## Bug-Feedback und Debugging

Nach Übergabe der Test-RBXL wird der Nutzer gebeten, Bugs möglichst mit folgendem Format zu melden:

```text
QOF/Build:
Gerät: PC / Mobile / Tablet
Aktion:
Erwartet:
Tatsächlich:
Reproduzierbar: immer / manchmal / einmal
Studio Output/Fehler:
Screenshot oder Video:
```

Bei einem Bug:

1. Reproduktion und betroffenen Server-/Clientpfad eingrenzen.
2. Falls Informationen fehlen, nur konkrete Diagnosefragen stellen.
3. Ursache beheben, nicht nur das sichtbare Symptom verdecken.
4. Betroffene Regressionstests wiederholen.
5. Neue versionierte Test-RBXL bereitstellen.
6. Erst nach Nutzerbestätigung oder ausdrücklichem `Weiter` zum nächsten QOF wechseln.

## Abschlussformat nach einem QOF

Die Antwort nach einem implementierten QOF enthält in dieser Reihenfolge:

1. Status (`Code-verifiziert – Studio-Test ausstehend`)
2. Download-Link zur RBXL
3. Änderungen
4. Testschritte und erwartete Ergebnisse
5. Bekannte Grenzen
6. Konkrete Feedback-/Debugging-Fragen
7. Hinweis: `Weiter` startet erst das nächste QOF
