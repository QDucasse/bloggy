default: build

build:
	hugo

.PHONY: clean

clean:
	find public -type f ! \( -name '.git' -o -name '.gitignore' -o -name 'README.md' \) -delete
	find public -type d -empty -delete