.PHONY: contracts validate test verify

MODULES ?=
MODULE_ARGS = $(if $(MODULES),--modules $(MODULES),)

contracts:
	python3 -m unittest discover -s tests -p 'test_*.py' -v
	python3 tests/verify_modules.py --static-only $(MODULE_ARGS)

validate:
	python3 tests/verify_modules.py $(MODULE_ARGS)

test: validate

verify:
	python3 -m unittest discover -s tests -p 'test_*.py'
	python3 tests/verify_modules.py $(MODULE_ARGS)
