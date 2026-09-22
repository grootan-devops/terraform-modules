.PHONY: contracts validate test verify

contracts:
	python3 tests/verify_modules.py --static-only

validate:
	python3 tests/verify_modules.py

test: validate

verify: contracts test
