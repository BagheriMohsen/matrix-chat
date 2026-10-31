.DEFAULT_GOAL := help

# Select explicitly: make MODE=local up. Production is the safe default.
MODE ?= production
CALLS ?= 0

.PHONY: up down status logs help

up:
	@bash scripts/stack.sh up "$(MODE)" "$(CALLS)"

down:
	@bash scripts/stack.sh down "$(MODE)" "$(CALLS)"

status:
	@bash scripts/stack.sh status "$(MODE)" "$(CALLS)"

logs:
	@bash scripts/stack.sh logs "$(MODE)" "$(CALLS)"

help:
	@printf '%s\n' \
	  'Matrix stack lifecycle commands' \
	  '' \
	  '  make up                 Initialize safely and start production' \
	  '  make down               Stop production without deleting data' \
	  '  make status             Show health and checked URLs' \
	  '  make logs               Follow production logs' \
	  '  make up CALLS=1         Start production with optional coturn' \
	  '' \
	  'Use MODE=local explicitly for the localhost-only stack:' \
	  '  make MODE=local up|down|status|logs' \
	  '' \
	  'CALLS=1 requires TURN_ENABLED=1 and is supported for production only.'
