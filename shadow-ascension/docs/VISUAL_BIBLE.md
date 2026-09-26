# ShadowAscension — Visual Bible

> **Status: authoritative since M13.1.** This is the project's official visual reference. An
> asset, a material, a VFX or a lighting setup that contradicts it is wrong until this document is
> changed. It changes by decision, recorded in the *Decision log* (§20), never by drift.
>
> It is written to be handed as-is to an artist, a Blender session, a 3D generator, an AI tool or a
> technical artist. Numbers are targets unless marked as measured. Where a value is measured from
> the project, it says so.

Companion documents: `GAME_DESIGN.md` (*Art direction* holds the high-level identity),
`ARCHITECTURE.md` (*Model and animation decoupling*, *Content pipeline*), `ROADMAP.md` (*M13*).

---

## 1. Vision

**ShadowAscension looks like a contemporary city with something ancient bleeding through it.**
The real world is clean, cold and rectilinear; the dungeons behind the Gates are old, wrong and
impossible; the power the player takes from them — the shadows — is darkness with light running
through its seams.

The direction, in one line:

> **Dark urban fantasy + supernatural military/arcane + clean action-RPG readability,
> rendered as stylized realism.**

- **Dark urban fantasy** — a modern world (concrete, glass, steel, streetlight) meeting the
  supernatural. Not medieval by default: medieval forms appear only as *the dungeon's* forms, as
  something foreign to the present.
- **Supernatural military / arcane** — the player and the people of the hub are organised, equipped
  and disciplined: tactical cuts, structured gear, machined metal, with arcane technology built in
  (light seams, charged channels). Power is controlled, not wild.
- **Clean action-RPG readability** — every visual decision is subordinate to reading the fight:
  who is who, who is about to hit, where, and when.

**Stylized realism**: realistic materials and lighting (PBR, physically plausible values) on shapes
that are simplified and slightly exaggerated (bigger hands, feet and weapons; cleaner planes; fewer,
larger details). Realistic enough to be taken seriously; stylized enough to hold a strong identity,
keep asset cost down, avoid the uncanny valley and allow modular assets.

**Originality is a requirement, not a preference.** ShadowAscension is not Solo Leveling and does
not borrow from it or from any other franchise: no characters (Jin-Woo, Igris, Beru or anyone
else), no recognisable outfits, symbols, weapons, creatures, logos, dungeons or signature effects.
Genre conventions (dark fantasy, portals, summoned allies, glowing energy) are shared vocabulary;
specific designs are not. §18 sets the rules that enforce this.

---

## 2. Visual Pillars

Six pillars. When two rules collide, the lower number wins.

| # | Pillar | Rule it produces |
| --- | --- | --- |
| 1 | **Combat readability first** | No visual may hide a telegraph, the perceived reach of a hitbox, the locked target, the dodge window or a boss attack. An effect that hides one of these is a bug, not a flourish. |
| 2 | **Strong silhouettes** | The player, each enemy archetype and the boss are identifiable from a black silhouette alone, at gameplay distance (§16.3: ~60 px tall at 1080p). |
| 3 | **Dark but readable** | Scenes are low-key; characters are never lost in them. The floor a fight happens on is never darker than the characters standing on it; no pure black where the player walks. |
| 4 | **Controlled supernatural colour** | Saturated colour and emission are signals with owners (§5). Environments are desaturated; supernatural colour appears only where it means something. |
| 5 | **Material contrast** | Metal, fabric, leather, skin, stone, energy and shadow are distinguishable by roughness, metalness and value — never all at the same roughness. |
| 6 | **Grounded proportions, supernatural exaggeration** | Humans (the player, the hub) are credible and slightly heroic; creatures, elites and bosses push proportions further. The more supernatural, the more exaggerated. |

---

## 3. Mood

**Dark, elegant, menacing, modern, supernatural.**

| It is | It is not |
| --- | --- |
| Low-key lighting with deliberate pools of light | Pitch black, or flat and evenly lit |
| Menace from scale, stillness and wrong geometry | Gore, body horror, jump-scare horror |
| Elegant: clean lines, restrained ornament | Cartoon: rubbery shapes, candy colours, outlines |
| Modern: tactical cloth, concrete, glass, streetlight | Generic medieval everywhere |
| Supernatural light used sparingly, so it matters | Neon everywhere, rainbow effects |
| Stylized realism: PBR materials, simplified shapes | Photorealism: scanned faces, pore-level detail |

The emotional arc of a run is visible: **the hub is safe and cold**, **the Gate is the one
impossible thing in it**, **the dungeon is the Gate's world**, and **the shadows are the player
bringing that world back under control.**

---

## 4. Shape Language

A vocabulary, not a formula. Each family has a **dominant shape** that must survive in the black
silhouette; details may use other shapes.

| Family | Dominant shapes | Reads as |
| --- | --- | --- |
| **Player** | Vertical lines, tapering triangles pointing forward/up, one strong diagonal (§7) | Precise, agile, controlled, rising |
| **Shadows** | The source's silhouette, with its extremities broken into sharp fragments and flowing wisps | The same creature, reclaimed |
| **Melee** | Forward-leaning triangle, one dominant weapon arm | Frontal pressure |
| **Ranged** | Thin vertical line with one extended element (arm/device) | Distance, fragility up close |
| **Tank** | Square / wide rectangle, low centre of mass | Mass, an obstacle |
| **Assassin** | Thin diagonals, sharp points trailing backwards | Speed, a lunge |
| **Support** | Circles and concentric rings, centred on the body axis | Protection, focus, helping others |
| **Boss** | Its own silhouette; one oversized attack part | Unique presence, legible danger |
| **Hub** | Right angles, rectilinear blocks, clean planes | Order, safety, the present |
| **Dungeon** | Non-orthogonal angles, repeated arches, monoliths, broken symmetry | Ancient, distorted, impossible |
| **Gate** | A perfect ring | Geometry that does not belong |

Hostile creatures in general are **irregular and asymmetric** (grown, forged, broken). The player's
side is **clean and machined** (cut, fitted, symmetric where it is equipment). That contrast alone
separates the two sides before colour is involved.

---

## 5. Color Language

### 5.1 The palette

Fourteen colours. Each has an owner and a use; nothing else is a palette colour. Where the project
already used a value for that role, the palette **adopts the value** (marked *in data*), so the
placeholders already speak the language and no data changes.

| Group | Name | HEX | Intended use |
| --- | --- | --- | --- |
| Neutral | **Void** | `#0B0C10` | Deepest value: shadow bodies' darkest areas, unlit dungeon depths. The darkest colour in the game — never pure `#000000`. |
| Neutral | **Graphite** | `#1C1E26` | Primary dark material: the player's coated armour, enemy base materials, dark stone. |
| Neutral | **Slate** | `#333642` | Secondary surfaces: cloth, straps, mid stone, hub floors (the hub floor placeholder is already this value). |
| Neutral | **Concrete** | `#6E717C` | Light neutral: hub concrete, worn steel, dungeon floors in light pools. |
| Neutral | **Ash** | `#C9C6BD` | Highlights: edge wear, bone, pale stone, neutral in-world text. |
| Player | **Arc Cyan** | `#46C8E6` | The player's arcane accent: the Arc Line (§7), the weapon's charged channel, player-side feedback. Emissive. |
| Player | **Signal Steel** | `#4A6A8F` | The player's secondary colour: cloth and trim on the player's side (hub uniforms included). Never emissive. |
| Shadow | **Umbral Violet** | `#8C59F2` | Shadow emission: rim, Seams, Core, aura; the Gate's light. *In data*: `ShadowData.accent_color`. |
| Shadow | **Abyss Indigo** | `#17132B` | Shadow base colour: near-black cold violet over which the Seams glow; the Gate's membrane. |
| Hostile | **Warning Yellow** | `#FFD933` | Hostile telegraph — *when*: the attacking part ramps to it during the wind-up. *In data*: `EnemyData.telegraph_color`. |
| Hostile | **Danger Red** | `#FF4026` | Hostile danger — *where* and *now*: AoE ground markers, the active-frame flash, hostile eye points, damage taken. *In data*: `EnemyData.active_color`. |
| Support | **Vital Green** | `#4DFF73` | Healing, by anyone: the support's heal, restoration effects. *In data*: `EnemySupportData.heal_color`. |
| Elite | **Elite Gold** | `#F2B826` | Elite overlay: gold trim, crest, the ELITE tag. Never on a boss. *In data*: `EnemyHealthBar3D.ELITE_FRAME_COLOR`. |
| Boss | **Boss Crimson** | `#B81F29` | Boss identity: its signature attack part, its Core, phase 2 and enrage. Never on an elite. *In data*: phase 2 `body_color` of `dungeon_boss_data.tres`. |

