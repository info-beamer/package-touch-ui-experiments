gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

util.no_globals()

local HORIZONTAL_SCALE, VERTICAL_SCALE = 1, 1
local HORIZONTAL_OFFSET, VERTICAL_OFFSET = 0, 0
local red = resource.create_colored_texture(1,0,0,1)
local green = resource.create_colored_texture(0,1,0,1)
local blue = resource.create_colored_texture(0,0,1,1)
local white = resource.create_colored_texture(1,1,1,1)

local font = resource.load_font "font.ttf"
local json = require "json"
local layout = require "layout"

util.json_watch('config.json', function(config)
    HORIZONTAL_SCALE = WIDTH / config.HORIZONTAL_MAX
    VERTICAL_SCALE = HEIGHT / config.VERTICAL_MAX
    HORIZONTAL_OFFSET = config.HORIZONTAL_OFFSET
    VERTICAL_OFFSET = config.VERTICAL_OFFSET
end)

local function centered(font, x1, x2, y, text, size, r,g,b,a)
    local w = font:width(text, size)
    return font:write((x1+x2-w)/2, y, text, size, r,g,b,a)
end

local function clamp(min, max, v)
    return math.max(min, math.min(max, v))
end

local function label(ui, state, x1, y1, x2, y2)
    font:write(x1, y1, state.text, y2-y1, 1,1,1,1)
    return state
end

local function button(ui, state, x1, y1, x2, y2)
    state = ui.get_state(state)

    local mode = state.mode or "off_touched"

    local touched = ui.touched(x1, y1, x2, y2)
    local outside_touched = ui.outside_touched(x1, y1, x2, y2)
    if mode == "off_touched" and not touched then
        mode = "off"
    elseif mode == "off" and touched then
        mode = "on_touched"
    elseif mode == "on_touched" and outside_touched then
        mode = "off_touched"
    elseif mode == "on_touched" and not touched then
        mode = "on"
    elseif mode == "on" then
        mode = "off_touched"
    end

    if mode == "on" then
        blue:draw(x1, y1, x2, y2)
    elseif mode == "on_touched" then
        green:draw(x1, y1, x2, y2)
    else
        red:draw(x1, y1, x2, y2)
    end
    white:draw(x1+3, y1+3, x2-3, y2-3, .5)

    centered(font, x1, x2, y1+5, state.text, y2-y1-10, 1,1,1,1)

    state.mode = mode
    state.clicked = mode == "on"
    return state
end

local function slider(ui, state, x1, y1, x2, y2)
    state = ui.get_state(state)
    local w = x2 - x1
    local cy = y1 + (y2 - y1) / 2

    local value = state.value or 0
    local mode = state.mode or "idle"
    local before = value

    if mode == "idle" and ui.touched(x1, y1, x2, y2) then
        mode = "change"
    elseif mode == "change" and not ui.touched() then
        mode = "idle"
    end

    if mode == "change" then
        local x, y = ui.touch_pos()
        value = clamp(0, 1, (x - x1) / w)
    end

    white:draw(x1, cy-2, x2, cy+2)
    local x = x1 + w * value
    white:draw(x-3, y1, x+3, y2, .5)

    state.mode = mode
    state.value = value
    state.changed = value ~= before
    return state
end

local function touch_confirm(ui, state, x1, y1, x2, y2)
    state = ui.get_state(state)
            
    local touch_time = state.touch_time or 1
    local mode = state.mode or "off_touched"

    local touched = ui.touched(x1, y1, x2, y2)
    if mode == "off_touched" and not touched then
        mode = "off"
    elseif mode == "on_touched" and not touched then
        mode = "on"
    elseif mode == "on" and touched then
        mode = "off"
    elseif mode == "off" and touched then
        mode = "activating"
        state.touch_start = sys.now()
    elseif mode == "activating" and not touched then
        mode = "off_touched"
        state.touch_start = nil
    end

    local progress = 0
    if mode == "activating" then
        progress = math.min(1, (sys.now() - state.touch_start) / touch_time)
        if progress == 1 then
            mode = "on_touched"
        end
    end

    if mode == "on" or mode == "on_touched" then
        blue:draw(x1, y1, x2, y2)
    elseif mode == "activating" then
        local w = x2-x1
        local p = x1 + w * progress
        green:draw(x1, y1, p, y2)
        red:draw(p, y1, x2, y2)
    else
        red:draw(x1, y1, x2, y2)
    end
    white:draw(x1+3, y1+3, x2-3, y2-3, .5)

    centered(font, x1, x2, y1+5, state.text, y2-y1-10, 1,1,1,1)

    state.mode = mode
    state.is_on = mode == "on" or mode == "on_touched"
    state.is_activating = mode == "activating"
    state.is_off = mode == "off" or mode == "off_touched"
    return state
end

