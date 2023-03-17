<pre>
cd src
make serial 'CCFLAGS = -O3 -g `pkg-config --cflags eigen3`'
./lmp_serial -in 1.in
</pre>
