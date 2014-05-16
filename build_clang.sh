#!/bin/bash
####
# script used for installation of clang compiler including llvm and libc++
####

# Variables which have to be adjusted to the needs of the system
version=34
version_full=3.4
source_dir=/tmp/build_llvm/$version_full
build_dir=/tmp/build_llvm/build/$version_full
build_dir_stage2=/tmp/build_llvm/build/${version_full}_stage2
tmpInstDir=/tmp/compiler_tmp/llvm/$version_full
InstDir=/Users/uhlig/compiler/llvm/$version_full

# Extract the directory where the script is loacted 
script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# check if the used compiler used if either gcc or clang
# and if the compiler is really available
compiler=$(basename "$CC")
if [ -z "$CC" ];
then
  compiler=gcc
fi
if [ "$compiler" != "clang" -a "$compiler" != "gcc" ];
then
  echo "The script only works with clang or gcc."
  exit 1
else
  answer=$(which $compiler)
  if [ "$answer" != "" ];
  then
    no_program=$(which $compiler | grep -c '^no' )
    no_program1=$(which $compiler | grep -c "^no $compiler")
    if [ "$no_program" != "0" -o "$no_program1" != "0" ];
    then
      answer=""  
    fi
  fi
  if [ "$answer" == "" ];
  then
    echo "Could not find compiler $compiler."
    exit 1
  fi
fi

# check compiler version. If the compiler is too old e.g. gcc 4.4 one cannot compile
# newer versions of llvm/clang. One has to compile first clang 3.2 and use this version
# to compile the final version of llvm/clang.
if [ "$compiler" = "clang" ];
then
  compiler_version=$(clang -v 2>&1 | sed -n 1p | cut -d' ' -f 3)
  if [ "$compiler_version" = "version" ]; # we are on mac
  then
    compiler_version=$(clang -v 2>&1 | sed -n 1p | cut -d' ' -f 9 | cut -c1-3)
  fi
  major=$(echo $compiler_version | cut -d. -f1 ) 
  minor=$(echo $compiler_version | cut -d. -f2) 
else
  compiler_version=$(gcc -dumpversion)
  major=$(echo $compiler_version | cut -d. -f1 ) 
  minor=$(echo $compiler_version | cut -d. -f2) 
fi
bootstrap=no
if [ "$compiler" = "gcc" ];
then
  if [ $major -lt 4 ];
  then
     bootstrap=yes
  elif [ $minor -lt 5 ];
  then
    bootstrap=yes   
  fi  
elif [ "$compiler" = "clang" ];
then
  if [ $major -eq 3 -a $minor -ge 2 ];
  then
    bootstrap=no
  else
    bootstrap=yes
  fi
fi

# Define directories for bootstrap installation
if [ "$bootstrap" = "yes" ];
then 
  echo "Your compiler is to old to compile version $version_full of Clang directly."
  version_tmp=32
  version_tmp_full=3.2
  source_dir=${source_dir/%$version_full/$version_tmp_full}
  build_dir=${build_dir/%$version_full/$version_tmp_full}
  tmpInstDir=${tmpInstDir/%$version_full/$version_tmp_full}
  InstDir=${InstDir/%$version_full/$version_tmp_full}
  echo "So we will build first Clang $version_tmp_full and use this version to"
  echo "compile the final Clang version $version_full."
  version=32
  version_full=3.2
  sleep 5
fi 

mkdir -p $source_dir/llvm
cd $source_dir/llvm

if [ ! -d $version ]; then
  svn co http://llvm.org/svn/llvm-project/llvm/tags/RELEASE_$version/final $version
fi

cd $source_dir/llvm/$version/tools
if [ ! -d clang ]; then
  svn co http://llvm.org/svn/llvm-project/cfe/tags/RELEASE_$version/final clang
fi

cd $source_dir/llvm/$version/projects
if [ "$bootstrap" = "yes" ];
then
  if [ ! -d libcxx ]; then
    svn co http://llvm.org/svn/llvm-project/libcxx/branches/release_$version libcxx
  fi
