# AI Artefact Audit (issue #166)

Generated art reads as "AI slop" when it is inconsistent: a face that changes between frames, an item that
pops in and out, a character who turns round mid-animation, scribbles that look like writing. This is the
repeatable check that every chapter's art goes through before screenshots, a trailer or a demo, and the
record of what was found and fixed for Act 1.

## How to run it

1. **Scanner** (about 7 seconds):
   `python3 tools/ai_audit.py` scans every sprite strip, prop, building and icon for half-transparent pixels,
   loose noise pixels, feet that jump between idle/walk frames, frames whose filled area pops, and outline
   thickness changing between frames. `--fix` repairs only the first two, which never change what a sprite
   means. Projectiles and FX that float on purpose are listed in `LOOSE_OK`.
2. **Character sheets**: `python3 tools/character_sheet.py out_dir` puts each character's portrait,
   expressions, CGs (from `assets/cg/`, once #117 adds them) and five sprite rotations side by side. Compare
   them against the canon table in docs/PORTRAITS.md.
3. **Animation sheets**: `python3 tools/contact_sheet.py out.png --scale 3 --row "walk south" assets/sprites/<id>/walk_south.png ...`
   for every idle and walk strip. Look for: a face on the back of the head, the character turning away from
   the strip's direction, a held item appearing, vanishing or swapping hands, a face or markings that change
   every frame, a weapon that changes length.
4. **Text in art**: look at every sign, banner, book, page and notice in props, icons, portraits and key art.
   Writing must be real text, clean ruled lines, or nothing.
5. **Portraits up close**: hands (finger count, merged fingers), teeth, ears, jewellery, buckles, and smudges
   the pixel conversion turned into blobs. tests/test_portraits.gd already checks size, hard alpha, specks
   and leftover background.

Scanner and sheets find candidates; a person decides. The free repairs below come from the character's own
approved art, so nothing new is invented. What needs a paid regeneration goes into a `needs-topup` issue.

## Free repairs

`tools/ai_fixes.json` lists every repair with its reason, and the tools that make them:

- `tools/fix_frames.py` (no arguments applies the list):
  - **breathe** rebuilds a broken idle strip as a one-pixel breathing loop of the rotation frame.
  - **lock** keeps a walk strip's leg motion but pastes the rotation frame's head/body band over each
    frame at its bob, so a simple shape's face stays the same (the Nibbler).
- `tools/recolor_sprite.py <id> <material>` turns one material of a field sprite to match the portrait.
- Hand edits (one-off pixel fixes) are listed under `hand_edits`.

## Act 1 results (2026-11-21)

Scope: everything Act 1 shows today. 973 sprite strips, props, buildings and icons; 28 portraits; the title
key art; the painted territory map. There are no CGs or expression portraits yet (#117, #107).

**Scanner:** clean. No half-transparent pixels, no loose noise pixels, no frame pops or outline changes.
24 feet-jitter flags, all checked by eye: walk bobs, the Moth's hover and the Auditor's coat swing. None
needed a fix.

**Fixed for free (this pass):**

| What | Where | Fix |
|---|---|---|
| Face appears on the back of the head / character turns round | Velvette, Dunmore, Tobble, Folk man, Nibbler idle north; Gristle idle east; Ottoline idle north-east | breathe |
| Held item pops in, vanishes or changes | Odile (briefcase), Hesper (tool), Folk elder (cane) idle north | breathe |
| Body swells and changes pose | Tobble idle south-east | breathe |
| A different face every frame | Nibbler idle south and south-east; walk south, south-east, east | breathe / lock |
| Glyph-like scribble on its side | Nibbler east rotation, idle and walk | hand edit + breathe/lock |
| Sprite hair does not match portrait | Velvette (magenta to crimson, every strip) | recolour |
| Sprite hood does not match portrait | Abeyance (slate grey to bone white) | recolour |
| Shadow blob and smear over the face | Merrow portrait (middle girl) | hand edit |
| Ledger page pixelated into fake writing | Concord Warden portrait | hand edit (clean ruled page + seal) |

**Checked and fine:** the painted map (no text, no melted details), all text-bearing props and icons
(noticeboard, sign, tax banners, ledgers, signature, field maps), the title key art's clock tower, every
other portrait's hands, the rest of the idle and walk strips.

**Left for a paid regeneration or a decision** (issue #173, `needs-topup`, nothing spent):

- Walk strips where the character turns mid-cycle or a weapon flickers: Ottoline, Jessamy and the Sellsword
  walking south, Velvette walking north (sword), the Spitter's mouth changing while walking south.
- Bran's field sprite has a full grey beard and red face marks; the portrait has grey stubble.
- The Auditor's sprite mask has no red mark.
- Clerk Pettigrew and Ozias Crane read as the same face (balding, spectacles, quill behind the ear).
- Title key art: Ash holds a sword and has a second hilt at the hip. Wait for #165 (human-made key art)
  before paying for a fix.
- Decision, $0: Ash's field sprite keeps the hood up, the portrait and key art have it down.
- Prompt rule for #107/#117, $0: Abeyance's writ shows glowing pseudo-script in the painted source. At
  224x336 it reads as glow, but new expressions should ask for "plain glowing lines, no letters".

Before/after images: project files `last-ink/art-pass/ai-audit/`.

## Art Review page

Every sprite animation, portrait, prop, building, icon, tile set and painted piece can be reviewed on one
page with a checklist per asset (private Artifact: https://claude.ai/artifact/Nfctt4HLGoT3kushq2PspF).
The page source lives in project files (last-ink/art-review/index.html). Its data comes from:

    python3 tools/build_art_review.py OUT_DIR

Rebuild and republish when art changes. Each unit carries a pixel hash, so the page marks an asset
"Changed" if it was edited after it was checked. Review state is stored in the page's database
(`reviews/<doc>`, one field per unit); Claude's notes per asset go in `notes/<doc>`.
