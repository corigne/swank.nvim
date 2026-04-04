-- tests/integration/connection_spec.lua
-- Integration tests against a live Swank server.
-- These tests are SKIPPED automatically when no Swank server is reachable
-- on 127.0.0.1:4005 (or SWANK_PORT env var).
--
-- To run: start sbcl + swank, then: make test-integration

local client   = require("swank.client")
local protocol = require("swank.protocol")

local HOST = "127.0.0.1"
local PORT = tonumber(vim.env.SWANK_PORT) or 4005

-- ---------------------------------------------------------------------------
-- Guard: check reachability before running any test
-- ---------------------------------------------------------------------------

local function swank_reachable()
  local handle = vim.uv.new_tcp()
  local ok = false
  local done = false
  handle:connect(HOST, PORT, function(err)
    ok = (err == nil)
    done = true
    handle:close()
  end)
  -- Plain libuv callback (no vim.schedule wrapper) — vim.uv.run() is safe here
  local deadline = vim.uv.now() + 1000
  while not done and vim.uv.now() < deadline do
    vim.uv.run("once")
  end
  if not done then handle:close() end
  return ok
end

local SKIP = not swank_reachable()

local function skip_or(desc, fn)
  if SKIP then
    pending(desc .. " [SKIPPED: no Swank server on " .. HOST .. ":" .. PORT .. "]")
  else
    it(desc, fn)
  end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Connect, run fn(done_cb), wait for done_cb() to be called (or timeout)
---@param fn fun(done: fun())
local function with_connection(fn)
  local orig_notify = vim.notify
  vim.notify = function() end

  client.connect(HOST, PORT)

  vim.wait(3000, function() return client.is_connected() end, 10)
  vim.notify = orig_notify

  assert.is_true(client.is_connected(), "failed to connect to Swank server")

  local done = false
  fn(function() done = true end)

  vim.wait(5000, function() return done end, 10)
  assert.is_true(done, "test timed out waiting for Swank response")

  client.disconnect()
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("Swank integration", function()
  describe("connection", function()
    skip_or("connects and gets connection-info", function()
      with_connection(function(done)
        client.rex({ "swank:connection-info" }, function(result)
          assert.is_table(result)
          assert.equals(":ok", result[1])
          local info = client._plist(result[2])
          assert.is_not_nil(info[":lisp-implementation"])
          done()
        end)
      end)
    end)
  end)

  describe("eval", function()
    skip_or("eval-and-grab-output returns correct value", function()
      with_connection(function(done)
        client.rex({ "swank:eval-and-grab-output", "(+ 1 2)" }, function(result)
          assert.equals(":ok", result[1])
          -- result[2] = (output-string value-string)
          local pair = result[2]
          assert.is_table(pair)
          assert.equals("3", pair[2])
          done()
        end)
      end)
    end)

    -- NOTE: testing :abort-on-unhandled-error is intentionally omitted.
    -- Evaluating (/ 1 0) activates Swank's SLDB, which requires an interactive
    -- restart choice to dismiss. In headless CI there is no way to invoke the
    -- restart, so the debug session lingers on the server and corrupts subsequent
    -- tests. SLDB behaviour is covered by sldb_spec (unit) and manual testing.

    skip_or("returns :abort for an unhandled error", function()
      with_connection(function(done)
        -- sldb.open() auto-aborts when headless (no UI attached), so Swank
        -- sends :return :abort and the callback fires normally.
        client.rex({ "swank:eval-and-grab-output", "(/ 1 0)" }, function(result)
          assert.is_table(result)
          assert.is_not_nil(result[1])
          done()
        end)
      end)
    end)


      with_connection(function(done)
        client.rex({ "swank:set-package", "COMMON-LISP-USER" }, function(result)
          assert.equals(":ok", result[1])
          done()
        end)
      end)
    end)
  end)

  describe("introspection", function()
    skip_or("describe-symbol returns a string for a known symbol", function()
      with_connection(function(done)
        client.rex({ "swank:describe-symbol", "mapcar" }, function(result)
          assert.equals(":ok", result[1])
          assert.is_string(result[2])
          assert.is_true(#result[2] > 0)
          done()
        end)
      end)
    end)

    skip_or("operator-arglist returns arglist for mapcar", function()
      with_connection(function(done)
        client.rex({ "swank:operator-arglist", "mapcar", "COMMON-LISP-USER" },
          function(result)
            assert.equals(":ok", result[1])
            -- Should be a string like "(FUNCTION &REST LISTS)"
            assert.is_string(result[2])
            done()
          end)
      end)
    end)

    skip_or("apropos-list-for-emacs finds CL symbols", function()
      with_connection(function(done)
        client.rex(
          { "swank:apropos-list-for-emacs", "mapcar", false, false, nil },
          function(result)
            assert.equals(":ok", result[1])
            assert.is_table(result[2])
            assert.is_true(#result[2] > 0)
            done()
          end)
      end)
    end)
  end)

  describe("compilation", function()
    skip_or("compile-file returns :compilation-result", function()
      -- Write a trivial lisp file to /tmp
      local path = "/tmp/swank_nvim_test.lisp"
      local f = io.open(path, "w")
      f:write("(defun test-fn (x) (* x x))\n")
      f:close()

      with_connection(function(done)
        client.rex({ "swank:compile-file", path, false }, function(result)
          assert.equals(":ok", result[1])
          local cr = result[2]
          assert.is_table(cr)
          assert.equals(":compilation-result", cr[1])
          done()
        end)
      end)

      os.remove(path)
    end)
  end)
end)
