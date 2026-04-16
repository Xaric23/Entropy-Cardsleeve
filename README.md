# Entropy Evolution

A Balatro mod that adds the **Entropy Sleeve** - discarded cards transform with evolving modifiers, and shop Jokers gain random editions.

## Features

### Core Mechanics
- **Evolving Modifiers**: Discarded cards gain random Editions, Seals, and Enhancements
- **Modifier Inheritance**: New mutations inherit traits from previous ones (propagation system)
- **Joker Editions**: Shop Jokers automatically gain random editions
- **Hand Resonance**: Cards in your hand may spontaneously mutate

### New in v1.1.0

#### 🎯 Weighted Edition Pools
Editions now have rarity tiers:
| Edition | Weight | Rarity |
|---------|--------|--------|
| Foil | 40 | Common |
| Holo | 30 | Uncommon |
| Polychrome | 20 | Rare |
| Negative | 10 | Very Rare |

#### 🔥 Streak System
Consecutive successful mutations build a streak that:
- Increases mutation chances (up to +15% bonus)
- Boosts hand resonance probability
- Improves joker edition inheritance

#### ⚡ Combo System
Synergistic modifier combinations trigger bonus effects:
- **Polychrome + Gold Seal**: 1.5x bonus
- **Negative + Glass Enhancement**: 1.3x bonus
- **Holo + Red Seal**: 1.2x bonus
- **Purple Seal + Lucky Enhancement**: 1.4x bonus

#### 📊 Evolution Stats
Track your mutation history:
- Total mutations applied
- Current/best streak
- Combos triggered

#### 🐛 Debug Mode
Enable `CONFIG.debug_mode = true` in the Lua file for detailed logging.

## Configuration

All parameters are tunable in the `CONFIG` table at the top of `EntropyEvolution.lua`:

```lua
CONFIG = {
    -- Core chances
    edition_override_chance = 0.2,
    seal_override_chance = 0.3,
    enhancement_override_chance = 0.4,
    
    -- Mutation settings
    joker_mutation_base_chance = 0.15,
    joker_mutation_memory_scaling = 0.004,
    joker_mutation_max_bonus = 0.2,
    
    -- Streak system
    streak_bonus_per_level = 0.02,
    streak_max_bonus = 0.15,
    
    -- Debug mode
    debug_mode = false,
}
```

## Installation

### Requirements
- [Steamodded](https://github.com/Steamodded/smods) >= 1.0.0~ALPHA-1424a
- [CardSleeves](https://github.com/larswijn/CardSleeves) >= 1.0.0
- [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) (optional)

### Steps
1. Download or clone this repository
2. Copy the `EntropyEvolution` folder to your Balatro mods directory:
   - Windows: `%AppData%\Balatro\Mods\`
   - Linux: `~/.local/share/Balatro/Mods/`
   - macOS: `~/Library/Application Support/Balatro/Mods/`
3. Launch Balatro

## Blacklisted Modifiers

- **Stone Enhancement** (`m_stone`): Excluded to prevent negative synergies
- **Dominated Jokers**: Perkeo, Caino, Triboulet, Yorick, Chicot (excluded from edition changes)

## Tests

Run the test suite with:

```bash
lua tests/run_tests.lua
```

## Changelog

### v1.1.0
- Added weighted edition pools with rarity tiers
- Added streak system for consecutive mutations
- Added combo system for synergistic modifiers
- Added evolution stats tracking
- Added debug mode toggle
- Added configurable parameters
- Improved code organization and maintainability

### v1.0.1
- Added Lovely Injector compatibility
- Fixed crash on invalid editions

### v1.0.0
- Initial release

## License

MIT License - See LICENSE file for details.

## Credits

- **Author**: Xaric
- Built for [Balatro](https://www.playbalatro.com/)
