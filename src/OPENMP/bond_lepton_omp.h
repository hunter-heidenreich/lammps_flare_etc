/* -*- c++ -*- ----------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator
   https://www.lammps.org/, Sandia National Laboratories
   LAMMPS development team: developers@lammps.org

   Copyright (2003) Sandia Corporation.  Under the terms of Contract
   DE-AC04-94AL85000 with Sandia Corporation, the U.S. Government retains
   certain rights in this software.  This software is distributed under
   the GNU General Public License.

   See the README file in the top-level LAMMPS directory.
------------------------------------------------------------------------- */

#ifdef BOND_CLASS
// clang-format off
BondStyle(lepton/omp,BondLeptonOMP);
// clang-format on
#else

#ifndef LMP_BOND_LEPTON_OMP_H
#define LMP_BOND_LEPTON_OMP_H

#include "bond_lepton.h"
#include "thr_omp.h"

namespace LAMMPS_NS {

class BondLeptonOMP : public BondLepton, public ThrOMP {

 public:
  BondLeptonOMP(class LAMMPS *lmp);
  void compute(int, int) override;

 private:
  template <int EVFLAG, int EFLAG, int NEWTON_BOND>
  void eval(int ifrom, int ito, ThrData *const thr);
};
}    // namespace LAMMPS_NS
#endif
#endif
