# Tofu Riddles — Content + KD-Gated Sub-Decks

**Date:** 2026-05-18
**Branch:** `feature/love-and-boxing-mvp`
**Scope:** First content pass for Tier 1 opponent Tofu, plus the underlying deck-tiering mechanic that all opponents will use.

## Summary

Add knockdown-gated sub-decks to the dialogue system, and author the first nine riddles for Tofu under a three-rung reasoning ladder (pattern match → category member → association). The new deck mechanic is generic and will carry forward to Minty and Sebastian, whose difficulty axis will be text length rather than image abstraction.

Content is authored with **text-only bodies and text-only answer cards** in this pass. The `DialoguePrompt` resource already supports both text and image content via `body_text` / `body_image` and `DialogueAnswer.text` / `DialogueAnswer.image` (see `riddle_box.gd:18`), so swapping each riddle to image form later is a per-`.tres` edit — no code change required.

## Mechanic: Knockdown-Gated Sub-Decks

### Concept

Each opponent's `Dialogue Deck` (CONTEXT.md) is split into **three sub-decks**, indexed by knockdown level:

| Sub-deck | Active when `_knockdowns.count()` equals |
|---|---|
| Tier 0 | 0 |
| Tier 1 | 1 |
| Tier 2 | 2 |

The active sub-deck is the *only* one drawn from at any given time. Scoring a knockdown promotes the player to the next sub-deck immediately on the next encounter.

### Round transitions

The CONTEXT.md rule that "Dialogue Deck resets at the start of each round" applies **per sub-deck**: every sub-deck reshuffles its full prompt pool at round start. The *active* sub-deck index mirrors `_knockdowns.count()` — `gameplay.gd` is the single source of truth and pushes the new value into the deck after every knockdown increment and after the round-end decrement at `gameplay.gd:143` (`_knockdowns.apply_round_end_decrement()`). The decrement therefore drops the active tier by one when entering Round 2, which is treated as a free forgiveness beat rather than a special case.

### Exhaustion behavior

When the active sub-deck empties between knockdowns, it refills in place from its source array and reshuffles. Other sub-decks are untouched. This matches the current `DialogueDeck._refill()` pattern but scoped to one tier.

No spillover: an exhausted Tier 0 sub-deck never pulls from Tier 1 prompts. The player will cycle the same three Tier 0 riddles until they score their first knockdown.

### Knockout

After a knockout (`_knockdowns.count() >= 3`), the match ends and the deck is no longer queried. There is no Tier 3.

### Code touch points

**`scripts/game/dialogue_deck.gd` — refactor:**
- Replace the single `_source` / `_remaining` pair with parallel arrays of size 3.
- `load_tier(tier: int, prompts: Array[DialoguePrompt])` populates one tier.
- `set_active_tier(tier: int)` selects which tier `draw()` reads from. Out-of-range tier values clamp to `[0, 2]` defensively.
- `draw()` refills only the active tier's `_remaining` when empty.
- `reset()` reshuffles all three tiers (used on round start).
- `seed_rng(...)` continues to seed the same shared RNG.

**`scripts/gameplay.gd` — wiring:**
- Replace `_build_placeholder_deck()` and its single `_deck.load_prompts(...)` call with a per-opponent deck-resource load (see *Authoring shape* below). Three `load_tier(...)` calls populate the deck on `_ready`.
- Call `_deck.set_active_tier(_knockdowns.count())` at two points: (a) after `_knockdowns.increment()` inside `_play_knockdown_sequence()`, (b) after `_knockdowns.apply_round_end_decrement()` in the round-end path.
- Replace any existing `_deck.reset()` round-start call with the new tiered reset.

**No changes to** `riddle_box.gd`, `dialogue_prompt.gd`, `dialogue_answer.gd`, or the encounter / gap state machine. The riddle UI already renders text or image content via existing `has_text_body()` / `has_image_body()` branches.

## Content Framework: Three-Rung Reasoning Ladder

| Tier | Cognitive task | Right | Neutral | Wrong |
|---|---|---|---|---|
| 0 | **Exact match.** Tofu shows X, wants X. | Same item as the body | Same broad family, wrong specific item | Unrelated |
| 1 | **Category member.** Tofu shows X, wants a *different* item from X's category. | Different whole member of the category | **Same substance** as the right answer, in a different form (e.g. juice of the fruit) | Different category entirely |
| 2 | **Association.** Tofu shows X, wants something X *reminds* him of (source, gift, kin). | The canonical association Tofu means | A different valid association Tofu does *not* mean this time (forces reading intent) | No association |