else  
  if [ ! -d libcxx ]; then
    svn co http://llvm.org/svn/llvm-project/libcxx/tags/RELEASE_$version/final libcxx
  fi
fi 

if [ "$bootstrap" = "no" ];
then 
  cd $source_dir/llvm/$version/tools/clang/tools/
  if [ ! -d  extra ]; then
    svn co http://llvm.org/svn/llvm-project/clang-tools-extra/branches/release_$version extra
  fi

  if [ ! -d  include-what-you-use ]; then
    svn co http://include-what-you-use.googlecode.com/svn/branches/clang_$version_full include-what-you-use

  patch -p0 << EOF
--- CMakeLists.txt~	2014-01-20 16:31:17.000000000 +0100
+++ CMakeLists.txt	2014-01-20 16:34:08.000000000 +0100
@@ -20,3 +20,4 @@
 # to keep the primary Clang repository small and focused.
 # It also may be included by LLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR.
 add_llvm_external_project(clang-tools-extra extra)
+add_subdirectory(include-what-you-use)
EOF
  fi

  cd $source_dir/llvm/$version/projects
  if [ ! -d compiler-rt ]; then
    svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_$version/final compiler-rt
  patch -p0 << EOF
--- compiler-rt/CMakeLists.txt_orig 2014-05-13 10:23:48.000000000 +0200
+++ compiler-rt/CMakeLists.txt 2014-05-13 10:24:11.000000000 +0200
@@ -188,9 +188,9 @@
     OUTPUT_STRIP_TRAILING_WHITESPACE
   )
   set(SANITIZER_COMMON_SUPPORTED_DARWIN_OS osx)
-  if (IOSSIM_SDK_DIR)
-    list(APPEND SANITIZER_COMMON_SUPPORTED_DARWIN_OS iossim)
-  endif()
+#  if (IOSSIM_SDK_DIR)
+#    list(APPEND SANITIZER_COMMON_SUPPORTED_DARWIN_OS iossim)
+#  endif()
 
   if(COMPILER_RT_USES_LIBCXX)
     set(SANITIZER_MIN_OSX_VERSION 10.7)
EOF
  fi
  
fi

# test for architecture
arch=$(uname -s | tr '[A-Z]' '[a-z]')
# get the number of processors
# and information about the host
if [ "$arch" = "linux" ];
then
  ncpu=$(cat /proc/cpuinfo | grep processor | wc -l)
  triple=-linux-
  ext=so
  cxxabi_checkfile=libc++abi.$ext.1.0
elif [ "$arch" = "darwin" ];
then
  mac_version=$(sw_vers -productVersion | cut -d . -f 1-2)
  ncpu=$(sysctl -n hw.ncpu)
  triple=-apple-
  ext=dylib
  cxxabi_checkfile=libc++abi.$ext
fi
    

if [ ! -f $tmpInstDir/bin/clang ]; then
  mkdir -p $build_dir
  cd $build_dir
  if [ "$bootstrap" = "yes" ];
  then 
    if [ "$mac_version" = "10.6" ];
    then
      cxxflags="-U__STRICT_ANSI__"  
    fi
  else 
    if [ "$mac_version" = "10.6" ];
    then
      cxxflags="-U__STRICT_ANSI__ -I$cxxabi_include_path"  
      ldflags="-L$cxxabi_lib_path -lc++abi"
      cmakeflags="-DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_LIBCXXABI_INCLUDE_PATHS=$cxxabi_include_path"   
      export libcxxabi_install_dir="$cxxabi_lib_path"
      export libcxx_install_dir="$tmpInstDir"
#      sed 's#/usr/lib/libc++.1.dylib#$ENV{libcxx_install_path}/lib/libc++.1.dylib#g' -i' ' $source_dir/llvm/$version/projects/libcxx/lib/CMakeLists.txt
#      sed 's#/usr/lib/libc++abi.dylib#$ENV{libcxxabi_install_path}/libc++abi.dylib#g' -i' ' $source_dir/llvm/$version/projects/libcxx/lib/CMakeLists.txt
    fi
  fi

  echo "BLA"
  echo $libcxxabi_install_dir
  echo $libcxx_install_dir
  CXXFLAGS=$cxxflags LDFLAGS=$ldflags \
    cmake $source_dir/llvm/$version -DCMAKE_INSTALL_PREFIX=$tmpInstDir $cmakeflags
 
  make -j$ncpu 
  # somehow the compilation of some tests crash due to inconsistent?? libstdc++  
