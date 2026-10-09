CHOMP -- a neon maze muncher for PHOSPHOR
=========================================

Controls
  方向键 / Arrow keys   move
  Enter                 pause (the music pauses with it)
  Shift                 restart the run
  Esc                   host pause menu (the cart never sees it)

The maze is data
  game.lua writes only the LEFT HALF and mirrors it at load: the maze stays
  symmetric and there is half as much to hand-edit.  Characters:
    '#' wall   '.' dot   'o' power pellet   ' ' empty (both ends of row 9 are
  the tunnel: walk off one side and come out the other).
  The shipped maze was generated from a "corridor band" spec and flood-filled
  to prove every dot is reachable -- treat it as data and regenerate it if you
  change the bands.

Ghosts
  Four of them, four tempers: blinky chases, pinky cuts you off, inky swings
  around the flank, clyde keeps his distance.  A power pellet turns the tables
  for seven seconds -- eat them for 200/400/800/1600, and watch for the white
  blink when the timer is about to run out.

Modules
  game.lua    rules only (no input, no drawing, no audio, no save)
  main.lua    keys -> intents, and all drawing
  panel.lua   the sidebar (score / lives / ghost roster)
  sfx.lua     synthesized sound, music.lua a two-pattern A-minor loop
