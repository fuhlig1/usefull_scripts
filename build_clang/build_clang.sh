#!/bin/bash
####
# script used for installation of clang compiler including llvm and libc++
####

# Variables which have to be adjusted to the needs of the system
# At least define the installation dir
# TODO: Change interface to pass the the temporary and the install dir

version=38
version_full=3.8

tmpDir=/tmp/build_llvm/
InstDir=/opt/compiler/llvm

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
    download_llvm_core_git || exit
    build_pre_stage1 || exit
  fi

  stage1_settings
  download_llvm_core_git || exit
  download_llvm_addons_git || exit
  patch_llvm || exit
  
  build_stage1 || exit

  stage2_settings
  build_stage2 || exit

  build_oclint || exit

  echo "To use clang as compiler you have to add the following lines to your environment"
  echo "##	#"
  echo " export PATH=$InstDir/bin:\$PATH"
  echo "###"
  echo "To use clang as default compiler you can add also the following lines"
  echo "###"
  echo " export CC=$InstDir/bin/clang"
  echo " export CXX=$InstDir/bin/clang++"
  echo "###"

  
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
  cmake_build_type=Release
  stage=2
  cc=$InstDir/bin/clang
  cxx=$InstDir/bin/clang++
  source_dir=$tmpDir/$version_full
  build_dir=$tmpDir/build/${version_full}_stage2
  tmpInstDir=$tmpDir/compiler_tmp/llvm/$version_full
  InstDir=$InstDirBackup/$version_full

  cxxflags="-std=c++11 -stdlib=libc++ -O3" 
  ldflags="-Wl,-rpath,$InstDir/lib " 

  if [ "$arch" = "linux" ]; then
    count=$(gcc -print-multiarch 2>&1 | grep -c unrecognized)
    if [ $count -eq 1 ]; then
      cIncDirs=$InstDir/include/c++/v1:/usr/include 
    else  
      gccIncDir=$(gcc -print-multiarch)
      gccVersion=$(gcc -dumpversion)
      cIncDirs=$InstDir/include/c++/v1:/usr/include:/usr/include/$gccIncDir:/usr/include/$gccIncDir/c++/$gccVersion
      cxxflags="$cxxflags -I/usr/include/$gccIncDir -I/usr/include/$gccIncDir/c++/$gccVersion"
    fi
  else  
    cIncDirs=$InstDir/include/c++/v1:/usr/include 
  fi

  cmakeflags="$cmakeflags -DLLVM_ENABLE_LIBCXX=TRUE -DC_INCLUDE_DIRS=$cIncDirs -DBUILD_SHARED_LIBS=on"
  # -DLIBCXX_CXX_ABI=libcxxabi-in-tree"   


#  cmakeflags="-DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_LIBCXXABI_INCLUDE_PATHS=$cxxabi_include_path -DC_INCLUDE_DIRS=$cIncDirs"   

  if [ "$arch" = "darwin" ]; then
    cmakeflags="$cmakeflags -DCMAKE_OSX_ARCHITECTURES=x86_64;i386"   
#    cmakeflags="$cmakeflags -DLIBCXX_LIBCXXABI_LIBRARY_PATH=$cxxabi_lib_path -DLIBCXX_INSTALL_PATH=$InstDir/lib"   
  fi
}

stage1_settings() {
  cmake_build_type=Release
  stage=1
  version=$version_final 
  version_full=$version_full_final
  if [ "$bootstrap" = "yes" ]; then
    cc=$tmpInstDir/bin/clang
    cxx=$tmpInstDir/bin/clang++
    bootstrap=no
  fi
  source_dir=$tmpDir/$version_full
  build_dir=$tmpDir/build/$version_full

  tmpInstDir=$tmpDir/compiler_tmp/llvm/$version_full
  InstDir=$tmpInstDir

  ldflags="-Wl,-rpath,$InstDir/lib"
  cmakeflags=""
  cxxflags=""
  cmakedugflags=""
  
  if [ "$arch" = "linux" ]; then
    cmakeflags="$cmakeflags -DLIBCXXABI_ENABLE_SHARED=off"
    cxxflags="$cxxflags -O3 -stdlib=libstdc++ -std=c++11"
    count=$(gcc -print-multiarch 2>&1 | grep -c unrecognized)
    if [ $count -eq 1 ]; then
      cIncDirs=$InstDir/include/c++/v1:/usr/include 
    else  
      gccIncDir=$(gcc -print-multiarch)
      gccVersion=$(gcc -dumpversion)
      cIncDirs=$InstDir/include/c++/v1:/usr/include:/usr/include/$gccIncDir:/usr/include/$gccIncDir/c++/$gccVersion
      cxxflags="$cxxflags -I/usr/include/$gccIncDir -I/usr/include/$gccIncDir/c++/$gccVersion"
    fi
  else  
    cIncDirs=$InstDir/include/c++/v1:/usr/include 
  fi

  cmakeflags="$cmakeflags -DC_INCLUDE_DIRS=$cIncDirs -DBUILD_SHARED_LIBS=on"

  if [ "$arch" = "darwin" ]; then
    cxxflags="-stdlib=libstdc++ -O3"

    cmakeflags="$cmakeflags -DLLVM_ENABLE_LIBCXX=TRUE -DCMAKE_OSX_ARCHITECTURES=x86_64;i386"
  fi  
}

