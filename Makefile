.DEFAULT_GOAL := help

# Select explicitly: make MODE=local up. Production is the safe default.
MODE ?= production
CALLS ?= 0

.PHONY: up down restart update status logs admin-up admin-down admin-status admin-logs admin-check help

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

# Ketesa is deliberately separate from the normal stack lifecycle. These
# commands never restart Nginx, Synapse, or PostgreSQL.
admin-up:
	@bash scripts/admin.sh up

admin-down:
	@bash scripts/admin.sh down

admin-status:
	@bash scripts/admin.sh status

admin-logs:
	@bash scripts/admin.sh logs

admin-check:
	@bash scripts/admin.sh check

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
	  '  make admin-up           Start only the optional localhost-only Ketesa UI' \
	  '  make admin-down         Stop only Ketesa' \
	  '  make admin-status       Show Ketesa status' \
	  '  make admin-logs         Follow Ketesa logs' \
	  '  make admin-check        Check Ketesa and its localhost-only route' \
	  '  make up CALLS=1         Start production with optional coturn' \
	  '' \
	  'Use MODE=local explicitly for the localhost-only stack:' \
	  '  make MODE=local up|down|restart|update|status|logs' \
	  '' \
	  'CALLS=1 requires TURN_ENABLED=1 and is supported for production only.' \
	  'Run git pull --ff-only yourself before make update; it never pulls Git changes.'
