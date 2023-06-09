SHELL = /bin/sh

# Path to LAMMPS extraction directory
LAMMPS_ROOT = ../../..
LAMMPS_SRC = $(LAMMPS_ROOT)/src

# Uncomment the line below if using the MPI stubs library
MPI_STUBS = #-I$(LAMMPS_SRC)/STUBS

FC = mpifort         # replace with your Fortran compiler
CXX = mpicxx         # replace with your C++ compiler
CXXLIB = -lstdc++    # replace with your C++ runtime libs

# Flags for Fortran compiler, C++ compiler, and C preprocessor, respectively
FFLAGS = -O2 -fPIC
CXXFLAGS = -O2 -fPIC
CPPFLAGS = -DOMPI_SKIP_MPICXX=1 -DMPICH_SKIP_MPICXX

all : liblammps_fortran.a liblammps_fortran.so
	@echo "WARNING: this Fortran interface is obsolete and is no longer
maintained. See $(LAMMPS_ROOT)/fortran for the new, maintained interface
(largely written by the same author). You may continue to use this interface if
desired, but it may eventually be removed from LAMMPS."

liblammps_fortran.so : LAMMPS.o LAMMPS-wrapper.o
	$(FC) $(FFLAGS) -shared -o $@ $^ $(CXXLIB)

liblammps_fortran.a : LAMMPS.o LAMMPS-wrapper.o
	$(AR) rs $@ $^

LAMMPS.o lammps.mod : LAMMPS.F90
	$(FC) $(CPPFLAGS) $(FFLAGS) -c $<

LAMMPS-wrapper.o : LAMMPS-wrapper.cpp LAMMPS-wrapper.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -I$(LAMMPS_SRC) $(MPI_STUBS)

clean :
	$(RM) *.o *.mod liblammps_fortran.a liblammps_fortran.so

dist :
	tar -czf Fortran-interface.tar.gz LAMMPS-wrapper.h LAMMPS-wrapper.cpp LAMMPS.F90 makefile README
