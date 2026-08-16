-- Creates a disposable Sample Player smoke project in a new REAPER project tab.
-- Import the generated WAV through Choose Sample, then press Play.

local function u16le(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32le(value)
  return string.char(
    value % 256,
    math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256
  )
end

local function pcm16le(value)
  if value < 0 then value = value + 65536 end
  return u16le(value)
end

local function write_test_wav(path)
  local sample_rate = 48000
  local frame_count = 24000
  local data_bytes = frame_count * 2
  local file, open_error = io.open(path, "wb")
  if not file then return false, open_error end

  file:write("RIFF", u32le(36 + data_bytes), "WAVE")
  file:write("fmt ", u32le(16), u16le(1), u16le(1))
  file:write(u32le(sample_rate), u32le(sample_rate * 2), u16le(2), u16le(16))
  file:write("data", u32le(data_bytes))

  for frame = 0, frame_count - 1 do
    local phase = 2 * math.pi * 220 * frame / sample_rate
    local fade_in = math.min(frame / 480, 1)
    local fade_out = math.min((frame_count - 1 - frame) / 2400, 1)
    local sample = math.floor(12000 * math.sin(phase) * fade_in * fade_out)
    file:write(pcm16le(sample))
  end

  file:close()
  return true
end

local temp_root = os.getenv("TMPDIR") or "/tmp/"
if temp_root:sub(-1) ~= "/" then temp_root = temp_root .. "/" end
local wav_path = temp_root .. "zig-vst3-sample-player-smoke.wav"
local project_path = temp_root .. "zig-vst3-sample-player-smoke.rpp"

local wrote, write_error = write_test_wav(wav_path)
if not wrote then
  reaper.ShowMessageBox("Could not create the test WAV:\n" .. tostring(write_error), "Sample Player smoke setup", 0)
  return
end

reaper.Main_OnCommand(40859, 0)
reaper.InsertTrackAtIndex(0, true)
local track = reaper.GetTrack(0, 0)
if not track then
  reaper.ShowMessageBox("Could not create the smoke-test track.", "Sample Player smoke setup", 0)
  return
end

reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "zig-vst3 Sample Player smoke", true)
local fx = reaper.TrackFX_AddByName(track, "VST3: zig-vst3 Sample Player (zig-vst3)", false, -1)
if fx < 0 then
  reaper.ShowMessageBox("Install the zig-vst3 Sample Player bundle, then run this script again.", "Sample Player not found", 0)
  return
end

local item = reaper.CreateNewMIDIItemInProj(track, 0.0, 2.0, false)
local take = item and reaper.GetActiveTake(item) or nil
if not take then
  reaper.ShowMessageBox("Could not create the smoke-test MIDI item.", "Sample Player smoke setup", 0)
  return
end

local note_start = reaper.MIDI_GetPPQPosFromProjTime(take, 0.25)
local note_end = reaper.MIDI_GetPPQPosFromProjTime(take, 1.75)
reaper.MIDI_InsertNote(take, false, false, note_start, note_end, 0, 60, 100, false)
reaper.MIDI_Sort(take)
reaper.SetEditCurPos(0.0, true, false)
reaper.TrackFX_Show(track, fx, 3)
reaper.Main_SaveProjectEx(0, project_path, 0)
reaper.UpdateArrange()

reaper.ShowMessageBox(
  "Choose Sample in the plugin, import:\n\n" .. wav_path ..
  "\n\nThen press Play. The project was saved to:\n\n" .. project_path,
  "Sample Player smoke project ready",
  0
)
