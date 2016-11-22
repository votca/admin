#! /bin/bash -e

#TODO
#- allow $what to be more flexible


burl="git@github.com:votca/buildutil.git"
durl="git@github.com:votca/downloads.git"
branch=stable
testing=no
clean=no
#build manual before csgapps to avoid csgapps in the manual
what="tools csg csg-manual csgapps csg-tutorials"
cmake_opts=()
usage="Usage: ${0##*/} [OPTIONS] rel_version builddir"

die () {
  echo -e "$*"
  exit 1
}

unset CSGSHARE VOTCASHARE

show_help() {
  cat << eof
This is the script to make release tarballs for VOTCA
$usage
OPTIONS:
    --help          Show this help
    --test BRANCH   Build test release from branch BRANCH (use with current rel ver)
    --clean         Clean tmp dirs  (SUPER DANGEROUS)
    --repos REL     Use repos instead of '$what'
-D*                 Extra option to give to cmake 

Examples:  ${0##*/} -q
           ${0##*/} --test stable 1.2.3 builddir

Report bugs and comments at https://code.google.com/p/votca/issues/list
eof
}

shopt -s extglob
while [[ $# -gt 0 ]]; do
  if [[ ${1} = --*=* ]]; then # case --xx=yy
    set -- "${1%%=*}" "${1#*=}" "${@:2}" # --xx=yy to --xx yy
  elif [[ ${1} = -[^-]?* ]]; then # case -xy split
    if [[ ${1} = -[jpD]* ]]; then #short opts with arguments
       set -- "${1:0:2}" "${1:2}" "${@:2}" # -xy to -x y
    else #short opts without arguments
       set -- "${1:0:2}" "-${1:2}" "${@:2}" # -xy to -x -y
    fi
 fi
 case $1 in
   --clean)
     clean=yes
     shift;;
   --repos)
     what="$2"
     shift 2;;
   --test)
     branch="$2"
     testing=yes
     shift 2;;
   -D)
    cmake_opts+=( -D"${2}" )
    shift 2;;
   --help)
     show_help
     exit $?;;
   -*)
     die "Unknown options $1";;
   --)
     break;;
   *)
     break;;
 esac
done

[[ -z $2 ]] && die "${0##*/}: missing argument.\nTry ${0##*/} --help"

[[ -d $2 ]] || mkdir -p "$2"
cd "$2"

if [[ -d buildutil ]]; then
  cd buildutil
  git pull --ff-only "$burl" master
  [[ -z "$(git ls-files -mo --exclude-standard)" ]] || die "There are modified or unknown files in buildutil"
  cd ..
else
  git clone $burl buildutil
fi

if [[ -d downloads ]]; then
  cd downloads
  git pull --ff-only "$durl"
  [[ -z "$(git ls-files -mo --exclude-standard)" ]] || die "There are modified or unknown files in downloads"
  cd ..
else
  git clone $durl downloads
fi

rel="$1"
shopt -s extglob
[[ $testing = "no" && ${rel} != [1-9].[0-9]?(.[1-9]|_rc[1-9])?(_pristine) ]] && die "release has the wrong form"

set -e
instdir="instdir"
build="build"
if [[ -d $instdir ]]; then
  [[ $clean = yes ]] || die "Test install dir '$instdir' is already there, run 'rm -rf $PWD/$instdir' or add --clean"
  rm -vrf $PWD/$instdir
fi
if [[ -d $build ]]; then
  [[ $clean = yes ]] || die "$build is already there, run 'rm -rf $PWD/$build' or add --clean"
  rm -vrf $PWD/$build
fi

