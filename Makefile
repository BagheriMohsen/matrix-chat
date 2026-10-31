.DEFAULT_GOAL := help

# Select explicitly: make MODE=local up. Production is the safe default.
MODE ?= production
CALLS ?= 0

.PHONY: up down restart update status logs help

up:
	@bash scripts/stack.sh up "$(MODE)" "$(CALLS)"

down:
	@bash scripts/stack.sh down "$(MODE)" "$(CALLS)"

restart:
	@bash scripts/stack.sh restart "$(MODE)" "$(CALLS)"

update:
	@bash scripts/stack.sh update "$(MODE)" "$(CALLS)"

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
	  '  make restart            Regenerate managed config and recreate affected services' \
	  '  make update             Use checked-out changes; pull missing pinned images and restart' \
	  '  make status             Show health and checked URLs' \
	  '  make logs               Follow production logs' \
	  '  make up CALLS=1         Start production with optional coturn' \
	  '' \
	  'Use MODE=local explicitly for the localhost-only stack:' \
	  '  make MODE=local up|down|restart|update|status|logs' \
	  '' \
	  'CALLS=1 requires TURN_ENABLED=1 and is supported for production only.' \
	  'Run git pull --ff-only yourself before make update; it never pulls Git changes.'
