if vim.g.loaded_onnx_nvim == 1 then
  return
end
vim.g.loaded_onnx_nvim = 1

local onnx = require("onnx")

vim.api.nvim_create_user_command("OnnxRecordStart", function()
  onnx.record_start()
end, {})

vim.api.nvim_create_user_command("OnnxRecordStop", function()
  onnx.record_stop()
end, {})

vim.api.nvim_create_user_command("OnnxRecordToggle", function()
  onnx.toggle_recording()
end, {})

vim.api.nvim_create_user_command("OnnxTranscribeFile", function(opts)
  onnx.transcribe_file(opts.args)
end, {
  nargs = 1,
  complete = "file",
})
