#---------------------------------------------------------------------------------
# Clear the implicit built in rules
#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------
ifeq ($(strip $(DEVKITPPC)),)
$(error "Please set DEVKITPPC in your environment. export DEVKITPPC=<path to>devkitPPC")
endif
ifeq ($(strip $(DEVKITPRO)),)
$(error "Please set DEVKITPRO in your environment. export DEVKITPRO=<path to>devkitPRO")
endif
export PATH			:=	$(DEVKITPPC)/bin:$(PORTLIBS)/bin:$(PATH)
export PORTLIBS		:=	$(DEVKITPRO)/portlibs/ppc

PREFIX	:=	powerpc-eabi-

export AS	    :=	$(PREFIX)as
export CC	    :=	$(PREFIX)gcc
export CXX	    :=	$(PREFIX)g++
export AR	    :=	$(PREFIX)ar
export OBJCOPY	:=	$(PREFIX)objcopy

#---------------------------------------------------------------------------------
# TARGET is the name of the output
# BUILD is the directory where object files & intermediate files will be placed
# SOURCES is a list of directories containing source code
# INCLUDES is a list of directories containing extra header files
#---------------------------------------------------------------------------------
TARGET		   := CodeLib
BUILD		   := build
BUILD_DBG	   := $(TARGET)_dbg
SOURCES		   := .
DATA		   :=
INCLUDES	   :=  include

# You might want to add one if those don't work (Issue with newer Cemu Versions)
MODULE_MATCHES := 0x867317DE,0x6237F45C,0x90112329

#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
CFLAGS	 :=  -std=gnu17 -mrvl -nostdlib -mcpu=750 -meabi -mhard-float -ffast-math -fshort-wchar -finline -Wl,-q -nostartfiles -fdata-sections -ffunction-sections \
		      -Os -D_GNU_SOURCE $(INCLUDE)
CXXFLAGS :=  -std=gnu++17 -mrvl -nostdlib -mcpu=750 -meabi -mhard-float -ffast-math -fshort-wchar -finline -Wl,-q -nostartfiles -fdata-sections -ffunction-sections \
		      -Os -D_GNU_SOURCE $(INCLUDE)
ASFLAGS	:= -mregnames
LDFLAGS	:= -Wl,-Map,$(notdir $@).map,--gc-sections

#---------------------------------------------------------------------------------
Q := @
MAKEFLAGS += --no-print-directory
#---------------------------------------------------------------------------------
# any extra libraries we wish to link with the project
#---------------------------------------------------------------------------------
LIBS	:= 

#---------------------------------------------------------------------------------
# list of directories containing libraries, this must be the top level containing
# include and lib
#---------------------------------------------------------------------------------
LIBDIRS	:=	$(CURDIR)	\
			$(DEVKITPPC)/lib  \
			$(DEVKITPPC)/lib/gcc/powerpc-eabi/12.1.0 \
			$(PORTLIBS)

#---------------------------------------------------------------------------------
# no real need to edit anything past this point unless you need to add additional
# rules for different file extensions
#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------
export PROJECTDIR := $(CURDIR)
export OUTPUT	:=	$(CURDIR)/$(TARGETDIR)/$(TARGET)
export VPATH	:=	$(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) \
					$(foreach dir,$(DATA),$(CURDIR)/$(dir))
export DEPSDIR	:=	$(CURDIR)/$(BUILD)

#---------------------------------------------------------------------------------
# automatically build a list of object files for our project
#---------------------------------------------------------------------------------
CFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
CPPFILES	:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.cpp)))
sFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))
SFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.S)))
BINFILES	:=	$(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.*)))
TTFFILES	:=	$(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.ttf)))
PNGFILES	:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.png)))

#---------------------------------------------------------------------------------
# use CXX for linking C++ projects, CC for standard C
#---------------------------------------------------------------------------------
ifeq ($(strip $(CPPFILES)),)
	export LD	:=	$(CC)
else
	export LD	:=	$(CXX)
endif

export OFILES	:=	$(CPPFILES:.cpp=.o) $(CFILES:.c=.o) \
					$(sFILES:.s=.o) $(SFILES:.S=.o) \
					$(PNGFILES:.png=.png.o) $(addsuffix .o,$(BINFILES))

