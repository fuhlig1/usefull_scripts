#!/bin/bash

# get first all the prerequisites which are needed to build gcc
# compile all the packages as static, to have them and gcc completely separated
# from the system

# change the directories according to your needs 
# at least change the installation directory
tmpInstDir=/tmp/compiler/gcc/
sourceDir=/tmp/build_gcc/
instDir=/data.local1/uhlig/compiler/gcc/

# basic definitions
# change the values if needed 
gmp_version=gmp-5.1.3
#gmp_version=gmp-6.0.0a
mpfr_version=mpfr-3.1.2
mpc_version=mpc-1.0.2
isl_version=isl-0.11.1
#isl_version=isl-0.12.2
cloog_version=cloog-0.18.0
#cloog_version=cloog-0.18.1
gcc_version=gcc-4.9.0

# change the directories according to your needs 
# at least change the installation directory
tmpInstDir=$tmpInstDir/$gcc_version
sourceDir=$sourceDir/$gcc_version
instDir=$instDir/$gcc_version

# test for architecture
arch=$(uname -s | tr '[A-Z]' '[a-z]')
# get the number of processors
# and information about the host
if [ "$arch" = "linux" ];
then
  export ncpu=$(cat /proc/cpuinfo | grep processor | wc -l)
elif [ "$arch" = "darwin" ];
then
  export ncpu=$(sysctl -n hw.ncpu)
fi

echo "Parallel build on $ncpu processors"
                    
mkdir -p $sourceDir

if [ ! -f $tmpInstDir/lib/libgmp.a ]; then
  cd $sourceDir
  wget https://ftp.gnu.org/gnu/gmp/$gmp_version.tar.bz2 || exit 1
  tar -xjvf $gmp_version.tar.bz2 || exit 1
  cd $gmp_version || exit 1
  ./configure --prefix=$tmpInstDir --enable-static --disable-shared || exit 1
  make -j$ncpu || exit 1
  make check -j$ncpu || exit 1
  make install || exit 1
fi

if [ ! -f $tmpInstDir/lib/libmpfr.a ]; then
  cd $sourceDir
  wget https://ftp.gnu.org/gnu/mpfr/$mpfr_version.tar.bz2 || exit 1
  tar -xjvf $mpfr_version.tar.bz2 || exit 1
  cd $mpfr_version || exit 1
  ./configure --prefix=$tmpInstDir --enable-static --disable-shared --with-gmp=$tmpInstDir || exit 1
  make -j$ncpu || exit 1
  make check -j$ncpu || exit 1
  make install || exit 1
fi

if [ ! -f $tmpInstDir/lib/libmpc.a ]; then
  cd $sourceDir
  wget https://ftp.gnu.org/gnu/mpc/$mpc_version.tar.gz || exit 1
  tar -xzvf $mpc_version.tar.gz || exit 1
  cd $mpc_version || exit 1
  ./configure --prefix=$tmpInstDir --enable-static --disable-shared --with-gmp=$tmpInstDir --with-mpfr=$tmpInstDir || exit 1
  make -j$ncpu || exit 1
  make check -j$ncpu || exit 1
  make install || exit 1
fi

if [ ! -f $tmpInstDir/lib/libisl.a ]; then
  cd $sourceDir
  wget ftp://gcc.gnu.org/pub/gcc/infrastructure/$isl_version.tar.bz2 || exit 1
  tar -xjvf $isl_version.tar.bz2 || exit 1
  cd $isl_version || exit 1
  ./configure --prefix=$tmpInstDir --enable-static --disable-shared || exit 1
  make -j$ncpu || exit 1
  make check -j$ncpu || exit 1
  make install || exit 1
fi

if [ ! -f $tmpInstDir/lib/libcloog-isl.a ]; then
  cd $sourceDir
  wget ftp://gcc.gnu.org/pub/gcc/infrastructure/$cloog_version.tar.gz || exit 1
  tar -xzvf $cloog_version.tar.gz || exit 1
  cd $cloog_version || exit 1
  ./configure --prefix=$tmpInstDir --enable-static --disable-shared --with-isl=system --with-isl-prefix=$tmpInstDir --with-gmp=system --with-gmp-prefix=$tmpInstDir || exit 1
  make -j$ncpu || exit 1
  make check -j$ncpu || exit 1
  make install || exit 1
fi

if [ ! -f $instDir/bin/gcc ]; then
  cd $sourceDir
  if [ ! -f $gcc_version.tar.bz2 ]; then
    wget ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/$gcc_version/$gcc_version.tar.bz2 || exit 1
    tar -xjvf $gcc_version.tar.bz2 || exit 1
  fi
  mkdir -p /tmp/build_$gcc_version || exit 1
  cd /tmp/build_$gcc_version || exit 1
  $sourceDir/$gcc_version/configure --prefix=$instDir --with-gmp=$tmpInstDir --with-mpfr=$tmpInstDir --with-mpc=$tmpInstDir --with-isl=$tmpInstDir --with-cloog=$tmpInstDir --enable-languages=c,c++,fortran || exit 1
  make -j$ncpu || exit 1
# To run the testsuite one needs some additional programs so this is commented. It would be good if user would do the tests.
#  make check || exit 1
  make install || exit 1
fi

# create cc and c++ in installation directory as link to gcc and g++
ln -s $instDir/bin/gcc $instDir/bin/cc
ln -s $instDir/bin/g++ $instDir/bin/c++

# At runtime the LD_LIBRARY_PATH environment variable need to be present and have to point to $InstDir/lib 
echo "To use the new gcc as compiler you have to add the following lines to your environment"
echo "###"
echo " export PATH=$InstDir/bin:\$PATH"
echo " export LD_LIBRARY_PATH=$InstDir/lib64:\$LD_LIBRARY_PATH"
echo "###"
echo "To use the new gcc as default compiler you can add also the following lines"
echo "###"
echo " export CC=$InstDir/bin/gcc"
echo " export CXX=$InstDir/bin/g++"
echo "###"



