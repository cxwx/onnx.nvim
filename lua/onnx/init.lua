local M = {}

local state = {
  recording = nil,
  config = nil,
  keymaps = {},
  status = {
    buf = nil,
    win = nil,
    timer = nil,
    started_at = nil,
    frame = 0,
  },
  preview = {
    buf = nil,
    win = nil,
    text = "",
  },
}

local config

local silence_patterns = {
  start = "silence_start:",
  ending = "silence_end:",
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "onnx.nvim" })
end

local function join_args(args)
  local parts = {}
  for _, arg in ipairs(args or {}) do
    if arg:find("[%s\"']") then
      table.insert(parts, vim.fn.shellescape(arg))
    else
      table.insert(parts, arg)
    end
  end
  return table.concat(parts, " ")
end

local function normalize_path(path)
  return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

local function system_name()
  local uname = vim.uv.os_uname()
  return uname.sysname
end

local function default_record_cmd(output_path, opts)
  local sys = system_name()
  local sample_rate = tostring(opts.sample_rate)
  local channels = tostring(opts.channels)
  local extra_args = {}

  if opts.vad and opts.vad.enabled then
    table.insert(extra_args, "-af")
    table.insert(extra_args, ("silencedetect=n=%s:d=%s"):format(opts.vad.noise, opts.vad.silence_duration))
  end

  if sys == "Darwin" then
    local cmd = {
      "ffmpeg",
      "-y",
      "-f",
      "avfoundation",
      "-i",
      opts.device or ":0",
      "-ac",
      channels,
      "-ar",
      sample_rate,
    }
    vim.list_extend(cmd, extra_args)
    table.insert(cmd, output_path)
    return cmd
  end

  if sys == "Linux" then
    local cmd = {
      "ffmpeg",
      "-y",
      "-f",
      "alsa",
      "-i",
      opts.device or "default",
      "-ac",
      channels,
      "-ar",
      sample_rate,
    }
    vim.list_extend(cmd, extra_args)
    table.insert(cmd, output_path)
    return cmd
  end

  error("Unsupported OS for default recorder: " .. sys)
end

local function default_transcribe_cmd(audio_path, opts)
  if not opts.command then
    error("transcriber.command is required")
  end

  local args = {}
  vim.list_extend(args, opts.args or {})

  local audio_flag = opts.audio_flag or "--wav"
  if audio_flag ~= "" then
    table.insert(args, audio_flag)
  end
  table.insert(args, audio_path)

  return opts.command, args
end

local function buf_insert_text(text)
  if not text or text == "" then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, lines)
end

local function build_temp_wav()
  return normalize_path(vim.fn.tempname() .. ".wav")
end

local function ensure_executable(bin)
  if vim.fn.executable(bin) ~= 1 then
    error(("Executable not found: %s"):format(bin))
  end
end

local function recorder_command(cfg, output_path)
  if type(cfg.recorder.command_builder) == "function" then
    return cfg.recorder.command_builder(output_path, cfg.recorder)
  end
  return default_record_cmd(output_path, cfg.recorder)
end

local function require_any_field(tbl, fields, message)
  for _, field in ipairs(fields) do
    local value = tbl[field]
    if value ~= nil and value ~= "" then
      return
    end
  end
  error(message)
end

local function append_flag(args, flag, value)
  if value == nil or value == "" then
    return
  end
  table.insert(args, ("%s=%s"):format(flag, value))
end

local function sherpa_onnx_cmd(audio_path, opts)
  local model = opts.model or {}
  local args = {}

  require_any_field(model, { "tokens" }, "sherpa-onnx requires model.tokens")
  require_any_field(
    model,
    { "paraformer", "ctc", "encoder" },
    "sherpa-onnx requires model.paraformer, model.ctc, or model.encoder"
  )
  if not model.paraformer and not model.ctc then
    require_any_field(model, { "decoder" }, "sherpa-onnx transducer requires model.decoder")
    require_any_field(model, { "joiner" }, "sherpa-onnx transducer requires model.joiner")
  end

  append_flag(args, "--tokens", model.tokens)
  append_flag(args, "--zipformer2-ctc-model", model.ctc)
  append_flag(args, "--encoder", model.encoder)
  append_flag(args, "--decoder", model.decoder)
  append_flag(args, "--joiner", model.joiner)
  append_flag(args, "--paraformer", model.paraformer)
  append_flag(args, "--bpe-vocab", model.bpe_vocab)
  append_flag(args, "--num-threads", model.num_threads)
  append_flag(args, "--decoding-method", model.decoding_method)
  append_flag(args, "--provider", model.provider)

  vim.list_extend(args, opts.args or {})
  table.insert(args, audio_path)

  return opts.command or "sherpa-onnx", args