# Define directories for bootstrap installation
bootstrap_settings() {
  cmake_build_type=Release
  InstDirBackup=$InstDir
  version_final=$version
  version_full_final=$version_full
  local version_tmp=$llvm_version
  local version_tmp_full=$llvm_version_full
  source_dir=$tmpDir/$version_tmp_full
  build_dir=$tmpDir/build/${version_tmp_full}_prestage
  tmpInstDir=$tmpDir/compiler_tmp/llvm/${version_tmp_full}_bootstrap
  InstDir=$tmpInstDir
  if [ "$bootstrap" = "yes" ]; then
    echo "So we will first build clang/llvm $version_tmp_full and use this version to compile the final clang/llvm version $version_full."
  fi
  version=$llvm_version
  version_full=$llvm_version_full

  sleep 2
}

function is_in_path {
    # This function checks if a file exists in the $PATH.
    # To do so it uses which.
    # There are several versions of which available with different
    # return values. Either it is "" or "no searched program in PATH" or
    # "/usr/bin/which: no <searched file>".
    # To check for all differnt versions check if the return statement is 
    # not "".
    # If it is not "" check if the return value starts with no or have
    # the string "no <searched file> in the return string. If so set
    # return value to "". So all negative return statements go to "".
    # If program is found in Path return 1, else return 0.

    searched_program=$1
    answer=$(which $searched_program)
    if [ "$answer" != "" ];
    then
      no_program=$(which $searched_program | grep -c '^no' )
      no_program1=$(which $searched_program | grep -c "^no $searched_program")
      if [ "$no_program" != "0" -o "$no_program1" != "0" ];
      then
        answer=""
      fi
    fi

    if [ "$answer" != "" ];
    then
      return 1
    else
      return 0
    fi
}


# Check if on of the supported compilers is present. First check for clang and then
# for gcc. Use the first one which is found. If none is found print the usage message.
# Check the compiler version to decide if we first have to bootstrap an older version
# of Clang.
# At least clang 3.2 or gcc 4.7 is needed to 
check_compiler() {

    is_in_path clang
    result=$?
    if [ "$result" = "0" ]; then
	is_in_path gcc
	result=$?
	if [ "$result" = "0" ]; then
	    echo "The script only works with clang or gcc."
            echo "The script could neither find clang nor gcc"
	    usage
        else
            compiler=gcc
	fi
    else
	compiler=clang
    fi
    echo "Found compiler $compiler"
    
    local compiler_version
    local minor
    local major
    bootstrap=no
    
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
	
	if [ $major -eq 3 -a $minor -ge 2 ];
	then
	    bootstrap=no
	else
	    bootstrap=yes
	    llvm_version_full=3.2
	    llvm_version=32
	fi
    else
	cc=gcc
	cxx=g++
	compiler_version=$(gcc -dumpversion)
	major=$(echo $compiler_version | cut -d. -f1 ) 
	minor=$(echo $compiler_version | cut -d. -f2) 
	if [ "$major" -lt 4 ]; then
	    echo "Your compiler is to old. At least gcc major version 4 is needed"
	    exit 1
	fi         
	bootstrap=yes
	if [ "$minor" -lt 7 ]; then
	    llvm_version_full=3.2
	    llvm_version=32
	else
	    llvm_version_full=3.5
	    llvm_version=350
	fi 
    fi
    if [ "$bootstrap" = "yes" ]; then 
	echo "To be able to compile the libc++ abi code one needs at least Clang 3.2"
	echo "Your compiler $compiler $major.$minor is not able to compile this code."
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
#    cxxabi_checkfile=libc++abi.a
  elif [ "$arch" = "darwin" ];
  then
    mac_version=$(sw_vers -productVersion | cut -d . -f 1-2)
    ncpu=$(sysctl -n hw.ncpu)
    triple=-apple-
    ext=dylib
#    cxxabi_checkfile=libc++abi.$ext
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
#    if [ ! -d libcxx ]; then
#      svn co http://llvm.org/svn/llvm-project/libcxx/branches/release_$version libcxx
#    fi
   echo ""
  else  
    if [ ! -d libcxx ]; then
      svn co http://llvm.org/svn/llvm-project/libcxx/tags/RELEASE_$version/final libcxx
    fi
    if [ ! -d libcxxabi ]; then
      svn co http://llvm.org/svn/llvm-project/libcxxabi/tags/RELEASE_$version/final libcxxabi
    fi
  fi 
}

