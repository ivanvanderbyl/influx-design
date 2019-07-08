.PHONY: list

list:
	@awk -F: '/^[A-z]/ {print $$1}' Makefile | sort

proof:
	@echo "weasel words: "
	@sh bin/weasel.sh *.md
	@echo
	@echo "passive voice: "
	@sh bin/passive.sh *.md
