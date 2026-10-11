# Evolution UI (plan)

A plan, not yet built. It covers the family document, the lineage view that
replaces the random grid, how wide trees are laid out, and what's left open
for mating. Mutation itself is done (see [Mutation.md](Mutation.md)); this is
the UI and storage around it.

## Words

- **Member**: one genotype in a family.
- **Litter**: the children made by one breeding action from the same
  parent(s) with one seed. Siblings are members of the same litter.
- **Generation**: a member's column. Roots are generation 0; anyone else is
  one more than their highest-generation parent.
- **Breed**: make a litter of mutated children from one member.
- **Mate** (later): make a litter from two members (Sims' crossover and
  graft, 1991 §4.3).
- **Reject**: delete a member from the family for good.
- **Unexplored**: a member nobody has bred from yet. Kept, just not
  followed.

## 1. The family document

A family is a document, not a library entry. You make or open one before
any evolution happens: **File > New Family** and **File > Open Family**,
and the lineage view only exists inside a family's window.

### Shape

`Name.evolvfamily` is a package (a folder Finder shows as one file):

```
Name.evolvfamily/
    family.json
```

One JSON file holds everything. A package rather than a bare `.json` so
later additions (a reference image, notes, a cover render) don't need a
format change. Thumbnails are *not* stored inside: they're a cache (below).

```json
{
  "format": 1,
  "created": "2026-10-11T13:20:00Z",
  "next_id": 58,
  "settings": {
    "litter_size": 19,
    "mutations_per_child": 1,
    "max_depth": 10,
    "excluded_functions": [],
    "excluded_root_functions": ["constant", "triplet-constant", "vector"],
    "excluded_variables": ["z"]
  },
  "litters": [
    { "id": "L1", "kind": "random", "parents": [], "seed": "8812...", "max_depth": 10,
      "created": "2026-10-11T13:20:00Z" },
    { "id": "L2", "kind": "mutation", "parents": ["g4"], "seed": "1290...",
      "settings": { "litter_size": 19, "mutations_per_child": 1, "...": "..." },
      "created": "2026-10-11T13:21:10Z" },
    { "id": "L3", "kind": "seed", "parents": [], "source": "library:11-figure-9",
      "created": "2026-10-11T13:25:00Z" }
  ],
  "members": [
    { "id": "g4", "litter": "L1", "index": 3,
      "expression": "(warped-color-noise x (abs y) 0.12 3)" },
    { "id": "g21", "litter": "L2", "index": 0,
      "expression": "(warped-color-noise x (abs (cos y)) 0.12 3)",
      "mutations": [ { "kind": "wrap", "path": [1, 0], "before": "y", "after": "(cos y)" } ],
      "name": "Nice one", "starred": true }
  ]
}
```

- **Litters carry the parents, members carry their litter.** A member's
  parents are its litter's `parents`, so mating is just a litter with two
  parents and nothing else changes. Breeding from the same member twice
  makes two litters.
- **Litter kinds**: `random` (no parents, from the generator), `seed` (no
  parents, a genotype brought in from the library, a file or pasted text),
  `mutation` (one parent), and later `mating` (two). Unknown kinds load as
  read-only members so an older app can still open a newer family.
- **Settings are snapshotted per litter**, so a litter is reproducible from
  its parents and seed even after the family's defaults change. With the
  same node set, `mutate_genotype` with that seed rebuilds it.
- **Ids** are short and sequential per family (`g4`, `L2`), from
  `next_id`, never reused after a reject. Readable in MCP output and bug
  reports; a UUID buys nothing inside one file.
- **Mutation logs** are what `ExpressionMutator.Child.mutations` already
  gives: kind, path, before, after. The view can use them to say what
  changed ("wrap at y").
- **Rejected members are not stored**, as asked. Rejecting is undoable
  until the window closes (normal document undo), then gone. A member with
  descendants can't be rejected on its own: the action offers to reject the
  whole branch, with a count.
- **Members aren't parsed at load time**, like `.evolvgenotype`: a member
  using a node that's broken or no longer loaded still opens (as a grey
  cell with the error), so a family survives node edits.
- The family's name is its file name; it isn't stored inside.
- JSON is written with sorted keys and pretty printing, so it diffs well
  and is readable by hand.

