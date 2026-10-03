# Random expression generation

How `RandomExpressionGenerator` builds first-generation genotypes, and the
evidence from Sims' papers behind it.

## What Sims says

Everything he says about generation is one paragraph, repeated almost word
for word in 1991 §4.1 and 1993 §2:

- Pick a function at random from the function set, then generate as many
  random arguments as it needs.
- Each argument is one of four forms: a random scalar (`.4`), a random
  3-vector (`#(.42 .23 .69)`), a variable (`X`, `Y`), or another random
  expression, generated recursively.
- The initial population is "simple" random expressions.
- Functions coerce their arguments to the types they need, or behave
  differently depending on the types they get. "Arguments to certain
  functions can optionally be restricted to some subset of the available
  types."

He says nothing about depth limits, constant ranges, per-function weights
or how often each form is picked. Mutation 4 (function to function) says
the arguments "are also adjusted if necessary to the correct number and
types", so each argument has a *correct type* that the system knows. That
sentence and the "restricted to some subset" one are the paper's support
for per-argument type annotations. Nothing in either paper suggests
per-function probability weights.

## The tally

I parsed every published texture genotype (1991: Figures 4c to 4i, 5, 6,
7, 8, 9, 10, 12 and 13; 1993: Figures 6 and 7) and recorded, for every
argument slot, whether the value passed was scalar or vector and whether
it was a literal, a variable or a sub-expression. A sub-expression's type
is the node's output type: noise and `bw` nodes give scalars; colour
noise, `hsv-to-rgb`, `color-grad`, `bump`, `rotate-vector` and `vector`
give vectors; arithmetic gives a vector if any argument is a vector. The
3D shape and dynamical-system genotypes use other function sets, so they
are left out.

For the slots that have an obvious preferred type (below), **146 of 150
arguments are already that type**. The one argument of unknown type (an
`ifs` fed to `hsv-to-rgb`) is excluded. The four exceptions:

- `dissolve`'s weight gets a vector twice (Figure 8's `image`, and a
  vector sub-expression).
- `rotate-vector` gets a scalar as the vector to rotate in Figure 6, and `x` as its axis in
  Figure 10.

Every other annotated slot is 100%:

| Node | Slot types (s = scalar, v = vector, · = either) | Args matching |
|---|---|---|
| `color-grad` | · s s v s | 20/20 |
| `bump` | · · s v v s s s | 36/36 |
| `bw-noise`, `color-noise` | s s | 6/6 |
| `warped-bw-noise`, `warped-color-noise` | · · s s | 26/26 |
| `grad-direction` | · s s | 4/4 |
| `blur` | · s | 3/3 |
| `vector` | s s s | 24/24 |
| `hsv-to-rgb` | v | 4/4 |
| `dissolve` | · · s | 19/21 |
| `rotate-vector` | v s v | 4/6 |

Two more patterns came out:

- **Parameter-like slots are nearly always literals**: 115 of 151
  annotated arguments are literal constants. The rest are mostly Figure
  7's `(dissolve a b time)` animation wrappers. `color-grad`'s p1, p2,
  colour and p3 are literal in all 20 cases. Signal slots (`source`,
  warped `u`/`v`, arithmetic operands) are the ones that get variables
  and sub-expressions.
- **Some slots are really mixed**, so they should stay untyped:
  `bump`'s multiplier (3 vectors, 3 scalars), warped noise `v` (7
  vectors, 6 scalars), and `log`'s base (6 scalars, 6 vectors).

Constant ranges, by eye: vector components are almost all in 0 to 1 (the
exceptions are -0.09, -0.14, 1.06). Scalars run from -31 to 23.9, mostly
0 to 16, and depend a lot on the slot: noise frequencies are 0.02 to 0.2,
light heights 0.9 to 12.

## Preferred types in `.evolvnode`

Extend the existing `name: role` param syntax (today only `fn` and
`value`) so the part after the colon can also name a type, and add an
optional output type:

```
node "color-grad"(source: fn, p1: scalar, p2: scalar, color: vector, p3: scalar) -> vector requires(lighting) { ... }
node "bw-noise"(e0: scalar, e1: scalar) -> scalar requires(perlin, octaves) { ... }
node "hsv-to-rgb"(hsv: vector) -> vector { ... }
node "+"(v0, v1) { ... }
node "x"() -> scalar { ... }
```

