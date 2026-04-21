local M = {}

M.zh_cn_zipformer = {
  keymaps = {
    toggle = "<leader>vv",
    modes = { "n", "i" },
  },
  recorder = {
    sample_rate = 16000,
    channels = 1,
    vad = {
      enabled = true,
      silence_duration = 1.0,
      noise = "-35dB",
      min_record_ms = 800,
    },
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/zh-cn-zipformer/tokens.txt",
      encoder = "/path/to/zh-cn-zipformer/encoder.onnx",
      decoder = "/path/to/zh-cn-zipformer/decoder.onnx",
      joiner = "/path/to/zh-cn-zipformer/joiner.onnx",
      num_threads = 2,
      provider = "cpu",
    },
  },
  ui = {
    status_window = {
      enabled = true,
      style = "meter",
    },
    preview_window = {
      enabled = false,
    },
  },
}

M.zh_cn_paraformer = {
  keymaps = {
    toggle = "<leader>vv",
    modes = { "n", "i" },
  },
  recorder = {
    sample_rate = 16000,
    channels = 1,
    vad = {
      enabled = true,
      silence_duration = 1.0,
      noise = "-35dB",
      min_record_ms = 800,
    },
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/zh-cn-paraformer/tokens.txt",
      paraformer = "/path/to/zh-cn-paraformer/model.int8.onnx",
      num_threads = 2,
      provider = "cpu",
    },
  },
}

M.zh_cn_small_ctc = {
  keymaps = {
    toggle = "<leader>vv",
    modes = { "n", "i" },
  },
  recorder = {
    sample_rate = 16000,
    channels = 1,
    vad = {
      enabled = true,
      silence_duration = 1.0,
      noise = "-35dB",
      min_record_ms = 800,
    },
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/zh-cn-small-ctc/tokens.txt",
      ctc = "/path/to/zh-cn-small-ctc/model.int8.onnx",
      bpe_vocab = "/path/to/zh-cn-small-ctc/bbpe.model",
      num_threads = 2,
      provider = "cpu",
    },
  },
}

function M.get(name)
  local preset = M[name]
  if not preset then
    error("Unknown onnx preset: " .. tostring(name))
  end
  return vim.deepcopy(preset)
end

return M
