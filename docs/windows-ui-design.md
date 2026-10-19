# Selected Windows UI direction

The user selected **C's visual style with A's Questlog-like content** from the
[original exploration](https://github.com/ph-cardoso/aion2dpsmeter/tree/67b84af8ecbc02cb476c990a6fce96dfceb0cd13/windows/prototype).
This decision settles the visual direction for PR #1.

## Composition

- Use C's near-black teal canvas (`#0b141a`), dark teal panels (`#131d24`),
  mint accent (`#78dbcc`), muted text, fine borders, compact type and 4–5 px
  panel/control corners.
- Use A's full labeled sidebar and grouped navigation on desktop. Collapse it
  only for narrow preview windows. Keep the profile and clear connection state.
- Start on A's overview: greeting, summary metrics, encounter card, party
  performance, upcoming events and quick actions.
- Keep A's companion hierarchy for combat, pet collection, overlay studio,
  fight history, event alerts and preferences; apply C's theme consistently.
- Use real connection/empty/error states when integrating the engine. Display
  sample data only in an explicit preview.

The [selected preview](../windows/prototype/README.md) is the visual reference.
The comparison controls and unused B/C content layouts have been removed;
the original alternatives remain accessible in Git history.

## Implementation boundary

The technology recommendation remains Tauri 2 + React + TypeScript + Vite for
the companion shell, the Rust daemon for capture, and an egui overlay host.
The [stack evaluation](windows-ui-stack.md) records migration boundaries and
the measurements required before replacing the current Windows frontend.

This selection update changes the preview and documentation. The current
Windows executable remains the existing Rust/egui implementation. Native
integration should carry this composition into the application and verify a
working live meter and detached overlay before expanding to the remaining
Questlog-like feature areas.
