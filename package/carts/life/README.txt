LIFE - Conway's Game of Life
============================

A cellular automaton sandbox. The board is a torus (edges wrap around),
so gliders travel forever instead of dying against a wall.

Controls
--------
  arrows    move the cursor
  A         toggle the cell under the cursor
  B         stamp the selected pattern at the cursor
  Y         next pattern
  X         step one generation (while paused)
  ENTER     run / pause
  SHIFT     clear the board
  ESC       host pause menu

The machine has no gamepad: the four face buttons ARE the letters A/B/X/Y on
the keyboard, and the sidebar prints those same letters (it asks the host via
phos.input.key_name), so the hints cannot drift from the real mapping.

Music is a slow ambient loop (bpm 62, sine/triangle, long holds) in music.lua.

Files
-----
  manifest.lua        cart identity (id / entry / sidebar)
  main.lua            lifecycle glue: input -> board -> draw
  board.lua           rules (B3/S23) and grid state, no audio or save
  patterns.lua        pattern library reader
  panel.lua           sidebar rendering (read-only)
  assets/patterns.txt pattern data: [NAME] then rows of '#'/'.'

Why it is built this way
------------------------
board.lua never touches audio, save or input, so a mod can replace the
rules (e.g. HighLife B36/S23) by swapping one file.

The initial soup uses phos.sys.random; pass `--seed` to make a run
reproducible.
