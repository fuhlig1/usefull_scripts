#!/bin/bash

# script to install subversion and its dependencies in one go

subversion_version=1.8.10
scons_version=2.3.4

installation_dir=/home/uhlig/software

svn checkout https://svn.apache.org/repos/asf/subversion/tags/$subversion_version subversion_$subversion_version
cd subversion_$subversion_version
./get-deps.sh

cd ..
wget http://prdownloads.sourceforge.net/scons/scons-$scons_version.tar.gz
tar -xzvf scons-$scons_version.tar.gz 
cd scons-2.3.4
python setup.py install --prefix=$installation_dir
python setup.py install --prefix=$installation_dir install

cd ../subversion_1.8.10/apr
./buildconf 
./configure --prefix=$installation_dir
make -j4 
make -j4 install
  
cd ../apr-util/
./buildconf 
./configure --prefix=$installation_dir --with-apr=$installation_dir
 make -j4
 make -j4 install

cd ../serf/
$installation_dir/bin/scons APR=$installation_dir PREFIX=$installation_dir APU=$installation_dir install

cd ..
./autogen.sh 
./configure --prefix=$installation_dir --with-apr=$installation_dir --with-apr-util=$installation_dir --enable-static --disable-shared --with-serf=$installation_dir
make -j4
make install