#---------------------------------------------------------------------------------
# build a list of include paths
#---------------------------------------------------------------------------------
export INCLUDE	:=	$(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
					$(foreach dir,$(LIBDIRS),-I$(dir)/include) \
					-I$(CURDIR)/$(BUILD) -I$(LIBOGC_INC) \
					-I$(PORTLIBS)/include -I$(PORTLIBS)/include/freetype2

#---------------------------------------------------------------------------------
# build a list of library paths
#---------------------------------------------------------------------------------
export LIBPATHS	:=	$(foreach dir,$(LIBDIRS),-L$(dir)/lib) \
					-L$(LIBOGC_LIB) -L$(PORTLIBS)/lib

export OUTPUT	:=	$(CURDIR)/$(TARGET)
.PHONY: $(BUILD) clean install

all: $(BUILD)

#---------------------------------------------------------------------------------
$(BUILD):
	@$(shell [ ! -d $(BUILD) ] && mkdir -p $(BUILD))
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -fr $(BUILD) $(OUTPUT).elf $(OUTPUT).bin $(BUILD_DBG).elf

#---------------------------------------------------------------------------------
else

DEPENDS	:=	$(OFILES:.o=.d)

#---------------------------------------------------------------------------------
# main targets
#---------------------------------------------------------------------------------

all: $(OUTPUT).asm

%.asm: %.elf
	@echo "Creating text_section.bin";
	@$(OBJCOPY) --only-section=.text $^ -O binary text_section.bin
	@echo "Creating .asm Content"
	@python -c 'with open("text_section.bin", "rb") as f: print("[Wrapper]\nmoduleMatches = ${MODULE_MATCHES}\n\n0x02F37154 = b _onStart\n\n0x104D4DD8 = .uint _Code\n0x104D4DDC = .uint 0x0\n\n.origin = codecave\n\n# .text\n_Code:"); print(".uint", end=" 0x"); [print("%02x" % val, end="" if i % 4 != 0 else "\n.uint 0x") for i, val in enumerate(f.read(), 1)]; print("00000000\n\n_onStart:\nbctrl\nlis r12, _Code@ha\naddi r12, r12, _Code@l\nmtctr r12\nbctrl\nb 0x02F37158")' > "$@"
	@python -c 'with open("$@") as f: print("Total Lines Written: " + str(sum(1 for _ in f)));'
	@cp "$@" "../GraphicPack/patch_codelib.asm" # small hack

$(OUTPUT).elf: $(OFILES)

#---------------------------------------------------------------------------------
# This rule links in binary data with the .jpg extension
#---------------------------------------------------------------------------------
%.elf: link.ld $(OFILES)
	@echo "Linking... $(TARGET).elf"
	$(Q)$(LD) -n -T $^ $(LDFLAGS) -o ../$(BUILD_DBG).elf $(LIBPATHS) $(LIBS)
	$(Q)$(OBJCOPY) -R .comment -R .gnu.attributes ../$(BUILD_DBG).elf $@

#---------------------------------------------------------------------------------
%.a:
#---------------------------------------------------------------------------------
	@echo $(notdir $@)
	@rm -f $@
	@$(AR) -rc $@ $^

#---------------------------------------------------------------------------------
%.o: %.cpp
	@echo $(notdir $<)
	@$(CXX) -MMD -MP -MF $(DEPSDIR)/$*.d $(CXXFLAGS) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.o: %.c
	@echo $(notdir $<)
	@$(CC) -MMD -MP -MF $(DEPSDIR)/$*.d $(CFLAGS) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.o: %.S
	@echo $(notdir $<)
	@$(CC) -MMD -MP -MF $(DEPSDIR)/$*.d -x assembler-with-cpp $(ASFLAGS) -c $< -o $@ $(ERROR_FILTER)

#---------------------------------------------------------------------------------
%.png.o : %.png
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.jpg.o : %.jpg
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.ttf.o : %.ttf
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.bin.o : %.bin
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.wav.o : %.wav
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.mp3.o : %.mp3
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

#---------------------------------------------------------------------------------
%.ogg.o : %.ogg
	@echo $(notdir $<)
	@bin2s -a 32 $< | $(AS) -o $(@)

-include $(DEPENDS)

#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------