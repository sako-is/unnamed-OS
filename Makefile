
# This is the name that our final kernel executable will have.
# Change as needed.
override KERNEL := kernel.elf

CC := clang
LD := ld.lld

# Convenience macro to reliably declare overridable command variables.
define DEFAULT_VAR =
    ifeq ($(origin $1),default)
        override $(1) := $(2)
    endif
    ifeq ($(origin $1),undefined)
        override $(1) := $(2)
    endif
endef

# It is highly recommended to use a custom built cross toolchain to build a kernel.
# We are only using "cc" as a placeholder here. It may work by using
# the host system's toolchain, but this is not guaranteed.
$(eval $(call DEFAULT_VAR,CC,cc))

# Same thing for "ld" (the linker).
$(eval $(call DEFAULT_VAR,LD,ld))

# User controllable CFLAGS.
CFLAGS ?= -g -O3 -pipe -Wall -Wextra

# User controllable preprocessor flags. We set none by default.
CPPFLAGS ?=

# User controllable nasm flags.
NASMFLAGS ?= -F dwarf -g

# User controllable linker flags. We set none by default.
LDFLAGS ?=

# Internal C flags that should not be changed by the user.
override CFLAGS +=       	 \
    -std=c18             	 \
    -ffreestanding       	 \
    -fno-stack-protector 	 \
    -fno-stack-check     	 \
    -fno-lto             	 \
    -fno-pie             	 \
    -fno-pic             	 \
    -m64                 	 \
	-target x86_64-none-elf  \
    -march=x86-64        	 \
    -mabi=sysv           	 \
    -mcmodel=kernel      	 \
    -MMD                 	 \
    -I.						 \
	-Iinclude/

# Internal linker flags that should not be changed by the user.
override LDFLAGS +=         \
    -nostdlib               \
    -static                 \
    -m elf_x86_64           \
    -z max-page-size=0x1000 \
    -T linker.ld

# Check if the linker supports -no-pie and enable it if it does
ifeq ($(shell $(LD) --help 2>&1 | grep 'no-pie' >/dev/null 2>&1; echo $$?),0)
    override LDFLAGS += -no-pie
endif

# Internal nasm flags that should not be changed by the user.
override NASMFLAGS += \
    -f elf64

# Use find to glob all *.c, *.S, and *.asm files in the directory and extract the object names.
override CFILES := $(shell find kernel -type f -name '*.c')
override ASFILES := $(shell find . -type f -name '*.S')
override NASMFILES := $(shell find . -type f -name '*.asm')
override OBJ := $(CFILES:.c=.o) $(ASFILES:.S=.o) $(NASMFILES:.asm=.o)
override HEADER_DEPS := $(CFILES:.c=.d) $(ASFILES:.S=.d)

# Default target.
.PHONY: all
all: $(KERNEL)
	cp -v kernel.elf limine.cfg limine/limine.sys limine/limine-cd.bin limine/limine-cd-efi.bin iso/
	xorriso -as mkisofs -b limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot limine-cd-efi.bin -efi-boot-part --efi-boot-image --protective-msdos-label iso -o image.iso
	./limine/limine-deploy image.iso
	
limine.h:
		# curl https://raw.githubusercontent.com/limine-bootloader/limine/trunk/limine.h -o include/limine/$@

# Link rules for the final kernel executable.
$(KERNEL): $(OBJ)
	$(LD) $(OBJ) $(LDFLAGS) bin/tamsyn.o -o $@

# Include header dependencies.
-include $(HEADER_DEPS)

# Compilation rules for *.c files.
%.o: %.c limine.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

# Compilation rules for *.S files.
%.o: %.S limine.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

# Compilation rules for *.asm (nasm) files.
%.o: %.asm
	nasm $(NASMFLAGS) $< -o $@

# Remove object files and the final executable.
.PHONY: clean
clean:
	rm -rf $(KERNEL) $(OBJ) $(HEADER_DEPS)

.PHONY: distclean
distclean: clean
	rm -f limine.h