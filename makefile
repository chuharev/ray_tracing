ARCH = 30

BLOCK_SIZE_X = 32
BLOCK_SIZE_Y = 16

TARGET = ray_tracing

NUM_SPHERES=10
NUM_LIGHTS=2
#WIDTH   = 35
#HEIGHT	= 35
#WIDTH   = 800
#HEIGHT	= 600
WIDTH   = 1920
HEIGHT	= 1080
FILE_NAME =bmp/1.bmp

NVCC = nvcc -Xptxas="-v" -g -O3 -arch=sm_$(ARCH) -DBLOCK_SIZE_X=$(BLOCK_SIZE_X) -DBLOCK_SIZE_Y=$(BLOCK_SIZE_Y)

SOURCES = debug.cu lib/EasyBMP.cpp main.cu  ray_tracing.cu kernel.cu
OBJECTS = $(addsuffix .o, $(basename $(SOURCES)))

all: $(SOURCE) $(TARGET)

$(TARGET): $(OBJECTS)
	$(NVCC) $(OBJECTS) -o $@ -lcuda -lcurand

%.o: %.cu
	$(NVCC) -c $< -o $@ 
	
.PHONY: clean run check

test: 
	./$(TARGET) $(NUM_SPHERES) $(NUM_LIGHTS) $(WIDTH) $(HEIGHT) $(FILE_NAME)

clean:
	rm -rf  $(TARGET) $(OBJECTS) $(FILE_NAME)
