{
  lib,
  pkgs,
  nixToYaml,
  ...
}:
rec {
  # helm.downloadHelmChart { repo = "https://traefik.github.io/charts"; chartName = "traefik"; version = "33.2.1"; chartHash = "sha256-RSd7Drtzeen5L96Zsj9N5LqQJtKSMK6EjsCwnkl5Gxk="; }
  downloadHelmChart =
    {
      repo,
      chartName,
      chartVersion,
      chartHash ? lib.fakeHash,
    }:
    pkgs.stdenv.mkDerivation {
      name = "helm-chart-${repo}-${chartName}-${chartVersion}";
      nativeBuildInputs = [ pkgs.cacert ];
      phases = [ "installPhase" ];
      installPhase = ''
        export HELM_CACHE_HOME="$TMP/.nix-helm-build-cache"

        OUT_DIR="$TMP/chart-tmp";
        mkdir -p $OUT_DIR

        ${pkgs.kubernetes-helm}/bin/helm pull \
          --repo ${repo} \
          --version ${chartVersion} \
          ${chartName} \
          -d $OUT_DIR \
          --untar

        mv $OUT_DIR/${chartName} "$out"
      '';
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = chartHash;
    };

  buildHelmChart =
    {
      repo,
      chartName,
      chartVersion,
      chartHash ? lib.fakeHash,
      values ? { },
      set ? [ ],
      setFile ? { },
      namespace ? null,
      createNamespace ? false,
      withCRDs ? true,
      kubeVersion ? "v${pkgs.kubernetes.version}",
      apiVersions ? [ ],
      extraOpts ? [ ],
    }:
    let
      # Helm template will not create the namespace even when being passed `--create-namespace` due to a bug I guess
      createNamespaceManfest =
        name:
        nixToYaml {
          apiVersion = "v1";
          kind = "Namespace";
          inherit name;
          labels = {
            "kubernetes.io/metadata.name" = name;
            inherit name;
          };
        };
    in
    # nsName = if !builtins.isNull namespace then "-${namespace}" else "";
    pkgs.stdenv.mkDerivation rec {
      # name = "${chartName}${nsName}";
      name = "${chartName}";
      chart = downloadHelmChart {
        inherit
          repo
          chartName
          chartVersion
          chartHash
          ;
      };

      helmValues = builtins.toJSON values;
      passAsFile = [ "helmValues" ];

      namespaceFlag = if !builtins.isNull namespace then "--namespace ${namespace}" else "";
      namespaceFlags =
        if (builtins.isNull namespace && createNamespace) then
          builtins.throw "createNamespace is set to true but namespace is null!"
        else
          lib.strings.concatStringsSep " " [
            namespaceFlag
            (if createNamespace then "--create-namespace" else "")
          ]; # Forces a string

      includeCRDsFlag = if withCRDs then "--include-crds" else "";

      setFlags = lib.strings.concatMapStrings (kv: "--set ${kv} ") set;
      setFileFlags =
        let
          setFileList = lib.attrsets.attrValues (
            lib.attrsets.mapAttrs (key: path: "--set-file ${key}=${path}") setFile
          );
        in
        lib.strings.concatStringsSep " " setFileList;

      apiVersionsFlags = lib.strings.concatMapStrings (v: "--api-versions ${v} ") apiVersions;

      extraOptsFlags = lib.strings.concatStringsSep " " extraOpts;

      phases = [ "installPhase" ];

      installPhase = ''

        export HELM_CACHE_HOME="$TMP/.nix-helm-build-cache"

        if $createNamespace; then
          cat ${createNamespaceManfest name} >> $out
          echo >> $out
        fi;

        ${pkgs.kubernetes-helm}/bin/helm template \
          $includeCRDsFlag \
          $namespaceFlags \
          --kube-version "${kubeVersion}" \
          ${
            if lib.lists.length (lib.attrsets.attrNames values) == 0 then "" else "--values $helmValuesPath"
          } \
          ${extraOptsFlags} \
          ${apiVersionsFlags} \
          ${name} \
          ${chart} \
          >> $out
      '';
    };
}