end

local function transcriber_command(cfg, audio_path)
  if type(cfg.transcriber.command_builder) == "function" then
    return cfg.transcriber.command_builder(audio_path, cfg.transcriber)
  end
  if cfg.transcriber.backend == "sherpa-onnx" then
    return sherpa_onnx_cmd(audio_path, cfg.transcriber)
  end
  return default_transcribe_cmd(audio_path, cfg.transcriber)
end

local function collect_output(chunks)
  local out = {}
  for _, chunk in ipairs(chunks) do
    if chunk and chunk ~= "" then
      table.insert(out, chunk)
    end
  end
  return table.concat(out, "")
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function format_duration(started_at)
  if not started_at then
    return "00:00"
  end
  local seconds = math.max(0, math.floor((vim.uv.now() - started_at) / 1000))
  local minutes = math.floor(seconds / 60)
  return ("%02d:%02d"):format(minutes, seconds % 60)
end

local function build_meter(frame, width, chars)
  local patterns = {
    { 1, 3, 5, 2, 4, 2, 1, 4 },
    { 2, 4, 2, 5, 3, 1, 3, 5 },
    { 4, 2, 1, 4, 5, 3, 2, 4 },
    { 5, 3, 2, 4, 2, 5, 1, 3 },
  }
  local pattern = patterns[(frame % #patterns) + 1]
  local full = chars.full or "|"
  local empty = chars.empty or "."
  local bars = {}

  for i = 1, math.max(1, width) do
    local level = pattern[((i - 1) % #pattern) + 1]
    bars[i] = level >= 3 and full or empty
  end

  return table.concat(bars)
end

local function status_text(status_ui)
  local style = status_ui.style or "meter"
  local icon = status_ui.icon or "●"
  local duration = format_duration(state.status.started_at)

  if style == "compact" then
    return ("%s REC %s"):format(icon, duration)
  end

  local meter_width = status_ui.meter_width or 8
  local meter_chars = status_ui.meter_chars or { full = "|", empty = "." }
  local meter = build_meter(state.status.frame, meter_width, meter_chars)
  return ("%s REC %s [%s]"):format(icon, duration, meter)
end

local function status_open(cfg)
  local ui = cfg.ui or {}
  local status_ui = ui.status_window or {}
  if status_ui.enabled == false then
    return
  end

  local width = status_ui.width or 26
  local height = status_ui.height or 1
  local row = status_ui.row or 1
  local col = status_ui.col
  if col == nil then
    col = math.max(0, vim.o.columns - width - 2)
  end

  if state.status.buf and vim.api.nvim_buf_is_valid(state.status.buf) then
    pcall(vim.api.nvim_buf_delete, state.status.buf, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = status_ui.border or "rounded",
    focusable = false,
    noautocmd = true,
  })

  local function render()
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    state.status.frame = state.status.frame + 1
    local text = status_text(status_ui)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  end

  state.status.buf = buf
  state.status.win = win
  state.status.started_at = vim.uv.now()
  state.status.frame = 0
  render()

  local timer = vim.uv.new_timer()
  timer:start(0, 1000, vim.schedule_wrap(render))
  state.status.timer = timer
end

local function status_close()
  if state.status.timer then
    state.status.timer:stop()
    state.status.timer:close()
    state.status.timer = nil
  end

  if state.status.win and vim.api.nvim_win_is_valid(state.status.win) then
    pcall(vim.api.nvim_win_close, state.status.win, true)
  end

  if state.status.buf and vim.api.nvim_buf_is_valid(state.status.buf) then
    pcall(vim.api.nvim_buf_delete, state.status.buf, { force = true })
  end

  state.status.buf = nil
  state.status.win = nil
  state.status.started_at = nil
  state.status.frame = 0
end

local function preview_close()
  if state.preview.win and vim.api.nvim_win_is_valid(state.preview.win) then
    pcall(vim.api.nvim_win_close, state.preview.win, true)
  end
  if state.preview.buf and vim.api.nvim_buf_is_valid(state.preview.buf) then
    pcall(vim.api.nvim_buf_delete, state.preview.buf, { force = true })
  end
  state.preview.buf = nil
  state.preview.win = nil
  state.preview.text = ""
end

local function preview_open(cfg)
  local ui = cfg.ui or {}
  local preview_ui = ui.preview_window or {}
  if preview_ui.enabled == false then
    return
  end

  preview_close()

  local width = preview_ui.width or 48
  local height = preview_ui.height or 3
  local row = preview_ui.row
  if row == nil then
    row = 3
  end
  local col = preview_ui.col
  if col == nil then
    col = math.max(0, vim.o.columns - width - 2)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = preview_ui.border or "rounded",
    title = preview_ui.title or " onnx partial ",
    title_pos = "left",
    focusable = false,
    noautocmd = true,
  })

  state.preview.buf = buf
  state.preview.win = win
  state.preview.text = ""
end

local function preview_set_text(text)
  if not state.preview.buf or not vim.api.nvim_buf_is_valid(state.preview.buf) then
    return
  end
  state.preview.text = text or ""
  local lines = vim.split(state.preview.text, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end
  vim.api.nvim_buf_set_lines(state.preview.buf, 0, -1, false, lines)
end

local function handle_recorder_stderr(line, cfg)
  local rec = state.recording
  local vad = cfg.recorder.vad
  if not rec or not vad or not vad.enabled then
    return
  end

  if line:find(silence_patterns.ending, 1, true) then
    rec.speech_detected = true
    return
  end

  if not rec.speech_detected then
    return
  end

  if line:find(silence_patterns.start, 1, true) then
    local elapsed = vim.uv.now() - (rec.started_at or vim.uv.now())
    if elapsed < (vad.min_record_ms or 800) then
      return
    end
    if rec.auto_stop_scheduled then
      return
    end

    rec.auto_stop_scheduled = true
    vim.schedule(function()
      if state.recording and state.recording.pid == rec.pid then
        notify("Auto stop on silence")
        M.record_stop()
      end
    end)
  end
end

local function process_recorder_stderr(data, cfg, stderr, rec)
  if not data then
    return
  end

  table.insert(stderr, data)
  rec.stderr_buffer = (rec.stderr_buffer or "") .. data

  while true do
    local newline = rec.stderr_buffer:find("\n", 1, true)
    if not newline then
      break
    end
    local line = trim(rec.stderr_buffer:sub(1, newline - 1))
    rec.stderr_buffer = rec.stderr_buffer:sub(newline + 1)
    if line ~= "" then
      handle_recorder_stderr(line, cfg)
    end
  end
end

local function parse_partial_line(line, cfg)
  local partial = cfg.transcriber.partial or {}
  if type(partial.parse) == "function" then
    return partial.parse(line)
  end

  local prefix = partial.prefix or "partial:"
  local lower = line:lower()
  local lower_prefix = prefix:lower()
  if lower:sub(1, #lower_prefix) == lower_prefix then
    return trim(line:sub(#prefix + 1))
  end

  return nil
end

local function process_transcriber_stdout(data, cfg, stdout, partial_state)
  if not data then
    return
  end

  table.insert(stdout, table.concat(data, "\n"))
  partial_state.buffer = partial_state.buffer .. table.concat(data, "\n")

  while true do
    local newline = partial_state.buffer:find("\n", 1, true)
    if not newline then
      break
    end
    local line = trim(partial_state.buffer:sub(1, newline - 1))
    partial_state.buffer = partial_state.buffer:sub(newline + 1)
    if line ~= "" then
      local text = parse_partial_line(line, cfg)
      if text and text ~= "" then
        partial_state.last_text = text
        vim.schedule(function()
          preview_set_text(text)
        end)
      end
    end
  end
end

local function parse_text(output, cfg)
  if type(cfg.transcriber.parse) == "function" then
    return cfg.transcriber.parse(output)
  end

  local lines = vim.split(output, "\n", { plain = true, trimempty = true })
  for i = #lines, 1, -1 do
    local line = trim(lines[i])
    if line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" and type(decoded.text) == "string" and decoded.text ~= "" then
        return trim(decoded.text)
      end

      local match = line:match("^text%s*[:=]%s*(.+)$")
      if match then
        return trim(match)
      end

      if not (
        line:match("^Start to create recognizer")
        or line:match("^start to create recognizer")
        or line:match("^recognizer created in ")
        or line:match("^Recognizer created in ")
        or line:match("^Creating recognizer")
        or line:match("^Started$")
        or line:match("^Done!?$")
        or line:match("^num threads:")
        or line:match("^decoding method:")
        or line:match("^Elapsed seconds:")
        or line:match("^Real time factor")
        or line:match("^%-%-%-%-$")
        or line:match("%.wav$")
      ) then
        return line
      end
    end
  end
  return ""
end

local default_config = {
  recorder = {
    sample_rate = 16000,
    channels = 1,
    device = nil,
    vad = {
      enabled = false,
      silence_duration = 1.2,
      noise = "-35dB",
      min_record_ms = 800,
    },
    command_builder = nil,
  },
  transcriber = {
    backend = nil,
    command = "sherpa-onnx",
    args = {},
    audio_flag = "--wav",
    command_builder = nil,
    parse = nil,
    model = {
      tokens = nil,
      encoder = nil,
      decoder = nil,
      joiner = nil,
      paraformer = nil,
      ctc = nil,
      bpe_vocab = nil,
      num_threads = nil,
      decoding_method = nil,
      provider = nil,
    },
    partial = {
      enabled = false,
      prefix = "partial:",
      parse = nil,
    },
  },
  insert_mode = true,
  auto_cleanup = true,
  keymaps = {
    toggle = nil,
    start = nil,
    stop = nil,
    modes = { "n", "i" },
  },
  ui = {
    status_window = {
      enabled = true,
      border = "rounded",
      icon = "●",
      style = "meter",
      width = 30,
      height = 1,
      row = 1,
      col = nil,
      meter_width = 8,
      meter_chars = {
        full = "|",
        empty = ".",
      },
    },
    preview_window = {
      enabled = true,
      border = "rounded",
      width = 48,
      height = 3,
      row = 4,
      col = nil,
      title = " onnx partial ",
    },
  },
}

local function map_lhs(lhs)
  return lhs and lhs ~= ""
end

local function clear_keymaps()
  for _, item in ipairs(state.keymaps) do
    pcall(vim.keymap.del, item.mode, item.lhs)
  end
  state.keymaps = {}
end

local function register_keymap(modes, lhs, rhs, desc)
  vim.keymap.set(modes, lhs, rhs, { desc = desc })
  for _, mode in ipairs(modes) do
    table.insert(state.keymaps, { mode = mode, lhs = lhs })
  end
end

local function setup_keymaps(cfg)
  local keymaps = cfg.keymaps or {}
  local modes = keymaps.modes or { "n", "i" }
  clear_keymaps()

  if map_lhs(keymaps.toggle) then
    register_keymap(modes, keymaps.toggle, function()
      M.toggle_recording()
    end, "onnx.nvim toggle recording")
  end

  if map_lhs(keymaps.start) then
    register_keymap(modes, keymaps.start, function()
      M.record_start()
    end, "onnx.nvim start recording")
  end

  if map_lhs(keymaps.stop) then
    register_keymap(modes, keymaps.stop, function()
      M.record_stop()
    end, "onnx.nvim stop recording")
  end
end

function M.setup(opts)
  state.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
  setup_keymaps(state.config)
end

function M.setup_from_example(name, overrides)
  local examples = require("examples.sherpa-onnx")
  local example = examples[name]
  if not example then
    error("Unknown onnx example: " .. tostring(name))
  end
  M.setup(vim.tbl_deep_extend("force", vim.deepcopy(example), overrides or {}))
end

function M.setup_from_preset(name, overrides)
  local preset = require("onnx.presets").get(name)
  M.setup(vim.tbl_deep_extend("force", preset, overrides or {}))
end

config = function()
  if not state.config then
    M.setup({})
  end
  return state.config
end

function M.get_config()
  return config()
end

function M.record_start()
  local cfg = config()
  if state.recording then
    notify("Recording already in progress", vim.log.levels.WARN)
    return
  end

  local output_path = build_temp_wav()
  local cmd = recorder_command(cfg, output_path)
  ensure_executable(cmd[1])

  local stderr = {}
  local err_pipe = vim.uv.new_pipe(false)
  local rec = {
    err_pipe = err_pipe,
    path = output_path,
    stderr = stderr,
    started_at = vim.uv.now(),
    speech_detected = false,
    auto_stop_scheduled = false,
    stderr_buffer = "",
  }
  local handle, pid = vim.uv.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    stdio = { nil, nil, err_pipe },
  }, function(code, signal)
    if state.recording and state.recording.pid == pid then
      state.recording.exit_code = code
      state.recording.signal = signal
    end
  end)

  if not handle then
    err_pipe:close()
    error("Failed to start recorder: " .. join_args(cmd))
  end

  err_pipe:read_start(function(read_err, data)
    assert(not read_err, read_err)
    process_recorder_stderr(data, cfg, stderr, rec)
  end)

  rec.handle = handle
  rec.pid = pid
  state.recording = rec

  status_open(cfg)
  notify("Recording to " .. output_path)
end

function M.toggle_recording()
  if state.recording then
    return M.record_stop()
  end
  return M.record_start()
end

local function run_transcription(audio_path)
  local cfg = config()
  local cmd, args = transcriber_command(cfg, audio_path)
  ensure_executable(cmd)

  local stdout = {}
  local stderr = {}
  local partial_state = {
    buffer = "",
    last_text = "",
  }
  if cfg.transcriber.partial and cfg.transcriber.partial.enabled then
    preview_open(cfg)
  else
    preview_close()
  end

  local job_id = vim.fn.jobstart(vim.list_extend({ cmd }, args), {
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      process_transcriber_stdout(data, cfg, stdout, partial_state)
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if partial_state.buffer ~= "" then
          local trailing = trim(partial_state.buffer)
          local text = parse_partial_line(trailing, cfg)
          if text and text ~= "" then
            partial_state.last_text = text
            preview_set_text(text)
          end
        end

        if code ~= 0 then
          preview_close()
          notify(("Transcription failed (%d): %s"):format(code, trim(collect_output(stderr))), vim.log.levels.ERROR)
          return
        end

        local combined_output = collect_output(stdout) .. "\n" .. collect_output(stderr)
        local text = parse_text(combined_output, cfg)
        if text == "" and partial_state.last_text ~= "" then
          text = partial_state.last_text
        end
        if text == "" then
          preview_close()
          notify("Transcriber returned empty text", vim.log.levels.WARN)
          return
        end

        if cfg.insert_mode then
          buf_insert_text(text)
        end
        preview_close()
        notify("Inserted: " .. text)

        if cfg.auto_cleanup then
          pcall(vim.fn.delete, audio_path)
        end
      end)
    end,
  })

  if job_id <= 0 then
    preview_close()
    error("Failed to start transcriber: " .. cmd)
  end
end

function M.record_stop()
  local rec = state.recording
  if not rec then
    notify("No active recording", vim.log.levels.WARN)
    return
  end

  state.recording = nil
  status_close()
  rec.handle:kill("sigint")
  rec.handle:close()
  if rec.err_pipe and not rec.err_pipe:is_closing() then
    rec.err_pipe:read_stop()
    rec.err_pipe:close()
  end
  run_transcription(rec.path)
end

function M.transcribe_file(path)
  local audio_path = normalize_path(path)
  if vim.fn.filereadable(audio_path) ~= 1 then
    error("Audio file not found: " .. audio_path)
  end
  run_transcription(audio_path)
end

function M.is_recording()
  return state.recording ~= nil
end

return M
