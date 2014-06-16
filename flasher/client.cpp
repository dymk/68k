#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

// prototypes
void usage(const char*);

int main(int argc, char **argv) {

	if(argc != 2) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	HANDLE comm_port = ::CreateFile(argv[1],
		GENERIC_READ|GENERIC_WRITE,  // access ( read and write)
		0,                           // (share) 0:cannot share the COM port
		0,                           // security  (None)
		OPEN_EXISTING,               // creation : open_existing
		FILE_FLAG_OVERLAPPED,        // we want overlapped operation
		0                            // no templates file for COM port...
		);

	return 0;
}

void usage(const char *name) {
	fprintf(stderr, "usage:\n\t%s COMPORT\n", name);
}
