NVIM ?= nvim
export NVIM_LOG_FILE := $(CURDIR)/tmp/nvim.log
export XDG_STATE_HOME := $(CURDIR)/tmp/state
export XDG_CACHE_HOME := $(CURDIR)/tmp/cache

.PHONY: test test-integration
test:
	mkdir -p tmp/state tmp/cache
	$(NVIM) --headless -u NONE -i NONE -l tests/run.lua
	$(NVIM) --headless -u NONE -i NONE -l tests/images.lua
	$(NVIM) --headless -u NONE -i NONE -l tests/view.lua
	$(NVIM) --headless -u NONE -i NONE -l tests/workflow.lua

test-integration:
	mkdir -p tmp/state tmp/cache
	$(NVIM) --headless -u NONE -i NONE -l tests/integration.lua
