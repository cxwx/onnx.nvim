local M = {}

-- Zipformer / transducer example.
-- Recommended download:
-- https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30
M.zipformer = {
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
      tokens = "/path/to/sherpa-onnx-model/tokens.txt",
      encoder = "/path/to/sherpa-onnx-model/encoder.onnx",
      decoder = "/path/to/sherpa-onnx-model/decoder.onnx",
      joiner = "/path/to/sherpa-onnx-model/joiner.onnx",
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

-- Paraformer example.
-- Recommended download:
-- https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09
M.paraformer = {
  keymaps = {
    toggle = "<leader>vv",
    modes = { "n", "i" },
  },
  recorder = {
    sample_rate = 16000,
    channels = 1,
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/sherpa-onnx-paraformer/tokens.txt",
      paraformer = "/path/to/sherpa-onnx-paraformer/model.int8.onnx",
      num_threads = 2,
      provider = "cpu",
    },
  },
}

-- CTC example.
-- Recommended download:
-- https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01
M.ctc = {
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
      tokens = "/path/to/sherpa-onnx-ctc/tokens.txt",
      ctc = "/path/to/sherpa-onnx-ctc/model.int8.onnx",
      bpe_vocab = "/path/to/sherpa-onnx-ctc/bbpe.model",
      num_threads = 2,
      provider = "cpu",
    },
  },
}

return M
