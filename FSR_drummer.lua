-- HTTPS://NOR.THE-RN.INFO
-- FSR_drummer
-- >> k1: exit
-- >> k2:
-- >> k3:
-- >> e1:
-- >> e2:
-- >> e3:

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

function init() ------------------------------ init() is automatically called by norns
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
end

function send_trigger(instrument)
  -- Placeholder for MIDI/crow trigger output
  -- TODO: implement MIDI and crow output
  print("Trigger instrument " .. instrument)
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
  if z == 0 then return end --------- do nothing when you release a key
  if k == 2 then press_down(2) end -- but press_down(2)
  if k == 3 then press_down(3) end -- and press_down(3)
  screen_dirty = true --------------- something changed
end

function press_down(i) ---------- a key has been pressed
  message = "press down " .. i -- build a message
end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if screen_dirty then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
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
  screen.move(100, 8)
  screen.text(tempo .. " BPM")

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
end