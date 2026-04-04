ROOT        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BADGE_SCRIPT := $(ROOT)/scripts/update_coverage_badge.sh

.PHONY: test test-unit test-integration test-all coverage badge lint

NVIM        ?= nvim
INIT        := $(ROOT)/tests/minimal_init.lua
COV_INIT    := $(ROOT)/tests/coverage_init.lua
UNIT_DIR    := $(ROOT)/tests/unit
INTEG_DIR   := $(ROOT)/tests/integration
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
	@rm -f $(ROOT)/luacov.stats.out $(ROOT)/luacov.report.out
	cd $(ROOT) && $(NVIM) --headless -u $(COV_INIT) \
	  -c "lua require('plenary.test_harness').test_directory('$(UNIT_DIR)', { minimal_init = '$(COV_INIT)', sequential = true })" \
	  -c "qa!"
	cd $(ROOT) && $(LUACOV)
	@echo ""
	@echo "=== Coverage summary ==="
	@grep -E "[0-9]+\.[0-9]+%" $(ROOT)/luacov.report.out || cat $(ROOT)/luacov.report.out

# Update the coverage badge in README.md (runs coverage first)
badge: coverage
	@bash $(BADGE_SCRIPT)