download_llvm_core_git() {

  mkdir -p $source_dir/llvm
  cd $source_dir/llvm

  if [ ! -d $version ]; then
    git clone https://github.com/llvm-mirror/llvm $version
    cd  $source_dir/llvm/$version
    git checkout release_$version    
  fi

  cd $source_dir/llvm/$version/tools
  if [ ! -d clang ]; then
    git clone https://github.com/llvm-mirror/clang
    cd  $source_dir/llvm/$version/tools/clang
    git checkout release_$version    
  fi

  cd $source_dir/llvm/$version/projects
  if [ "$bootstrap" = "yes" ];
  then
#    if [ ! -d libcxx ]; then
#      svn co http://llvm.org/svn/llvm-project/libcxx/branches/release_$version libcxx
#    fi
   echo ""
  else  
    if [ ! -d libcxx ]; then
      git clone https://github.com/llvm-mirror/libcxx
      cd  $source_dir/llvm/$version/projects/libcxx
      git checkout release_$version    
    fi
    cd $source_dir/llvm/$version/projects
    if [ ! -d libcxxabi ]; then
      git clone https://github.com/llvm-mirror/libcxxabi
      cd  $source_dir/llvm/$version/projects/libcxxabi
      git checkout release_$version    
    fi
  fi 
}

download_llvm_addons() {
  cd $source_dir/llvm/$version/tools/clang/tools/
  if [ ! -d  extra ]; then
    svn co http://llvm.org/svn/llvm-project/clang-tools-extra/tags/RELEASE_$version/final extra
  fi

  if [ ! -d  include-what-you-use ]; then
    #TODO: maybe use branches or tags instead of trunk
    svn co http://include-what-you-use.googlecode.com/svn/trunk include-what-you-use
  fi

  cd $source_dir/llvm/$version/projects
  if [ ! -d compiler-rt ]; then
    svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_$version/final compiler-rt
  fi  
}

download_llvm_addons_git() {
  cd $source_dir/llvm/$version/tools/clang/tools/
  if [ ! -d  extra ]; then
    git clone https://github.com/llvm-mirror/clang-tools-extra extra 
    cd  $source_dir/llvm/$version/tools/clang/tools/extra
    git checkout release_$version    
  fi

  cd $source_dir/llvm/$version/tools/clang/tools/
  if [ ! -d  include-what-you-use ]; then
    git clone https://github.com/include-what-you-use/include-what-you-use
    cd  $source_dir/llvm/$version/tools/clang/tools/include-what-you-use
    git checkout clang_$full_version
  fi

  cd $source_dir/llvm/$version/projects
  if [ ! -d compiler-rt ]; then
    git clone https://github.com/llvm-mirror/compiler-rt
    cd  $source_dir/llvm/$version/projects/compiler-rt
    git checkout release_$version    
  fi  
}

build_llvm() {

  set -xv
  CC=$cc CXX=$cxx \
  CXXFLAGS=$cxxflags LDFLAGS=$ldflags \
  cmake $cmakedebugflags  $source_dir/llvm/$version \
    -DCMAKE_INSTALL_PREFIX=$InstDir \
    -DCMAKE_BUILD_TYPE=$cmake_build_type \
    -DCMAKE_CXX_COMPILER=$cxx \
    -DCMAKE_C_COMPILER=$cc \
    -DLLVM_BUILD_EXTERNAL_COMPILER_RT=On \
    $cmakeflags
  set +xv
  
  # if building in parallel libc++ depends on libc++abi, so we have to build this first
#  if [ "$bootstrap" = "no" ]; then 
#    cd projects/libcxxabi
#    make -j$ncpu 
#    mkdir -p $InstDir
#    make install
#    mkdir -p $InstDir/include/cxxabi
#    cp -r $source_dir/llvm/$version/projects/libcxxabi/include/* $InstDir/include/cxxabi
#    cd ../..
#  fi

  make -j$ncpu 
  make install
  
}

build_pre_stage1() {
   if [ ! -f $tmpInstDir/bin/clang ]; then
    echo "** Build prestage **"
    mkdir -p $build_dir
    cd $build_dir
    build_llvm

    # create symbolic links for cc and c++ 
    cd $tmpInstDir/bin
    ln -s clang cc
    ln -s clang++ c++
  fi
}