#release 1.0 - 1.2 had a pristine tarball
[[ rel = 1.[012]* ]] && tools_pristine=tools_pristine
#order matters for deps
#and pristine before non-pristine to 'overwrite less components by more components'
for p in ${tools_pristine} $what; do
  [[ -z ${p%%*_pristine} ]] && dist="dist-pristine" || dist="dist"
  prog="${p%_pristine}"
  ./buildutil/build.sh \
    --no-progcheck --no-branchcheck --no-wait --just-update --prefix $PWD/$instdir $prog || \
    die "build -U failed" #clone and checkout
  cd $prog
  [[ -z "$(git ls-files -mo --exclude-standard)" ]] || die "There are modified or unknown files in $p"
  git checkout $branch || die "Could not checkout $branch"
  [[ -z "$(git ls-files -mo --exclude-standard)" ]] || die "There are modified or unknown files in $p"
  if [[ $testing = "yes" ]]; then
    :
  elif [[ $p = *manual ]]; then
    sed -i "s/^VER=.*$/VER=$rel/" Makefile || die "sed of Makefile failed"
    git add Makefile
  elif [[ -f CMakeLists.txt ]]; then
    sed -i "/set(PROJECT_VERSION/s/\"[^\"]*\"/\"$rel\"/" CMakeLists.txt || die "sed of CMakeLists.txt failed"
    git add CMakeLists.txt
  fi
  if [[ $testing = "no" ]]; then
    #|| true because maybe version has not changed
    git commit -m "Version bumped to $rel" || true
  fi
  cd ..

  if [[ $testing = "yes" ]]; then
    REL="$rel" ./buildutil/build.sh \
      --no-progcheck --no-branchcheck --no-changelogcheck \
      --no-wait --prefix $PWD/$instdir \
      --$dist --clean-ignored "${cmake_opts[@]}" \
      $prog || die
  else
    REL="$rel" ./buildutil/build.sh \
      --no-wait --prefix $PWD/$instdir \
      --$dist --clean-ignored "${cmake_opts[@]}" \
      $prog || die
  fi
done
rm -rf $instdir
mkdir $instdir
[ -d $build ] && die "$build is already there, run 'rm -rf $PWD/$build'"
mkdir $build
cd $build

echo "Starting build check from tarball"

if [[ rel = 1.[012]* ]]; then
  r=""
  for i in ../votca-tools-$rel*_pristine.tar.gz; do
    [[ -f $i ]] || die "Could not find $i"
    [[ -n $r ]] && die "There are two file matching votca-tools-$rel*_pristine.tar.gz"
    cp $i .
    [[ $testing = "yes" ]] || cp $i ../downloads
    [[ $i =~ ../votca-tools-(.*_pristine).tar.gz ]] && r="${BASH_REMATCH[1]}"
  done
  [[ -z $r ]] && die "Could not fetch rel"
  ../buildutil/build.sh \
    --no-wait --prefix $PWD/../$instdir --no-relcheck --release $r \
    -DEXTERNAL_BOOST=ON --selfdownload "${cmake_opts[@]}" tools
  rm -rf *
fi

for p in $what; do
  [[ $p = *pristine ]] && die "Edit ${0##*/} as there are multiple pristine tarballs"
  if [[ $p = *manual ]]; then
    [[ $testing = "yes" ]] || cp votca-$p-${rel}.pdf ../downloads
    continue
  fi
  r=""
  for i in ../votca-$p-$rel*.tar.gz; do
    [[ $i = *_pristine* ]] && continue
    [[ -f $i ]] || die "Could not find $i"
    [[ -n $r ]] && die "There are two non-pristine file matching votca-$p-$rel*.tar.gz"
    cp $i .
    [[ $testing = "yes" ]] || cp $i ../downloads
    [[ $i =~ ../votca-$p-(.*).tar.gz ]] && r="${BASH_REMATCH[1]}"
  done
  [[ -z $r ]] && die "Could not fetch rel"
  ../buildutil/build.sh \
    --no-wait --prefix $PWD/../$instdir --no-relcheck --release $r \
    --no-progcheck -DEXTERNAL_BOOST=OFF --selfdownload "${cmake_opts[@]}" $p
  [[ -d $p/.git ]] && die ".git dir found in $p"
  [[ -f $p/Makefile ]] || die "$p has no Makefile"
  rm -rf *
done
cd ..
rm -rf $build
rm -rf $instdir

if [[ $testing = "no" ]]; then
  cd downloads
  git add votca-*-${rel}*
  git commit -m "Added files from release $rel"
  cd ..
  echo "####### TODO by you #########"
  echo cd $PWD
  echo "for p in $what downloads; do git -C \$p log -p origin/master..master; done"
  echo "for p in $what downloads; do git -C \$p  push; done"
  echo "uploads tarball" *$rel*
else
  echo cd $PWD
  echo "Take a look at" *$rel*
fi
