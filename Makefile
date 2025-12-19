.PHONY: all build clean

# Build directory
BIN_DIR := ./bin

# Binary name
BINARY := git-backup

# Go build flags
GOOS := linux
GOARCH := amd64

all: build

build:
	@echo "Building $(BINARY) for Linux..."
	@mkdir -p $(BIN_DIR)
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build -o $(BIN_DIR)/$(BINARY) main.go
	@echo "Build complete: $(BIN_DIR)/$(BINARY)"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BIN_DIR)
	@echo "Clean complete"
