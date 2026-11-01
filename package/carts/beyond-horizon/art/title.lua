-- art/title.lua —— 标题画面、英文字标与标题文字槽位。
-- 只负责"画得像"：不读输入、不改状态；文字由程序按 slots 打印（中文走默认字体的中文回退）。
local U = require("art.util")

-- 标题背景 80x45：深空星场 + 下方半沉的事件视界与吸积盘。
-- 这是**确定性生成的静态图**（星点固定），不是每帧随机——同一块文字基线每帧一致。
local SCREEN = U.block{
  id = "title.screen",
  anchor = "top-left",
  art = [==[
                                         ,                                      
                                             '                                  
                                                                                
                             ,             '                                    
                                                           *                    
                                                      ,                         
                                                                                
                                                                                
                                                                                
                                        *                                       
                                        '                                       
                                                                                
                                                                                
                       ,                    *                                   
                                                '                               
                                                                                
                                                   '                            
                                                                                
                                                                        ,       
                                         ,                                '     
                                                                                
                    '             +                                       '     
                                                                        +       
                                                                            '   
   '                                           '                            '   
  ' '                                                                           
    *   ,                     '    '              '* ' '        *              +
                     ' +         *                                              
       '          +                              '                         '    
                               +                       *  '        ' ' ,        
    '           '  ,                  ,,,,,                                '    
             '                 *** ,,,,oOO,,,,==          ',  '             ,   
                    ,    ***  **  ,,OooO OOOO,,   ==== ===        ,             
    ,         '      ***        ,,Ooo       OOO,,   '    = ==        '          
                   '*           ,oo           OO,       '            '          
           *                   ,OO             OO,                              
          '            #=   =#,,o               O,, ==-            *            
    '           #==  ###=~~  =,oo               OO,-, ---  ---                  
           #== ##  =~~ ~= ~-- ,o                 O,--  --  ---  +---            
        #==# ' ~=~   --~-    ,,o                 O,,   -- --   --'   --         
       =#    ~~    -~~       ,oO                 OO,        --    -     --      
       =     ~    --         ,oo                 oO,    '  ' -     -,    -      
       =#    ~~   ,-~         ,o                 o,        ---    --    -       
         ==# * ~~= , -~,-~    ,o                 o,     ----   ---'  - --       
'      '   = ==#= *~== ~~~- -~,o                 o, --- -  ---  -- *--          
]==],
  colors = {
    ["O"] = "body",   -- 光子环亮部
    ["o"] = "ice",    -- 光子环暗部/辉光
    ["*"] = "body",   -- 亮星、远侧盘面高光
    ["+"] = "line",   -- 仪器刻点、星点
    ["'"] = "panel",  -- 远处暗星
    [","] = "panel",  -- 尘埃/环外辉光
    ["#"] = "warm",   -- 吸积盘内侧（唯一的暖色）
    ["="] = "ice",    -- 吸积盘主体
    ["~"] = "deep",   -- 盘面外缘/冷光
    ["-"] = "deep",   -- 盘面外缘（暗）
  },
  note = "80x45 标题背景；文字槽位见 title.slots",
}

-- 英文字标：BEYOND THE / EVENT HORIZON（5x3 像素字，两行）
local WORDMARK = U.block{
  id = "title.wordmark",
  anchor = "top-center",
  art = [==[
      ##. ### #.# .#. #.# ##.     ### #.# ###      
      #.# #.. #.# #.# ### #.#     .#. #.# #..      
      ##. ##. .#. #.# ### #.#     .#. ### ##.      
      #.# #.. .#. #.# ### #.#     .#. #.# #..      
      ##. ### .#. .#. #.# ##.     .#. #.# ###      
                                                   
### #.# ### #.# ###     #.# .#. ##. ### ### .#. #.#
#.. #.# #.. ### .#.     #.# #.# #.# .#. ..# #.# ###
##. #.# ##. ### .#.     ### #.# ##. .#. .#. #.# ###
#.. #.# #.. ### .#.     #.# #.# #.# .#. #.. #.# ###
### .#. ### #.# .#.     #.# .#. #.# ### ### .#. #.#
]==],
  colors = { ["#"] = "body" },
  note = "51x11 英文字标；# 可整体换成 ice/line 以降低存在感",
}

local T = {
  screen = SCREEN,
  wordmark = WORDMARK,

  -- 文本字段：程序按 lang 取用（本作中文为主，英文为副标题）
  zh = { text = "视界线外", scale = 3 },
  zh_sub = { text = "在黑洞边缘，没有人能替你决定" },
  en = { text = "BEYOND THE EVENT HORIZON", scale = 1 },
  en_sub = { text = "HORIZON-1  DEEP FIELD OBSERVATORY" },

  -- 文字槽位（屏幕坐标）：center 是中心列，程序用 phos.text.width/2 求左缘；
  -- scale 与 phos.screen.print 的末参同义（1..3）。
  slots = {
    zh = { y = 5, scale = 3, center = 40 },          -- 占 y..y+2 三行
    zh_sub = { y = 9, scale = 1, center = 40 },
    en_wordmark = { x = (80 - 51) // 2, y = 13 },    -- WORDMARK 左上角（水平居中）
    en_sub = { y = 26, scale = 1, center = 40 },
  },
  blocks = {},
}
T.blocks["title.screen"] = SCREEN
T.blocks["title.wordmark"] = WORDMARK
return T