**Neutral vs. Wrong rule at Tier 1:** "Substance over action." Whether the player would *eat* or *drink* the answer doesn't matter to Tofu — what matters is whether the answer shares the **substance** of the right answer. Coconut milk and coconut share substance; pretzel and coconut do not. A glass of juice and a banana share substance; a hamburger and a banana do not.

## The Nine Tofu Riddles

Each riddle is authored as one `DialoguePrompt` resource with three `DialogueAnswer` children. The body text and answer text are shown in the riddle UI. Bullet rationales below are spec commentary only — they do not appear in-game.

### Tier 0 — Exact Match

**0.1 — Banana**
- **Body:** `BANANA`
- **Right:** `BANANA` — exact match
- **Neutral:** `APPLE` — also a fruit, wrong specific fruit
- **Wrong:** `MONEY` — gorilla doesn't care about money

**0.2 — Coconut**
- **Body:** `COCONUT`
- **Right:** `COCONUT`
- **Neutral:** `PINEAPPLE` — also a tropical fruit
- **Wrong:** `WRENCH` — tool, no relevance

**0.3 — Palm Tree**
- **Body:** `PALM TREE`
- **Right:** `PALM TREE`
- **Neutral:** `LEAFY BUSH` — also a plant, wrong specific plant
- **Wrong:** `SKYSCRAPER` — vertical, but the urban opposite of jungle

### Tier 1 — Category Member (substance > action)

**1.1 — Banana → fruit**
- **Body:** `BANANA`
- **Right:** `ORANGE` — different whole fruit
- **Neutral:** `GLASS OF JUICE` — fruit substance, liquid form
- **Wrong:** `HAMBURGER` — food but no fruit substance

**1.2 — Coconut → tropical fruit**
- **Body:** `COCONUT`
- **Right:** `PINEAPPLE` — different tropical fruit
- **Neutral:** `COCONUT MILK CARTON` — coconut substance, processed form
- **Wrong:** `PRETZEL` — processed grain, no fruit substance

**1.3 — Leafy Tree → tree**
- **Body:** `LEAFY TREE` (oak-style)
- **Right:** `PALM TREE` — different tree, same category
- **Neutral:** `WOODEN LOG` — tree substance, no longer a living tree
- **Wrong:** `STONE BRICK` — wrong material entirely

### Tier 2 — Association

**2.1 — Banana → where it grows**
- **Body:** `BANANA`
- **Right:** `PALM TREE` — the source. Tofu is thinking about *where bananas come from*.
- **Neutral:** `MONKEY` — also strongly banana-associated, but as the eater, not the source
- **Wrong:** `CAR` — no association

**2.2 — Sun → what sun gives him**
- **Body:** `SUN`
- **Right:** `RIPE MANGO` — sun ripens fruit; Tofu is thinking about *what the sun makes for him*
- **Neutral:** `SUNFLOWER` — also sun-associated, but the "things that follow the sun" angle
- **Wrong:** `SNOWFLAKE` — opposite of sun

**2.3 — Heart → who he loves** *(nods to game title)*
- **Body:** `HEART`
- **Right:** `ANOTHER GORILLA` — Tofu's family / troop
- **Neutral:** `ROSE` — also a love symbol, but the human-romantic flavor, not familial
- **Wrong:** `COIN` — no love association

## Authoring Shape

### Resource files

A new directory tree under `data/dialogue/`:

```
data/dialogue/
  tofu/
    deck.tres                     # DialogueDeckResource — points to the 9 prompts
    tier_0/
      banana.tres                 # DialoguePrompt
      coconut.tres
      palm_tree.tres
    tier_1/
      banana.tres
      coconut.tres
      tree.tres
    tier_2/
      banana.tres
      sun.tres
      heart.tres
```

Each `DialoguePrompt.tres` has `body_text` set (Tier 0/1/2 body strings above) and three `DialogueAnswer` sub-resources inline, one per outcome. Per-file naming uses the body's primary referent (so the two `banana.tres` files in tier_0 and tier_1 are distinct prompts that share a body).

### New resource type

**`scripts/game/dialogue_deck_resource.gd`:**

```gdscript
class_name DialogueDeckResource
extends Resource

@export var tier_0: Array[DialoguePrompt] = []
@export var tier_1: Array[DialoguePrompt] = []
@export var tier_2: Array[DialoguePrompt] = []
```

`tofu/deck.tres` is an instance of this resource with the nine prompts wired up via the inspector.

### Gameplay loading

`gameplay.gd._ready()` derives the deck path from `config.opponent_slug`:

```gdscript
var deck_path := "res://data/dialogue/%s/deck.tres" % config.opponent_slug
var deck_res := load(deck_path) as DialogueDeckResource
_deck.load_tier(0, deck_res.tier_0)
_deck.load_tier(1, deck_res.tier_1)
_deck.load_tier(2, deck_res.tier_2)
_deck.set_active_tier(_knockdowns.count())  # starts at 0
```