- Param: `name`, `name: fn`, `name: scalar`, `name: vector`,
  `name: fn scalar`, and so on. No type means either type is fine.
- Output: `-> scalar`, `-> vector`, or nothing. Nothing means the node
  follows its untyped arguments: vector if any of them is vector,
  otherwise scalar. That covers all the arithmetic nodes, `dissolve`,
  `if`, `blur`, `round`, `log` and the rest with no annotation.
- It's a hint for the generator only. Codegen doesn't change: every
  child is still a `float3`, and coercion stays as it is now (averaging a
  vector into a scalar slot, broadcasting a scalar into a vector slot).
  Hand-written and published genotypes that break the preference keep
  working exactly as they do now.
- Plumbing: `DSLParam` gets a `preferredType` field, `DSLTemplate` gets
  an `outputType`, and `NodeRegistry` exposes a signature (name, arity,
  arg types, output type) next to each constructor so a generator can
  look it up without building a node.

Types for the bundled nodes, from the table plus what each node does:

- scalar in: noise frequencies and octaves, warped `e2`/`e3`,
  `color-grad` p1/p2/p3, `bump` strength/dirX/dirY/lightHeight,
  `grad-direction` dirs, `blur` radius, `rotate-vector` angle,
  `dissolve` weight
- vector in: `color-grad` color, `bump` color1/color2, `hsv-to-rgb`,
  `rotate-vector` v and axis
- scalar out: `x`, `y`, `z`, `bw-noise`, `warped-bw-noise`,
  `grad-direction`
- vector out: `color-noise`, `warped-color-noise`, `hsv-to-rgb`,
  `color-grad`, `color-grad-curvature`, `bump`, `rotate-vector`
- everything else untyped

## The generator

A direct reading of Sims' paragraph, with the preferred type as the
only addition:

```
randomExpression(depth):
    f = uniform pick from the function set (every node with arity > 0)
    return (f, [randomArgument(t, depth + 1) for t in f.argTypes])

randomArgument(type, depth):
    forms = allowed forms for type:
        scalar -> scalar literal, variable, expression
        vector -> vector literal, vector variable, expression
        any    -> scalar literal, vector literal, variable, expression
    if depth >= maxDepth: drop "expression"
    form = "expression" at pExpr(depth), otherwise a weighted pick from
           the other forms (terminalWeights)
    expression -> randomExpression(depth), with f limited to nodes whose
                  output fits the type (-> scalar, -> vector or untyped)
```

- **The root is always a function**, since Sims says to start by picking
  a function. That rules out a bare `x` or `.4` as a whole genotype.
- **Some nodes are never the root.** `excludedRootFunctions` lists
  node names the root call can't be, though they can appear anywhere
  below it. The app reads it from the `randomExcludedRootNodes` user
  default (an array of node names, no UI; set it with `defaults write`),
  defaulting to `constant`, `triplet-constant` and `vector`
  (2026-10-01). A whole genotype that's a flat value or a `vector` of
  three sub-expressions isn't interesting. The two literals can't be a
  root anyway, since the root is always a call; they're listed so the
  setting says what's meant.
- **Every node with no arguments is a variable.** Taking no arguments
  makes a node a terminal by definition, so the generator treats every
  such node as the "variable" form, including user-written ones, and
  never as a function (2026-10-01). A variable fits a slot by its output
  type, like a function: `x` and `y` are `-> scalar`, so they never land
  in a vector slot, but a user's `-> vector` no-argument node can.
  `excludedVariables` (the `randomExcludedVariables` user default, no
  UI) leaves some out, defaulting to `z`, which is only for volume
  textures. A node author who wants a no-argument node picked like a
  function instead (a plain random-number node, say) writes
  `nonconst` after its output type; see EvolvNodeFormat.md.