**Derived tints are not new colours.** A lighter or darker step of a palette colour, or a mix of
two neighbours in the same group, is allowed for gradients and VFX ramps. Example: the support's
buff (`#FF8C26`, `EnemySupportData.buff_color`) sits between Warning Yellow and Danger Red — hostile
empowerment, inside the hostile group. The hub's Gate light (`#9E6BFF`) is a lighter Umbral Violet.

**Lighting colours are not palette colours.** Light temperatures are set per environment (§13).

### 5.2 The one rule: warm is hostile, cold is ours

- **Cold emission (cyan, violet) belongs to the player's side**: the player (Arc Cyan) and the
  shadows (Umbral Violet), and the Gate they come through.
- **Warm emission (yellow, orange, red, gold, crimson) belongs to hostiles**: telegraphs, danger,
  hostile eyes, elites, bosses.
- **Green is restoration**, whoever does it (a hostile support healing an ally is still green —
  the player learns to kill the healer).
- A hostile never carries cold emission. An ally never carries warm emission.

### 5.3 Colour hierarchy

From quietest to loudest. A level may not borrow the loudness of a level above it.

| Level | Saturation | Emission | Notes |
| --- | --- | --- | --- |
| Environment | ≤ 20% on surfaces | Navigation and interactables only (§13) | Recedes. Carries light, not colour. |
| Normal enemy | ≤ 35% | Small hostile points (eyes, cracks) at energy ≤ 1.0 | Read by silhouette and material, not hue. |
| Elite | Normal enemy + gold accents | Steady gold, low (§10) | Accent area ≤ 15% of the silhouette. |
| Shadow | The lowest value in the scene | Umbral Violet rim, Seams, Core | Darkest bodies, self-lit edges. |
| Boss | Crimson dominant accent | The largest emissive area allowed (its Core) | One focal accent, not a lit-up body. |
| Player | Neutral dark base | The Arc Line: the most recognisable accent on screen | Always findable in a crowd. |
| Combat feedback | Full | The only things allowed to pulse or flash | Telegraphs, hits, heals. |

### 5.4 Combat colours

Future VFX pick from this table, never from taste.

| Signal | Colour | Non-colour carriers (mandatory, §5.5) |
| --- | --- | --- |
| Hostile telegraph — when | Warning Yellow ramp on the attacking part | Anticipation pose; brightness ramp; wind-up sound (M14) |
| Hostile danger — where (AoE only) | Danger Red ground outline | The outline is the hitbox footprint; it fills as impact approaches |
| Hostile danger — now | Danger Red flash on the attacking part | The strike motion; impact |
| Damage taken | Danger Red | Hit reaction; hit stop; camera shake (M11.9) |
| Heal | Vital Green | Rising motion; a ring on the healed body; the health bar growing |
| Hostile empowerment (buff) | Hostile tint `#FF8C26` | A marker on the buffed body |
| Critical hit | Warning Yellow family (`PlayerCombatFeedbackData.critical_label_color`) | The label; the stronger hit stop |
| Shadow | Umbral Violet | Rim + Core + Seams; allied behaviour |
| Elite | Elite Gold | Crest; the ELITE tag; never pulses |
| Boss special / enrage | Boss Crimson | Pose; charge; environment cue; the boss bar |

The definitive UI palette is **not** decided here (the UI's own colours — rarity tiers, bars — are
UI work). World VFX follow this table.

### 5.5 Accessibility

**Readability never depends on colour alone.** Every signal in §5.4 has at least two non-colour
carriers. Concretely:

- **Enemy role** is read by silhouette (§9), stance and movement pattern — never by hue.
- **Telegraphs** are read by pose, brightness change and timing. Warning Yellow and Danger Red also
  differ strongly in *value* (yellow is far lighter), so they separate under protanopia and
  deuteranopia.
- **Heal vs damage** differ by motion (rising vs impact) and shape (the ring on the healed), not
  only green vs red.
- **Shadow vs hostile in low light**: shadows are the darkest bodies in the scene, lit only by their
  own violet rim and a single central Core; hostiles are mid-value bodies with paired warm eye
  points, lit by the level. In darkness a violet outline with one central light is an ally; warm
  points on an unlit mass are an enemy. Neither needs the UI.
- **Elite vs boss**: an elite is an archetype's silhouette at normal size with a gold crest and the
  ELITE tag on a normal health bar; a boss is a unique silhouette at 1.3–2.0× human scale with its
  own screen bar, name and intro. They never share an accent colour.
- **Validation** (from M13.6): every new character is checked in greyscale and through deuteranopia,
  protanopia and tritanopia simulations before it is accepted.

---

## 6. Material Language

### 6.1 Families

PBR metallic-roughness. Values are **guidelines** — the ranges a material should normally sit in —
not rigid numbers. Albedo values are sRGB 0–255.

| Family | Metallic | Roughness | Albedo value | Used for |
| --- | --- | --- | --- | --- |
| Matte fabric | 0 | 0.80–0.95 | 40–180 | Uniforms, cloth, wraps |
| Leather | 0 | 0.55–0.75 | 30–120 | Straps, gloves, boots, belts |
| Skin | 0 | 0.45–0.60 | natural range | Faces, hands |
| Coated armour (painted / blackened metal) | 0 | 0.35–0.55 | 30–90 | The player's dark plates — dielectric paint over metal |
| Worn metal (exposed) | 1 | 0.35–0.65 | 150–220 | Edges where the coat is worn, hostile corroded metal |
| Polished arcane metal | 1 | 0.15–0.30 | 170–235 | The player's weapon edges and fittings, elite gold trim |
| Stone / concrete | 0 | 0.75–0.95 | 50–160 | Environments |
| Bone / chitin / hide (hostile) | 0 | 0.40–0.75 | 60–200 | Dungeon-born creatures |
| Obsidian-glass (dungeon, Gate) | 0 | 0.10–0.30 faces, 0.7+ broken edges | 15–40 | Gate segments, dungeon accents |
| Supernatural energy | — | — | — | Emission only (seams, cores, charges) |
| Shadow body | 0 | 0.60–0.80 | 15–35 | §11 |

**Metal must look metallic, and only metal is metallic.** Fabric, leather and skin are never
metallic, not even partially. Dark armour is *coated* metal: a dielectric with metal showing only
where the coat is worn — this keeps dark gear dark without faking a black metal.

**No albedo below 15 or above 240** (except emissive masks), so lighting always has something to
work with.

### 6.2 Roughness hierarchy

Glossiness leads the eye, so it is spent on what matters.

1. **Smoothest** (0.10–0.35): weapon edges, the player's arcane fittings, elite trim, Gate faces —
   the things the eye should find.
2. **Middle** (0.35–0.70): armour, leather, skin, creature plates.
3. **Roughest** (0.70–0.95): fabric, stone, concrete — the environment and large cloth areas recede.

An environment's average roughness stays ≥ 0.7. A character never has one roughness everywhere.

### 6.3 Emission discipline

Emission is reserved for:

- **Shadows** — rim, Seams, Core, aura;
- **the player's arcane accents** — the Arc Line, the weapon's charged channel;
- **Elite accents** — steady and low;
- **Boss** — its Core, its attack charge;
- **gameplay telegraphs and feedback** — §14, §5.4;
- **environment signals** — the Gate, interactables' state, navigation cues (§13).

Nothing else glows. Budgets:

- At rest, ≤ **5%** of a character's visible surface is emissive, at energy ≤ **1.5**.
- Only telegraphs and charges may peak above that (up to energy **4**), and only for the length of
  the wind-up or the active window.
- Bloom (M14) is tuned so that only emission above energy ~1 blooms; albedo never does.

---

## 7. Player

### 7.1 Silhouette

The player must read as **mobile, precise, growing, shadow-bound, the protagonist** — and never
heavy.

- **Build**: athletic, lean, long-legged. Weight on the balls of the feet.
- **Outfit**: a structured, **hip-length** tactical jacket with a high collar — deliberately *not*
  a long coat, a hood or a cloak (the generic dark-hero silhouette, and the one this project avoids).
  Fitted trousers, shin-guarded boots, segmented forearm guards.
- **Asymmetry**: an armoured shoulder and upper-arm plate on the **off-hand (left)** side only, so
  the weapon arm stays clean and readable; a cloth tail at the right hip that trails movement.
