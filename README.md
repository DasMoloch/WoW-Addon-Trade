# Group Loot Helper - World of Warcraft Addon

Ein World of Warcraft Addon für automatische Loot-Ankündigung und Interessensverwaltung in Gruppen.

## 🎯 Funktionen

### Automatische Loot-Erkennung
- Erkennt automatisch handelbare Items, die gedroppt werden
- Funktioniert nur in aktiven Dungeon-/Raid-Instanzen
- Alle Gruppenmitglieder müssen das Addon installiert haben

### Kommunikation
- Nutzt `C_ChatInfo.SendAddonMessage()` für unsichtbare Nachrichten
- Eigener Prefix "GLH_LOOT" für interne Kommunikation
- Keine öffentlichen Chat-Nachrichten

### Item-Kompatibilität
- Prüft automatisch Rüstungstyp-Kompatibilität (Leder für Druide, etc.)
- Waffentyp-Validierung
- Schmuck (Ringe, Halsketten, Schmuckstücke) sind immer erlaubt
- Tooltip-Analyse für Handelbarkeit

### Benutzeroberfläche
- **Interesse-Fenster**: Erscheint am Cursor bei kompatiblen Items
  - Zeigt Item-Link mit Tooltip
  - ✅ Grüner Haken für Interesse
  - ❌ Rotes X zum Ablehnen
  - Schließt automatisch nach 15 Sekunden

- **Interessen-Übersicht**: GUI für Loot-Besitzer
  - Liste aller interessierten Spieler
  - Übersichtliche Darstellung: "Spieler wants: Item"
  - Scrollbare Liste für viele Einträge

## 🚀 Installation

1. Lade die Addon-Dateien in deinen WoW AddOns Ordner:
   ```
   World of Warcraft/_retail_/Interface/AddOns/GroupLootHelper/
   ```

2. Stelle sicher, dass folgende Dateien vorhanden sind:
   - `GroupLootHelper.toc`
   - `GroupLootHelper.lua`

3. Starte World of Warcraft neu oder lade die UI neu (`/reload`)

4. **WICHTIG**: Alle Gruppenmitglieder müssen das Addon installiert haben!

## 📋 Befehle

### Test-Befehle
- `/sendloot [itemID]` - Simuliert einen Item-Drop für Tests
- `/glh` oder `/glhinterest` - Öffnet die Interessen-Übersicht
- `/glh clear` - Löscht die aktuelle Interessenliste

### Beispiele
```
/sendloot 34334    # Testet mit "Thori'dal, the Stars' Fury"
/glh               # Zeigt Interessen-GUI
/glh clear         # Löscht alle Interessen
```

## 🔧 Technische Details

### Kompatibilität
- **WoW Version**: 11.2.0
- **Interface**: 110200
- **Saved Variables**: `GroupLootHelperDB`

### Instanz-Validierung
Das Addon ist nur aktiv in:
- Dungeons (`instanceType == "party"`)
- Raids (`instanceType == "raid"`)

### Klassen-Kompatibilität

#### Rüstungstypen
- **Cloth**: Alle Klassen
- **Leather**: Druide, Mönch, Schurke, Dämonenjäger
- **Mail**: Jäger, Schamane, Evoker
- **Plate**: Krieger, Paladin, Todesritter

#### Waffen
- Grundlegende Waffentyp-Validierung
- Schmuck ist immer für alle Klassen verfügbar

### Ereignis-Handler
- `ADDON_LOADED` - Initialisierung
- `CHAT_MSG_LOOT` - Loot-Erkennung
- `CHAT_MSG_ADDON` - Addon-Nachrichten
- `GROUP_ROSTER_UPDATE` - Gruppen-Status-Updates

## 🎮 Verwendung

### Für Loot-Empfänger
1. Tritt einer Gruppe bei und betrete eine Instanz
2. Wenn ein handelbare Item gedroppt wird, erscheint automatisch ein Fenster
3. Klicke ✅ für Interesse oder ❌ zum Ablehnen
4. Das Fenster schließt sich automatisch nach 15 Sekunden

### Für Loot-Besitzer
1. Wenn jemand Interesse äußert, erhältst du eine Chat-Nachricht
2. Verwende `/glh` um die Interessen-Übersicht zu öffnen
3. Die GUI zeigt alle interessierten Spieler und Items
4. Führe Trades manuell durch

## 🔍 Fehlerbehebung

### Addon lädt nicht
- Prüfe, ob die `.toc` Datei korrekt ist
- Stelle sicher, dass der Ordnername "GroupLootHelper" ist
- Verwende `/reload` nach Installation

### Keine Nachrichten empfangen
- Alle Gruppenmitglieder müssen das Addon haben
- Prüfe, ob du in einer gültigen Instanz bist
- Verwende `/sendloot [itemID]` zum Testen

### Items werden nicht erkannt
- Das Addon prüft nur handelbare Items
- Seelengebundene Items werden ignoriert
- Nur Items für deine Klasse werden angezeigt

## 📝 Changelog

### Version 1.0.0
- Initiale Veröffentlichung
- Automatische Loot-Erkennung
- Klassen-Kompatibilitätsprüfung
- Cursor-folgende UI
- Interessen-Verwaltung
- Test-Befehle

## 🤝 Mitwirken

Das Addon ist Open Source. Verbesserungen und Bugfixes sind willkommen!

### Geplante Features
- Erweiterte Waffentyp-Validierung
- Priorisierungssystem (Main Spec vs. Off Spec)
- Automatische Trade-Funktionen
- Verlauf/Log der Lootverteilung

## ⚠️ Hinweise

- **Alle Gruppenmitglieder müssen das Addon haben** - es gibt keine Fallbacks
- Das Addon funktioniert nur in Instanzen (Dungeons/Raids)
- Trades müssen weiterhin manuell durchgeführt werden
- Das Addon respektiert WoWs Handelsbeschränkungen