local function UI(opt)
    local touch_down, touch_x, touch_y = false, 0, 0

    local function input_state(next_touch_down, next_touch_x, next_touch_y)
        touch_down = next_touch_down
        touch_x = next_touch_x
        touch_y = next_touch_y
    end

    local function is_over(x1, y1, x2, y2)
        return touch_x >= x1 and touch_x <= x2 and touch_y >= y1 and touch_y <= y2
    end

    local function outside_touched(x1, y1, x2, y2)
        return touch_down and not is_over(x1, y1, x2, y2)
    end

    local function touched(x1, y1, x2, y2)
        if x1 and y1 and x2 and y2 then
            return touch_down and is_over(x1, y1, x2, y2)
        else
            return touch_down
        end
    end

    local function touch_pos()
        return touch_x, touch_y
    end

    local persistent_state = {}

    local function get_state(state)
        if state.id then
            if persistent_state[state.id] then
                state = persistent_state[state.id]
            else
                persistent_state[state.id] = state
            end
        end
        return state
    end

    local exports = {
        get_state = get_state;

        touched = touched;
        outside_touched = outside_touched;
        touch_pos = touch_pos;
    }

    local function wrapped(ui_fn)
        return function(...)
            return ui_fn(exports, ...)
        end
    end

    -- coroutine based continuos UI
    local co = coroutine.wrap(opt.entry)

    local function loop()
        coroutine.yield()
        return true
    end

    return {
        run = co;
        loop = loop;

        input_state = input_state;

        touch_confirm = wrapped(touch_confirm);
        button = wrapped(button);
        label = wrapped(label);
        slider = wrapped(slider);
    }
end


-- Input sourcing
local input_state = { down = false, x = 0, y = 0, }
util.data_mapper{
    input = function(raw)
        input_state = json.decode(raw)
        input_state.x = (input_state.x - HORIZONTAL_OFFSET) * HORIZONTAL_SCALE
        input_state.y = (input_state.y - VERTICAL_OFFSET) * VERTICAL_SCALE
    end
}

-- The interface!
local ui, sub_menu1, sub_menu2, main_menu, confirm_dialog

function confirm_dialog(text)
    local yes = {
        text = "Yes";
        touch_time = 0.33;
    }
    local no = {
        text = "No";
        touch_time = 0.33;
    }
    while ui.loop() do
        white:draw(30, 30, WIDTH-30, HEIGHT-30, .8)

        ui.label({text = text}, 100, 100, WIDTH-100, 130)

        if ui.touch_confirm(yes, 200, 300, 350, 350).is_on then
            return true
        end
        if ui.touch_confirm(no, 450, 300, 600, 350).is_on then
            return false
        end
    end
end

local background = resource.load_image "background.jpg"
local enable_foo = false
local background_alpha = { value = 0.5 }

local function header()
    if ui.button({id='tab_1', text = "menu1"}, 400, 20, 600, 60).clicked then
        return sub_menu1
    end
    if ui.button({id='tab_2', text = "menu2"}, 620, 20, 790, 60).clicked then
        return sub_menu2
    end
end

function sub_menu1()
    local feature_off = {
        text = "activate 'foo'";
    }
    local feature_on = {
        text = "deactivate 'foo'";
    }
    local back = {
        text = "back";
        touch_time = 0.2;
    }
    while ui.loop() do
        local selected = header()
        if selected then
            return selected()
        end

        ui.label({text = "Menu 1"}, layout.row(760, 20))

        if not enable_foo then
            if ui.button(feature_off, layout.row(400, 50)).clicked then
                if confirm_dialog("Really?") then
                    enable_foo = true
                end
            end
        else
            if ui.button(feature_on, layout.row(400, 50)).clicked then
                enable_foo = false
            end
        end

        if ui.button(back, layout.row(400, 100)).clicked then
            return main_menu()
        end

        local x = 650 + math.floor(math.sin(sys.now()*4)*50)
        local y = 350 + math.floor(math.cos(sys.now()*4)*50)

        if ui.button({id='next', text = "2 >>"}, x, y, x+80, y+60).clicked then
            return sub_menu2()
        end
    end
end

function sub_menu2()
    local back = {}
    for i = 1,5 do
        back[i] = {
            text = string.format("back to main %d", i);
            touch_time = 0.5;
        }
    end
    while ui.loop() do
        local selected = header()
        if selected then
            return selected()
        end

        ui.label({text = "Menu 2"}, layout.row(760, 20))

        for i = 1,5 do
            if ui.touch_confirm(back[i], layout.row(400, 60)).is_on then
                return main_menu()
            end
        end

        if ui.button({id='prev', text = "1 <<"}, 700, 400, 780, 460).clicked then
            return sub_menu1()
        end
    end
end

function main_menu()
    local menu1 = {
        text = "menu1";
    }
    local menu2 = {
        text = "menu2";
    }
    local btn = {
        text = "toggle";
    }
    while ui.loop() do
        if ui.button(menu1, layout.row(300, 50)).clicked then
            return sub_menu1()
        end
        if ui.button(menu2, layout.row(300, 50)).clicked then
            return sub_menu2()
        end

        ui.label({
            text = enable_foo and "Setting 'foo' enabled" or "Setting 'foo' disabled"
        }, layout.row(760, 20))
        
        if ui.button(btn, layout.row(400, 100)).clicked then
            enable_foo = not enable_foo
        end

        if enable_foo then
            if ui.slider(background_alpha, layout.row(400, 40)).changed then
                print("background alpha updated", background_alpha.value)
            end

            ui.label({
                text = string.format("Background alpha: %.2f", background_alpha.value)
            }, layout.row(760, 20))
        end
    end
end

ui = UI{
    entry = main_menu;
}

function node.render()
    gl.clear(0,0,0,1)
    background:draw(0, 0, WIDTH, HEIGHT, background_alpha.value)

    layout.reset(20, 20, 20, 10)

    ui.input_state(input_state.down, input_state.x, input_state.y)
    ui.label({text = "info-beamer touch UI experiment"}, layout.row(760, 20))
    ui.run()
end
