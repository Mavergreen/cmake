# Release notes

The generator (`release-notes.sh`, from shipyard) writes the notes file for every release: the title, a
"What changed" section (with a link to Kitware's notes for a new upstream), a "Build ingredients"
section when a pin moved, and the footer. That one file, `dist/RELEASE_NOTES.md`, becomes the GitHub
Release body and the Sparkle feed's (`cmake.xml`) `<description>`: the same bytes, read twice.

A file here named `<full-version>.md` (e.g. `4.4.4-mavericks.1.md`) is OPTIONAL hand-written prose
for that one release. When present, it is inserted verbatim right after the generated title. It must
NOT start with its own `## ` heading, since the generator already emits the title.

Most releases have no file here, and that's fine: the generator's own sections are the whole note.
