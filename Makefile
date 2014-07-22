LUADATA?=.
CC=gcc
CFLAGS=-I$(LUADATA) -fPIC
LDLIBS=-llua
OBJ=data_io.o

data_io.so: $(OBJ)
	$(CC) -shared -o $@ $(OBJ) $(LDLIBS)

clean:
	rm -f *.so *.o || true
