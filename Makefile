.DEFAULT_GOAL := help

# Select explicitly: make MODE=local up. Production is the safe default.
MODE ?= production

.PHONY: up down status logs help

up:
	@bash scripts/stack.sh up "$(MODE)"

down:
	@bash scripts/stack.sh down "$(MODE)"

status:
	@bash scripts/stack.sh status "$(MODE)"

logs:
	@bash scripts/stack.sh logs "$(MODE)"

help:
	@printf '%s\n' \
	  'Matrix stack lifecycle commands' \
	  '' \
	  '  make up                 Initialize safely and start production' \
	  '  make down               Stop production without deleting data' \
	  '  make status             Show health and checked URLs' \
	  '  make logs               Follow production logs' \
	  '' \
	  'Use MODE=local explicitly for the localhost-only stack:' \
	  '  make MODE=local up|down|status|logs'
