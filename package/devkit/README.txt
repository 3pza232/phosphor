PHOSPHOR DevKit
===============

Tools for making cartridges. Nothing here is required to run the console --
it is for cartridge authors (human or agent).


1. TEMPLATE  -- devkit/template/
--------------------------------
A minimal, commented cartridge skeleton. Create one straight from the CLI --
a directory name is all it needs:

    phosphor.exe --new carts/mygame

The id and the title default to that name; edit manifest.lua for the rest
(author / desc / icon / sidebar / save) -- changes take effect at once.

Then start with game.lua (your rules: no input, no drawing, no audio, no save)
and main.lua (read keys -> call the rules -> draw). Run it directly:

    phosphor.exe --cart carts/mygame

Or drop the folder into carts/ and pick it from the shelf. When done, pack it:

    phosphor.exe --pack carts/mygame            (produces dist/mygame.phos)


2. EDITOR SUPPORT  -- devkit/phos.lua
-------------------------------------
Type definitions for the whole phos.* API (EmmyLua / Lua Language Server).
Add it to your cartridge workspace so you get completion and parameter hints.
VSCode: create .luarc.json next to your cart:

    {
      "workspace.library": ["../devkit/phos.lua"],
      "runtime.version": "Lua 5.4"
    }

Keep it honest -- the console can check the annotations against the real API:

    phosphor.exe --check-api        (exit 0 = consistent, 2 = drift)


3. CONTROL CHANNEL  -- for automated testing and agents
-------------------------------------------------------
Start the console with a control port open:

    phosphor.exe --cart carts/mygame --control 7654

Then talk newline-delimited JSON over 127.0.0.1:7654:

    {"id":1,"cmd":"state.query"}
    {"id":2,"cmd":"screen.read"}
    {"id":3,"cmd":"input.inject","key":"right","frames":5}
    {"id":4,"cmd":"time.step","frames":60}     <- advance exactly 60 logic frames
    {"id":5,"cmd":"cart.reload"}               <- hot reload after editing code

Commands: ping / state.query / screen.read / screenshot / carts.scan /
          input.inject / input.text / input.clear / time.step / time.resume /
          save.export / save.import / cart.load / cart.reload / cart.eject / quit
          (full parameter list: docs/agent-interface.md)

A one-shot alternative without the channel:

    phosphor.exe --cart carts/mygame --headless --frames 300 --dump-screen


References
----------
  docs/api-reference.md      every phos.* call
  docs/cart-format.md        manifest fields, lifecycle, sandbox
  docs/agent-interface.md    CLI + control channel protocol
  carts/snake/               a worked multi-file example (6 modules)
