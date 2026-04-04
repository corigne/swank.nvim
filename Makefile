.PHONY: test test-unit test-integration lint

NVIM      ?= nvim
INIT      := tests/minimal_init.lua
UNIT_DIR  := tests/unit
INTEG_DIR := tests/integration

# Run all unit tests (no server required)
test: test-unit

test-unit:
	$(NVIM) --headless -u $(INIT) \
	  -c "lua require('plenary.test_harness').test_directory('$(UNIT_DIR)', { minimal_init = '$(INIT)' })" \
	  -c "qa!"

# Run integration tests (requires a live Swank server on 127.0.0.1:4005)
test-integration:
	$(NVIM) --headless -u $(INIT) \
	  -c "lua require('plenary.test_harness').test_directory('$(INTEG_DIR)', { minimal_init = '$(INIT)' })" \
	  -c "qa!"

# Run everything
test-all: test-unit test-integration
