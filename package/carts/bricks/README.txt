BRICKS - Breakout
=================

Break every brick in the wall (84 of them, six tiers worth 10..60 points)
without dropping the ball. Three lives, then level 2 starts with a faster
ball (x1.07 per level). High score is stored in the cart save file.

Controls
--------
  left/right  move the paddle
  A           launch the ball / restart after game over
  ENTER       pause / resume
  SHIFT       restart from level 1
  ESC         host pause menu

The machine has no gamepad: the four face buttons ARE the letters A/B/X/Y on
the keyboard, and both the sidebar and the centre prompts ask the host for the
real key name (phos.input.key_name), so what is printed is what you press.

Music is a four-section arcade loop (bpm 138, order A B A C A B D C, ~28s
before it repeats) in music.lua.

Files
-----
  manifest.lua   cart identity (id / entry / sidebar / save = true)
  main.lua       lifecycle glue: input -> game -> draw + sound
  game.lua       paddle, ball, bricks, levels. No audio, no save, no input
  panel.lua      sidebar rendering (read-only)
  sfx.lua        sound effects only (swap this file to retune the cart)
  music.lua      two-bar looping tune
  scores.lua     high score persistence

No randomness by design
-----------------------
There is no random number anywhere in this cart: the launch angle is
fixed and the ball moves on a fixed timestep, so an identical input
sequence always produces an identical score. That is what makes the
tests able to assert exact values ("score is 10 at frame 200").

The bottom status line (READY | PAD 24 | BALL 28,35 | SPD 21) is the
machine readout: it is drawn for players, and the test suite reads it
to verify paddle and ball state.

Testing note
------------
phos.input.pressed() is edge triggered. A test that presses a key twice
must release it in between:

    input 250 start down
    input 255 start up
    input 280 start down
