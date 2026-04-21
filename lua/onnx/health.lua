local M = {}

local function file_ok(path)
  return path and path ~= "" and vim.fn.filereadable(vim.fn.expand(path)) == 1
end

function M.check()
  vim.health.start("onnx.nvim")

  if vim.fn.executable("ffmpeg") == 1 then
    vim.health.ok("ffmpeg found")
  else
    vim.health.warn("ffmpeg not found; recording commands will fail")
  end

  if vim.fn.executable("sherpa-onnx") == 1 then
    vim.health.ok("sherpa-onnx found")
  else
    vim.health.warn("sherpa-onnx not found; configure transcriber.command or install it")
  end

  local ok, onnx = pcall(require, "onnx")
  if not ok then
    vim.health.error("failed to load onnx module")
    return
  end

  local cfg = onnx.get_config()
  local transcriber = cfg.transcriber or {}
  local model = transcriber.model or {}

  if transcriber.backend ~= "sherpa-onnx" then
    vim.health.info("transcriber.backend is not set to sherpa-onnx; model file checks skipped")
    return
  end

  vim.health.start("sherpa-onnx config")

  if file_ok(model.tokens) then
    vim.health.ok("tokens found: " .. vim.fn.expand(model.tokens))
  else
    vim.health.warn("model.tokens is missing or unreadable")
  end

  if file_ok(model.paraformer) then
    vim.health.ok("paraformer model found: " .. vim.fn.expand(model.paraformer))
    return
  end

  if file_ok(model.ctc) then
    vim.health.ok("ctc model found: " .. vim.fn.expand(model.ctc))
    if file_ok(model.bpe_vocab) then
      vim.health.ok("bpe vocab found: " .. vim.fn.expand(model.bpe_vocab))
    else
      vim.health.info("model.bpe_vocab is optional; add it for CTC models that ship bbpe.model")
    end
    return
  end

  local missing = {}
  for _, key in ipairs({ "encoder", "decoder", "joiner" }) do
    if file_ok(model[key]) then
      vim.health.ok(key .. " found: " .. vim.fn.expand(model[key]))
    else
      table.insert(missing, key)
    end
  end

  if #missing > 0 then
    vim.health.warn("missing sherpa-onnx transducer files: " .. table.concat(missing, ", "))
  end
end

return M
