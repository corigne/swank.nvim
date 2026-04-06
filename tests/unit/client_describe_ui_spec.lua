-- tests/unit/client_describe_ui_spec.lua
-- Test client.describe UI: ensure a floating buffer/window is created and trailing blank lines are trimmed

local client = require("swank.client")

describe("client.describe UI", function()
  local orig_silent_rex, orig_create_buf, orig_buf_set_lines, orig_open_win
  local orig_win_is_valid, orig_win_close, orig_create_autocmd, orig_bo, orig_wo
  local orig_config, orig_notify, orig_cols, orig_lines

  before_each(function()
    client._test_reset()
    orig_silent_rex = client.silent_rex
    orig_create_buf = vim.api.nvim_create_buf
    orig_buf_set_lines = vim.api.nvim_buf_set_lines
    orig_open_win = vim.api.nvim_open_win
    orig_win_is_valid = vim.api.nvim_win_is_valid
    orig_win_close = vim.api.nvim_win_close
    orig_create_autocmd = vim.api.nvim_create_autocmd
    orig_bo = vim.bo
    orig_wo = vim.wo
    orig_config = require("swank").config
    orig_notify = vim.notify
    orig_cols = vim.o.columns
    orig_lines = vim.o.lines

    require("swank").config = { ui = { floating = { border = "rounded" } } }
    vim.o.columns = 120
    vim.o.lines = 60

    fake_buf = 101
    fake_win = 202
    captured_lines = nil
    opened_opts = nil
    created_autocmd = nil

    vim.api.nvim_create_buf = function(listed, scratch) return fake_buf end
    vim.bo = vim.bo or {}
    vim.bo[fake_buf] = {}
    vim.api.nvim_buf_set_lines = function(buf, start, _end, strict, lines) captured_lines = lines end
    vim.api.nvim_open_win = function(buf, enter, opts) opened_opts = opts; vim.wo = vim.wo or {}; vim.wo[fake_win] = {}; return fake_win end
    vim.api.nvim_win_is_valid = function(win) return true end
    win_closed = false
    vim.api.nvim_win_close = function(win, _) win_closed = true end
    vim.api.nvim_create_autocmd = function(ev, opts) created_autocmd = {ev=ev, opts=opts} end
  end)

  after_each(function()
    client.silent_rex = orig_silent_rex
    vim.api.nvim_create_buf = orig_create_buf
    vim.api.nvim_buf_set_lines = orig_buf_set_lines
    vim.api.nvim_open_win = orig_open_win
    vim.api.nvim_win_is_valid = orig_win_is_valid
    vim.api.nvim_win_close = orig_win_close
    vim.api.nvim_create_autocmd = orig_create_autocmd
    vim.bo = orig_bo
    vim.wo = orig_wo
    require("swank").config = orig_config
    vim.notify = orig_notify
    vim.o.columns = orig_cols
    vim.o.lines = orig_lines
    client._test_reset()
  end)

  it("creates a floating window with sanitized description", function()
    client.silent_rex = function(form, cb)
      cb({ ":ok", "Alpha\nBeta\n\n" })
    end

    client.describe("Alpha")

    assert.equals(2, #captured_lines)
    assert.equals("Alpha", captured_lines[1])
    assert.equals("Beta", captured_lines[2])
    assert.is_true(opened_opts ~= nil)
    assert.equals(" Alpha ", opened_opts.title)
    assert.is_true(created_autocmd ~= nil)
  end)
end)
