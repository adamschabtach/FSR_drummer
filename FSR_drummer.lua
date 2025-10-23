-- HTTPS://NOR.THE-RN.INFO
-- FSR_drummer
-- >> k1: exit
-- >> k2:
-- >> k3: start/stop sequencer
-- >> e1:
-- >> e2:
-- >> e3:
-- >> grid: rows 1,3,5,7 = bit states; rows 2,4,6,8 = feedback taps

-- Constants
NUM_ROWS = 4      -- four instruments/shift registers
REGISTER_LENGTH = 16  -- length of each shift register

-- Shift register data structures
shift_registers = {}  -- holds the bit states for each row
feedback_taps = {}    -- holds feedback tap positions for each row

-- Clock/tempo
tempo = 120  -- BPM
step_division = 1/4  -- 16th notes (1/4 of a beat)
sequencer_clock_id = nil
running = false

-- Grid
g = grid.connect()
grid_dirty = true

-- MIDI settings
midi_device = nil
midi_channel = 1
midi_velocity = 100
-- MIDI note numbers for each instrument (standard GM drum mapping)
midi_notes = {
  36,  -- Instrument 1: Kick (C1)
  38,  -- Instrument 2: Snare (D1)
  42,  -- Instrument 3: Closed Hi-Hat (F#1)
  49   -- Instrument 4: Crash Cymbal (C#2)
}

function init() ------------------------------ init() is automatically called by norns
  -- Initialize parameters
  params:add_separator("FSR_drummer")

  -- Add crow output parameters for each instrument
  for i = 1, NUM_ROWS do
    params:add_separator("Instrument " .. i)

    params:add{
      type = "number",
      id = "crow_voltage_" .. i,
      name = "Crow " .. i .. " Voltage",
      min = 0,
      max = 10,
      default = 5,
      formatter = function(param) return param:get() .. "V" end,
      action = function() init_crow_outputs() end
    }

    params:add{
      type = "control",
      id = "crow_duration_" .. i,
      name = "Crow " .. i .. " Duration",
      controlspec = controlspec.new(0.01, 1.0, "lin", 0.01, 0.05, "s"),
      formatter = function(param) return string.format("%.2fs", param:get()) end,
      action = function() init_crow_outputs() end
    }

    params:add{
      type = "number",
      id = "midi_note_" .. i,
      name = "MIDI Note " .. i,
      min = 0,
      max = 127,
      default = midi_notes[i],
      formatter = function(param) return param:get() end
    }
  end

  params:add_separator("MIDI")

  params:add{
    type = "control",
    id = "midi_duration",
    name = "MIDI Duration",
    controlspec = controlspec.new(0.01, 1.0, "lin", 0.01, 0.05, "s"),
    formatter = function(param) return string.format("%.2fs", param:get()) end
  }

  -- Initialize shift registers
  for i = 1, NUM_ROWS do
    shift_registers[i] = {}
    feedback_taps[i] = {}
    for j = 1, REGISTER_LENGTH do
      shift_registers[i][j] = 0  -- all bits start at 0
      feedback_taps[i][j] = false  -- no feedback taps set initially
    end
  end

  message = "FSR_drummer" -------------------- set our initial message
  screen_dirty = true ------------------------ ensure we only redraw when something changes
  redraw_clock_id = clock.run(redraw_clock) -- create a "redraw_clock" and note the id

  -- Start the sequencer clock
  start_sequencer()

  -- Set up grid callbacks
  g.key = grid_key
  grid_redraw()

  -- Initialize crow outputs (outputs 1-4 for instruments 1-4)
  init_crow_outputs()

  -- Connect to MIDI device
  midi_device = midi.connect(1)  -- Connect to first MIDI device
end

function init_crow_outputs()
  for i = 1, 4 do
    local voltage = params:get("crow_voltage_" .. i)
    local duration = params:get("crow_duration_" .. i)
    crow.output[i].action = "{to(" .. voltage .. ",0), to(0," .. duration .. ")}"
  end
end

function sequencer_clock()
  while true do
    clock.sync(step_division)  -- sync to tempo-based clock divisions
    if running then
      step_sequencer()
    end
  end
end

function start_sequencer()
  if sequencer_clock_id then
    clock.cancel(sequencer_clock_id)
  end
  clock.tempo = tempo / 60  -- convert BPM to beats per second
  running = true
  sequencer_clock_id = clock.run(sequencer_clock)
end

function stop_sequencer()
  running = false
end

function calculate_feedback(row)
  -- Calculate XOR of all feedback tap positions for a given row
  local result = 0
  for i = 1, REGISTER_LENGTH do
    if feedback_taps[row][i] then
      result = result ~ shift_registers[row][i]  -- XOR operation
    end
  end
  return result
end

function shift_register(row)
  -- Check if rightmost bit is high (trigger condition)
  local trigger = shift_registers[row][REGISTER_LENGTH] == 1

  -- Shift all bits to the right
  for i = REGISTER_LENGTH, 2, -1 do
    shift_registers[row][i] = shift_registers[row][i - 1]
  end

  -- Calculate new input bit from feedback taps
  shift_registers[row][1] = calculate_feedback(row)

  return trigger
end

function step_sequencer()
  -- Step all shift registers and handle triggers
  for row = 1, NUM_ROWS do
    local trigger = shift_register(row)
    if trigger then
      send_trigger(row)
    end
  end
  screen_dirty = true  -- update display after step
  grid_dirty = true    -- update grid after step
end

function send_trigger(instrument)
  -- Send trigger via crow output
  crow.output[instrument].execute()

  -- Send MIDI note
  if midi_device then
    local midi_note = params:get("midi_note_" .. instrument)
    local midi_duration = params:get("midi_duration")
    midi_device:note_on(midi_note, midi_velocity, midi_channel)
    -- Schedule note off after the configured duration
    clock.run(function()
      clock.sleep(midi_duration)
      midi_device:note_off(midi_note, 0, midi_channel)
    end)
  end

  print("Trigger instrument " .. instrument)
end

-- Grid functions
function grid_key(x, y, z)
  if z == 1 then  -- key pressed
    -- Ensure we're within column bounds
    if x >= 1 and x <= REGISTER_LENGTH then
      -- Calculate which register (row pair) we're in
      -- y=1,2 -> register 1, y=3,4 -> register 2, etc.
      local register = math.ceil(y / 2)

      if register >= 1 and register <= NUM_ROWS then
        local is_feedback_row = (y % 2 == 0)  -- even rows are feedback taps

        if is_feedback_row then
          -- Toggle feedback tap
          feedback_taps[register][x] = not feedback_taps[register][x]
        else
          -- Toggle bit state
          shift_registers[register][x] = shift_registers[register][x] == 1 and 0 or 1
        end

        grid_dirty = true
        screen_dirty = true
      end
    end
  end
end

function grid_redraw()
  g:all(0)  -- clear grid

  for register = 1, NUM_ROWS do
    local bit_row = (register * 2) - 1      -- odd rows: 1, 3, 5, 7
    local feedback_row = register * 2        -- even rows: 2, 4, 6, 8

    for col = 1, REGISTER_LENGTH do
      -- Draw bit state in odd row
      local bit_brightness = shift_registers[register][col] == 1 and 15 or 0
      g:led(col, bit_row, bit_brightness)

      -- Draw feedback tap in even row
      local feedback_brightness = feedback_taps[register][col] and 8 or 0
      g:led(col, feedback_row, feedback_brightness)
    end
  end

  g:refresh()
  grid_dirty = false
end

function enc(e, d) --------------- enc() is automatically called by norns
  if e == 1 then turn(e, d) end -- turn encoder 1
  if e == 2 then turn(e, d) end -- turn encoder 2
  if e == 3 then turn(e, d) end -- turn encoder 3
  screen_dirty = true ------------ something changed
end

function turn(e, d) ----------------------------- an encoder has turned
  message = "encoder " .. e .. ", delta " .. d -- build a message
end

function key(k, z) ------------------ key() is automatically called by norns
  if k == 1 then return end --------- k1 is reserved for exit

  if k == 3 and z == 1 then
    running = not running  -- k3 to toggle start/stop
    screen_dirty = true
  end
end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if screen_dirty then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
    if grid_dirty then ------ only if grid changed
      grid_redraw() --------- redraw grid
    end
  end
end

function redraw() -------------- redraw() is automatically called by norns
  screen.clear() --------------- clear space
  screen.aa(0) ----------------- disable anti-aliasing for crisp pixels

  -- Draw title
  screen.level(15)
  screen.font_face(1)
  screen.font_size(8)
  screen.move(2, 8)
  screen.text("FSR_drummer")

  -- Draw tempo and status
  screen.move(80, 8)
  screen.text(tempo .. " BPM")

  -- Draw status indicator
  screen.move(2, 62)
  screen.level(8)
  screen.text(running and "RUNNING" or "STOPPED")

  -- Display shift registers
  local cell_width = 7
  local cell_height = 10
  local start_x = 4
  local start_y = 16
  local row_spacing = 12

  for row = 1, NUM_ROWS do
    local y = start_y + (row - 1) * row_spacing

    -- Draw row label
    screen.level(8)
    screen.move(0, y + 7)
    screen.text(row)

    -- Draw each bit in the shift register
    for col = 1, REGISTER_LENGTH do
      local x = start_x + (col - 1) * cell_width

      -- Determine brightness based on bit state and feedback tap
      if shift_registers[row][col] == 1 then
        if feedback_taps[row][col] then
          screen.level(8)  -- dimmer for feedback tap that's high
        else
          screen.level(15) -- bright for regular high bit
        end
        screen.rect(x, y, cell_width - 2, cell_height - 2)
        screen.fill()
      elseif feedback_taps[row][col] then
        screen.level(4)    -- very dim for feedback tap that's low
        screen.rect(x, y, cell_width - 2, cell_height - 2)
        screen.stroke()
      else
        screen.level(2)    -- outline for empty cells
        screen.rect(x, y, cell_width - 2, cell_height - 2)
        screen.stroke()
      end
    end
  end

  screen.update() -------------- update space
end


function r() ----------------------------- execute r() in the repl to quickly rerun this script
  norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
  if sequencer_clock_id then
    clock.cancel(sequencer_clock_id) -- stop the sequencer clock
  end

  -- Reset crow outputs to 0V
  for i = 1, 4 do
    crow.output[i].volts = 0
  end

  -- Send MIDI all notes off
  if midi_device then
    for i = 1, NUM_ROWS do
      midi_device:note_off(midi_notes[i], 0, midi_channel)
    end
  end
end