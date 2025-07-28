# Version format validation
ifndef VERSION
$(error VERSION is not defined in project.mk)
endif

# Check if VERSION matches vX.Y.Z format
ifeq ($(shell echo "$(VERSION)" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$'),)
$(error Invalid VERSION format: $(VERSION). Must be in vX.Y.Z format (e.g., v1.0.0))
endif

# Extract version components for later use
VERSION_MAJOR := $(shell echo "$(VERSION)" | sed 's/v\([0-9]\+\)\..*/\1/')
VERSION_MINOR := $(shell echo "$(VERSION)" | sed 's/v[0-9]\+\.\([0-9]\+\)\..*/\1/')
VERSION_PATCH := $(shell echo "$(VERSION)" | sed 's/v[0-9]\+\.[0-9]\+\.\([0-9]\+\).*/\1/')
