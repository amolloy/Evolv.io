# The `.evolvgenotype` format

A genotype is one expression the app can render: the entries in the
sidebar. Each lives in its own `.evolvgenotype` file, so adding, editing or
removing one never means editing Swift. (Node *definitions*, the operators an
expression calls, are a separate format: see
[EvolvNodeFormat.md](EvolvNodeFormat.md).)

Implementation: `ExpressionTree/GenotypeLibrary.swift` (parsing, scanning),
`Evolv.io/GenotypeStore.swift` (the app's live list),
`Evolv.io/MCP/MCPGenotypeTools.swift` (MCP tools).

## File shape

An optional header between two `---` lines, then the expression:

```
---
name: Figure 9
original_image: OriginalFigure9.gif
---
(round (log (+ y (color-grad (round (+ (abs (round
(log (+ y (color-grad (round (+ y (log (invert y) 15.5))
x) 3.1 1.86 #(0.95 0.7 0.59) 1.35)) 0.19) x)) (log (invert
y) 15.5)) x) 3.1 1.9 #(0.95 0.7 0.35) 1.35)) 0.19) x)
```

Without a header the whole file is the expression:

```
(mod X (abs Y))
```

- The header is a small YAML-like subset: one `key: value` per line, blank
  lines and `#` comments allowed, and a value may be wrapped in single or
  double quotes (needed only if it contains something like a leading `#`).
  No nesting, lists or multi-line values.
- `name` (optional): what the sidebar, window title and MCP tools show.
  Without one, the expression itself is shown.
- `original_image` (optional): a reference image this expression is trying to
  reproduce, shown beside the render in the Debug View. Looked up next to the
  genotype file first (so a user genotype can bring its own image), then in
  the app bundle's resources (where Sims' `OriginalFigure{9,10,12}.gif`
  live).
- The body is the expression in the usual s-expression syntax, trimmed of
  surrounding whitespace. Line breaks inside it are fine.
- An unknown header key is logged as a load issue and ignored; the file still
  loads. A header that never closes, a header line without a `:`, or an empty
  body is a load issue and the file is skipped.

The expression is not parsed at load time (a genotype may use a user node
that's broken or not written yet); a bad expression renders as a constant 0
with the parse error in the console, exactly as before. The MCP
`write_genotype` tool does parse it and reports a failure.

## Identity and ordering

A genotype's **id** is its file name without the extension (`11-figure-9`).
Ids are unique across the library: a user file with the same id as a bundled
one is a load issue and skipped, so the bundled one wins, as with nodes.

The sidebar lists bundled genotypes first, as one flat group, then user ones
under **My Genotypes**. User genotypes can sit in folders (and folders in
folders) inside the user Genotypes folder; the sidebar shows them as a
collapsible outline, folders first sorted by name the way Finder does, then
that folder's genotypes sorted by file name. The bundled files carry numeric
prefixes (`01-x`, ..., `13-figure-12`) only to keep their order; user files
can do the same if order matters. A folder doesn't change a genotype's id, so
two files with the same name in different folders still collide.

Folders are ordinary folders on disk: from the sidebar, a folder's context
menu creates, renames, moves or trashes folders, and dragging a genotype or
folder onto a folder (or using **Move To**) moves it. Dragging a
`.evolvgenotype` in from Finder copies it into that folder. Changes made in
Finder show up after **Reload Genotypes**.

## Where files live

- **Bundled**: `Evolv.io/Resources/BundledGenotypes/*.evolvgenotype`. Like
  `BundledNodes`, Xcode flattens these into the built app's
  `Contents/Resources/`; a new file here ships on the next build with no
  project-file edit.
- **User-editable**: `Genotypes/` beside the user `Nodes/` folder: the
  **Evolv.io** folder in iCloud Drive when iCloud is available (shared
  between Macs on the same Apple ID), otherwise the app's container
  Documents
  (`~/Library/Containers/com.amolloy.Evolv-io/Data/Documents/Genotypes/`),
  scanned recursively. The **Reveal Genotypes Folder** menu item opens it.
- **Reload Genotypes** (app menu) re-scans both without relaunching. The MCP
  `write_genotype`/`delete_genotype` tools reload automatically;
  `write_genotype` takes an optional `folder` and `list_genotypes` reports
  each user genotype's folder.

Load issues print to the console as `Genotype load issue (<file>): <message>`
and are returned by the MCP `list_genotypes` tool.
