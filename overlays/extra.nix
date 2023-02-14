final: prev: {
  # ---------------------------------------------------------------------------------------
  # GDAL - Industry standard transformation geometries
  # ---------------------------------------------------------------------------------------
  gdal = prev.gdal.overrideAttrs (old:
    let version = "3.6.1";
    in {
      name = "gdal-${version}";
      inherit version;
      src = final.fetchFromGitHub {
        owner = "OSGeo";
        repo = "gdal";
        rev = "v${version}";
        hash = "sha256-hWuV73b7czmbxpnd82V2FHM+ak9JviDHVodVXAHh/pc=";
      };

      # -------------------------------------------------------------------------------------------
      # because gdal 3.4.2 wants to be installed, I have to
      # override the derivation as it is written at this particular point in time:
      # https://github.com/NixOS/nixpkgs/blob/e52d6c1260e37aa6b3413f7dfa3846481325342d/pkgs/development/libraries/gdal/default.nix
      hardeningDisable = [ ];
      CXXFLAGS = "";
      preConfigure = "";
      preBuild = "";
      # -------------------------------------------------------------------------------------------

      # defining (not overriding), because @3.4.2, CMake builds were unavailable
      cmakeFlags = with final;
        [
          "-DGDAL_USE_INTERNAL_LIBS=OFF"
          "-DGEOTIFF_INCLUDE_DIR=${lib.getDev libgeotiff}/include"
          "-DGEOTIFF_LIBRARY_RELEASE=${
            lib.getLib libgeotiff
          }/lib/libgeotiff${stdenv.hostPlatform.extensions.sharedLibrary}"
          "-DMYSQL_INCLUDE_DIR=${lib.getDev libmysqlclient}/include/mysql"
          "-DMYSQL_LIBRARY=${
            lib.getLib libmysqlclient
          }/lib/mysql/libmysqlclient${stdenv.hostPlatform.extensions.sharedLibrary}"
          "-DBUILD_TESTING=OFF"
          "-DENABLE_IPO=ON" # what is this?
          "-DCMAKE_BUILD_TYPE=Release"
          "-DBUILD_SHARED_LIBS=ON"
          "-DBUILD_APPS=ON"
        ] ++ final.lib.optionals (!final.stdenv.isDarwin) [
          "-DCMAKE_SKIP_BUILD_RPATH=ON" # without, libgdal.so can't find libmariadb.so
        ] ++ final.lib.optionals final.stdenv.isDarwin
        [ "-DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON" ];

      # defining (overriding) b/c codebase was different when it was @3.4.2
      nativeBuildInputs = with final.pkgs; [
        bison
        cmake
        doxygen
        graphviz
        pkg-config
        python38Full.pkgs.setuptools
        python38Full.pkgs.wrapPython
        swig
      ];

      # defining (overriding) b/c codebase was different when it was @3.4.2
      buildInputs = with final.pkgs;
        [
          armadillo
          c-blosc

          cfitsio
          crunch
          curl
          libdeflate
          expat

          geos

          libheif
          dav1d # required by libheif
          libaom # required by libheif
          libde265 # required by libheif
          rav1e # required by libheif
          x265 # required by libheif

          hdf4
          hdf5-cpp

          shapelib
          json_c

          libjxl
          libhwy # required by libjxl

          xz

          lz4
          netcdf

          # Security
          cryptopp
          openssl_1_1.dev
          pcre2

          # Data
          libspatialite
          libspatialindex
          libmysqlclient

          libxml2.dev

          # Media File Formats
          libjpeg
          libpng
          libwebp
          openjpeg
          giflib
          libgeotiff

          poppler

          postgresql
          proj
          qhull
          sqlite.dev
          tiledb
          zlib
          zstd
          python38Full
          python38Full.pkgs.numpy
        ] ++ final.lib.optionals (!final.stdenv.isDarwin) [
          # tests for formats enabled by these packages fail on macos
          arrow-cpp
          brunsli
          lerc
          openexr
          xercesc
        ] ++ lib.optional final.stdenv.isDarwin final.libiconv;

      # defining (overriding) b/c codebase was different when it was @3.4.2
      sourceRoot = "source";

      # defining (overriding) b/c weird permission fix that is unnecessary
      preCheck = ''
        pushd ../autotest
        export HOME=$(mktemp -d)
        export PYTHONPATH="$out/${final.python38Full.sitePackages}:$PYTHONPATH"
      '';

      # defining (overriding) to override so Python env is the same (special case)
      installCheckInputs = with final.python38Full.pkgs; [
        pytestCheckHook
        pytest-env
        lxml
      ];

      # extended by examining nixpkgs.gdal source code @ 3.4.2 <-> 3.6.1
      disabledTests = old.disabledTests ++ [
        "test_tiff_srs_compound_crs_with_local_cs" # tests that fail because error message specificity too high
        " test_sentinel2_zipped" # ZIP does not support timestamps before 1980
      ] ++ final.lib.optionals (!final.stdenv.isx86_64) [ ]
        ++ final.lib.optionals final.stdenv.isDarwin [ ]
        ++ final.lib.optionals (final.lib.versionOlder final.proj.version "8")
        [ "test_ogr_parquet_write_crs_without_id_in_datum_ensemble_members" ];

    });

  # ---------------------------------------------------------------------------------------
  # PROJ: Cartographic Projections and Coordinate Transformations Library
  # ---------------------------------------------------------------------------------------
  proj = prev.proj.overrideAttrs (old:
    let version = "9.1.0";
    in {
      name = "proj-${version}";
      inherit version;
      src = final.fetchFromGitHub {
        owner = "OSGeo";
        repo = "PROJ";
        rev = version;
        hash = "sha256-Upsp72RorV+5PFPHOK3zCJgVTRZ6fSVVFRope8Bp8/M=";
      };
      cmakeFlags = old.cmakeFlags ++ [
        "-DBUILD_TESTING=OFF"
        "-DENABLE_IPO=ON"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DBUILD_SHARED_LIBS=ON"
      ];
    });
}
