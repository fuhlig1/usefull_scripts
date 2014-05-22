#!/bin/bash
####
# script used for installation of clang compiler including llvm and libc++
####

# Variables which have to be adjusted to the needs of the system
# At least define the installation dir
# TODO: Change interface to pass the the temporary and the install dir

version=34
version_full=3.4

tmpDir=/data.local3/tmp/build_llvm/
InstDir=/data.local2/uhlig/compiler/llvm

# unset environment variables
unset CFLAGS
unset CXXFLAGS
unset CPPFLAGS
unset LDFLAGS
unset LIBRARY_PATH
unset LD_LIBRARY_PATH
unset DYLD_LIBRARY_PATH

main() {
  # Extract the directory where the script is loacted 
  script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

  check_architecture
  check_compiler
  bootstrap_settings
  if [ "$bootstrap" = "yes" ];
  then 
    download_llvm_core
    build_pre_stage1
  fi

  stage1_settings
  download_llvm_core
  download_llvm_addons
  patch_llvm

  build_cxxabi 
  build_stage1 
  exit
  stage2_settings
  build_cxxabi 
  build_stage2
  exit

}

usage() {
  echo ""
  echo ""
  echo "The script will install clang/llvm ${version_full} from sources."
  echo ""
  echo "It will check the existing compiler infrastructure. Supported" 
  echo "compilers are clang and gcc, where gcc is the default. If you want" 
  echo "to use clang you have to the environment variable CC which has to" 
  echo "point to to the clang executable."
  echo ""
  echo "In case the compiler is to old to compile the required"
  echo "clang/llvm version the script will install first an older clang/llvm"
  echo "version to compile the final one."
  echo ""
  echo "Beside clang/llvm the script will install also some other usefull"
  echo "tools for software development."
  echo ""
  echo "include-what-you-use: https://code.google.com/p/include-what-you-use/"
  echo "   tool to check the #include statements"
  echo ""
  echo "oclint: http://oclint.org/"
  echo "   static code analysis tool" 
  echo ""
  echo ""
  exit 0
}

stage2_settings() {
  stage=2
  cc=$InstDir/bin/clang
  cxx=$InstDir/bin/clang++
  source_dir=$tmpDir/$version_full
  build_dir=$tmpDir/build/${version_full}_stage2
  tmpInstDir=$tmpDir/compiler_tmp/llvm/$version_full
  InstDir=$InstDirBackup/$version_full
  cxxabi_include_path=$InstDir/include/cxxabi
  cxxabi_lib_path=$InstDir/lib
  cxxflags="-std=c++11 -stdlib=libc++" 
#  ldflags="-L$tmpInstDir/lib -lc++ -L$InstDir/lib -Wl,-rpath,$InstDir/lib" 
  ldflags="-L$tmpInstDir/lib -L$InstDir/lib -Wl,-rpath,$InstDir/lib" 
  
  cIncDirs=$InstDir/include/c++/v1:/usr/include

  cmakeflags="-DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_LIBCXXABI_INCLUDE_PATHS=$cxxabi_include_path -DC_INCLUDE_DIRS=$cIncDirs"   
#    export LIBRARY_PATH=$tmpInstDir/lib:$LIBRARY_PATH
#    export DYLD_LIBRARY_PATH=$tmpInstDir/lib:$DYLD_LIBRARY_PATH
  if [ "$arch" = "linux" ];
  then
    export LD_LIBRARY_PATH=$tmpInstDir/lib:$LD_LIBRARY_PATH
  echo "bla"
  fi
  
  if [ "$mac_version" = "10.6" ];
  then
    cxxflags="$cxxflags-U__STRICT_ANSI__" 
    ldflags="-L$tmpInstDir/lib -lc++ -L$InstDir/lib -Wl,-rpath,$InstDir/lib" 
  
    cIncDirs=$InstDir/include/c++/v1:/usr/include

    cmakeflags="$cmakeflags -DLIBCXX_LIBCXXABI_LIBRARY_PATH=$cxxabi_lib_path -DLIBCXX_INSTALL_PATH=$tmpInstDir/lib"   
#    export LIBRARY_PATH=$tmpInstDir/lib:$LIBRARY_PATH
#    export DYLD_LIBRARY_PATH=$tmpInstDir/lib:$DYLD_LIBRARY_PATH
  fi
}

