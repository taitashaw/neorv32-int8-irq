# dot4_irq: INT8 inference on the CFU under interrupts, combined NEORV32 design, with the
# CFU accumulator saved across the trap (CFU_SAVE=1: GETACC in the handler, SETACC to restore)
MARCH = rv32imc_zicsr_zicntr_zifencei
EFFORT = -O2
RISCV_PREFIX ?= riscv64-unknown-elf-
USER_FLAGS += -DUART0_SIM_MODE
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
APP_INC += -I ../common

N_IRQ ?= 500
HANDLER_TOUCHES_CFU ?= 1
CFU_SAVE ?= 1
USER_FLAGS += -DN_IRQ=$(N_IRQ) -DHANDLER_TOUCHES_CFU=$(HANDLER_TOUCHES_CFU) -DCFU_SAVE=$(CFU_SAVE)

# latency bounds (cycles) come from a json file, the same file the gate reads
BOUNDS_JSON ?= ../../scripts/bounds_dot4.json
USER_FLAGS += $(shell python3 -I -c "import json,sys; b=json.load(open('$(BOUNDS_JSON)')); print(' '.join('-DBOUND_%s=%du' % (k, v) for k, v in b.items() if not k.startswith('_')))")

APP_SRC += main.c dot4_stress.S
NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