- **"Simple"** was first read as `maxDepth = 2` (two levels of calls:
  the root's arguments can be calls, theirs are leaves), about the size
  of Figure 4's examples. In the app those first generations looked too
  plain. With a Depth control in the grid window's toolbar, the deepest
  setting tried (10) gave the best results, so that's the default
  (2026-09-29). The paper gives no numbers, so these are knobs on
  `RandomExpressionGenerator.Configuration`.
- **`pExpr` falls with depth.** It started as a flat 0.3, which gave a
  lot of solid-colour genotypes: in 5,000 of them, 23% had no `x` or `y`
  anywhere, and the median tree had 6 nodes while the biggest had 1,370.
  Now it's 0.9 for the root's arguments and halves at each level below
  (`expressionProbability`, `expressionProbabilityDecay`), so trees are
  bushy near the top and end in literals and variables (2026-10-01).
  Same 5,000 seeds:

  | pExpr, decay | No `x`/`y` | Median nodes | 99th percentile | Max |
  |---|---|---|---|---|
  | 0.3, 1 (old) | 23% | 6 | 546 | 1,370 |
  | 0.5, 0.7 | 17% | 11 | 215 | 500 |
  | 0.8, 0.5 | 10% | 19 | 268 | 486 |
  | 0.9, 0.5 | 7% | 25 | 334 | 560 |
  | 1.0, 0.4 | 6% | 22 | 290 | 432 |
- **Terminals are picked in a second step, favouring variables.** Once
  an argument isn't a sub-expression, `randomTerminal` picks a scalar
  literal, vector literal or variable among those the slot's type
  allows, by `terminalWeights` (scalar 1, vector 1, variable 3). Before,
  the pick was uniform, so 60% of terminals were constants. A vector
  slot gets a vector literal, or a variable whose output is a vector.
  With pExpr 0.9 halving, over
  5,000 genotypes (2026-10-01):

  | Variable weight | No `x`/`y` | Terminals that are variables |
  |---|---|---|
  | 1 (uniform) | 7.7% | 40% |
  | 2 | 4.1% | 56% |
  | **3** | **2.7%** | **65%** |
  | 5 | 1.8% | 74% |

  Tree sizes barely change with the weight.
- **Constants**: scalar literals uniform in -1 to 1, vector components
  uniform in 0 to 1, rounded to two significant figures to match the
  papers. They're rounded when they're made; `description` prints exactly,
  so genotype text read back for mutation keeps its constants (see
  [Mutation.md](Mutation.md)). Sims' larger scalars (10.7, 15.5, -31) most likely came from
  mutation adding up over generations, so there's no need to generate
  them directly.
- **No per-node weights**, because Sims never mentions them. An untyped
  expression slot picks uniformly from the whole function set, and a
  typed one picks uniformly from the nodes that fit.
- **Untyped nodes can return either type**, and the generator doesn't
  try to steer them. If an untyped node lands in a vector slot and
  happens to return a scalar, coercion handles it. The 146/150 figure
  says that matching the preferred type at the literal and typed-node
  level is what matters.
- **Seeded RNG**, so a population can be regenerated from its seed for
  tests and bug reports.
- **Speed**: Sims threw away expressions he estimated would be too slow
  (1991 §4.2). A cost check can come later if the multi-tap nodes
  (`blur`, `bump`, `color-grad`) make first generations slow.

## Decisions

Andy agreed with the defaults on 2026-09-29:

1. `bump`'s multiplier and warped noise `u`/`v` stay untyped, as the data
   suggests.
2. One global scalar range (-1 to 1), no per-slot ranges.
3. Scalar slots can still get sub-expressions, at `pExpr`, as the paper
   allows.

## Where it lives

- `ExpressionTree/DSL/DSLParser.swift`: parses `name: scalar`,
  `name: fn vector` and `-> scalar`/`-> vector`.
- `ExpressionTree/NodeSignature.swift`: `NodeValueType` and
  `NodeSignature` (arity, argument types, output type).
- `DSLLibrary.scanWithSignatures` and `NodeRegistry.shared.signatures`:
  a signature for every DSL node.
- `ExpressionTree/RandomExpressionGenerator.swift`: the generator,
  `GeneratedExpression` (its `description` is genotype text `Parser`
  reads), and `SeededRandomNumberGenerator`.
- `ExpressionTreeTests/RandomExpressionGeneratorTests.swift`.
