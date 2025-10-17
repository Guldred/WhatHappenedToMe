# What Happened To Me - WoW 1.12.1 Addon

A combat log tracker addon for World of Warcraft Classic (version 1.12.1) that shows you what happened before you died. Perfect for analyzing dungeon and raid deaths!

## Features

- **Automatic Combat Logging**: Silently tracks all combat events affecting your character
- **Death Recap**: Automatically displays the combat log window when you die
- **Separate Window**: Independent of chat systems, works with any chat addon
- **Circular Buffer**: Stores the last 50 combat events to prevent memory issues
- **Color-Coded Events**: 
  - Red for damage and spells
  - Green for healing
  - Light blue for misses/dodges/parries
  - Orange for buff/debuff changes
- **Timestamps**: Shows relative time for each event (e.g., "5s ago")
- **Health Tracking**: Displays your health percentage at the time of each event
- **Movable Window**: Drag the window anywhere on screen

## Installation

1. Download or clone this repository
2. Copy the `WhatHappenedToMe` folder to your WoW installation directory:
   ```
   World of Warcraft/Interface/AddOns/
   ```
3. Restart WoW or reload UI (`/reload`)
4. The addon will confirm loading in your chat window

## Usage

### Automatic Operation
The addon automatically:
- Tracks all combat events affecting you
- Shows the combat log window 1 second after you die
- Maintains a rolling buffer of the last 50 events

### Manual Commands

| Command | Description |
|---------|-------------|
| `/whtm` or `/whtm show` | Show the combat log window |
| `/whtm hide` | Hide the combat log window |
| `/whtm toggle` | Toggle window visibility |
| `/whtm clear` | Clear all recorded events |
| `/whtm help` | Show command list |
| `/whathappened` | Alternative command (same as `/whtm`) |

### Window Controls
- **Drag**: Click and drag the window title area to move it
- **Clear Log**: Button to clear all recorded events
- **Refresh**: Manually refresh the display
- **Close**: Close the window (also works with X button)

## What Gets Tracked

The addon monitors these combat events:
- Melee hits and misses from creatures
- Melee hits and misses from enemy players
- Spell damage from creatures and players
- Damage-over-time effects (DoTs)
- Healing (if enabled in settings)
- Buff and debuff changes (if enabled)
- Reflection damage (Thorns, etc.)

## Configuration

Settings are stored in `WhatHappenedToMeDB` (SavedVariables).

Current defaults:
```lua
bufferSize = 50          -- Number of events to store
showOnDeath = true       -- Auto-show window on death
trackHealing = true      -- Track healing events
trackBuffs = true        -- Track buff/debuff changes
autoShowDelay = 1.0      -- Delay (seconds) before showing on death
```

## Technical Details

- **Lua Version**: 5.0 (WoW 1.12.1 compatible)
- **Interface Version**: 11200
- **Memory**: Minimal - circular buffer prevents growth
- **Performance**: Optimized for raid environments

## Files

- `WhatHappenedToMe.toc` - Addon metadata
- `CircularBuffer.lua` - Circular buffer data structure
- `WhatHappenedToMe.lua` - Core logic and event handling
- `WhatHappenedToMe.xml` - UI frame definitions

## Known Limitations

- Does not track damage to other players (by design)
- Combat log messages are parsed as strings (no structured API in 1.12.1)

## Future Enhancements

Potential features for future versions:
- Configuration UI panel
- Export log to chat for party members
- Statistics (total damage taken, top sources)
- Filter options (damage only, etc.)
- Minimap button
- Custom buffer size configuration

## Support

For issues or suggestions, please refer to the project repository.

## License

This addon is provided as-is for World of Warcraft 1.12.1 (Vanilla/Classic).

---

**Version**: 1.0.0  
**Author**: Christian Malak  
**Compatible**: WoW 1.12.1 (Vanilla/Classic)