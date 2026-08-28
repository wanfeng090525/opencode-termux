# OpenCode for Termux — build orchestrator
SHELL := /bin/bash
.DEFAULT_GOAL := help

VER ?= 1.18.25
VERS ?=
PKG ?= both
ODIR ?=
MIX ?= 0
TAG ?= Push$(shell date +%y%m%d)
REPO ?= wanfeng090525/opencode-termux
OUTPUT_ROOT := $(if $(ODIR),$(ODIR),$(CURDIR)/packing)
STAGE := artifacts/staged/prefix

.PHONY: help wrap stage deb pacman all batch clean release-upload smoke

help:
	@echo "OpenCode Termux build helper"
	@echo
	@echo "Primary:"
	@echo "  make all VER=1.18.23 PKG=both      wrap + stage + package (deb and/or pacman)"
	@echo "  make all VER=latest PKG=pacman"
	@echo "  make wrap                          npm opencode-linux-arm64@VER + bun-termux-loader -> runtime/opencode-termux"
	@echo "  make stage                         stage install prefix -> artifacts/staged/prefix"
	@echo "  make deb                           build opencode_<ver>_aarch64.deb (needs stage)"
	@echo "  make pacman                        build opencode-<ver>-1-aarch64.pkg.tar.xz (needs stage, no makepkg)"
	@echo
	@echo "Batch + release:"
	@echo "  make batch VERS='1.18.23 1.19.0' PKG=both ODIR=~/oct-out"
	@echo "  make batch VERS='1.18.[20-23]' PKG=deb ODIR=~/oct-out"
	@echo "  make release-upload TAG=Push260828 VERS='1.18.[20-23]' REPO=$(REPO)"
	@echo
	@echo "Output policy:"
	@echo "  Default root: ./packing. With ODIR: write to ODIR only."
	@echo "  MIX=1 flattens artifacts into one dir."

wrap:
	./scripts/produce.sh $(VER)

stage: wrap
	./scripts/build.sh

deb: stage
	VERSION=$(VER) ./scripts/package_deb.sh

pacman: stage
	VERSION=$(VER) ./scripts/package_pacman.sh

all:
	$(MAKE) wrap
	$(MAKE) stage
	@case "$(PKG)" in \
		deb) $(MAKE) deb ;; \
		pacman) $(MAKE) pacman ;; \
		*) $(MAKE) deb && $(MAKE) pacman ;; \
	esac
	$(MAKE) package_out

batch:
	@if [ -z "$(VERS)" ]; then echo "Error: VERS is empty, e.g. VERS='1.18.23 1.19.0'"; exit 1; fi
	@expanded=(); \
	for token in $(VERS); do \
		if [[ "$$token" =~ ^([0-9]+\.[0-9]+)\.\[([0-9]+)-([0-9]+)\]$$ ]]; then \
			base="$${BASH_REMATCH[1]}"; start="$${BASH_REMATCH[2]}"; end="$${BASH_REMATCH[3]}"; \
			for ((i=start; i<=end; i++)); do expanded+=("$$base.$$i"); done; \
		else expanded+=("$$token"); fi; \
	done; \
	for v in "$${expanded[@]}"; do \
		echo "=== Batch build $$v ==="; \
		$(MAKE) all VER=$$v PKG=$(PKG) ODIR=$(ODIR) MIX=$(MIX) || exit 1; \
	done

# After deb/pacman, honor output policy (ODIR/MIX flatten).
package_out:
	@if [ "$(OUTPUT_ROOT)" != "$(CURDIR)/packing" ]; then \
		if [ "$(MIX)" = "1" ]; then \
			mkdir -p "$(OUTPUT_ROOT)" && cp -f opencode_*.deb "$(OUTPUT_ROOT)/" 2>/dev/null || true; \
			cp -f packing/pacman/opencode-*.pkg.* "$(OUTPUT_ROOT)/" 2>/dev/null || true; \
		else \
			mkdir -p "$(OUTPUT_ROOT)/deb" && cp -f opencode_*.deb "$(OUTPUT_ROOT)/deb/" 2>/dev/null || true; \
			mkdir -p "$(OUTPUT_ROOT)/pacman" && cp -f packing/pacman/opencode-*.pkg.* "$(OUTPUT_ROOT)/pacman/" 2>/dev/null || true; \
		fi; \
	fi

clean:
	rm -rf runtime .cache artifacts opencode_*.deb
	rm -rf packing/deb packing/pacman/pkg packing/pacman/src

# Run-level smoke: extract inner aarch64 Bun ELF and run it via qemu + arm64 glibc.
# Needs: apt install qemu-user-static + libc6:arm64 (dpkg --add-architecture arm64).
smoke:
	./scripts/smoke_qemu.sh runtime/opencode-termux "$(VER)"

# Release upload: batch build -> push all assets to a release tag (create or clobber).
release-upload:
	@if [ -z "$(VERS)" ]; then echo "Error: VERS is required, e.g. VERS='1.18.[20-23]'"; exit 1; fi
	@echo "=== Release upload: TAG=$(TAG) VERS=$(VERS) PKG=$(PKG) REPO=$(REPO) ==="
	$(MAKE) batch VERS='$(VERS)' PKG='$(PKG)' ODIR='/tmp/oc-release-$(TAG)' MIX=1
	@echo "=== Uploading to release $(TAG) ==="; \
	failed=0; \
	if ! gh release view "$(TAG)" --repo "$(REPO)" >/dev/null 2>&1; then \
		echo "Creating release $(TAG)..."; \
		gh release create "$(TAG)" --repo "$(REPO)" --title "$(TAG)" --notes "Automated build $$(date -u +%Y-%m-%d)" || exit 1; \
	fi; \
	for f in /tmp/oc-release-$(TAG)/opencode_*.deb /tmp/oc-release-$(TAG)/opencode-*.pkg.*; do \
		if [ -f "$$f" ]; then \
			echo "  uploading $$(basename $$f)..."; \
			gh release upload "$(TAG)" "$$f" --repo "$(REPO)" --clobber || failed=1; \
		fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then echo "Error: some assets failed to upload" >&2; exit 1; fi; \
	echo "=== Done: https://github.com/$(REPO)/releases/tag/$(TAG) ==="