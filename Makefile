config ?= release
PACKAGE := irc

BUILD_DIR ?= build/$(config)
SRC_DIR := $(PACKAGE)
tests_binary := $(BUILD_DIR)/$(PACKAGE)
docs_dir := build/$(PACKAGE)-docs

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

ssl ?= 3.0.x

ifeq (,$(filter $(ssl),0.9.0 1.1.x 3.0.x))
  $(error Unknown SSL version "$(ssl)". Use 0.9.0, 1.1.x or 3.0.x)
endif

SSL_FLAG := -Dopenssl_$(ssl)

ifeq ($(config),release)
	PONYC = corral run -- ponyc $(SSL_FLAG)
else
	PONYC = corral run -- ponyc --debug $(SSL_FLAG)
endif

SOURCE_FILES := $(shell find $(SRC_DIR) -name '*.pony')
EXAMPLES := $(shell find examples -mindepth 1 -maxdepth 1 -type d)

deps:
	corral fetch

test: unit-tests build-examples

unit-tests: $(tests_binary)
	$^ --exclude=integration --sequential

$(tests_binary): $(SOURCE_FILES) | $(BUILD_DIR)
	$(PONYC) -o $(BUILD_DIR) $(SRC_DIR)

build-examples: $(SOURCE_FILES)
	$(foreach example,$(EXAMPLES), \
		$(PONYC) $(example) -o $(BUILD_DIR) \
			--bin-name $(notdir $(example)) --path . || exit 1;)

clean:
	rm -rf $(BUILD_DIR)

$(docs_dir): $(SOURCE_FILES)
	rm -rf $(docs_dir)
	corral run -- pony-doc -o build $(SRC_DIR)

docs: $(docs_dir)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: deps test unit-tests build-examples clean docs