stage1_settings() {
  stage=1
  version=$version_final 
  version_full=$version_full_final
  cc=$tmpInstDir/bin/clang
  cxx=$tmpInstDir/bin/clang++
  source_dir=$tmpDir/$version_full
  build_dir=$tmpDir/build/$version_full

  tmpInstDir=$tmpDir/compiler_tmp/llvm/$version_full
  InstDir=$tmpInstDir
#  InstDir=$InstDirBackup/$version_full

  cxxabi_include_path=$InstDir/include/cxxabi
  cxxabi_lib_path=$InstDir/lib
  cxxflags="-stdlib=libstdc++"
  ldflags="-L$cxxabi_lib_path -Wl,-rpath,$InstDir/lib -lstdc++"
  cIncDirs=$InstDir/include/c++/v1:/usr/include 
  cmakeflags="-DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_LIBCXXABI_INCLUDE_PATHS=$cxxabi_include_path -DC_INCLUDE_DIRS=$cIncDirs"   
  if [ "$mac_version" = "10.6" ];
  then
    cxxflags="$cxxflags -U__STRICT_ANSI__"
    cmakeflags="$cmakeflags -DLIBCXX_LIBCXXABI_LIBRARY_PATH=$cxxabi_lib_path -DLIBCXX_INSTALL_PATH=$InstDir/lib"   
  fi
}

# Define directories for bootstrap installation
bootstrap_settings() {
  InstDirBackup=$InstDir
  version_final=$version
  version_full_final=$version_full
  local version_tmp=32
  local version_tmp_full=3.2
  source_dir=$tmpDir/$version_tmp_full
  build_dir=$tmpDir/build/$version_tmp_full
  tmpInstDir=$tmpDir/compiler_tmp/llvm/$version_tmp_full
  InstDir=$tmpInstDir
  echo "So we will first build clang/llvm $version_tmp_full and use this version to compile the final clang/llvm version $version_full."
  version=32
  version_full=3.2
  if [ "$mac_version" = "10.6" ];
  then
    cxxflags="-U__STRICT_ANSI__"  
    ldflags="-Wl,-rpath,$tmpInstDir/lib"
    cIncDirs=$tmpInstDir/include/c++/v1:/usr/include 
    cmakeflags="-DC_INCLUDE_DIRS=$cIncDirs"
  fi
  sleep 2
}

# check if the used compiler used if either gcc or clang,
# if the compiler is really available, and if the installed
# compiler version is not to old to compile clang/llvm
# At least clang 3.2 or gcc 4.7 is needed to 
check_compiler() {
  
  local compiler=$(basename "$CC")
  if [ -z "$CC" ];
  then
    compiler=gcc
  fi
  if [ "$compiler" != "clang" -a "$compiler" != "gcc" ];
  then
    echo "The script only works with clang or gcc."
    usage
  else
    local answer
    local no_program
    local no_program1
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
      usage
    fi
  fi

  local compiler_version
  local minor
  local major
  if [ "$compiler" = "clang" ];
  then
    cc=clang
    cxx=clang++
    compiler_version=$(clang -v 2>&1 | sed -n 1p | cut -d' ' -f 3)
    if [ "$compiler_version" = "version" ]; # we are on mac
    then
      compiler_version=$(clang -v 2>&1 | sed -n 1p | cut -d' ' -f 9 | cut -c1-3)
    fi
    major=$(echo $compiler_version | cut -d. -f1 ) 
    minor=$(echo $compiler_version | cut -d. -f2) 
  else
    cc=gcc
    cxx=g++
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
    elif [ $minor -lt 7 ];
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
  if [ "$bootstrap" = "yes" ];
  then 
    echo "Your compiler $compiler $major.$minor is to old to compile clang/llvm $version_full directly."
  fi

}

# test for architecture
# get the number of processors
# and information about the host
# set some architecture specific variables
check_architecture() {
  arch=$(uname -s | tr '[A-Z]' '[a-z]')
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
  else
    echo "The script supports only linux and MacOSX (darwin)."
  fi
}

download_llvm_core() {

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
}

download_llvm_addons() {
  cd $source_dir/llvm/$version/tools/clang/tools/
  if [ ! -d  extra ]; then
    svn co http://llvm.org/svn/llvm-project/clang-tools-extra/branches/release_$version extra
  fi

  if [ ! -d  include-what-you-use ]; then
    svn co http://include-what-you-use.googlecode.com/svn/branches/clang_$version_full include-what-you-use
  fi

  cd $source_dir/llvm/$version/projects
  if [ ! -d compiler-rt ]; then
    svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_$version/final compiler-rt
  fi  
}

build_llvm() {
  echo "CC: $cc"
  echo "CXX: $cxx"
  CC=$cc CXX=$cxx \
  CXXFLAGS=$cxxflags LDFLAGS=$ldflags \
  cmake $source_dir/llvm/$version \
    -DCMAKE_INSTALL_PREFIX=$InstDir $cmakeflags

  make -j$ncpu 
  make install
  
  # create symbolic links for cc and c++ 
  cd $tmpInstDir/bin
  ln -s clang cc
  ln -s clang++ c++
}

