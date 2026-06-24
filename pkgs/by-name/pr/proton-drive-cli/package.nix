{
  lib,
  stdenvNoCC,
  bun,
  nodejs,
  fetchFromGitHub,
  glib,
  libffi,
  libgcrypt,
  libgpg-error,
  libsecret,
  libselinux,
  makeWrapper,
  pcre2,
  util-linux,
  writableTmpDirAsHomeHook,
  xdg-utils,
}:
let
  secretsLibs = [
    libsecret
    glib
    pcre2
    libffi
    libselinux
    libgpg-error
    util-linux.lib
    libgcrypt.lib
  ];
in

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "proton-drive-cli";
  version = "0.4.6";

  strictDeps = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "ProtonDriveApps";
    repo = "sdk";
    rev = "e3d666b3395aa140b7629d8fdc46a8990c044c45";
    hash = "sha256-plYUi7lN9dqiZPgiVGX4ka7Ls6DiIvTuxrRFKFdoA4o=";
  };

  sourceRoot = "${finalAttrs.src.name}/js/cli";

  node_modules = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src sourceRoot;

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [
      bun
      nodejs
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --cpu="*" \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress \
        --os="*"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -R node_modules $out/

      drive_sdk="$out/node_modules/@protontech/drive-sdk"
      rm -r "$drive_sdk"
      cp -R --dereference node_modules/@protontech/drive-sdk "$out/node_modules/@protontech/"


      runHook postInstall
    '';

    dontFixup = true;

    outputHash = "sha256-eJ+JVFOCujmJKo7WkrMcDCoXdbieWL61HvwCU0JLLFw=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    bun
    makeWrapper
  ];
  buildInputs = secretsLibs;

  configurePhase = ''
    runHook preConfigure

    # Upstream uses a sibling workspace dependency via `file:../sdk`,
    # so both the CLI tree and sibling SDK tree need vendored node_modules.
    chmod -R u+w ../sdk
    cp -R ${finalAttrs.node_modules}/node_modules .
    cp -R ${finalAttrs.node_modules}/node_modules ../sdk/

    substituteInPlace node_modules/.bin/tsc \
      --replace-fail '#!/usr/bin/env node' '#!${lib.getExe nodejs}'

    substituteInPlace ../sdk/node_modules/.bin/tsc \
      --replace-fail '#!/usr/bin/env node' '#!${lib.getExe nodejs}'

    runHook postConfigure
  '';

  env.CLI_VERSION = finalAttrs.version;
  env.JS_VERSION = "0.16.0";
  env.CLI_APP_VERSION_NAME = "external-drive-proton_drive_cli";

  buildPhase = ''
    runHook preBuild

    pushd ../sdk
    bun run build
    popd
    chmod -R u+w node_modules/@protontech/drive-sdk
    rm -rf node_modules/@protontech/drive-sdk/dist
    cp -R ../sdk/dist node_modules/@protontech/drive-sdk/
    bun run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 release/proton-drive $out/bin/proton-drive
    wrapProgram $out/bin/proton-drive \
      --suffix LD_LIBRARY_PATH : "${lib.makeLibraryPath secretsLibs}" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]}

    runHook postInstall
  '';

  dontStrip = true;

  nativeInstallCheckInputs = [ writableTmpDirAsHomeHook ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # installCheck runs without a Secret Service backend in the Nix sandbox.
    PROTON_DRIVE_UNSAFE_SECRETS=1 $out/bin/proton-drive version | grep -F "external-drive-proton_drive_cli@${finalAttrs.version}"
    PROTON_DRIVE_UNSAFE_SECRETS=1 $out/bin/proton-drive help > /dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line interface for Proton Drive";
    homepage = "https://github.com/ProtonDriveApps/sdk/tree/${finalAttrs.src.rev}/js/cli";
    changelog = "https://github.com/ProtonDriveApps/sdk/blob/${finalAttrs.src.rev}/js/cli/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ cameroncandau ];
    mainProgram = "proton-drive";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
})
