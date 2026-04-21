# onnx.nvim

Neovim 语音输入插件，走 ONNX 小模型，不走 Whisper。

默认设计是：

- 录音：`ffmpeg`
- 转写：外部 ONNX 可执行程序
- 推荐后端：`sherpa-onnx`

这套方案的重点不是“模型大而全”，而是：

- 启动快
- 模型小
- CPU 可用
- 延迟低
- 容易替换后端

## 为什么不是 Whisper

Whisper 在本地编辑器场景里常见问题很明确：

- 模型偏大
- 首次加载慢
- CPU 体验差
- 短句输入延迟不够稳定

如果你的目标是“像按住说话然后立刻出字”，更适合用基于 ONNX 的流式/小型 ASR 工具链。

## 推荐后端

推荐直接用 `sherpa-onnx` 的 zipformer/transducer 小模型。

你只需要保证命令行能跑通，例如：

```bash
sherpa-onnx \
  --tokens=./models/tokens.txt \
  --encoder=./models/encoder.onnx \
  --decoder=./models/decoder.onnx \
  --joiner=./models/joiner.onnx \
  --wav=/tmp/test.wav
```

插件本身不绑死某个模型，只负责：

1. 录音到 wav
2. 调起 ONNX 转写命令
3. 解析文本
4. 把文本插回当前 buffer

## 小模型下载

官方总入口：

- sherpa-onnx 预训练模型索引: https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html
- sherpa-onnx ASR models release: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models

如果你主要做中文语音输入，先看这 3 个：

1. 最小优先，先跑起来
   `sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01`
   体积大约 27 MB
   https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01

2. 平衡速度和效果
   `sherpa-onnx-paraformer-zh-small-2024-03-09`
   体积大约 82 MB
   https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09

3. 更强但还算能接受
   `sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30`
   体积大约 168 MB
   https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30

我的建议很直接：

- 你要“最快先能用”：先下 `small-ctc-zh-int8`
- 你要“编辑器里体验更顺手”：先下 `paraformer-zh-small`
- 你要“更准一点”：再试 `streaming-zipformer-zh-int8`

注意一点：

- `small-ctc-zh-int8` 是 CTC 单模型，需要 `tokens.txt` 和 `model.int8.onnx`
- 它通常还会附带 `bbpe.model`，建议一起放好
- 现在仓库已经内置了它的 preset

## 内置 sherpa-onnx 适配

现在可以直接写：

```lua
require("onnx").setup({
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/models/tokens.txt",
      encoder = "/path/to/models/encoder.onnx",
      decoder = "/path/to/models/decoder.onnx",
      joiner = "/path/to/models/joiner.onnx",
      num_threads = 2,
      provider = "cpu",
    },
  },
})
```

这会自动拼出：

- `--tokens=...`
- `--encoder=...`
- `--decoder=...`
- `--joiner=...`
- `audio.wav`

如果你用的是 paraformer，也可以改成：

```lua
require("onnx").setup({
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/models/tokens.txt",
      paraformer = "/path/to/models/model.int8.onnx",
    },
  },
})
```

如果你用的是 CTC 小模型，可以改成：

```lua
require("onnx").setup({
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/models/tokens.txt",
      ctc = "/path/to/models/model.int8.onnx",
      bpe_vocab = "/path/to/models/bbpe.model",
    },
  },
})
```

仓库里已经带了可直接改路径的模板：

- [examples/sherpa-onnx.lua](/Users/CX/devAI/onnx.nvim/examples/sherpa-onnx.lua:1)

里面有两套预设：

- `zipformer`
- `paraformer`
- `ctc`

## 中文 preset

如果主要目标就是中文语音输入，直接用内置 preset 更省事：

```lua
require("onnx").setup_from_preset("zh_cn_zipformer", {
  transcriber = {
    model = {
      tokens = "/real/path/tokens.txt",
      encoder = "/real/path/encoder.onnx",
      decoder = "/real/path/decoder.onnx",
      joiner = "/real/path/joiner.onnx",
    },
  },
})
```

可用 preset：

- `zh_cn_zipformer`
- `zh_cn_paraformer`
- `zh_cn_small_ctc`

定义在 [lua/onnx/presets.lua](/Users/CX/devAI/onnx.nvim/lua/onnx/presets.lua:1)。

对应下载建议：

- `zh_cn_zipformer` 对应 `sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30`
- `zh_cn_paraformer` 对应 `sherpa-onnx-paraformer-zh-small-2024-03-09`
- `zh_cn_small_ctc` 对应 `sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01`

最小模型直接用法：

```lua
require("onnx").setup_from_preset("zh_cn_small_ctc", {
  transcriber = {
    model = {
      tokens = "/real/path/tokens.txt",
      ctc = "/real/path/model.int8.onnx",
      bpe_vocab = "/real/path/bbpe.model",
    },
  },
})
```

也可以直接用内置 helper：

```lua
require("onnx").setup_from_example("zipformer", {
  transcriber = {
    model = {
      tokens = "/real/path/tokens.txt",
      encoder = "/real/path/encoder.onnx",
      decoder = "/real/path/decoder.onnx",
      joiner = "/real/path/joiner.onnx",
    },
  },
})
```

## 安装

`lazy.nvim` 示例：

```lua
{
  dir = "/Users/CX/devAI/onnx.nvim",
  config = function()
    require("onnx").setup_from_preset("zh_cn_zipformer", {
      transcriber = {
        model = {
          tokens = "/path/to/tokens.txt",
          encoder = "/path/to/encoder.onnx",
          decoder = "/path/to/decoder.onnx",
          joiner = "/path/to/joiner.onnx",
        },
      },
    })
  end,
}
```