# package g++-multilib was missing, so the tests for 32bit executables couldn't be
# compiled  
#  make check-all -j16
  make install

  # create symbolic links for cc and c++ 
  cd $tmpInstDir/bin
  ln -s clang cc
  ln -s clang++ c++
fi

if [ "$bootstrap" = "yes" ];
then 
  export PATH=$tmpInstDir/bin:$PATH
  export CC=$tmpInstDir/bin/clang
  export CXX=$tmpInstDir/bin/clang++
fi

# compile libcxxabi which is needed for a standalone version of libc++
# information taken from
# http://dragoonsheir.wordpress.com/2013/03/16/wayland-and-c11-programming-part-1-of-n/

if [ "$bootstrap" = "yes" ];
then 
  InstDirTmp=$tmpInstDir
else
  InstDirTmp=$InstDir
fi

if [ ! -f $InstDirTmp/lib/$cxxabi_checkfile ]; then
  cd $source_dir
  mkdir -p libc++
  cd libc++
#  svn co http://llvm.org/svn/llvm-project/libcxxabi/trunk libcxxabi
#  svn co http://llvm.org/svn/llvm-project/libcxxabi/branches/release_32 libcxxabi
  svn co -r 200202 http://llvm.org/svn/llvm-project/libcxxabi/trunk libcxxabi
  cd libcxxabi/lib

  if [ "$arch" = "darwin" ];
  then
    sed 's#-install_name /usr/lib/libc++abi.dylib#-install_name $InstDirTmp/lib/libc++abi.dylib#g' -i' ' buildit  
  fi    
        
  InstDirTmp=$InstDirTmp CC=$tmpInstDir/bin/clang CXX=$tmpInstDir/bin/clang++ \
  CPATH=$source_dir/llvm/$version/projects/libcxx/include LIBRARY_PATH=$tmpInstDir/lib \
  TRIPLE=$triple ./buildit
  
  if [ ! -f $cxxabi_checkfile ]; then
    exit
  fi  

  mkdir -p $InstDirTmp/include/cxxabi
  cp -r ../include/* $InstDirTmp/include/cxxabi
 
  mkdir -p $InstDirTmp/lib
  cp  $cxxabi_checkfile $InstDirTmp/lib
  if [ "$arch" = "linux" ];
  then
    cd $InstDirTmp/lib
    ln -s libc++abi.$ext.1.0 libc++abi.$ext.1
    ln -s libc++abi.$ext.1 libc++abi.$ext
  fi
fi

if [ "$bootstrap" = "yes" ];
then 
  echo "Now we will build the final version of clang"
  export cxxabi_include_path=$InstDirTmp/include/cxxabi
  export cxxabi_lib_path=$InstDirTmp/lib
  $script_dir/build_clang.sh  
  exit
fi

# Now we can recompile clang using the temporary clang and the lbcxxabi
if [ ! -f $InstDir/bin/clang ]; 
then
  mkdir $build_dir_stage2
  cd $build_dir_stage2
#  rm -rf *
#  echo "InstallDir: $InstDir"
#  ls -la  $InstDir/lib
  
  export LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
  if [ "$arch" = "linux" ];
  then
    export LD_LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
    cxxflags="-std=c++11 -stdlib=libc++ -I$tmpInstDir/include/c++/v1/" 
    ldflags="-L$tmpInstDir/lib -L$InstDir/lib -lc++abi" 
  elif [ "$arch" = "darwin" ];
  then
    export DYLD_LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
    cxxflags="-std=c++11 -stdlib=libc++ -I$tmpInstDir/include/c++/v1/" 
    ldflags="-L$tmpInstDir/lib -L$InstDir/lib -lc++abi" 
    if [ "$mac_version" = "10.6" ];
    then
      export libcxxabi_install_dir="$InstDir/lib"
      export libcxx_install_dir="$InstDir"
      cxxflags="$cxxflags -U__STRICT_ANSI__"  
    fi
  fi  
#  elif [ "$arch" = "darwin" ];
#  then
#    export DYLD_LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
#  fi
  
  # extract the correct C_INCLUDE_DIRS
  if [ "$arch" = "linux" ];
  then
    gccIncDir=$(gcc -print-multiarch)
    cIncDirs=/usr/include/$gccIncDir:/usr/include:$InstDir/include/c++/v1
  elif [ "$arch" = "darwin" ];
  then
    cIncDirs=/usr/include:$InstDir/include/c++/v1
  fi
  
  env
  echo "BLA"
  echo $libcxxabi_install_dir
  echo $libcxx_install_dir
  CC=$tmpInstDir/bin/clang CXX=$tmpInstDir/bin/clang++ \
  CXXFLAGS=$cxxflags LDFLAGS=$ldflags \
  cmake $source_dir/llvm/$version \
        -DCMAKE_INSTALL_PREFIX=$InstDir \
        -DLIBCXX_CXX_ABI=libcxxabi \
        -DLIBCXX_LIBCXXABI_INCLUDE_PATHS=$InstDir/include/cxxabi \
        -DC_INCLUDE_DIRS=$cIncDirs 
  make VERBOSE=1 -j$ncpu
  make install

  if [ ! -f bin/clang ]; 
  then
    exit
  fi

  mkdir -p $InstDir/bin     
  cp -r $source_dir/llvm/$version/tools/clang/tools/scan-view $InstDir/bin
  cp -r $source_dir/llvm/$version/tools/clang/tools/scan-build $InstDir/bin
  # create symbolic links for cc and c++ 
  cd $InstDir/bin
  ln -s clang cc
  ln -s clang++ c++
fi

export LIBRARY_PATH=$InstDir/lib
if [ "$arch" = "linux" ];
then
  export LD_LIBRARY_PATH=$InstDir/lib
elif [ "$arch" = "darwin" ];
then
  if [ "$mac_version" = "10.6" ];
  then
    export DYLD_LIBRARY_PATH=$InstDir/lib
    export libcxxabi_install_dir="$InstDir/lib"
    export libcxx_install_dir="$InstDir"
    cxxflags="-U__STRICT_ANSI__"  
  fi
fi  

if [ ! -f $InstDir/bin/oclint ]; 
then
  cd $source_dir
  git clone https://github.com/oclint/oclint
  cd oclint
  git checkout release_08
  
  if [ "$arch" = "linux" ];
  then
    sed 's/libstdc++/libc++/g' -i'' oclint-core/cmake/OCLintConfig.cmake 
    ld_flags="" 
  elif [ "$arch" = "darwin" ];
  then
    if [ "$mac_version" = "10.6" ];
    then
      sed 's/-fPIC"/-fPIC -U__STRICT_ANSI__"/g' -i'' oclint-core/cmake/OCLintConfig.cmake 
      sed "s|\${OSX_DEVELOPER_ROOT}/Toolchains/XcodeDefault.xctoolchain/usr/lib|$InstDir/include|g" -i'' oclint-core/cmake/OCLintConfig.cmake
      ld_flags="-L$InstDir/lib -lc++abi" 
#    ld_flags="-lc++abi" 
    fi
  fi

  echo $cxxflags  
  mkdir -p build/oclint-core
  cd build/oclint-core
  LDFLAGS=$ld_flags CXXFLAGS=$cxxflags \
  cmake -D OCLINT_BUILD_TYPE=Release \
        -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
        -D CMAKE_C_COMPILER=$InstDir/bin/clang \
        -D LLVM_ROOT=$InstDir \
        $source_dir/oclint/oclint-core
  make VERBOSE=1

  cd $source_dir/oclint/build
  mkdir -p oclint-metrics
  cd oclint-metrics
  LDFLAGS=$ld_flags CXXFLAGS=$cxxflags \
  cmake -D OCLINT_BUILD_TYPE=Release \
        -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
        -D CMAKE_C_COMPILER=$InstDir/bin/clang \
        -D LLVM_ROOT=$InstDir \
        $source_dir/oclint/oclint-metrics
  make -j$ncpu      

  cd $source_dir/oclint/build
  mkdir -p oclint-rules
  cd oclint-rules
  echo "DIR: $source_dir/oclint/oclint-rules"
  LDFLAGS=$ld_flags CXXFLAGS=$cxxflags \
  cmake -D OCLINT_BUILD_TYPE=Release \
        -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
        -D CMAKE_C_COMPILER=$InstDir/bin/clang \
        -D LLVM_ROOT=$InstDir \
        -D OCLINT_BUILD_DIR=$source_dir/oclint/build/oclint-core \
        -D OCLINT_SOURCE_DIR=$source_dir/oclint/oclint-core \
        -D OCLINT_METRICS_SOURCE_DIR=$source_dir/oclint/oclint-metrics \
        -D OCLINT_METRICS_BUILD_DIR=$source_dir/oclint/build/oclint-metrics \
        $source_dir/oclint/oclint-rules
  make -j$ncpu

  cd $source_dir/oclint/build
  mkdir -p oclint-reporters
  cd oclint-reporters
  LDFLAGS=$ld_flags CXXFLAGS=$cxxflags \
  cmake -D OCLINT_BUILD_TYPE=Release \
        -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
        -D CMAKE_C_COMPILER=$InstDir/bin/clang \
        -D LLVM_ROOT=$InstDir \
        -D OCLINT_BUILD_DIR=$source_dir/oclint/build/oclint-core \
        -D OCLINT_SOURCE_DIR=$source_dir/oclint/oclint-core \
        $source_dir/oclint/oclint-reporters
  make -j$ncpu

  cd $source_dir/oclint/build
  mkdir -p oclint-driver
  cd oclint-driver
  LDFLAGS=$ld_flags CXXFLAGS=$cxxflags \
  cmake -D OCLINT_BUILD_TYPE=Release \
        -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
        -D CMAKE_C_COMPILER=$InstDir/bin/clang \
        -D LLVM_ROOT=$InstDir \
        -D OCLINT_BUILD_DIR=$source_dir/oclint/build/oclint-core \
        -D OCLINT_SOURCE_DIR=$source_dir/oclint/oclint-core \
        $source_dir/oclint/oclint-driver
  make VERBOSE=1

  mkdir -p $InstDir/lib/oclint/reporters
  cp $source_dir/oclint/build/oclint-reporters/reporters.dl/*.$ext $InstDir/lib/oclint/reporters
  mkdir -p $InstDir/lib/oclint/rules
  cp $source_dir/oclint/build/oclint-rules/rules.dl/*.$ext $InstDir/lib/oclint/rules
  cp $source_dir/oclint/build/oclint-driver/bin/oclint-0.8 $InstDir/bin
  ln -s $InstDir/bin/oclint-0.8 $InstDir/bin/oclint
  cd $source_dir/oclint/
  git clone https://github.com/oclint/oclint-json-compilation-database.git
  cp $source_dir/oclint/oclint-json-compilation-database/oclint-json-compilation-database $InstDir/bin
fi

# At runtime the LD_LIBRARY_PATH and LIBRARY_PATH environment varables need to be present and have to point to $InstDir/lib 
echo "To use clang as compiler you have to add the following lines to your environment"
echo "###"
echo " export PATH=$InstDir/bin:\$PATH"
echo " export LD_LIBRARY_PATH=$InstDir/lib:\$LD_LIBRARY_PATH"
echo " export LIBRARY_PATH=$InstDir/lib:\$LIBRARY_PATH"
echo "###"
echo "To use clang as default compiler you can add also the following lines"
echo "###"
echo " export CC=$InstDir/bin/clang"
echo " export CXX=$InstDir/bin/clang++"
echo "###"

                    