build_pre_stage1() {
   if [ ! -f $tmpInstDir/bin/clang ]; then
    mkdir -p $build_dir
    cd $build_dir
    build_llvm
  fi
}

build_stage1() {
  if [ ! -f $build_dir/bin/clang ]; then
    mkdir -p $build_dir
    cd $build_dir
    build_llvm
  fi  
}

patch_llvm() {
  if [ ! -f $source_dir/llvm/$version/patched ]; then
    cd $source_dir/llvm/$version/
    patch -p0 < $script_dir/llvm_core.patch
    patch -p0 < $script_dir/llvm_addons.patch
    patch -p0 < $script_dir/llvm_libcxx_macosx.patch

    if [ "$mac_version" = "10.6" ];
    then
      patch -p0 < $script_dir/llvm_libcxx_macosx_10_6_1.patch
    fi
    touch $source_dir/llvm/$version/patched
  fi
}


build_stage2() {

  if [ ! -f $build_dir/bin/clang ]; then
    mkdir $build_dir
    cd $build_dir
  
##  export LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
#  if [ "$arch" = "linux" ];
#  then
##    export LD_LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
#    cxxflags="-std=c++11 -stdlib=libc++ -I$tmpInstDir/include/c++/v1/" 
#    ldflags="-L$tmpInstDir/lib -L$InstDir/lib -lc++abi" 
#  elif [ "$arch" = "darwin" ];
#  then
##    export DYLD_LIBRARY_PATH=$tmpInstDir/lib:$InstDir/lib
#    cxxflags="-std=c++11 -stdlib=libc++ -I$tmpInstDir/include/c++/v1/" 
#    ldflags="-L$tmpInstDir/lib -L$InstDir/lib -lc++abi" 
#    ldflags="-L$InstDir/lib -Wl,-rpath,$InstDir/lib -lc++abi" 
#    if [ "$mac_version" = "10.6" ];
#    then
#      cxxflags="$cxxflags -U__STRICT_ANSI__"  
#    fi
#  fi  


#  cxxflags="-std=c++11 -stdlib=libc++ -I$tmpInstDir/include/c++/v1/ -U__STRICT_ANSI__" 
    build_llvm 
  fi
}

# compile libcxxabi which is needed for a standalone version of libc++
# information taken from
# http://dragoonsheir.wordpress.com/2013/03/16/wayland-and-c11-programming-part-1-of-n/
build_cxxabi() {
  set -xv
  if [ ! -f $source_dir/libc++/$stage/libcxxabi/lib/$cxxabi_checkfile ]; then

    mkdir -p $source_dir/libc++/$stage
    cd $source_dir/libc++/$stage

    svn co -r 200202 http://llvm.org/svn/llvm-project/libcxxabi/trunk libcxxabi
    cd libcxxabi/lib

    if [ "$arch" = "darwin" ];
    then
      sed 's#-install_name /usr/lib/libc++abi.dylib#-install_name $InstDir/lib/libc++abi.dylib#g' -i' ' buildit  
    elif [ "$arch" = "linux" ];
    then
      if [ "$stage" = "1" ];
      then
        sed 's#-std=c++11 -stdlib=libc++#-std=c++11 -stdlib=libstdc++#g' -i buildit  
      elif [ "$stage" = "2" ];
      then
        sed 's#-lrt -lc -lstdc++#-lrt -lc -L$InstDir/lib -lc++#g' -i buildit  
      fi
    fi    

    InstDir=$InstDir \
      CC=$cc CXX=$cxx \
      CPATH=$source_dir/llvm/$version/projects/libcxx/include \
      TRIPLE=$triple ./buildit

  
    if [ ! -f $cxxabi_checkfile ]; then
      exit
    fi  

    mkdir -p $InstDir/include/cxxabi
    cp -r ../include/* $InstDir/include/cxxabi
 
    mkdir -p $InstDir/lib
    cp  $cxxabi_checkfile $InstDir/lib
    if [ "$arch" = "linux" ];
    then
      cd $InstDir/lib
      ln -s libc++abi.$ext.1.0 libc++abi.$ext.1
      ln -s libc++abi.$ext.1 libc++abi.$ext
    fi
  fi
  set +xv
}

main "$@"

echo "Should not come here"
exit




   
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
  echo "Now we will build the final version of clang"
  export cxxabi_include_path=$InstDir/include/cxxabi
  export cxxabi_lib_path=$InstDir/lib
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

                    

