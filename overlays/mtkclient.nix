final: prev: {
  mtkclient = prev.python3Packages.buildPythonApplication {
    pname = "mtkclient";
    version = "2.1.4.1";
    pyproject = true;

    src = prev.fetchFromGitHub {
      owner = "bkerler";
      repo = "mtkclient";
      tag = "v2.1.4.1";
      hash = "sha256-8Y9tyw+dmhhc4tFo3slr4wQIPXIrmIk/wuCK4aM6oLY=";
    };

    build-system = [ prev.python3Packages.hatchling ];

    dependencies = with prev.python3Packages; [
      colorama
      fusepy
      pycryptodome
      pycryptodomex
      pyserial
      pyside6
      pyusb
      shiboken6
    ];

    pythonImportsCheck = [ "mtkclient" ];

    meta = with prev.lib; {
      description = "MTK reverse engineering and flash tool";
      homepage = "https://github.com/bkerler/mtkclient";
      mainProgram = "mtk";
      license = licenses.gpl3;
      sourceProvenance = with sourceTypes; [
        binaryFirmware
        fromSource
      ];
    };
  };
}