build_stage1() {
  if [ ! -f $InstDir/bin/clang ]; then
    echo "** Build final compiler 1 time"
    mkdir -p $build_dir
    cd $build_dir
    build_llvm
  fi  
}

patch_llvm() {
  if [ ! -f $source_dir/llvm/$version/patched ]; then
    cd $source_dir/llvm/$version/
    patch -p0 < $script_dir/clang_core_380.patch	
    patch -p0 < $script_dir/libc++abi_380.patch	
    patch -p0 < $script_dir/libcxx_380.patch
    patch -p0 < $script_dir/clang_extra_380.patch
    touch $source_dir/llvm/$version/patched
  fi
}


build_stage2() {

  if [ ! -f $InstDir/bin/clang ]; then
    echo "** Build final compiler 2 time"
    mkdir $build_dir
    cd $build_dir
  
    build_llvm 
#    mkdir -p $InstDir/bin     
#    cp -r $source_dir/llvm/$version/tools/clang/tools/scan-view $InstDir/bin
#    cp -r $source_dir/llvm/$version/tools/clang/tools/scan-build $InstDir/bin

    # create symbolic links for cc and c++ 
    cd $InstDir/bin
    ln -s clang cc
    ln -s clang++ c++

  fi
}


build_oclint() {

  if [ ! -f $InstDir/bin/oclint ]; 
  then
    cd $source_dir
    if [ ! -d oclint ]; then
      git clone https://github.com/oclint/oclint
    fi
    cd oclint
#    git checkout 5dba3452a80a0531c9f58e967586b83684668ae2
    git checkout master      
#    patch -p0 < $script_dir/oclint_$version.patch
           
    if [ "$arch" = "linux" ];
    then
      sed 's/libstdc++/libc++/g' -i'' oclint-core/cmake/OCLintConfig.cmake 
    fi

    mkdir -p build/oclint-core
    cd build/oclint-core
    LDFLAGS=$ldflags CXXFLAGS=$cxxflags \
    cmake -D OCLINT_BUILD_TYPE=Release \
          -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
          -D CMAKE_C_COMPILER=$InstDir/bin/clang \
          -D LLVM_ROOT=$InstDir \
          $source_dir/oclint/oclint-core
#    make -j$ncpu
make
    exit
      
    cd $source_dir/oclint/build
    mkdir -p oclint-metrics
    cd oclint-metrics
    LDFLAGS=$ldflags CXXFLAGS=$cxxflags \
    cmake -D OCLINT_BUILD_TYPE=Release \
          -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
          -D CMAKE_C_COMPILER=$InstDir/bin/clang \
          -D LLVM_ROOT=$InstDir \
          $source_dir/oclint/oclint-metrics
    make -j$ncpu      
  
    cd $source_dir/oclint/build
    mkdir -p oclint-rules
    cd oclint-rules
    LDFLAGS=$ldflags CXXFLAGS=$cxxflags \
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
    LDFLAGS=$ldflags CXXFLAGS=$cxxflags \
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
    LDFLAGS=$ldflags CXXFLAGS=$cxxflags \
    cmake -D OCLINT_BUILD_TYPE=Release \
          -D CMAKE_CXX_COMPILER=$InstDir/bin/clang++ \
          -D CMAKE_C_COMPILER=$InstDir/bin/clang \
          -D LLVM_ROOT=$InstDir \
          -D OCLINT_BUILD_DIR=$source_dir/oclint/build/oclint-core \
          -D OCLINT_SOURCE_DIR=$source_dir/oclint/oclint-core \
          $source_dir/oclint/oclint-driver
    make -j$ncpu
  
    mkdir -p $InstDir/lib/oclint/reporters
    cp $source_dir/oclint/build/oclint-reporters/reporters.dl/*.$ext $InstDir/lib/oclint/reporters
    mkdir -p $InstDir/lib/oclint/rules
    cp $source_dir/oclint/build/oclint-rules/rules.dl/*.$ext $InstDir/lib/oclint/rules
    cp $source_dir/oclint/build/oclint-driver/bin/oclint-0.9 $InstDir/bin
    ln -s $InstDir/bin/oclint-0.9 $InstDir/bin/oclint
    cd $source_dir/oclint/
    git clone https://github.com/oclint/oclint-json-compilation-database.git
    cp $source_dir/oclint/oclint-json-compilation-database/oclint-json-compilation-database $InstDir/bin
  fi
}

fix_library_pathes() {
  # set the path to libc++ relative to the binary
  cd $InstDir/bin
  for file in $(find . -type f -exec file -L {} \; | grep Mach | cut -f1 -d:); do
    install_name_tool -change libc++.1.dylib @loader_path/../lib/libc++.1.dylib $file
  done
  # maybe also to be done for libraries 
}



main "$@"

exit






                    

