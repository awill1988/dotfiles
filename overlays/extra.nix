final: prev: {
  # ---------------------------------------------------------------------------------------
  # GDAL - Industry standard transformation geometries
  # ---------------------------------------------------------------------------------------
  gdal = prev.gdal.overrideAttrs (old:
    let version = "3.5.2";
    in {
      name = "gdal-${version}";
      inherit version;
      src = final.fetchFromGitHub {
        owner = "OSGeo";
        repo = "gdal";
        rev = "v${version}";
        hash = "sha256-jtAFI1J64ZaTqIljqQL1xOiTGC79AZWcIgidozWczMM=";
      };
      sourceRoot = "source";
      buildInputs = old.buildInputs;
      configureFlags = [
        "--with-libspatialindex=${final.libspatialindex}"
        "--with-expat=${final.expat.dev}"
        "--with-jpeg=${final.libjpeg.dev}"
        "--with-libtiff=${final.libtiff.dev}" # optional (without largetiff support)
        "--with-png=${final.libpng.dev}" # optional
        "--with-poppler=${final.poppler.dev}" # optional
        "--with-libz=${final.zlib.dev}" # optional
        "--with-pg=yes" # since gdal 3.0 doesn't use ${postgresql}/bin/pg_config
        "--with-geotiff=${final.libgeotiff}"
        "--with-libwebp=${final.libwebp}"
        "--with-shapelib=${final.shapelib}"
        "--with-sqlite3=${final.sqlite.dev}"
        "--with-spatialite=${final.libspatialite.dev}"
        "--with-python=${final.python310Full.out}/bin/python" # optional
        "--with-proj=${final.proj.dev}" # optional
        "--with-geos=${final.geos}/bin/geos-config" # optional
        "--with-hdf4=${final.hdf4.dev}" # optional
        "--with-xml2=yes" # optional
        "--with-netcdf=${final.netcdf}"
      ];

      # nixpkgs check phase refers to files that do not exist in recent versions of gdal
      doInstallCheck = false;
      doCheck = false;
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
