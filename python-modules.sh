package: Python-modules
version: "1.0"
requires:
  - "Python:slc.*"
  - "Python-system:(?!slc.*)"
  - FreeType
  - libpng
build_requires:
  - curl
  - Python-modules-list
prepend_path:
  PYTHONPATH: $PYTHON_MODULES_ROOT/share/python-modules/lib/python/site-packages
---
#!/bin/bash -ex

# Major.minor version of Python
export PYVER=$(python3 -c 'import distutils.sysconfig; print(distutils.sysconfig.get_python_version())')

# Ignore what is already in PYTHONPATH. We will set PYTHONPATH or PYTHONUSERBASE per command
unset PYTHONPATH

# PIP_REQUIREMENTS & PIP36_REQUIREMENTS come from Python-modules-list
echo $PIP_REQUIREMENTS | tr \  \\n > requirements.txt
if python3 -c 'import sys; exit(0 if 1000*sys.version_info.major + sys.version_info.minor >= 3006 else 1)' && [[ $ARCHITECTURE != slc6* ]]; then
  echo $PIP36_REQUIREMENTS | tr \  \\n >> requirements.txt
fi

# We use a different INSTALLROOT, so that we can build updatable RPMS which
# do not conflict with the underlying Python installation.
# FIXME: required because of the newly introduced dependency on scikit-garden requires
# a numpy to be installed separately
# See also:
#   https://github.com/scikit-garden/scikit-garden/issues/23
grep RootInteractive requirements.txt && pip3 install -IU numpy
pip3 install -IU -r requirements.txt

# Install matplotlib (quite tricky)
MATPLOTLIB_TAG="3.0.3"
if [[ $ARCHITECTURE != slc* ]]; then
  # Simply get it via pip in most cases
  pip3 install "matplotlib==$MATPLOTLIB_TAG"
else
  # We are on a RHEL-compatible OS. We compile it ourselves, and link it to our dependencies

  # Check if we can enable the Tk interface
  python3 -c 'import _tkinter' && MATPLOTLIB_TKAGG=True || MATPLOTLIB_TKAGG=False
  MATPLOTLIB_URL="https://github.com/matplotlib/matplotlib/archive/v${MATPLOTLIB_TAG}.tar.gz"  # note the "v"
  curl -SsL "$MATPLOTLIB_URL" | tar xzf -
  cd matplotlib-*
  cat > setup.cfg <<EOF
[directories]
basedirlist  = ${FREETYPE_ROOT:+$PWD/fake_freetype_root,$FREETYPE_ROOT,}${LIBPNG_ROOT:+$LIBPNG_ROOT,}${ZLIB_ROOT:+$ZLIB_ROOT,}/usr/X11R6,$(freetype-config --prefix),$(libpng-config --prefix)
[gui_support]
gtk = False
gtkagg = False
tkagg = $MATPLOTLIB_TKAGG
wxagg = False
macosx = False
EOF

  # matplotlib wants include files in <PackageRoot>/include, but this is not the case for FreeType
  if [[ $FREETYPE_ROOT ]]; then
    mkdir fake_freetype_root
    ln -nfs $FREETYPE_ROOT/include/freetype2 fake_freetype_root/include
  fi

  export PYTHONPATH="$PYTHON_MODULES_INSTALLROOT/lib/python/site-packages"
    python3 setup.py build
    python3 setup.py install --prefix "$PYTHON_MODULES_INSTALLROOT"
  unset PYTHONPATH
fi

# Test if matplotlib can be loaded
python3 -c 'import matplotlib'


# Modulefile
MODULEDIR="$INSTALLROOT/etc/modulefiles"
MODULEFILE="$MODULEDIR/$PKGNAME"
mkdir -p "$MODULEDIR"
cat > "$MODULEFILE" <<EoF
#%Module1.0
proc ModulesHelp { } {
  global version
  puts stderr "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
}
set version $PKGVERSION-@@PKGREVISION@$PKGHASH@@
module-whatis "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
# Dependencies
module load BASE/1.0 ${PYTHON_REVISION:+Python/$PYTHON_VERSION-$PYTHON_REVISION} ${ALIEN_RUNTIME_REVISION:+AliEn-Runtime/$ALIEN_RUNTIME_VERSION-$ALIEN_RUNTIME_REVISION}
# Our environment
set PYTHON_MODULES_ROOT \$::env(BASEDIR)/$PKGNAME/\$version
prepend-path PATH \$PYTHON_MODULES_ROOT/share/python-modules/bin
prepend-path LD_LIBRARY_PATH \$PYTHON_MODULES_ROOT/share/python-modules/lib
prepend-path PYTHONPATH \$PYTHON_MODULES_ROOT/share/python-modules/lib/python/site-packages
EoF