Size: a busy family (3 litters of 19 per generation, 30 generations) is
about 1,700 members. Expressions are capped at 1,000 nodes; a typical one is
well under 2 KB of text, so a few MB at most. One JSON file is fine at that
size.

### App plumbing

- `DocumentGroup` with a `ReferenceFileDocument` (`FamilyDocument`),
  reading and writing a `FileWrapper` directory. That gives New/Open/Save,
  autosave, Revert/Browse All Versions, the recent-documents menu, undo and
  iCloud Drive on macOS, iOS and visionOS without any code of ours.
- An exported type in Info.plist: `com.amolloy.evolv-io.family`,
  extension `evolvfamily`, conforming to `com.apple.package`.
- Families are ordinary documents: saved and opened anywhere through the
  standard File menu (New, Open, Open Recent, Save), with no folder of
  their own and no sidebar entry (Andy, 2026-10-11). A launch window with
  recents may come later.
- The family model and its JSON coding go in `ExpressionTree` (no UI), so
  they're unit-testable alongside `ExpressionMutator`.

### Thumbnail cache

Hundreds of members each need a render, and each distinct tree costs a
Metal pipeline compile (tens of ms, see `TreeThumbnailStore`). Thumbnails
are cached on disk in the app's Caches folder, keyed by a hash of the
expression text, supersampling and every node definition file (so editing
a node and reloading, or relaunching after an edit, re-renders). Every
thumbnail renders at one size (256 pixels) and is scaled to its cell, so
chips, the size slider and Show Path never re-render, so reopening a big family is instant, the same genotype in
two families shares one image, and nothing bloats the document or iCloud.
Renders run a few at a time, visible cells first.

## 2. The lineage view

The family window's main view. It replaces the Random Grid window (its depth
stepper and context menu move here).

```
 gen 0          gen 1             gen 2            gen 3
┌────┐
│ g1 │
└────┘
┌────┐   ┌────┐
│ g4 │━┳━│ g21│━━━━━━━━━━━┳━━━━━┌────┐
└────┘ ┃ └────┘            ┃     │ g40│ ← newest litter, full size
┌────┐ ┃ ▫▫▫▫▫ ▫▫▫▫▫ ▫▫▫▫▫ ┃     └────┘
│ g5 │ ┃ ▫▫▫ (18 unexplored)┃    ┌────┐
└────┘ ┃                   ┃     │ g41│
  ⋮    ┃ ┌────┐            ┃     └────┘
       ┗━│ g30│ ...              ⋮
         └────┘
```

- **Left to right by generation, siblings stacked vertically**, in one
  scroll view that scrolls both ways.
- **Each litter is a block** in its parent's generation + 1 column, joined
  to its parent by a connector. Inside the block, siblings are in litter
  order.
- **Members someone has bred from are shown full size; unexplored siblings
  in a litter that already has a bred-from member shrink to small chips**
  in a wrapped mini-grid (a third of the thumbnail size). A button on the
  top right of the litter's outline (or **Show Siblings Full Size** on the
  context menu) expands them again and shrinks them back; it's saved as
  the litter's `expanded` flag, so the family reopens the same way. A
  litter nobody has bred from yet (the newest) shows everyone full size.
  This is what keeps the view usable: a 19-child litter you've moved past
  costs a few rows of chips, not 19 thumbnails. Chips stay in litter
  order, in runs between the full-size members, and starred members stay
  full size. The first breed from a litter shrinks its siblings, so the
  parent moves up; the view adjusts the scroll so it stays under the
  pointer.
- A **thumbnail size** slider in the toolbar, as in Finder.
- After a breed, the view scrolls to the new litter.

### Actions

- **Click** selects; Shift/Command-click select several.
- **Breed** (Return, or the toolbar button): one new litter for each
  selected member. Selecting three members and breeding is the "several
  parents in one generation" case.
- **Reject** (Delete): removes the selected members (see above for members
  with descendants).
- **Star** and **Rename**, both stored on the member.
- **Double-click**: full size. The context menu keeps everything the grid
  has (full size, Debug View, expression tree, show/copy expression, export
  image) plus **Save to Library…**, which writes a `.evolvgenotype` into
  the user Genotypes folder.
