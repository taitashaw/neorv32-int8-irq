# NEORV32 application makefile (INT8 MLP)
MARCH = rv32imc_zicsr_zicntr_zifencei
EFFORT = -O2
USER_FLAGS += -DUART0_SIM_MODE
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
APP_INC += -I ../common
NEORV32_HOME ?= ../../neorv32
include $(NEORV32_HOME)/sw/common/common.mk
