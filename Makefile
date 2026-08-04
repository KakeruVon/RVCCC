# Makefile for implementing the project with Verilator and NVboard.

TOPNAME = RVCCC
NXDC_FILES = constr/RVCCC.nxdc
INC_PATH ?=
BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)
ASM ?= programs/cnn_mmio_poll.S
INSTR_MEM ?= mem_files/instruction.mem

VERILATOR = verilator
VERILATOR_CFLAGS += -MMD --build -cc  \
					-O3 --x-assign fast --x-initial fast --noassert

default: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# constraint file
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
# CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
CSRCS = $(abspath ./csrc/run.cpp)
CSRCS += $(SRC_AUTO_BIND)

# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk

# rules for verilator
INCFLAGS = $(addprefix -I, $(INC_PATH))
CXXFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	@rm -rf $(OBJ_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CXXFLAGS)) $(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

all: default

program:
	python3 scripts/asm_to_mem.py $(ASM) -o $(INSTR_MEM)

sim:
	$(VERILATOR) --trace -cc --exe --build -j ./vsrc/top.v ./csrc/sim.cpp

run: $(BIN)
	@$^
	
clean:
	rm -rf $(BUILD_DIR)

.PHONY: default all program sim clean run
include /home/steve-von/ysyx-workbench/Makefile
