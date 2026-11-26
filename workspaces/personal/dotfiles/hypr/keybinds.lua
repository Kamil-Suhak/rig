local terminal = "ghostty"
local fileManager = "ghostty -e yazi"
local menu = "~/.config/hypr/scripts/rofi-toggle.sh -show drun"

---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Core window & session actions
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal)) -- Open terminal (Ghostty)
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd(terminal)) -- Open terminal (Ghostty)
local closeWindowBind = hl.bind(mainMod .. " + X", hl.dsp.window.close()) -- Close active window
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager)) -- Open file manager (Yazi)
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" })) -- Toggle floating window
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu)) -- App launcher (Rofi)
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock")) -- Lock screen
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- Toggle pseudotile
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- Toggle split orientation (dwindle)

-- Apps & pickers
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("ghostty -e agy -c")) -- Resume latest Antigravity CLI session
hl.bind(mainMod .. " + CTRL + A", hl.dsp.exec_cmd("~/code/projects/rig/configs/bin/agy-picker")) -- Pick Antigravity CLI / ask session
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("~/code/projects/rig/configs/bin/workset-picker")) -- Pick workset (Enter: open, Alt+G: GitHub)
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("brave")) -- Open Brave browser
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("code")) -- Open VS Code (default profile)
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("obsidian")) -- Open Obsidian
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/code-picker.sh")) -- Pick VS Code profile
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("ghostty --class=com.spotatui.scratch -e spotatui")) -- Open Spotatui in scratchpad
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/quick-note.sh")) -- Quick-save raw Obsidian note
hl.bind(mainMod .. " + CTRL + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/note-picker.sh")) -- Pick raw Obsidian note
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("~/.config/hypr/scripts/keybinds-help.sh")) -- Show keybinds helper
hl.window_rule({ name = "spotatui-scratch", workspace = "special:magic", match = { class = "^(com\\.spotatui\\.scratch)$" } })

-- Power menu
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/powermenu.sh")) -- Power menu (Lock/Suspend/Logout/Reboot/Shutdown)

-- Screenshots & clipboard
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh")) -- Area screenshot (save + copy path & image)
hl.bind(mainMod .. " + CTRL + SHIFT + S", hl.dsp.exec_cmd("mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" - | satty -f - --output-filename ~/Pictures/Screenshots/screenshot-$(date +%Y%m%d-%H%M%S).png")) -- Area screenshot + annotate in Satty
hl.window_rule({ name = "float-satty", float = true, match = { class = "^(com\\.gabm\\.satty)$" } })
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("ghostty --class=com.clipse.float -e clipse")) -- Clipboard history (Clipse)
hl.window_rule({ name = "float-clipse", float = true, match = { class = "^(com\\.clipse\\.float)$" } })
hl.window_rule({ name = "float-pavucontrol", float = true, size = "780 520", center = true, match = { class = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol)$" } })
hl.window_rule({ name = "float-audio-tui", float = true, size = "780 500", center = true, match = { class = "^(com\\.audio\\.tui)$" } })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" })) -- Focus window left
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" })) -- Focus window right
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" })) -- Focus window up
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" })) -- Focus window down

-- Swap two windows in active workspace
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.swap({ direction = "left" })) -- Swap window left
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "right" })) -- Swap window right
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.swap({ direction = "up" })) -- Swap window up
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.swap({ direction = "down" })) -- Swap window down

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + Q",       hl.dsp.workspace.toggle_special("magic")) -- Toggle scratchpad workspace
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.move({ workspace = "special:magic" })) -- Move window to scratchpad

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" })) -- Next workspace
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" })) -- Previous workspace

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true }) -- Drag window (LMB)
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- Resize window (RMB)

-- Floating TUI windows
hl.window_rule({ name = "float-bluetui", float = true, match = { class = "^(com\\.bluetui\\.float)$" } })

-- Laptop multimedia keys for volume and LCD brightness (with swayosd OSD)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("swayosd-client --output-volume raise"),       { locked = true, repeating = true }) -- Volume up
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("swayosd-client --output-volume lower"),       { locked = true, repeating = true }) -- Volume down
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true, repeating = true }) -- Mute audio
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("swayosd-client --input-volume mute-toggle"),  { locked = true, repeating = true }) -- Mute microphone
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("swayosd-client --brightness raise"),          { locked = true, repeating = true }) -- Brightness up
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"),          { locked = true, repeating = true }) -- Brightness down

-- Clamshell / lid switch handling
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/scripts/lid-switch.sh close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/lid-switch.sh open"),  { locked = true })

-- Media playback
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true }) -- Next track
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- Play/pause media
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true }) -- Play/pause media
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true }) -- Previous track
