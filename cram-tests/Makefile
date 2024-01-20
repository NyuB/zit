# Can only be run on Linux
# See the docker targets in the main Makefile for testing from Windows

EXEC=$(CURDIR)/../bin/lin/bin/tools
PY=python3

ifeq ($(PROMOTE), y)
	CRAM=cram -i -y
else
	CRAM=cram
endif

test:
	EXEC=$(EXEC) $(PY) -m $(CRAM) diff

