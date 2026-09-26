.PHONY: contracts validate test verify

contracts:
	python3 -m unittest discover -s tests -p 'test_*.py' -v
	python3 tests/verify_modules.py --static-only

validate:
	python3 tests/verify_modules.py

test: validate

verify: contracts test
