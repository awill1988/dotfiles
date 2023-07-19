final: prev: {
  python3 = prev.python3.override {
    # Careful, we're using a different final and prev here!
    packageOverrides = final: prev: {
      cloudsmith-api = prev.buildPythonPackage rec {
        pname = "cloudsmith-api";
        version = "2.0.7";
        format = "wheel";

        src = prev.fetchPypi {
          pname = "cloudsmith_api";
          inherit format version;
          hash = "sha256-Vw5ifMJ+gwXecYjSe8QKkq+RtrBWxx3B/LdA80ZxuxU=";
        };

        propagatedBuildInputs = with prev; [
          certifi
          python-dateutil
          six
          urllib3
        ];

        doCheck = false;

        pythonImportsCheck = [ "cloudsmith_api" ];
      };
    };
  };

  # ---------------------------------------------------------------------------------------
  # Cloudsmith CLI
  # ---------------------------------------------------------------------------------------
  cloudsmith-cli = final.python3.pkgs.buildPythonPackage rec {
    pname = "cloudsmith-cli";
    version = "0.43.0";
    format = "wheel";

    src = final.python3.pkgs.fetchPypi {
      pname = "cloudsmith_cli";
      inherit format version;
      hash = "sha256-14IearahRIzk18CYwijr6ncKOYuuJUnGa+7IeTsdkw8=";
    };

    propagatedBuildInputs = with final.python3.pkgs; [
      click
      click-configfile
      click-didyoumean
      click-spinner
      cloudsmith-api
      colorama
      future
      requests
      requests-toolbelt
      semver
      simplejson
      six
      setuptools # needs pkg_resources
    ];

    # Wheels have no tests
    doCheck = false;

    pythonImportsCheck = [ "cloudsmith_cli" ];

    meta = with final.lib; {
      homepage = "https://help.cloudsmith.io/docs/cli/";
      description = "Cloudsmith Command Line Interface";
      changelog =
        "https://github.com/cloudsmith-io/cloudsmith-cli/blob/v${version}/CHANGELOG.md";
      maintainers = with maintainers; [ ];
      license = licenses.asl20;
      platforms = with platforms; unix;
    };
  };
  # ---------------------------------------------------------------------------------------
  # GDAL - Industry standard transformation geometries
  # ---------------------------------------------------------------------------------------
  gdal = prev.gdal.overrideAttrs (old:
    let version = "3.6.2";
    in {
      name = "gdal-${version}";
      inherit version;
      src = final.fetchFromGitHub {
        owner = "OSGeo";
        repo = "gdal";
        rev = "v${version}";
        hash = "sha256-fdj/o+dm7V8QLrjnaQobaFX80+penn+ohx/yNmUryRA=";
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
        python3.pkgs.setuptools
        python3.pkgs.wrapPython
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
          python3
          python3.pkgs.numpy
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
        export PYTHONPATH="$out/${final.python3.sitePackages}:$PYTHONPATH"
      '';

      postInstall = ''
        wrapPythonPrograms
      '';

      enableParallelBuilding = true;

      doInstallCheck = true;

      # defining (overriding) to override so Python env is the same (special case)
      installCheckInputs = [ ];

      nativeInstallCheckInputs = with final.python3.pkgs; [
        pytestCheckHook
        pytest-env
        lxml
      ];

      # extended by examining nixpkgs.gdal source code @ 3.4.2 <-> 3.6.1
      disabledTests = old.disabledTests ++ [
        "test_jp2openjpeg_45"
        "test_transformer_dem_overrride_srs"
        "test_osr_ct_options_area_of_interest"
        # ZIP does not support timestamps before 1980
        " test_sentinel2_zipped"
        "test_tiff_srs_compound_crs_with_local_cs" # tests that fail because error message specificity too high
        " test_sentinel2_zipped" # ZIP does not support timestamps before 1980
      ] ++ final.lib.optionals (!final.stdenv.isx86_64) [
        # likely precision-related expecting x87 behaviour
        "test_jp2openjpeg_22"
      ] ++ final.lib.optionals final.stdenv.isDarwin [
        # flaky on macos
        "test_rda_download_queue"
      ] ++ final.lib.optionals (final.lib.versionOlder final.proj.version "8")
        [ "test_ogr_parquet_write_crs_without_id_in_datum_ensemble_members" ];

    });

}