- **Show Path** highlights the chain from a member back to its root and
  shrinks everything else to chips (`FamilyLayout`'s `focus`), for
  following one line in a big family. The member keeps its place on
  screen when it's turned on or off.
- **Export Path…** (macOS) exports a member and all its ancestors with
  the Export Image options (size, format, supersampling, metadata) into a
  folder, one file each, named `Base-gen03.png` with generations
  zero-padded; a generation with two genotypes on the path (a mated
  child's two lines) adds the member id, `Base-gen03-g45.png`. The stored
  name is the member's name, or "Base generation 3". Once the folder is
  chosen the dialog closes and the renders run in the background, shown
  as a circular progress in the toolbar whose popover can stop them.
  `ExportPathSheet.swift`.
- **Captions** (Export Image and Export Path, off by default): the
  expression in white monospaced text on a dark band, either over the
  bottom of the image (at most 40% of it) or in a band added below. The
  text is about 1.8% of the image width (at least 11 pixels) and wraps; a
  caption too long for its band ends in "…". Export Path sizes the band
  below for its longest expression, so every image comes out the same
  size. Images under 256 pixels aren't captioned. `ExportCaption.swift`.
- Starting a family: **New Family** asks how to start: a random litter
  (litter size, depth, optional seed), or a genotype from the library
  (also a **Start Family From This** item on the sidebar's context menu),
  a file, or pasted text. **Add Roots** adds another random or seed litter
  to an existing family, in generation 0.
- A **settings popover** for the family defaults: litter size, mutations
  per child, depth, excluded nodes. Changes apply to new litters only.

## 3. Laying out wide trees

The tree grows downward as well as rightward when you breed from several
members, so the question is where each litter block goes vertically.

**Proposal: a top-aligned tidy tree.** Each member owns a horizontal band
as tall as the larger of its own cell and the stacked heights of all its
litters' blocks (recursively). A member sits at the **top** of its band,
not centred; its litters stack beneath each other in the next column,
starting level with it; the next sibling starts below the band.

- Top-aligned rather than centred (Reingold–Tilford style) because it's
  **stable**: breeding adds space below and to the right, but nothing
  above or to the left moves. With centring, every breed re-centres every
  ancestor and the thing you were looking at jumps.
- Bands never overlap, so connectors never cross, and a column can hold
  litters from many parents with each one beside its parent.
- The cost is empty space under a parent whose subtree is tall. Shrinking
  unexplored siblings to chips is what keeps that manageable; a branch can
  also be **collapsed** to a single "+42" badge (stored per member as view
  state in the document, so it reopens the same way).

Alternatives considered:

- **Plain columns** (every generation a flat list, parents and children
  linked by lines): compact, but lines cross everywhere as soon as two
  parents breed in the same generation. Fine for 3 litters, unreadable at
  10.
- **One litter per row, grid per litter** (Sims' 4×5 sheet for each
  generation, scrolled vertically): close to the original tool, but loses
  the left-to-right history.
- **Centred tidy tree**: prettier, unstable while you work.

### Room for mating

Mating makes the tree a graph: a child with two parents in two branches.
The layout stays a tree by putting a mating litter in its **primary
parent's** band (the first one selected), in the column after the
higher-generation parent, and drawing a **dashed connector** from the
second parent. That's the usual family-tree compromise. Nothing in the file
format changes: a mating litter is a litter with two `parents`. Mating
itself (crossover, graft) is a separate piece of work after this.

## Mating (plan)

### What Sims says

1991 §4.3 gives two methods; 1993 §2.2 keeps only the second.

- **Crossover** (needs similar parents): walk both trees together, copying
  nodes; wherever they differ, copy one parent's version with equal
  chance. His example, `(* (abs X) (mod X Y))` with `(* (/ Y X) (* X -.7))`,
  can only make 4 children, two of them the parents. Parents with
  different roots make nothing new ("two different species").
- **Graft** ("crossing over"): pick a random node of one parent and
  replace it with a random node of the other. Any part of either can land
  anywhere in the other; his example pair gives 61 different children.
  1993 adds that the result is checked for legal syntax and redrawn if
  it isn't.
- Nothing on probabilities, on which parent receives the graft, or on
  mutating mated children (1993's dynamical systems say "mutation and/or
  mating", nothing more).

### What's built

Andy chose (2026-10-11): both methods with graft the default; the graft's
receiving parent a coin flip per child, with the UI showing which parent
each child is built on; duplicates dropped, so a litter can be smaller;
no mutation on top of mating for now (to be revisited).

- **Select two members and Mate** (Shift-Return or the toolbar's Mate
  button grafts; crossover is in the Mate menu and the context menu). The
  first one selected is the primary parent: the litter is drawn in its
  branch. The litter is a `mating` litter with both as `parents` and a
  `method` (`graft` or `crossover`).
- **Colours**: in a mating litter the line from the first parent is blue
  and from the second orange, and each child has a dot in the same colour
  for the parent it's built on (its `base`).
- **Graft**: each child is one parent (a coin flip) with one random node
  replaced by a random node of the other. It uses the mutator's typing (a
  vector slot gets a node that fits, the root stays a call) and size cap
  (the larger parent's). The child's `mutations` log the graft (kind
  `graft`, path in the base, before, after).
- **Crossover**: Sims' coin flips at each difference, built on the first
  parent; the log lists what came from the second (kind `crossover`).
  Parents with different roots are refused with a message. Two parents
  with *n* differences make at most 2^*n* - 2 children.
- Children equal to a parent or to a sibling are dropped; drawing stops
  at the litter size or after about 50 fruitless draws per child.
- Mated children aren't mutated (yet). Breeding one afterwards mutates it
  as usual.
- Same seed, same children: `ExpressionMutator.mate` in
  `ExpressionTree/ExpressionMating.swift`, `Family.mate`, and the MCP
  tools `mate_genotypes` and `mate_family`.

## 4. MCP

The existing tools stay stateless. The family tools work on the families
open in windows: `list_families`, `read_family`, `breed_family`,
`reject_family_members` and `update_family_member` (see
[MCPServer.md](MCPServer.md#family-tools)).

## Where it lives

- `ExpressionTree/Family.swift`: `Family`, `Litter`, `Member`,
  breeding, rejecting, generations and the `family.json` coding.
- `ExpressionTree/FamilyLayout.swift`: the lineage view's layout, as
  frames for each member and litter plus connectors.
- `ExpressionTreeTests/FamilyTests.swift`.
- `Evolv.io/Family/FamilyDocument.swift`: the document, with undo.
- `Evolv.io/Family/FamilyWindowView.swift`: the lineage view and the
  settings popover.
- `Evolv.io/Family/FamilyThumbnails.swift`: the thumbnail cache.

## Phases

1. **Format and model** (done) in `ExpressionTree`: `Family`, `Litter`,
   `Member`, JSON coding, generation and band layout as pure functions,
   with tests (round-trip, reject rules, layout stability).
2. **Document** (done): `FamilyDocument`, the exported type, New/Open Family,
   undo for breed and reject. File > Open Genotype moved to Shift-Command-O
   and Save Genotype to Option-Command-S, since Command-O and Command-S
   now open and save families. A first cut of the lineage view came with
   it (`Evolv.io/Family/FamilyWindowView.swift`): layout, connectors,
   selection, breed, reject, star, collapse and an in-memory thumbnail
   cache.
3. **Lineage view** (done): layout, connectors, full-size vs chip cells,
   breeding from the selection, the thumbnail cache, the existing context
   menu. Remove the Random Grid window (its view code is now
   `GenotypeViews.swift`, and its depth stepper is the family settings
   popover). Thumbnails live in `Evolv.io/Family/FamilyThumbnails.swift`;
   only cells within half a screen of the visible area exist.
4. **Polish** (done): collapse branches, Show Path (Escape clears it),
   star/rename (names show on the thumbnail), Save to Library, Start
   Family From This (library sidebar context menu), and **Add Roots >
   Paste Genotype** for a copied expression, and **Add Roots > Open
   Genotype Files…** for `.evolvgenotype` files or images exported with
   their genotype (several at once make one root litter, each member named
   for its file). Each litter is outlined
   (`FamilyLayout.litterOutlines`).
5. **MCP family tools** and **mating** (done).

## Decisions

Andy, 2026-10-11:

1. Litters have **19** children, as in Sims' figures.
2. Families **replace the Random Grid window**; it goes once a family can
   start from a random litter.
3. Families are **plain documents** through the standard File menu: no
   Families folder, no sidebar listing. Maybe a launch window with recents
   one day.
4. Rejecting a member with descendants **offers to reject the whole
   branch**.