- **The Arc Line** (the player's signature): one **Arc Cyan** emissive seam running diagonally
  across the back, from the left collar to the right hip, continued down the weapon forearm guard.
  The camera sees the player's back most of the time (§16.3), so the back is the most designed view,
  and the Arc Line is a diagonal slash that reads at any distance, in backlight, among any number of
  shadows. It is unique to the player: no other character carries it.
- **Head**: bare head, short hair, face visible (early progression). No mask, no hood.
- **Backlight test**: in pure silhouette the player reads as the high collar, the asymmetric
  shoulder, the long legs and the weapon.

### 7.2 Proportions (reference for M13.3+)

| Measure | Target |
| --- | --- |
| Height | **1.80 m** (matches the gameplay capsule: radius 0.4, height 1.8, origin at the feet — *measured*) |
| Heads | **7.75** (head ≈ 23 cm) — realistic, slightly heroic |
| Legs (inseam) | ≈ 0.50 × height |
| Shoulders | ≈ 2.1 head-heights wide |
| Hands, feet | ≈ **110%** of realistic size, for readability |
| Eye height | ≈ 1.68 m |
| Weapon | ≈ **115%** of a realistic equivalent (§8) |

The torso stays inside the 0.4 m-radius capsule; arms, weapon and cloth may exceed it. The capsule
is never resized to fit a model.

### 7.3 Visual evolution (concept only — not implemented)

The player's look evolves with progression through **materials, emission and accessories on the
same silhouette**, not new bodies. No equipment set is designed here.

| Stage | Silhouette | Materials | Emission | Shadow details |
| --- | --- | --- | --- | --- |
| **Early** | The base outfit above | Fabric, leather, coated metal | The Arc Line only, faint | None |
| **Mid** | Collar rises into a neck guard; the shoulder plate extends | More plates; polished fittings appear | The Arc Line brighter; the weapon channel lights on charge | The first thin **violet Seams** at the ends of the Arc Line |
| **Late** | Sharper shoulder line; the hip tail splits into fragments | Polished arcane metal dominant | Arc Cyan and Umbral Violet together | Violet Seams along the arms and weapon |

**Invariant**: the Arc Line stays **cyan** at every stage and the player's body stays lighter than
Void/Abyss. However much shadow the player takes on, the player is never mistaken for a shadow.

### 7.4 Player materials

Graphite coated armour; Slate and Signal Steel fabric; dark leather straps; Ash worn edges;
polished arcane-metal fittings; Arc Cyan emission on the Arc Line only.

---

## 8. Weapons

**Readable, original, fast, slightly oversized, never ornate.**

- **Forms**: geometric and aggressive — straight lines, flat planes, chisel-cut angled tips, clean
  bevels. No filigree, no skulls, no gems, no wings, no scrollwork.
- **Scale**: ~115% of a realistic equivalent. The current one-handed blade family (the
  `training_sword` and `swift_blade` items): blade 0.85–0.95 m, width 5–7 cm, total ≈ 1.1–1.2 m.
- **Arcane detail, controlled**: a recessed **channel** along the blade replaces a fuller; it is
  dark at rest and carries the owner's accent (Arc Cyan) when charged — heavy attacks, criticals.
  One emissive element per weapon, no more.
- **Always in hand**: the game has no sheathing. The idle pose holds the weapon low and angled back,
  and it must read in the silhouette at rest.
- **Materials**: polished arcane metal edges (roughness 0.15–0.30), coated metal body, wrapped
  leather grip.
- **Hostile weapons** use the opposite language: forged, grown or broken; asymmetric; stone, bone,
  corroded metal; heavy and crude. A player weapon is *machined*, a hostile weapon is *made*.
- **Shadow weapons** are the source's weapon under the shadow material (§11).
- **Evolution**: a weapon evolves through its material and channel, not through more ornament.
- **Anchor**: the weapon's origin is the **centre of the grip**; the blade points along the weapon's
  local +Y, the edge faces forward (−Z in Godot). It attaches to the hand at M13.5 (§16.5).

---

## 9. Enemy Archetypes

### 9.1 Palette philosophy and the faction rule

- Enemies are **not colour-coded**. Every archetype uses the same hostile material family and
  neutral palette; **the silhouette is the primary identifier**, stance and motion the second, a
  small role accent the third.
- **One hostile family exists today: the dungeon-born.** Their material language is the dungeon's:
  weathered stone, bone plate, dark hide, corroded metal, obsidian-glass fragments — ancient against
  the player's modern. Their emission is warm and small: paired Danger Red eye points (energy ≤ 1.0).
- **No factions are invented here.** Any future faction must bring, before any asset is made:
  a **palette** (neutrals plus at most one secondary hue, inside the warm half), a **shape language**,
  a **material language** and an **iconography** — written into this document.

### 9.2 Silhouette rules (measured sizes are the gameplay capsules)

| Archetype | Size (measured) | Silhouette rule | Shape | Role accent |
| --- | --- | --- | --- | --- |
| **Melee** | 1.9 m, capsule r 0.45 | Medium build, forward lean, balanced centre of mass; one **dominant weapon** on the right, clearly bigger than the forearm | Forward triangle | The weapon's edge |
| **Ranged** | 1.9 m (visual 1.85, r 0.40 — thinner than its body) | Thin, upright, narrow lower body (fragile up close); one **extended emitter** — a long arm or device — at the projectile point (shoulder height, forward) | Vertical line + one extension | The emitter: dark at rest, Warning Yellow during the wind-up |
| **Tank** | 2.3 m, capsule r 0.6; shoulders ≈ 1.7 m wide | Mass above everything; **the widest silhouette**; head sunk between the shoulders (flat top line); wide heavy stance; a two-handed weapon or massive gauntlet | Square | Heavy plates |
| **Assassin** | 1.7 m, capsule r 0.35 | Thin, sharp, low; permanent forward-diagonal crouch; **one long blade** (≈ 0.8 m) or blade-arm; long thin elements trailing backwards | Diagonals, points | The blade |
| **Support** | 1.8 m (visual 1.75, r 0.38) | Upright and centred; a **circular element at head height on the body axis** — a ring or disc holding its focus in front of the head; protective, concentric forms | Circles | The focus: Vital Green when healing, hostile tint when buffing |

**Ranged vs Support** — both keep their distance, so they must never share a silhouette: the
ranged is a *line* with its danger at the end of an extended arm; the support is a *circle* with
its focus on the body's axis. One points, the other holds.

**Test** (from M13.6): a screenshot without UI, all five archetypes in black silhouette at gameplay
distance; a reviewer names each role. A failure blocks the asset.

---

## 10. Elite

An elite is **the archetype, overlaid** — never a new model (consistent with M12.7, which scales an
elite's numbers but not its size or timings).

The **elite overlay kit**, applicable to any archetype:

| Element | Rule |
| --- | --- |
| Accent material | Elite Gold polished arcane metal (metallic 1, roughness 0.2–0.35) on 2–3 existing plates or edges — through a material slot or mask the base mesh already has |
| Emission | Elite Gold, **steady**, energy ≤ 0.6 on the trim. It never pulses: pulsing belongs to telegraphs |
| Pattern | Gold chevron bands on the accented plates — one motif, repeated |
| Marker | The **Elite Crest**: a small angular gold shard fixed at the upper back / shoulder, ≤ 15% of the silhouette's width |
| UI | The existing gold ELITE tag on its health bar (M12.7) |

**Invariants**: same scale as the archetype (no size change); silhouette within +10% of the
archetype's; the telegraph language is unchanged (an elite's attacks announce themselves exactly
like the archetype's). **Gold never appears on a boss.**

---

## 11. Shadow

The shadows are the project's signature. They must read at once as **allies, supernatural, derived
from the enemies, one visual system**.

### 11.1 Shadow Version — mesh reuse

A shadow is **its source enemy's mesh and skeleton**, under one shared shadow material — never a
separate model unless a design explicitly needs one. This is what lets any enemy become a shadow,
and what keeps the army affordable.

- **Scale: 0.9 × the source**, applied uniformly on the shadow's model pivot. This matches the
  existing data (the basic melee shadow's capsule is 1.7 m for a 1.9 m source), so no gameplay
  changes; and it keeps the player (1.80 m) taller than every standard shadow — the leader stays the
  focal figure in a crowd of them.
- Animations: the source's clips on the source's skeleton (§16.6), unchanged.
- Weapons: the source's weapon, under the same material.

### 11.2 Palette

Void `#0B0C10` and Abyss Indigo `#17132B` for the body; Umbral Violet `#8C59F2` for all emission.
**One hue of light.** No second emissive colour, no neon mix. Highlights are Umbral Violet pushed
brighter (bloom whitens its core), not a new colour.

### 11.3 Material behaviour (concept — the shader is not written in M13.1)

| Channel | Behaviour |
| --- | --- |
| Base colour | The source's albedo reduced to its luminance, crushed to ≤ 12% value and tinted Abyss Indigo: the form detail survives, the colours do not |
| Roughness | Uniform 0.6–0.8: it absorbs light; no specular glints |
| Metallic | 0 everywhere, including the weapon |
| Normal | The source's normal map, kept — the form stays readable |
| Emission | Umbral Violet in three places only: the rim, the Seams, the Core (§11.5) |
| Fresnel / rim | **The primary readability tool**: an Umbral Violet rim, strongest at grazing angles — the outline never disappears, whatever the background |
| Transparency | **Opaque.** The M8 placeholder is translucent; the definitive shadow is not (translucency sorts badly, costs overdraw at army scale and reads as "ghost", not "power"). Summon and dismiss use a **dissolve** (alpha scissor over noise), not alpha blending |
| Aura | A low, ground-hugging **ink drift** at the feet — slow, dark, a few violet sparks. Not flames, not smoke columns. Off beyond ~15 m and when many shadows are present (§16.8) |

The material is built with the shadow visual system (ROADMAP M13.7); its VFX polish is M14's.

### 11.4 Silhouette treatment

- The source's **primary silhouette is preserved** — a shadow melee is still a melee at a glance.
- Extremities (hands, weapon tips, cloth, hair) break into short sharp fragments and wisps that
  trail motion: *fragmented, sharp, flowing*.
- **Never a flat black cut-out**: the rim is always present.

### 11.5 The shadow's mark — Core and Seams

Chosen over glowing eyes and runes (see *Decision log*):

- **The Core**: a single small, geometric diamond of Umbral Violet light at the sternum (≈ 0.58 ×
  height, the same height as a TargetAnchor). One central point reads at a distance where two eye
  points merge, and it is the opposite of the hostile read (two warm points).
- **The Seams**: thin violet fracture lines following the source's anatomy — joints, plate edges,
  the weapon's edge — as if the body were darkness held together by light.
- **No glowing eyes, no runes.** Glowing eyes are the most generic identity for summoned minions in
  the genre; runes add noise.

Documented only; implemented with the shadow visual system.

### 11.6 Readability among many shadows

With any number of shadows on screen the player must tell apart **allies, enemies, elites, the boss**:

- ally = darkest value + violet rim + one central Core;
- enemy = mid value + level light + paired warm eyes;
- elite = enemy + gold crest (steady);
- boss = scale + unique silhouette + crimson;
- the player = lighter than any shadow, the cyan Arc Line, the camera's centre.

A shadow's state (selected, commanded, targeting) is shown by rim intensity or a marker, never by a
new hue.

---

## 12. Boss

### 12.1 Scale and proportions

- **1.3–2.0× human scale**, chosen per design. The current boss is **2.6 m (1.44×)**, capsule
  radius 0.6 — *measured*, inside the range. Its definitive model (M13.10) is authored to that
  capsule (±5%): no gameplay change. A boss is not automatically a giant.
- Proportions: a smaller head relative to the body (8.5–9 heads) so it reads bigger; the **attack
  parts oversized** (arms, weapon: 1.2–1.4× the humanoid ratio) so every wind-up reads.

### 12.2 Silhouette and focus

- A **unique silhouette** — not an archetype's, not an elite's.
- **One signature attack part** — the arm or weapon that performs its heaviest attack (the Heavy
  Slam today) — is the largest single shape and carries Boss Crimson.
- **At most three focal points**: the head (identity), the signature part (danger), the **Core**
  (its state: dim in phase 1, crimson-lit in phase 2, bright and slowly pulsing enraged).
- Phase and enrage are shown by the Core, the Seams of the signature part and the crimson rim —
  **not by recolouring the whole body** (what the placeholder does today).
- Low-noise surfaces: large planes and few secondary forms, so telegraph and active frames read
  against the body.

### 12.3 Readability of attacks

The parts that generate attacks — weapon, arms, core, appendages — carry the telegraph (§14). No
decorative spikes, capes or particles may cross them during a wind-up. **Crimson is never used on an
elite, gold never on a boss.**

---

## 13. Environment overview

Direction only — environments are built at M15. No environment asset is made in M13.

### 13.1 Hub — the controlled safe zone

- **Modern urban**: a walled courtyard in a reclaimed city district at night / blue hour — concrete,
  glass, steel, asphalt, signage without logos. Rectilinear, human-scale architecture.
- **Palette**: cold and neutral — surfaces from Graphite to Concrete, saturation ≤ 20%.
- **Light**: a cold key (the current `DirectionalLight3D` is `#C7CCFF`, energy 0.55 — *measured*),
  cool fog; **warm practical lights** (`#FFDB9E`, the training light) mark human places — the
  training area, future NPCs and services. Warm light in the hub means "people", never "danger".
- **The Gate is the brightest thing in the hub** (a rule already in `GAME_DESIGN.md`) and the only
  strong supernatural colour in it.
- No hostile colours in the hub's world (the UI aside).

### 13.2 Dungeon — the distorted, ancient, impossible reality

- **Forms**: non-orthogonal walls, repeated and inverted arches, monoliths, stairs that go nowhere,
  architecture 2–3× human scale — ancient, wrong, but traversable.
- **Palette**: darker and more contrasted than the hub (ambient roughly 30–40% lower), materials
  ancient — stone, corroded metal, obsidian-glass. Saturation ≤ 20%.
- **Light**: cold, desaturated key; **pools of light mark the path**; the floor where fights happen
  is always lighter than the walls (value ≥ Slate in the lit areas). No absolute black where the
  player walks.
- **Reserved colours stay out of the architecture**: no violet (shadows, Gate) or red (hostile)
  washes on large surfaces. Environment emission is limited to interactable state (doors: locked in
  the Danger Red family, open in the Vital Green family — as the placeholders do today) and the exit.

### 13.3 Gate — the iconic element

The Gate must be recognisably ShadowAscension's and nobody else's.

| Aspect | Definition |
| --- | --- |
| **Form** | A **vertical ring of separate segments** — heavy, angular obsidian-glass monolith pieces — standing on the ground, framing a flat **membrane**. Outer diameter ≈ 4 m, centre at ≈ 2.2 m (the placeholder's measured values), framed by the hub's two pillars |
| **Membrane** | A still, **mirror-black surface of Abyss Indigo** that reflects the hub dim and inverted — not a swirl, not a vortex |
| **Energy / colour** | Umbral Violet light **leaks through the gaps between segments** — the same "light through seams" as the shadows (they share one energy). The membrane itself does not glow |
| **Movement** | Segments drift slowly out of alignment at rest; when the player enters interaction range they **lock into a perfect ring** and the seams brighten — the Gate wakes. The membrane ripples only on entry |
| **Material** | Obsidian-glass faces (roughness 0.1–0.3) with rough broken edges; no ornament, no symbols |

Deliberately avoided: floating swirling vortices, blue or red portal discs, runic circles.

---

## 14. Telegraph language

Telegraphs are **anticipated, readable, consistent and distinct from decoration**. Their timings
are owned by the data (`AttackData.windup / active / recovery`), and the visuals follow the data —
never the reverse.

### 14.1 Hostile telegraph (every enemy)

One code for all hostiles:

1. **Pose first**: the wind-up pose breaks the idle silhouette within its first ~0.1–0.15 s
   (weapon drawn back, arm raised, body coiled). It must read with colour turned off.
2. **Yellow tells *when***: the attacking part (weapon, emitter, fist) ramps Warning Yellow emission
   from zero to peak over the wind-up. Brightness rising = time running out.
3. **Red tells *now***: a short Danger Red flash on the attacking part at the start of the active
   window.
4. **Red on the ground tells *where* — for AoE only**: area attacks show a Danger Red outline on
   the ground whose footprint **is exactly the hitbox footprint**, filling as impact approaches.
   Single-target swings and projectiles have no ground marker.
5. **Recovery reads as vulnerability**: emission off, weapon low, body open.
6. **Sound** (M14): a wind-up cue per attack family.

Decorative VFX never use Warning Yellow or Danger Red and never pulse at a telegraph's rhythm.
Projectiles: a Danger Red core with a short Warning Yellow trail — hostile at a glance.

### 14.2 Boss telegraph

- The same code, scaled up.
- **More dangerous = more evident, not necessarily brighter**: a longer, bigger anticipation pose
  (the Heavy Slam's `RAISE` wind-up), a charge (the Core brightening), a sound, an **environment
  cue** (dust falling, the floor cracking around the marker).
- A boss telegraph never gets shorter with a phase or the enrage (the M12.9 rule), and a phase's
  visual escalation never hides it: an enraged boss glows crimson; its telegraphs stay yellow and
  red on the attacking part, and read against it.
- Ground markers for boss AoE follow §14.1.4.

---

## 15. Scale standards

### 15.1 Units

**1 Godot unit = 1 metre** — *verified*: `project.godot` overrides no unit or scale setting and
keeps the default gravity (9.8 m/s²), every gameplay value is written in metres and m/s, and every
measured body below is human-sized in those units. Blender works in Metric, unit scale 1.0;
glTF is in metres. **Import scale is always 1.0**: a model at the wrong scale is fixed in its
source, never by scaling a node in Godot.

### 15.2 Reference sizes

| Element | Size | Source |
| --- | --- | --- |
| Player | 1.80 m | measured (capsule) |
| Standard enemy | 1.7–1.9 m (assassin 1.7, support 1.8, melee and ranged 1.9) | measured |
| Tank | 2.3 m tall, ≈ 1.7 m across the shoulders | measured |
| Boss (current) | 2.6 m, 1.44× | measured |
| Future bosses | 1.3–2.0× (2.35–3.6 m) | rule |
| Shadow | 0.9 × its source (basic melee shadow 1.7 m) | measured / rule |
| Doorway (gameplay) | ≥ 4.0 m wide × 3.0 m clear height | measured (doors 4 × 3 m) |
| Corridor | ≥ 4.0 m wide; ≥ 4.5 m ceiling when roofed | rule (M15) |
| Combat room | 12–18 m across; ≥ 6 m ceiling when roofed (camera arm 4 m) | measured / rule |
| Boss arena | ≥ 18 × 18 m | measured |
| Gate ring | ≈ 4 m diameter, centre 2.2 m | measured |
| Hub courtyard | 44 × 44 m, walls 5 m | measured |

Art may exaggerate architecture (dungeon frames 2–3× human), but the **passable volume** above is
gameplay's and does not shrink.

---

## 16. Technical art principles

### 16.1 Axes and orientation — verified

| Convention | Axis | How it was verified |
| --- | --- | --- |
| Godot world up | +Y | engine |
| **Gameplay forward** | **−Z** (`Vector3.FORWARD`) | the project's code: every gameplay facing is `atan2(-x, -z)` or `-basis.z` (player, enemies, boss, shadow, targeting); every hitbox and spawn sits at negative Z |
| **Imported model front** | **+Z** (`Vector3.MODEL_FRONT`) | printed by Godot 4.5; the glTF 2.0 spec: "the front of a glTF asset faces +Z" |
| Blender character front | **−Y**, Z up | Blender's convention (the Front view looks along +Y at the model's face) |
| Blender → glTF (+Y Up export) | Blender −Y → glTF **+Z** | the exporter maps (x, y, z) → (x, z, −y) |

**Decision**: characters are modelled the Blender way (facing −Y, Z up), exported with +Y Up, and
arrive in Godot facing +Z. **The model instance is rotated 180° about Y** where it is placed — on the
imported scene's own instance node, **never on a pivot that scripts drive** (`DungeonBoss` resets
`MeshRoot`'s rotation during its beats; the player's tilts drive `Model`). M13.2 turns this into the
pipeline (and may automate it with an import script); the rule itself is fixed here.

### 16.2 Origin and ground contact

- The model's origin is **at the feet**: on the ground plane, centred between the feet in the rest
  pose. The `CharacterBody3D` origin is already there for every character (capsules sit at half
  their height — *measured*).
- **Feet touch y = 0** — no floating, no sinking. Checked on import (M13.2's test asset).
- Weapons: origin at the centre of the grip (§8). Props: origin at their ground contact point.

### 16.3 Camera readability

*Measured*: the camera rig sits at 1.5 m on the player, a 4.0 m spring arm behind, vertical FOV 72°.
The camera sees the player's **back** and three-quarter back most of the time.

Height on screen of a 1.8 m character at 1080p (vertical FOV 72°):

| Camera distance | Situation | Height on screen |
| --- | --- | --- |
| 4 m | the player; an enemy in melee | ≈ 335 px |
| 10 m | ranged ring (4–10 m), detection (10–12 m) | ≈ 135 px |
| 15 m | lock acquisition (15 m from the player) | ≈ 90 px |
| 22 m | lock lost (18 m from the player) | ≈ 60 px |

**Detail hierarchy** — every character works with primary and secondary forms alone:

1. **Primary forms** — the silhouette, big masses, the weapon: readable at **~60 px** (the lock's
   edge). This is what identifies the role.
2. **Secondary forms** — plates, major material blocks, the Arc Line, the Core: readable at
   **~135 px** (10 m).
3. **Tertiary details** — seams, straps, scratches, trims: only at **≥ ~300 px** (the player and
   melee range). They live mostly in normal maps and never change the silhouette.

**No visual noise.** Every element needs a visual job. Out: stacks of belts and pouches, rune
carpets, spike clusters, emission everywhere, busy high-frequency textures. When in doubt, remove it.

### 16.4 Texel density and textures

Tiers (values consolidated at M13.2):

| Tier | Texel density | Covers | Indicative texture sets |
| --- | --- | --- | --- |
| **Hero** | 512 px/m | Player, player weapon, bosses | Player 2048² (body + outfit), weapon 1024², boss 2048² (up to two sets) |
| **Gameplay** | 256 px/m | Standard enemies, elite overlay, the Gate, interactables | 1024²–2048² per enemy; overlays share one set |
| **Secondary** | 128 px/m | Minor variants, props, background | Shared atlases and trim sheets |

Why these: a character at 4 m on a 1440p screen shows ~250 px/m, so 512 px/m gives the hero
headroom for a close camera and 256 px/m matches an enemy at melee range.

**Texture strategy**:

- Maps: **Base Colour** (sRGB), **ORM** packed (linear: R occlusion, G roughness, B metallic —
  glTF-compatible), **Normal** (OpenGL, Y+ — Godot's and Blender's convention), optional
  **Emission mask** (greyscale). The emission **colour is a material parameter from the palette**,
  not painted into a texture — so elite, shadow, phase and enrage variants need no new textures.
- **No lighting painted into albedo** (beyond subtle cavity): lighting is dynamic.
- **Player / boss**: unique UVs, more detail. **Standard enemies**: reusable materials and shared
  detail textures. **Shadows**: a material override on the source — **no textures of their own**.
- Environment: tiling materials and trim sheets (M15).

### 16.5 Scene structure — the boundary between mesh and gameplay

The rule (already true since M12.9, `ARCHITECTURE.md`): **a definitive model replaces a placeholder
without any gameplay script or gameplay node changing.**

Standard structure (adapted from the real scenes):

```
<Entity> (CharacterBody3D)           origin at the feet
├── CollisionShape3D                 gameplay body: a primitive capsule, never fitted to a model
├── Hurtbox (Area3D)                 a primitive capsule on the root, never animated
├── VisualRoot (Node3D)              the facing — the only node that turns
│   ├── Model (Node3D)               presentation pivot scripts may tilt/scale
│   │   └── <asset>.glb instance     rotated 180° on Y; the only thing that is replaced
│   ├── AttackOrigin(s) → Hitbox     gameplay; siblings of Model, never children
│   └── ProjectileSpawn (Marker3D)   gameplay; carries no visual
├── TargetAnchor (Marker3D)          the torso centre, on the root
└── components                       health, navigation, targeting, attack, …
```

How the real scenes map to it (*measured*):

| Scene | Facing | Model pivot | Hitboxes | Anchors |
| --- | --- | --- | --- | --- |
| Player | `VisualRoot` | `VisualRoot/Model` (the tilts) | `VisualRoot/AttackHitbox` (box 1.4 × 1.4 × 1.6 at z −1.2), a sibling of `Model` | none — enemies aim at the hurtbox centre (0.95 m) |
| Enemies (5) | `VisualRoot` | none yet — the mesh is `VisualRoot/MeshInstance3D` | `VisualRoot/AttackOrigin/Hitbox` | `TargetAnchor` on the root at 0.58–0.61 × height; `VisualRoot/ProjectileSpawn` (ranged, support) |
| Boss | `VisualRoot` | `VisualRoot/MeshRoot` (telegraph deformation) | `VisualRoot/AttackOrigins/*Hitbox`, `HeavySlamMarker` | `TargetAnchor` at 1.5 m |
| Shadow | `VisualRoot` | none yet — `VisualRoot/MeshInstance3D` | `VisualRoot/AttackOrigin/Hitbox` | none (not a lock target) |

- **`VisualRoot` is the standard** and every combatant already has it. No new one is needed.
- **`Model` pivot for enemies and the shadow**: added with the first definitive enemy (M13.6),
  moving the placeholder poses (flinch squash, stagger lean, telegraph tint) from the mesh to the
  pivot / overlay — a presentation-only change made there with its suite. Not added in M13.1: it
  would change what `BasicEnemy` reads today for no present gain.
- **`VFXRoot`**: not added yet (nothing to put in it). Body-following VFX attach under the model
  (bone attachments, M14); world-space VFX are `top_level` nodes, like the support's `CastMarker`.

**TargetAnchor**: a `Marker3D` on the root at the torso centre (≈ 0.58–0.62 × body height), serving
the lock-on ring, the camera and projectiles' aim. It never depends on the mesh. The player keeps
none: the aim point is its hurtbox centre, through `EnemyTargeting.get_aim_point`.

**Anchors for weapons, projectiles and VFX** (future markers and bones — not implemented now):

| Anchor | Owner | Rule |
| --- | --- | --- |
| Weapon hand | presentation | A bone attachment on the hand (M13.5); the weapon's grip origin snaps to it |
| Projectile spawn | gameplay | `ProjectileSpawn` stays the truth; **the model is authored so its emitter sits at the marker** (ranged 1.25 m up, 0.6 m forward; support 1.55 m up, 0.55 m forward — *measured*), not the reverse |
| Attack origin / hitbox | gameplay | Where a swing lands; the animation is made to pass through it during the active window |
| VFX points | presentation | Bone attachments or `VisualRoot` markers for body effects; gameplay events spawn at gameplay markers |

**Hitbox separation**: a combat hitbox is **never** the render mesh, never parented to a bone, never
generated from the mesh's collision. **Collider principle**: characters use primitive capsules;
props use boxes or convex hulls; **nothing that moves has concave collision**; static environment
uses boxes/convex pieces, concave only where a floor's shape requires it. Environment collision
comes from Godot's import hints (`-col`, `-colonly`, `-convcolonly`) or authored primitives (M13.2).

### 16.6 Characters, skeletons, animation

- **Modular characters**: the player and future humanoids are a **base body + outfit modules**
  (torso, legs, arms, head accessory) **+ separate weapons**, all skinned to one skeleton; hidden
  body parts are removed under clothing. The M13.3 player is authored as one outfit in modular
  pieces, so later outfits swap pieces. The visual equipment system itself is not built.
- **Shared humanoid skeleton**: humanoid characters (player, humanoid enemies, humanoid bosses — and
  therefore their shadows) map to Godot's `SkeletonProfileHumanoid` through a `BoneMap` at import,
  so animation libraries retarget across them. Creatures that are not humanoid get their own
  skeletons; nothing is forced onto the humanoid rig.
- **Animation readability** (clips arrive at M14):
  - **Anticipation**: the wind-up lasts the attack's `windup`; the pose changes in its first beats.
  - **Active**: the strike travels through the hitbox volume inside the `active` window.
  - **Recovery**: follow-through and weight; a readable vulnerable pose for the `recovery`.
  - **Weight**: heavier archetypes settle longer; nothing snaps.
  - **No sliding**: locomotion playback is matched to the gameplay speed.
  - **Timing is data's**: a clip is retimed to its `AttackData`, never the data to the clip.
- **Root motion policy**: **gameplay movement is authoritative** — `CharacterBody3D` velocity from
  scripts (movement, dodge, the assassin's `lunge_speed`, knockback). Clips are authored **in place**;
  root translation is stripped at import. M14 may later adopt controlled root motion for specific
  clips; nothing in M13 depends on it.
- **Animation hooks**: an attack names its clip by id — `AttackData.animation`, a `StringName` —
  and **the id is the clip's name in the character's animation library**. *Verified*: attack ids are
  logical (`light_attack_1..3`, `heavy_attack_1`, `melee_basic_attack`, `ranged_basic_bolt`,
  `tank_heavy_swing`, `assassin_quick_strike`, `support_heal/buff/bolt`, `boss_quick_strike`,
  `boss_wide_sweep`, `boss_ground_slam`, `boss_double_strike`, `boss_heavy_slam`); the player's
  animation ids are `light_attack_01..03` and `heavy_attack_01`; enemy and boss attacks leave
  `animation` empty (nothing plays enemy clips yet) and get ids in the same form (`<action>_NN`) when
  their clips exist (M13.6 / M14). No `SwordSwingAnimation01`-style names.

### 16.7 LOD

- Godot generates mesh LODs on import and picks them by screen size; M13 authors **LOD0 only**
  unless the generated LODs fail visually.
- **Player / boss**: less aggressive (higher `lod_bias`). **Standard enemies**: default.
  **Shadows**: the most aggressive, plus visibility ranges on their aura. Numbers at M13.2 / M13.12.

### 16.8 Shadow army performance and material instancing

Many shadows can exist at once (M17's army). A shadow must not need:

- a unique heavy material — **one shared shadow material** for all shadows, per-shadow differences
  (dissolve, rim strength, selection) through **instance uniforms**;
- several particle systems — **at most one light GPU aura**, with a visibility range;
- an expensive shader — rim, seams and core are cheap per-pixel terms; no refraction, no
  translucency;
- individual textures — the shadow reuses the source's normal map and shared noise.

No shadow carries a real light: the Core is emission plus bloom.

**Material instancing for all definitive assets**: materials are shared `.tres` resources, loaded,
never duplicated per instance. Per-instance tints (telegraph flash, hit flash, elite, phase, enrage)
go through **instance uniforms** or a shared **`material_overlay`**, not through `duplicate()` of the
base material. The placeholders duplicate materials for their tints today — acceptable for
placeholders, replaced with each category (M13.6 enemies, M13.7 shadows, M13.10 boss).

### 16.9 Source vs runtime

| | Source | Runtime |
| --- | --- | --- |
| What | `.blend` files, sculpts / high poly, bake cages, texture-painting projects, working files | `.glb`, exported textures, Godot materials (`.tres`), shaders (`.gdshader`) |
| Where | `art_source/` at the repository root — **outside the Godot project** | `shadow-ascension/assets/` |
| Imported by Godot | never | always |

**Pipeline: Blender → GLB → Godot.** `.blend` files are **never runtime assets** (Godot can import
them directly, but that ties every import to a local Blender install; this is not chosen). Sources
live outside the project so Godot never tries to import them. Whether sources go through Git LFS is
decided at M13.2.

---

## 17. Naming and folder conventions

### 17.1 Naming

The repository requires `snake_case` file names (`CLAUDE.md` §5), so the usual studio prefixes
(`CH_`, `WP_`, `MAT_`, `TEX_`) are adopted **lowercase**, with the same meaning.

| Kind | Pattern | Examples |
| --- | --- | --- |
| Character | `ch_<name>` | `ch_player.glb` |
| Enemy | `ch_en_<archetype>[_<variant>]` | `ch_en_melee.glb`, `ch_en_tank.glb`, `ch_en_assassin_b.glb` |
| Boss | `ch_boss_<boss_id>` | `ch_boss_dungeon_boss.glb` (the `BossData.id`) |
| Player weapon | `wp_<item_id>` (the `ItemData.id`) | `wp_training_sword.glb`, `wp_swift_blade.glb` |
| Enemy weapon | `wp_en_<archetype>_<type>` | `wp_en_tank_maul.glb` |
| Material | `mat_<asset>_<part>`; shared: `mat_<purpose>` | `mat_ch_player_outfit.tres`, `mat_shadow.tres`, `mat_elite_overlay.tres` |
| Texture | `tex_<asset>_<part>_<map>`, map ∈ `bc` `orm` `n` `e` | `tex_ch_player_outfit_orm.png` |
| Shader | `sh_<purpose>.gdshader` | `sh_shadow.gdshader`, `sh_hit_overlay.gdshader` |
| Environment piece | `env_<kit>_<piece>[_<size>]` | `env_dungeon_wall_4m.glb`, `env_hub_bench.glb` |
| Prop | `pr_<name>` | `pr_training_dummy.glb` |
| VFX | `fx_<name>` | `fx_shadow_summon.tscn` |
| Skeleton / animation library | `sk_<family>` / `anim_<family>` | `sk_humanoid`, `anim_humanoid` |
| Source file | the runtime name, `.blend` | `art_source/characters/ch_player/ch_player.blend` |

- **Scenes keep their existing names** (`basic_melee_enemy.tscn` …): they are gameplay, not art.
- **Scene nodes are PascalCase**, as Godot's convention: `VisualRoot`, `Model`, `TargetAnchor`,
  `ProjectileSpawn`, `AttackOrigin`.
- **Objects inside a `.glb`**: `<asset>_<part>` (`ch_player_jacket`); bones free-named in the source
  as long as the `BoneMap` maps them.
- **Clips**: the `AttackData.animation` id for attacks; `<action>[_NN]` otherwise (`idle`, `run`,
  `dodge_01`).

### 17.2 Folders

Runtime assets go into the **existing** `assets/` folders — nothing moves, nothing parallel is
created. One folder per asset keeps an asset's files together (easy to replace, easy to delete).

```
<repository root>/
├── art_source/                          created at M13.2 with its first file
│   ├── characters/<asset>/              .blend, sculpts, bakes, painting projects
│   ├── weapons/<asset>/
│   ├── environments/<kit>/
│   └── references/REFERENCES.md         links and notes — no copied images (§18)
└── shadow-ascension/assets/             runtime only
    ├── characters/<asset>/              ch_player/, ch_en_melee/, ch_boss_<id>/ → .glb, textures/, materials/
    ├── models/weapons/<asset>/          wp_*
    ├── models/props/<asset>/            pr_*
    ├── environments/<kit>/              env_hub/, env_dungeon/ (M15)
    ├── materials/                       shared materials; shaders/ for sh_*.gdshader
    ├── textures/                        shared noise, detail maps, trim sheets
    ├── fx/                              VFX textures, meshes, particle materials
    └── audio/                           unchanged
```

Godot's `.import` files are committed with their assets (as the project already does).

---

## 18. Asset sourcing and licensing

### 18.1 The asset register

Every asset that is **not wholly authored for this project from scratch** — bought, downloaded,
generated, derived — gets an entry in an **asset register** before it is committed. The register
is a Markdown table at `shadow-ascension/assets/ASSET_REGISTER.md`, created with its first entry
(M13.2 / M13.3). Fields:

| Field | Content |
| --- | --- |
| Asset | runtime path(s) |
| Source | URL, store, tool, or "original" |
| Author | person or tool |
| Licence | SPDX id or the licence's name + link |
| Permitted use | commercial / redistribution in a repository / modification |
| Modifications | what was changed |
| AI | tool and version, date, a summary of the prompt — or "no" |
| Originality check | who checked it, when |

### 18.2 Licences

- **Allowed**: original work; CC0; CC-BY (attribution recorded in the register); paid licences that
  allow commercial use in a game and storage in this repository.
- **Not allowed**: unknown or unclear licences; non-commercial (NC) or no-derivatives (ND);
  "personal use only"; anything ripped from another game; fan art of any franchise; assets whose
  licence forbids redistribution of source files in a repository.
- **Doubt means no.** An asset with a questionable licence is not committed.

### 18.3 AI-generated assets

Generative tools may be used as **starting points** (concepts, blockouts, texture bases) when their
terms allow commercial use. Their output is **never imported raw**. Before it enters the game it is:

1. **verified** — scale, origin, forward axis, topology, UVs, naming;
2. **cleaned** — retopology, texture cleanup, removed artefacts;
3. **optimised** — to its tier's budget;
4. **adapted** — to this bible: palette, shapes, materials, readability;
5. **checked for originality** — no recognisable character, creature, outfit, logo or signature
   design of another work.

**Prompts never name a protected franchise, character or living artist.** The register records the
tool, the date and the prompt summary.

### 18.4 References

- **No protected images are committed** to the repository — no images copied from the web, no
  "reference dump".
- A reference board is `art_source/references/REFERENCES.md`: **links and notes**, plus the
  project's **own** photos, sketches and concepts, and licensed images with their licence recorded.
- References illustrate genre principles (lighting, material, silhouette); they are never copied.

---

## 19. M13 production priorities

### 19.1 Investment priority (where quality and time are spent)

1. **Player** — silhouette and model (seen 100% of the time).
2. **Player weapon** (in every frame of combat).
3. **Core humanoid enemy** — the melee (the most frequent enemy; its rig and material set feed the
   other archetypes).
4. **Shadow material** (the signature; built on the melee).
5. **Boss** (a Hero-tier asset).
6. **Archetype variations** — ranged, tank, assassin, support; then the elite overlay kit.

**Investment order is not the calendar**: production follows the ROADMAP (M13.8 further enemies and
M13.9 elite come before M13.10 boss), because the variations reuse M13.6's rig and materials and are
cheap, while the boss needs the most time — scheduling it last does not lower its tier.

### 19.2 Quality tiers

| Tier | Assets | Standard |
| --- | --- | --- |
| **Hero** | Player, player weapon, bosses | 512 px/m, unique UVs, full PBR + emission masks, the least aggressive LOD, the most review |
| **Gameplay** | Standard enemies, elite overlay, shadows (derived), the Gate, interactables | 256 px/m, reusable materials, default LOD |
| **Secondary** | Minor variants, props, background | 128 px/m, atlases and trim sheets, aggressive LOD |

### 19.3 Placeholder migration

- **One category at a time**, in the ROADMAP's order: player (M13.3–M13.4) → weapon (M13.5) →
  melee (M13.6) → shadow (M13.7) → other archetypes (M13.8) → elite overlay (M13.9) → boss (M13.10)
  → remaining placeholders (M13.11: training dummy, items, markers). The environment and the Gate
  are M15's. **Never "replace all meshes" in one step.**
- **Each replacement**:
  1. instance the model under the category's model pivot (rotated 180° on Y, §16.1);
  2. remove the placeholder mesh;
  3. leave every gameplay node untouched — body, collider, hurtbox, `VisualRoot`, `TargetAnchor`,
     hitboxes, spawns, scripts (the diff shows no gameplay change);
  4. run the category's suite, `mixed_encounter_test` and `tests/run_all.gd`;
  5. pass the silhouette test (§9.2) and the accessibility check (§5.5).

### 19.4 Placeholder audit (M13.1)

What the audit of the real scenes found, and what happens to it.

**Scale** — coherent; nothing blocks M13, nothing resized.

| Placeholder | Measured | Verdict |
| --- | --- | --- |
| Player | capsule 1.8 m, r 0.4 | the reference |
| Melee / Ranged | 1.9 m, r 0.45 (ranged visual r 0.40) | ✔ standard enemy |
| Support | 1.8 m (visual 1.75) | ✔ |
| Assassin | 1.7 m, r 0.35 | ✔ smallest |
| Tank | 2.3 m, r 0.6, shoulders 1.7 m | ✔ widest |
| Boss | 2.6 m, r 0.6 (1.44×) | ✔ inside 1.3–2.0× |
| Basic melee shadow | 1.7 m for a 1.9 m source | ✔ becomes the 0.9× rule (§11.1) |
| Doors / rooms / hub / Gate | 4 × 3 m; 12–18 m; 44 m; ring Ø 4 m | ✔ |

**Anchors**

| Item | Finding | Action |
| --- | --- | --- |
| TargetAnchor — enemies, boss | on the root at 0.58–0.61 × height, independent of the mesh | ✔ standard |
| TargetAnchor — player | none; aim point = hurtbox centre | ✔ documented, no change |
| ProjectileSpawn — ranged, support | a gameplay marker under `VisualRoot`, independent of the mesh — but the placeholder **Orb was a child of the marker** | **Fixed in M13.1**: the Orb is now a sibling under `VisualRoot`, same position; the marker carries no visual. No script referenced the Orb; the ranged and support suites pass |
| Player weapon hitbox | `VisualRoot/AttackHitbox`, a fixed box, sibling of `Model` — no dependency on the placeholder primitive | ✔ |
| Enemy hitboxes | under `AttackOrigin`, siblings of the mesh | ✔ |
| Tank shoulders / assassin blade | placeholder meshes under the placeholder mesh; nothing references them | ✔ leave with the placeholder |
| Attack / animation ids | logical (§16.6) | ✔ confirmed from M11 |

**Visual / gameplay coupling left as documented debt** (none blocks M13.2):

1. The enemies' and the shadow's placeholder poses (flinch squash, stagger lean) and telegraph tint
   act on `VisualRoot/MeshInstance3D`; with a model they are lost until M13.6 adds the `Model` pivot
   (already known since M12.9).
2. `DungeonBoss` resets `MeshRoot`'s rotation and position in its beats → the 180° correction goes
   on the model instance under it (§16.1).
3. The player's `VisualRoot/Model` is a required path → kept; the model goes under it.
4. Placeholders duplicate materials for tints → overlay / instance uniforms with each category.
5. `CastMarker` (support) and `HeavySlamMarker` (boss) are gameplay-driven VFX placeholders → their
   nodes stay (script-exported / named by data); their look is M14's.

**Colour conflicts with this palette** — placeholder values, corrected by the milestone that
replaces them (not in M13.1: they are looks, not structure):

| Placeholder | Current | Conflict | Target | When |
| --- | --- | --- | --- | --- |
| Enemy projectile | `#CC73FF` violet | a hostile in the shadows' colour | Danger Red core, Warning Yellow trail | M13.8 / M14 |
| Ranged body | `#594DB3` violet-blue | same | hostile neutrals | M13.8 |
| Heavy Slam ground marker | `#BF4DFF` violet | a hostile telegraph in the shadows' colour | Danger Red outline | M13.10 / M14 |
| Shadow command-target marker | `#FF8C4D` orange | a player-side marker in a hostile hue | Umbral Violet | M13.7 / M14 |
| Boss enrage body / glow | `#F2591A` / `#FF4D0D` | outside the boss accent | Boss Crimson Core and rim (`BossEnrageData`, data) | M13.10 |
| Player / melee / support bodies | `#6699E6` / `#B34040` / `#4D8C73` | identification colours | the models' materials | with each model |

---

## 20. Decision log

| # | Decision | Alternatives considered | Why |
| --- | --- | --- | --- |
| D1 | Dark urban fantasy + supernatural military/arcane + clean ARPG readability, **stylized realism** | painterly stylised; photorealistic | Serious tone, lower asset cost, no uncanny valley, modular assets; the modern/ancient contrast is the world's premise |
| D2 | A 14-colour palette; values already used for a role are **adopted** | a fresh palette | The placeholders already speak it; no data changes; one source for each colour |
| D3 | **Warm = hostile, cold = ours**; green = restoration | per-archetype hues | One rule anyone can learn in a fight; carries across lighting |
| D4 | The shadow's mark is a **Core + Seams**; no glowing eyes, no runes | glowing eyes; runes; cracks only | Eyes are the genre's most generic minion identity; one central Core reads further and opposes the hostile two-point read |
| D5 | Shadows are **opaque** with a violet rim; dissolve by alpha scissor | translucent (the placeholder) | Readability, sorting and overdraw at army scale |
| D6 | Shadow Version at **0.9 × source** | 1.0 × with a new collider | Matches the existing data (no gameplay change); keeps the player the tallest in a crowd of shadows |
| D7 | Elite = **overlay kit** (gold trim, crest, steady low emission), same scale | a bigger model; a new model | Consistent with M12.7; keeps the archetype's silhouette; cheap for every archetype |
| D8 | The M13.10 boss is authored to the **existing 2.6 m capsule** | a bigger boss | No gameplay change; 1.44× is already inside 1.3–2.0× |
| D9 | Telegraphs: **yellow = when** (body), **red = where** (ground, AoE only) and **now** (flash) | one colour; per-enemy colours | Matches the data already in place; separates timing from area; value difference helps colour-blind players |
| D10 | Gameplay forward **−Z**; models arrive facing **+Z**; the **180° turn lives on the model instance** | modelling backwards in Blender; rotating a scripted pivot | Keeps sources standard; scripted pivots are reset by code (`MeshRoot`) |
| D11 | **1 unit = 1 m**, import scale 1.0 | per-asset scale fixes | Verified in the project; fixes belong in the source |
| D12 | **Lowercase prefixes** (`ch_`, `wp_`, `mat_`, `tex_`, …) | `CH_Player_*` | The repository's `snake_case` file rule wins |
| D13 | Runtime in the **existing `assets/`**, one folder per asset; sources in **`art_source/` outside the project** | `art/` inside the project; `.blend` as runtime | No moves; Godot never imports sources; no Blender dependency at import |
| D14 | **No root motion** in M13; gameplay authoritative | root motion now | M11/M12 movement is data-driven and tested; M14 may revisit per clip |
| D15 | Humanoids share a skeleton via **`SkeletonProfileHumanoid` retargeting** | one rig for everything | Animation reuse without forcing creatures onto a human rig |
| D16 | Tints on definitive models via **instance uniforms / `material_overlay`** | duplicating materials (placeholders) | Batching, army scale, no per-instance materials |
| D17 | **Investment order ≠ production order** (§19.1) | building the boss earlier | Variations reuse M13.6's work; the boss keeps its Hero tier either way |
| D18 | The placeholder **Orb moved off `ProjectileSpawn`** | leave it as debt | A gameplay marker must carry no visual; trivial and verified safe |
| D19 | The player gets **no TargetAnchor** | add one | Enemies already aim at the hurtbox centre; nothing needs it |
| D20 | The player's jacket is **hip-length**, no hood, no long coat; the **Arc Line** is the signature | long dark coat; hooded hero | Avoids the genre's most generic (and most franchise-associated) dark-hero silhouette; the back view is what the camera sees |
| D21 | Working names that echo other works are **renamed when their content is made** — the ROADMAP's "Hunter Association" (M15) is a working title only | keep | Originality applies to names as well as designs |

---

## 21. Validation checklist

| Question | Answer |
| --- | --- |
| **How should ShadowAscension look?** | A cold modern city with an ancient impossible world bleeding through Gates; dark but readable; stylized realism; supernatural colour only where it means something (§1–§3). |
| **How do I recognise the player?** | Hip-length tactical jacket, high collar, left-side shoulder plate, long legs, a blade in hand, and the cyan **Arc Line** diagonal across the back (§7). |
| **How do I recognise the melee?** | Medium build, forward lean, one dominant weapon on the right — a forward triangle (§9). |
| **How do I recognise the ranged?** | Thin, upright, narrow at the base, one extended emitter arm or device — a line (§9). |
| **How do I recognise the tank?** | The widest silhouette: square, shoulders ≈ 1.7 m, head sunk, heavy stance (§9). |
| **How do I recognise the assassin?** | Thin, low, diagonal crouch, one long blade, points trailing back (§9). |
| **How do I recognise the support?** | Upright and centred, a circle at head height holding its focus — circles (§9). |
| **How do I recognise an elite?** | Its archetype's silhouette at normal size, gold trim with steady glow, the gold crest, the ELITE tag (§10). |
| **How do I recognise a shadow?** | Its source's silhouette at 0.9×, the darkest body on screen, a violet rim, one violet Core at the chest, violet Seams (§11). |
| **How do I recognise the boss?** | A unique silhouette at 1.3–2.0×, one oversized crimson attack part, a crimson Core, its own bar (§12). |
| **Which colours are reserved to the supernatural?** | Umbral Violet (shadows, Gate), Arc Cyan (the player's arcane), Elite Gold, Boss Crimson; telegraph Warning Yellow / Danger Red and heal Vital Green are combat signals. Environments carry none of them on surfaces (§5). |
| **Which materials will we use?** | Fabric, leather, skin, coated armour, worn metal, polished arcane metal, stone/concrete, bone/hide, obsidian-glass, energy, the shadow material — with a roughness hierarchy (§6). |
| **What is the scale?** | 1 unit = 1 m; player 1.80 m; enemies 1.7–2.3 m; boss 2.6 m (1.3–2.0× for future ones); doors ≥ 4 × 3 m (§15). |
| **How will placeholders be replaced?** | One category at a time, the model under the pivot, gameplay nodes untouched, suites + silhouette + accessibility checks (§19.3). |
| **Where is the boundary between mesh and gameplay?** | Everything on the root and every hitbox/marker is gameplay; only the model instance under `VisualRoot`'s pivot is art (§16.5). |
| **What is the planned pipeline?** | Blender (−Y front, Z up, metres) → GLB (+Y up) → Godot (180° on the instance, import scale 1.0); sources in `art_source/`, runtime in `assets/` (§16.1, §16.9). |

---

## 22. M13.2 readiness — what the pipeline must turn into tooling

M13.2 — *Blender → Godot Asset Pipeline Setup* — takes these standards and makes them repeatable:

1. **Blender scene setup**: Metric, unit scale 1.0, Z up, character front −Y, origin at the feet.
2. **Export preset**: glTF Binary (`.glb`), +Y Up, modifiers applied, only the asset's collection,
   no cameras or lights; naming per §17.
3. **Godot import preset**: scale 1.0; LOD generation on; materials extracted to `.tres` per §17;
   texture import (Base Colour sRGB, ORM linear, normal maps as normal); the humanoid `BoneMap` to
   `SkeletonProfileHumanoid`; collision hints for environment pieces.
4. **The forward correction** (§16.1): the 180° turn on the model instance — by hand or by an
   import script, M13.2 chooses.
5. **The source folder** (`art_source/`) and whether it uses Git LFS.
6. **The asset register** (`assets/ASSET_REGISTER.md`) with its first entry.
7. **Texel density and budgets**: the tiers of §16.4 and triangle budgets, measured on a test asset.
8. **A round-trip test asset**: a 1.8 m mannequin placed under the player's `VisualRoot/Model` —
   proving scale, origin, ground contact, forward axis, material slots and that no gameplay test
   changes.

Nothing of this is implemented in M13.1.
