BUILDDIR := bin
OUTPUT := $(BUILDDIR)/main.out

all: $(OUTPUT)

$(BUILDDIR)/%.o: %.asm | $(BUILDDIR)
	nasm -f elf64 $< -o $@

$(BUILDDIR)/%.out: $(BUILDDIR)/%.o
	ld $< -o $@

debug: $(OUTPUT)
	gdb -q --args $(OUTPUT) bin/test.qoi a.bmp

test: $(OUTPUT)
	$(OUTPUT) bin/test.qoi a.bmp

clean:
	rm -f $(OUTPUT)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

