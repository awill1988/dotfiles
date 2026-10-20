final: prev:
let
  version = "0.1.0";
  rev = "1cfe254e8d25b15f37048c3730134686abe60335";

  src = prev.fetchFromGitHub {
    owner = "google-research";
    repo = "harness2";
    inherit rev;
    hash = "sha256-cQVJDwcE0eCcS65JeIC+aa5OOeuChkn+RG5pzgoFopk=";
  };
in
{
  harness2 = prev.python3Packages.buildPythonApplication {
    pname = "harness2";
    inherit version src;
    pyproject = true;

    build-system = [ prev.python3Packages.setuptools ];

    dependencies = with prev.python3Packages; [
      fastapi
      google-auth
      openpyxl
      python-pptx
    ];

    nativeCheckInputs = [ prev.python3Packages.unittestCheckHook ];
    unittestFlagsArray = [
      "-s"
      "tests"
      "-v"
    ];

    postPatch = ''
      substituteInPlace harness2/config.py \
        --replace-fail \
          'THIRD_PARTY = ROOT / "third_party"' \
          'THIRD_PARTY = Path(os.environ["HARNESS2_THIRD_PARTY"]) if os.environ.get("HARNESS2_THIRD_PARTY") else (ROOT / "third_party" if (ROOT / "third_party").is_dir() else PKG / "third_party")'

      substituteInPlace harness2/install.py \
        --replace-fail \
          'ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "PROVENANCE.md"),' \
          'ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "PROVENANCE.md"), copy_function=shutil.copyfile,'
    '';

    postInstall = ''
      cp -r third_party "$out/${prev.python3.sitePackages}/harness2/third_party"
      install -Dm755 scripts/split_tasks.py "$out/bin/harness2-split-tasks"
    '';

    makeWrapperArgs = [
      "--prefix"
      "PYTHONPATH"
      ":"
      "$PYTHONPATH"
    ];

    pythonImportsCheck = [
      "harness2"
      "harness2.cli.run_sweep"
      "harness2.cli.setup"
      "harness2.cli.check"
      "harness2.cli.demo"
      "harness2.cli.judge"
      "harness2.cli.report"
      "harness2.cli.bridge"
    ];

    meta = with prev.lib; {
      description = "Harness2: Recursive Agent Harnessing for an Open World";
      homepage = "https://github.com/google-research/harness2";
      license = licenses.asl20;
      mainProgram = "harness2";
      platforms = platforms.unix;
      maintainers = [ ];
    };
  };
}
