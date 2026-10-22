# irq_lat stress program for NEORV32 + irq_lat_mon
MARCH = rv32imc_zicsr_zifencei
EFFORT = -Os
RISCV_PREFIX ?= riscv64-unknown-elf-
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=16k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
USER_FLAGS += -DUART0_SIM_MODE

# number of interrupts per scenario and length of the interrupts-disabled loop
N_IRQ  ?= 500
CRIT_N ?= 50
USER_FLAGS += -DN_IRQ=$(N_IRQ) -DCRIT_N=$(CRIT_N)

# latency bounds (cycles) come from scripts/bounds.json, the same file the gate reads
BOUNDS_JSON ?= ../../scripts/bounds.json
USER_FLAGS += $(shell python3 -I -c "import json,sys; b=json.load(open('$(BOUNDS_JSON)')); print(' '.join('-DBOUND_%s=%du' % (k, v) for k, v in b.items() if not k.startswith('_')))")

APP_SRC += main.c stress.S
NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
