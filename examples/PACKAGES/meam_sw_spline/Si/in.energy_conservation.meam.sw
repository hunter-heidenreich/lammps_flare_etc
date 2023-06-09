# bulk Si lattice

variable        x index 1
variable        y index 1
variable        z index 1

units           metal
atom_style      atomic


atom_style      atomic
lattice         diamond 5.431
region          box block 0 5 0 5 0 5
boundary       p p p

create_box      1 box
create_atoms    1 box


pair_style      meam/sw/spline
pair_coeff      * * Si.b.meam.sw.spline Si
mass            * 28.085

velocity        all create 300.0 376847 loop geom

neighbor        1.0 bin
neigh_modify    every 1 delay 5 check yes

fix             1 all nve

thermo 1
thermo_style    custom step vol etotal press pxx pyy pxz
thermo_modify   format 2 %14.8f
thermo_modify   format 3 %14.8f
thermo_modify   format 4 %14.8f
thermo_modify   format 5 %14.8f
thermo_modify   format 6 %14.8f
thermo_modify   format 7 %14.8f


timestep        0.002
thermo          10

run             2000

