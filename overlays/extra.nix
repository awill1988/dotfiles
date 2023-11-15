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

}
