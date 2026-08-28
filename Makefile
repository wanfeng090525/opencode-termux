# OpenCode for Termux — 构建
VER ?= 1.18.23
OUT := opencode_$(VER)_aarch64.deb

.PHONY: help wrap deb all clean

help:
	@echo "  make wrap     produce runtime/opencode-termux (npm download + bun-termux-loader)"
	@echo "  make deb      build $(OUT)"
	@echo "  make all      wrap + deb"
	@echo "  make clean    remove outputs"
	@echo "  VERSION: make VER=1.19.0 all"

wrap:
	./scripts/produce.sh $(VER)

deb: wrap
	VERSION=$(VER) ./scripts/package_deb.sh

all: wrap deb

clean:
	rm -rf runtime .cache opencode_*.deb