Minty and Sebastian don't have decks authored yet. Until they do, their `.tres` files either fall back to Tofu's deck or carry a minimal placeholder — *decision deferred to the implementation plan*; both opponents currently render with Tofu's sprites in any case per the M13 simplification.

## Art Assets (Deferred)

When art lands, each `DialoguePrompt.tres` swaps `body_text` → `body_image` and each `DialogueAnswer.tres` swaps `text` → `image`. The list below enumerates the unique icons needed. Bananas, coconuts, palm trees, and pineapples are reused across riddles; total unique icons: **27** (or 26 if `leafy_bush` and `leafy_tree` consolidate, noted below the table).

Suggested location: `assets/sprites/riddle_icons/<slug>.png`. Naming convention follows existing assets: lowercase, underscore-separated.

| Slug | Used in |
|---|---|
| `banana` | 0.1 body+right, 1.1 body, 2.1 body |
| `apple` | 0.1 neutral |
| `money` | 0.1 wrong |
| `coconut` | 0.2 body+right, 1.2 body |
| `pineapple` | 0.2 neutral, 1.2 right |
| `wrench` | 0.2 wrong |
| `palm_tree` | 0.3 body+right, 1.3 right, 2.1 right |
| `leafy_bush` | 0.3 neutral |
| `skyscraper` | 0.3 wrong |
| `orange` | 1.1 right |
| `glass_of_juice` | 1.1 neutral |
| `hamburger` | 1.1 wrong |
| `coconut_milk_carton` | 1.2 neutral |
| `pretzel` | 1.2 wrong |
| `leafy_tree` | 1.3 body |
| `wooden_log` | 1.3 neutral |
| `stone_brick` | 1.3 wrong |
| `monkey` | 2.1 neutral |
| `car` | 2.1 wrong |
| `sun` | 2.2 body |
| `ripe_mango` | 2.2 right |
| `sunflower` | 2.2 neutral |
| `snowflake` | 2.2 wrong |
| `heart` | 2.3 body |
| `another_gorilla` | 2.3 right |
| `rose` | 2.3 neutral |
| `coin` | 2.3 wrong |

`leafy_bush` (0.3 neutral) and `leafy_tree` (1.3 body) may be drawn as the same silhouette at different scales, at the artist's discretion.

## Testing

### Unit tests (GUT)

New tests in `tests/unit/test_dialogue_deck.gd` (extending the existing file if present, or new):
- `load_tier` populates only the named tier.
- `draw()` after `set_active_tier(N)` returns only prompts from tier N until exhausted, then refills tier N (not the others) and continues.
- `set_active_tier` clamps out-of-range values to `[0, 2]`.
- `reset()` refills all three tiers in one call.
- Seeded RNG produces a deterministic draw order within a tier (existing behavior preserved).

### Manual test plan

Once the new deck mechanic + Tofu deck resource are wired:
1. Start a Tofu match. Confirm the first riddle drawn is one of the three Tier 0 riddles.
2. Take a wrong / neutral / right answer through each Tier 0 riddle. After scoring a right answer + completing the attack phase at `x3` combo to trigger a knockdown, confirm the *next* encounter draws from Tier 1.
3. Repeat to confirm Tier 1 → Tier 2 transition on the second knockdown.
4. Empty a tier by cycling through its three prompts (taking wrong/neutral answers) without scoring a knockdown. Confirm the tier refills in place and the same three prompts repeat in a new shuffled order.
5. End Round 1 with 2 knockdowns scored. Confirm Round 2 begins in Tier 1 (post-decrement) and that all three tier pools have been reshuffled.
6. Land the third knockdown for a knockout; confirm the deck is no longer queried.

## Out of Scope

- **Minty and Sebastian content.** Their decks remain unauthored. Either a fallback to Tofu's deck or a minimal placeholder lands as part of the implementation plan.
- **Real art.** Riddles ship as text-bodied prompts in this pass; image swap is per-`.tres` once icons exist.
- **More than 3 prompts per tier.** The user has indicated the deck will grow over time; this pass is the seed set.
- **`gameplay.gd` size.** A previously-flagged `EncounterController` extraction (memory: "M11+ scope") is not part of this work. If the deck-wiring touch points grow uncomfortable inside `gameplay.gd`, the extraction can be revisited in a follow-up.
- **Per-tier announcement banners** ("Tofu is mad now!" on tier promotion). No visual signal of tier change beyond the riddle content itself.

## Open Questions

None at write time. All design decisions are locked.
