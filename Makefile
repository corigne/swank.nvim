.PHONY: test test-unit test-integration test-all coverage lint

NVIM        ?= nvim
INIT        := tests/minimal_init.lua
COV_INIT    := tests/coverage_init.lua
UNIT_DIR    := tests/unit
INTEG_DIR   := tests/integration
LUACOV      := $(HOME)/.luarocks/bin/luacov

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

# Run unit tests with luacov, then generate luacov.report.out
coverage:
	@rm -f luacov.stats.out luacov.report.out
	$(NVIM) --headless -u $(COV_INIT) \
	  -c "lua require('plenary.test_harness').test_directory('$(UNIT_DIR)', { minimal_init = '$(COV_INIT)' })" \
	  -c "qa!"
	$(LUACOV)
	@echo ""
	@echo "=== Coverage summary ==="
	@grep -E "[0-9]+\.[0-9]+%" luacov.report.out || cat luacov.report.out
