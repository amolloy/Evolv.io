# Mutation (asexual reproduction)

How `ExpressionMutator` makes a child genotype from one parent, and the
evidence from Sims' papers behind it. Mating (sexual reproduction) isn't
implemented yet. There's no UI; it's reached through the MCP
`mutate_genotype` tool (see [MCPServer.md](MCPServer.md)).

## What Sims says

1991 §4.2 and 1993 §2.1 say the same thing, almost word for word:

- Expressions "should often be only slightly modified, but sometimes
  significantly adjusted in structure and size."
- A **recursive scheme**: the tree is traversed and each node in turn is
  subject to possible mutation, with frequencies that depend on the kind of
  node.
- Seven kinds of mutation:
  1. Any node can become a new random expression.
  2. A scalar can have a random amount added.
  3. A vector can have random amounts added to each element.
  4. A function can become a different function, `(abs X)` to `(cos X)`,
     with its arguments "adjusted if necessary to the correct number and
     types".
  5. A node can become the argument of a new random function, the other
     arguments random: `X` to `(* X .3)`.
  6. An argument can jump out and replace its function: `(* X .3)` to `X`.
  7. A node can become a copy of another node of the parent:
     `(+ (abs X) (* Y .6))` to `(+ (abs (* Y .6)) (* Y .6))`.
- Shrinking should be **slightly more probable than growing**, so
  expressions don't drift toward large, slow forms; growth should come from
  selection.
- The overall mutation frequency is **scaled inversely to the parent's
  length**, so large parents stay stable.
- Offspring estimated to be **too slow** are thrown away and redrawn before
  the user sees them.
- Figure 5 (1991) and Figure 2 (1993) show a parent with **19 children**.

He gives no actual frequencies, no size for "a random amount" on an
expression constant, and no size for a mutation-1 subtree. For parameter
sets (1991 §3.2) he used a mutation chance of 0.2 and a flat ±0.4 on genes
normalised to 0 to 1, and suggested a Gaussian would be better.

## The scheme

```
mutate(parent):
    p = mutationsPerChild / nodeCount(parent)
    walk the tree from the root; at each node, with chance p:
        pick a kind by weight among those that apply to the node
        replace the node, and don't walk into the replacement
    otherwise walk into its arguments
    redraw if the child equals the parent or is over the size cap
```

- **`mutationsPerChild` is 1**, so a child averages one mutation whatever
  the parent's size. About a third of draws change nothing and are redrawn.
- **New material isn't mutated again** in the same child.
- **The root stays a call with arguments**, as the generator makes it, so a
  parent like `x` can only be wrapped or replaced, and a hoist or copy into
  the root can't pick one of the generator's excluded roots.
- **Types** follow the generator (see [RandomGeneration.md](RandomGeneration.md)):
  each node gets the type it actually returns (a literal's own, its node's
  `-> type`, or for untyped nodes vector if any untyped argument is), and a
  replacement in a typed slot has to fit it. New functions fit a slot by
  their declared output, as in the generator. Nodes the parent already
  passes "wrongly" (Figure 6's scalar `rotate-vector` vector) are left as
  they are unless they mutate.

## Each kind

| # | Kind | Applies to | What it does |
|---|---|---|---|
| 1 | `new-expression` | any node | `RandomExpressionGenerator.randomArgument` at the node's depth, so it thins out like first-generation material and respects `maxDepth`. At the root, a whole new genotype. |
| 2 | `adjust-scalar` | scalar | Adds a Gaussian with standard deviation 0.25 times the value's size (at least 0.5), rounded to 3 significant figures. |
| 3 | `adjust-vector` | vector | Adds a Gaussian with standard deviation 0.1 to each element, 3 significant figures. |
| 4 | `swap-function` | call with arguments | Any other function that fits the slot. Old arguments stay in their positions where they fit the new slot types; the rest are generated; extras are dropped. |
| 4 | `swap-variable` | variable | Another variable that fits (`x` to `y`). Mutation 4 for a function with no arguments. |
| 5 | `wrap` | any node | A function that fits the slot and has a slot of its own this node fits. The node goes in a random fitting slot, random terminals in the others. |
| 6 | `hoist` | call with arguments | One of its arguments that fits the slot. |
| 7 | `copy` | any node | Another node of the original parent (not the half-built child) that fits. |

**Constants.** Proportional Gaussian steps, as Andy chose (2026-10-03),
rather than Sims' flat ±d: Sims' published constants run from -31 to 24,
and a flat step big enough to move 15.5 would wreck 0.2. No clamping, since
his vectors include -0.14 and 1.06. Three significant figures, one more than
new constants get, so a small nudge to 1.86 isn't rounded away.

**Weights** (relative, among the kinds that apply):

| Node | new | adjust | swap | wrap | hoist | copy |
|---|---|---|---|---|---|---|
| call | 1 | | 3 | 1 | 2 | 1 |
| variable | 1 | | 2 | 1 | | 1 |
| literal | 1 | 5 | | 1 | | 1 |

Literals are mostly nudged: Sims' constants (15.5, 1.86, -31) look like the
sum of many small steps. Hoist outweighs wrap so shrinking wins slightly.
2,000 children of each of the six published figures (2026-10-03):

| wrap, hoist | Smaller | Bigger | Mean change |
|---|---|---|---|
| 1.5, 2 | 27% | 33% | -1.4 nodes |
| **1, 2** | **29%** | **28%** | **-1.7** |
| 1, 3 | 31% | 27% | -2.1 |

Tiny parents (`x`, `(abs x)`) can only grow, which is what lets evolution
start from them.

## Speed: a size cap

Sims' runtime estimate becomes a node-count cap for now: a child is redrawn
if it has more than twice the parent's nodes (but the cap is at least 200
and at most 1,000; a parent already over 1,000 can have children up to its
own size). Without the 1,000 ceiling, 100 generations of unselected random
picks reached nearly 1,000 nodes. A real cost table (the multi-tap `blur`,
`bump` and `color-grad` cost far more per node) can come later.

## Number printing

`GeneratedExpression.description` used to print every constant with two
significant figures, which was fine for generated constants but would have
silently rounded a parent's constants on every mutation (15.5 to 16, 1.86 to
1.9). It now prints the shortest exact form (`2`, `15.5`, `1.86`), and the
generator rounds new constants to two significant figures when it makes them.

## Where it lives

- `ExpressionTree/ExpressionMutator.swift`: `GeneratedExpression(parsing:)`
  (genotype text to tree), `nodeCount`, and `ExpressionMutator` with its
  `Configuration` and mutation log.
- `ExpressionTree/RandomExpressionGenerator.swift`: the generator, whose
  `randomArgument`, `randomCall` and `randomTerminal` the mutator reuses.
- `Evolv.io/MCP/MCPMutateTool.swift` and `MCPRenderGridTool.swift`.
- `ExpressionTreeTests/ExpressionMutatorTests.swift`.
