/***************************************************************************
                                   ufm.cu
                             -------------------
                            Rodolfo Paula Leite (Unicamp/Brazil)
                            Maurice de Koning (Unicamp/Brazil)

  Device code for acceleration of the ufm pair style

 __________________________________________________________________________
    This file is part of the LAMMPS Accelerator Library (LAMMPS_AL)
 __________________________________________________________________________

    begin                :
    email                : pl.rodolfo@gmail.com
                           dekoning@ifi.unicamp.br
 ***************************************************************************/

#if defined(NV_KERNEL) || defined(USE_HIP)
#include "lal_aux_fun1.h"
#ifndef _DOUBLE_DOUBLE
_texture( pos_tex,float4);
#else
_texture_2d( pos_tex,int4);
#endif
#else
#define pos_tex x_
#endif

__kernel void k_ufm(const __global numtyp4 *restrict x_,
                   const __global numtyp4 *restrict uf1,
                   const __global numtyp4 *restrict uf3,
                   const int lj_types,
                   const __global numtyp *restrict sp_lj,
                   const __global int * dev_nbor,
                   const __global int * dev_packed,
                   __global acctyp3 *restrict ans,
                   __global acctyp *restrict engv,
                   const int eflag, const int vflag, const int inum,
                   const int nbor_pitch, const int t_per_atom) {
  int tid, ii, offset;
  atom_info(t_per_atom,ii,tid,offset);

  int n_stride;
  local_allocate_store_pair();

  acctyp3 f;
  f.x=(acctyp)0; f.y=(acctyp)0; f.z=(acctyp)0;
  acctyp energy, virial[6];
  if (EVFLAG) {
    energy=(acctyp)0;
    for (int i=0; i<6; i++) virial[i]=(acctyp)0;
  }

  if (ii<inum) {
    int i, numj, nbor, nbor_end;
    nbor_info(dev_nbor,dev_packed,nbor_pitch,t_per_atom,ii,offset,i,numj,
              n_stride,nbor_end,nbor);

    numtyp4 ix; fetch4(ix,i,pos_tex); //x_[i];
    int itype=ix.w;

    numtyp factor_lj;
    for ( ; nbor<nbor_end; nbor+=n_stride) {
      ucl_prefetch(dev_packed+nbor+n_stride);

      int j=dev_packed[nbor];
      factor_lj = sp_lj[sbmask(j)];
      j &= NEIGHMASK;

      numtyp4 jx; fetch4(jx,j,pos_tex); //x_[j];
      int jtype=jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp rsq = delx*delx+dely*dely+delz*delz;

      int mtype=itype*lj_types+jtype;
      if (rsq<uf1[mtype].z) {
        numtyp expuf = exp(- rsq * uf1[mtype].y);
        numtyp force = factor_lj * uf1[mtype].x * expuf / (1.0 - expuf);

        f.x += delx*force;
        f.y += dely*force;
        f.z += delz*force;

        if (EVFLAG && eflag) {
          energy += - factor_lj * uf3[mtype].x*log(1.0 - expuf) - uf3[mtype].z;
        }
        if (EVFLAG && vflag) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
  } // if ii
  store_answers(f,energy,virial,ii,inum,tid,t_per_atom,offset,eflag,vflag,
                ans,engv);
}

__kernel void k_ufm_fast(const __global numtyp4 *restrict x_,
                        const __global numtyp4 *restrict uf1_in,
                        const __global numtyp4 *restrict uf3_in,
                        const __global numtyp *restrict sp_lj_in,
                        const __global int * dev_nbor,
                        const __global int * dev_packed,
                        __global acctyp3 *restrict ans,
                        __global acctyp *restrict engv,
                        const int eflag, const int vflag, const int inum,
                        const int nbor_pitch, const int t_per_atom) {
  int tid, ii, offset;
  atom_info(t_per_atom,ii,tid,offset);

  __local numtyp4 uf1[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp4 uf3[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp sp_lj[4];
  int n_stride;
  local_allocate_store_pair();

  if (tid<4)
    sp_lj[tid]=sp_lj_in[tid];
  if (tid<MAX_SHARED_TYPES*MAX_SHARED_TYPES) {
    uf1[tid]=uf1_in[tid];
    if (EVFLAG && eflag)
      uf3[tid]=uf3_in[tid];
  }

  acctyp3 f;
  f.x=(acctyp)0; f.y=(acctyp)0; f.z=(acctyp)0;
  acctyp energy, virial[6];
  if (EVFLAG) {
    energy=(acctyp)0;
    for (int i=0; i<6; i++) virial[i]=(acctyp)0;
  }

  __syncthreads();

  if (ii<inum) {
    int i, numj, nbor, nbor_end;
    nbor_info(dev_nbor,dev_packed,nbor_pitch,t_per_atom,ii,offset,i,numj,
              n_stride,nbor_end,nbor);

    numtyp4 ix; fetch4(ix,i,pos_tex); //x_[i];
    int iw=ix.w;
    int itype=fast_mul((int)MAX_SHARED_TYPES,iw);

    numtyp factor_lj;
    for ( ; nbor<nbor_end; nbor+=n_stride) {
      ucl_prefetch(dev_packed+nbor+n_stride);

      int j=dev_packed[nbor];
      factor_lj = sp_lj[sbmask(j)];
      j &= NEIGHMASK;

      numtyp4 jx; fetch4(jx,j,pos_tex); //x_[j];
      int mtype=itype+jx.w;

      // Compute r12
      numtyp delx = ix.x-jx.x;
      numtyp dely = ix.y-jx.y;
      numtyp delz = ix.z-jx.z;
      numtyp rsq = delx*delx+dely*dely+delz*delz;

      if (rsq<uf1[mtype].z) {
        numtyp expuf = exp(- rsq * uf1[mtype].y);
        numtyp force = factor_lj * uf1[mtype].x * expuf / (1.0 - expuf);

        f.x += delx*force;
        f.y += dely*force;
        f.z += delz*force;

        if (EVFLAG && eflag) {
          energy += - factor_lj * uf3[mtype].x * log(1.0 - expuf) - uf3[mtype].z;
        }
        if (EVFLAG && vflag) {
          virial[0] += delx*delx*force;
          virial[1] += dely*dely*force;
          virial[2] += delz*delz*force;
          virial[3] += delx*dely*force;
          virial[4] += delx*delz*force;
          virial[5] += dely*delz*force;
        }
      }

    } // for nbor
  } // if ii
  store_answers(f,energy,virial,ii,inum,tid,t_per_atom,offset,eflag,vflag,
                ans,engv);
}

