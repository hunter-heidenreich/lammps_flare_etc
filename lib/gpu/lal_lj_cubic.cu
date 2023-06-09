// **************************************************************************
//                                  lj_cubic.cu
//                             -------------------
//                               Trung Dac Nguyen
//
//  Device code for acceleration of the lj/cubic pair style
//
// __________________________________________________________________________
//    This file is part of the LAMMPS Accelerator Library (LAMMPS_AL)
// __________________________________________________________________________
//
//    begin                :
//    email                : ndactrung@gmail.com
// ***************************************************************************

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

// LJ quantities scaled by epsilon and rmin = sigma*2^1/6 (see src/pair_lj_cubic.h)

#define _RT6TWO (numtyp)1.1224620483093730  /* 2^1/6 */
#define _PHIS (numtyp)-0.7869822485207097   /* energy at s */
#define _DPHIDS (numtyp)2.6899008972047196  /* gradient at s */
#define _A3 (numtyp)27.9335700460986445     /* cubic coefficient */

__kernel void k_lj_cubic(const __global numtyp4 *restrict x_,
                         const __global numtyp4 *restrict lj1,
                         const __global numtyp4 *restrict lj2,
                         const __global numtyp2 *restrict lj3,
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
      if (rsq<lj1[mtype].z) {
        numtyp r2inv,r6inv,force,t;
        r2inv=ucl_recip(rsq);
        if (rsq <= lj2[mtype].x) {
          r6inv = r2inv*r2inv*r2inv;
          force = r6inv * (lj1[mtype].x*r6inv - lj1[mtype].y);
        } else {
          numtyp r = ucl_sqrt(rsq);
          numtyp rmin = lj2[mtype].z*_RT6TWO;
          t = (r - lj2[mtype].y)/rmin;
          force = lj2[mtype].w*(-_DPHIDS + _A3*t*t/2.0)*r/rmin;
        }

        force*=factor_lj*r2inv;

        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (EVFLAG && eflag) {
          numtyp e;
          if (rsq <= lj2[mtype].x)
            e = r6inv*(lj3[mtype].x*r6inv-lj3[mtype].y);
          else
            e = lj2[mtype].w*(_PHIS + _DPHIDS*t - _A3*t*t*t/6.0);
          energy+=factor_lj*e;
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

__kernel void k_lj_cubic_fast(const __global numtyp4 *restrict x_,
                              const __global numtyp4 *restrict lj1_in,
                              const __global numtyp4 *restrict lj2_in,
                              const __global numtyp2 *restrict lj3_in,
                              const __global numtyp *restrict sp_lj_in,
                              const __global int * dev_nbor,
                              const __global int * dev_packed,
                              __global acctyp3 *restrict ans,
                              __global acctyp *restrict engv,
                              const int eflag, const int vflag, const int inum,
                              const int nbor_pitch, const int t_per_atom) {
  int tid, ii, offset;
  atom_info(t_per_atom,ii,tid,offset);

  __local numtyp4 lj1[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp4 lj2[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp2 lj3[MAX_SHARED_TYPES*MAX_SHARED_TYPES];
  __local numtyp sp_lj[4];
  int n_stride;
  local_allocate_store_pair();

  if (tid<4)
    sp_lj[tid]=sp_lj_in[tid];
  if (tid<MAX_SHARED_TYPES*MAX_SHARED_TYPES) {
    lj1[tid]=lj1_in[tid];
    lj2[tid]=lj2_in[tid];
    if (EVFLAG && eflag)
      lj3[tid]=lj3_in[tid];
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

      if (rsq<lj1[mtype].z) {
        numtyp r2inv,r6inv,force,t;
        r2inv=ucl_recip(rsq);
        if (rsq <= lj2[mtype].x) {
          r6inv = r2inv*r2inv*r2inv;
          force = r6inv * (lj1[mtype].x*r6inv - lj1[mtype].y);
        } else {
          numtyp r = ucl_sqrt(rsq);
          numtyp rmin = lj2[mtype].z*_RT6TWO;
          t = (r - lj2[mtype].y)/rmin;
          force = lj2[mtype].w*(-_DPHIDS + _A3*t*t/2.0)*r/rmin;
        }

        force*=factor_lj*r2inv;

        f.x+=delx*force;
        f.y+=dely*force;
        f.z+=delz*force;

        if (EVFLAG && eflag) {
          numtyp e;
          if (rsq <= lj2[mtype].x)
            e = r6inv*(lj3[mtype].x*r6inv-lj3[mtype].y);
          else
            e = lj2[mtype].w*(_PHIS + _DPHIDS*t - _A3*t*t*t/6.0);
          energy+=factor_lj*e;
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