如果你不想用中文 preset，也可以直接 `require("onnx").setup_from_example("zipformer", overrides)`，或者手动加载 [examples/sherpa-onnx.lua](/Users/CX/devAI/onnx.nvim/examples/sherpa-onnx.lua:1)。

## 命令

- `:OnnxRecordStart`
- `:OnnxRecordStop`
- `:OnnxRecordToggle`
- `:OnnxTranscribeFile /path/to/audio.wav`

## 最小使用流程

1. 执行 `:OnnxRecordStart`
2. 说一句话
3. 执行 `:OnnxRecordStop`
4. 文本自动插入当前光标位置

## 快捷键录音

终端版 Neovim 对普通键盘按键没有可靠的 key-up 事件，所以没法做成真正的“按住开始，松开结束”。

当前插件提供实用版 push-to-talk：

- 按一次开始录音
- 再按一次停止并转写
- 录音时右上角会显示状态浮窗和计时

配置示例：

```lua
require("onnx").setup({
  keymaps = {
    toggle = "<leader>vv",
    modes = { "n", "i" },
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/models/tokens.txt",
      encoder = "/path/to/models/encoder.onnx",
      decoder = "/path/to/models/decoder.onnx",
      joiner = "/path/to/models/joiner.onnx",
    },
  },
})
```

如果你不想显示录音浮窗：

```lua
require("onnx").setup({
  ui = {
    status_window = {
      enabled = false,
    },
  },
})
```

如果你更喜欢分开的键位，也可以：

```lua
require("onnx").setup({
  keymaps = {
    start = "<leader>vs",
    stop = "<leader>ve",
    modes = { "n", "i" },
  },
})
```
 
命令行也支持同样逻辑：

```vim
:OnnxRecordToggle
```

## 录音状态浮窗

默认会在编辑器右上角显示一个轻量浮窗：

- `● REC 00:03 [||.||..|]`
- 开始录音时出现
- 停止录音后自动关闭
- bar 会做轻量动态动画，强化“正在录音”的反馈

可配置项：

```lua
require("onnx").setup({
  ui = {
    status_window = {
      enabled = true,
      border = "rounded",
      icon = "●",
      style = "meter",
      width = 30,
      row = 1,
      meter_width = 8,
      -- col = 80,
    },
  },
})
```

如果你只想要最简状态文本：

```lua
require("onnx").setup({
  ui = {
    status_window = {
      style = "compact",
      width = 18,
    },
  },
})
```

## 自动停录

可以直接用 `ffmpeg` 的 `silencedetect` 做自动停录，效果接近轻量 VAD：

- 开始说话后进入识别窗口
- 检测到持续静音后自动执行 `record_stop`
- 不需要额外引入一套音频推理模型

配置示例：

```lua
require("onnx").setup({
  recorder = {
    vad = {
      enabled = true,
      silence_duration = 1.2,
      noise = "-35dB",
      min_record_ms = 800,
    },
  },
})
```

参数说明：

- `silence_duration`: 静音多久后自动停录
- `noise`: 静音判定阈值
- `min_record_ms`: 最短录音时长，避免刚启动就误停

这个实现依赖默认 `ffmpeg` 录音链路。如果你完全改写了 `recorder.command_builder`，就需要你自己的录音命令也输出兼容的静音检测信息。

## Partial 预览

如果你的 ONNX 转写后端会持续输出中间结果，可以直接显示 partial 浮窗。

默认约定是 stdout 里出现这种行：

```text
partial: 你好这是中间结果
```

配置示例：

```lua
require("onnx").setup({
  transcriber = {
    command = "my-streaming-asr",
    args = { "--model", "/path/to/model.onnx" },
    partial = {
      enabled = true,
      prefix = "partial:",
    },
  },
})
```

如果你的后端输出格式不一样，可以自定义解析：

```lua
require("onnx").setup({
  transcriber = {
    partial = {
      enabled = true,
      parse = function(line)
        local chunk = line:match('^PARTIAL%s+(.+)$')
        return chunk
      end,
    },
  },
})
```

partial 浮窗默认显示在右上角状态窗下方，转写结束后自动关闭。

## 自定义录音命令

默认录音用 `ffmpeg`：

- macOS: `avfoundation`
- Linux: `alsa`

如果你想换成别的录音器，可以自定义：

```lua
require("onnx").setup({
  recorder = {
    command_builder = function(output_path, recorder)
      return {
        "sox",
        "-d",
        "-c",
        tostring(recorder.channels),
        "-r",
        tostring(recorder.sample_rate),
        output_path,
      }
    end,
  },
  transcriber = {
    backend = "sherpa-onnx",
    model = {
      tokens = "/path/to/tokens.txt",
      encoder = "/path/to/encoder.onnx",
      decoder = "/path/to/decoder.onnx",
      joiner = "/path/to/joiner.onnx",
    },
  },
})
```

## 自定义输出解析

不同 ONNX 后端输出格式可能不一样，可以自己改解析逻辑：

```lua
require("onnx").setup({
  transcriber = {
    command = "my-asr",
    args = { "--model", "/path/to/model.onnx" },
    audio_flag = "--input",
    parse = function(output)
      local json = vim.json.decode(output)
      return json.text
    end,
  },
})
```

## 检查环境

```vim
:checkhealth onnx
```

健康检查除了看 `ffmpeg` 和 `sherpa-onnx` 是否在 `$PATH`，也会检查当前 `setup()` 里的 sherpa-onnx 模型路径是否可读。
