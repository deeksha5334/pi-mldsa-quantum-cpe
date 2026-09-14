CC      ?= cc
PARAM   ?= 65

CFLAGS  += -Wall -Wextra -std=c99 -O2
CFLAGS  += -Imldsa_native -Isrc
CFLAGS  += -DMLD_CONFIG_NAMESPACE_PREFIX=mldsa
CFLAGS  += -DMLD_CONFIG_PARAMETER_SET=$(PARAM)

MLDSA_SRC = mldsa_native/mldsa_native.c
COMMON    = src/pt_common.c
RNG       = src/rng_getrandom.c
BIN       = build/pt-keygen build/pt-sign build/pt-verify

.PHONY: all clean vendor check

all: $(BIN)

build:
	mkdir -p build

build/pt-keygen: src/pt_keygen.c $(COMMON) $(RNG) $(MLDSA_SRC) | build
	$(CC) $(CFLAGS) -o $@ $^

build/pt-sign: src/pt_sign.c $(COMMON) $(RNG) $(MLDSA_SRC) | build
	$(CC) $(CFLAGS) -o $@ $^

build/pt-verify: src/pt_verify.c $(COMMON) $(RNG) $(MLDSA_SRC) | build
	$(CC) $(CFLAGS) -o $@ $^

vendor:
	cp -r $(MLDSA)/examples/monolithic_build/mldsa_native ./mldsa_native

clean:
	rm -rf build
