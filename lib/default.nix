{ pkgs, lib, ... }:
let

  readAndThen = path: f: f (builtins.readFile path);

  getGeneratedFiles =
    with builtins;
    drv:
    let
      fileRelPaths = attrNames (readDir drv.outPath);
    in
      map (file: drv.outPath + "/" + file) fileRelPaths;

in
rec {
  helm = pkgs.callPackage ./helm.nix { inherit nixToYaml; };
  # recurseKeys = elem:
  #   # let
  #   #   baseCase = elem;
  #   #   recursiveCase = recurseKeys elem;
  #   # in
  #   # if lib.isAttrs val => recurse and then keys (val)
  #   lib.attrsets.foldlAttrs
  #     (acc: key: val:
  #       let subsequent = s: if (lib.isAttrs s) then (recurseKeys s) else {};
  #       in
  #     {
  #       keys = acc.keys ++ [ key ] ++ (lib.attrNames (subsequent val));
  #     })
  #     { keys = []; }
  #     elem;

  toList = items: {
    apiVersion = "v1";
    kind = "List";
    inherit items;
  };

  keyValFromJsonResource =
    path:
    let
      content = builtins.fromJSON (builtins.readFile path);
    in
    {
      "${content.metadata.name}-${lib.strings.toLower content.kind}-${
        content.metadata.namespace or (lib.strings.toLower content.kind)
      }" =
        content;
    };

  keyValFromJsonResources =
    paths:
    let
      list = map (p: keyValFromJsonResource p) paths;
    in
    lib.attrsets.mergeAttrsList list;

  yamlToJsonFile =
    yamlContent:
    pkgs.stdenv.mkDerivation {
      name = "yaml2jsonfile";
      inherit yamlContent;
      passAsFile = [ "yamlContent" ];
      phases = [ "buildPhase" ];
      buildPhase = "${pkgs.yq-go}/bin/yq -p yaml -o json $yamlContentPath > $out";
    };

  yamlToMultiJsonFiles =
    yamlContent:
    lib.pipe yamlContent [
      (
        yamlContent:
        pkgs.stdenv.mkDerivation {
          name = "yaml2multijsonfile";
          inherit yamlContent;
          passAsFile = [ "yamlContent" ];
          phases = [ "buildPhase" ];
          buildPhase = ''
            mkdir $out
            cd $out
            ${pkgs.yq-go}/bin/yq -p yaml -o json -s '.metadata.name + "-" + .kind + "-" + (.metadata.namespace // "namespace")' $yamlContentPath
          '';
        }
      )
      getGeneratedFiles
    ];

  yamlToNixList =
    with builtins;
    yamlContent:
    let
      fileAbsPaths = yamlToMultiJsonFiles yamlContent;
    in
    map (path: fromJSON (readFile path)) fileAbsPaths;

  yamlToJson = yamlContent: builtins.readFile (yamlToJsonFile yamlContent);
  # lib.pipe
  # yamlContent
  # [
  #   yamlToJsonFile
  #   builtins.readFile
  # ];

  yamlToNix = yamlContent: builtins.fromJSON (yamlToJson yamlContent);
  # lib.pipe
  # yamlContent
  # [
  #   yamlToJson
  #   builtins.fromJSON
  # ];

  yamlFileToMultiJsonFiles = path: yamlToMultiJsonFiles (builtins.readFile path); # path: readAndThen path yamlToMultiJsonFiles;

  yamlFileToNix = path: readAndThen path yamlToNix;

  yamlFileToNixList = path: readAndThen path yamlToNixList;

  nixToYaml = attrs:
    let jsonContent = builtins.toJSON attrs;
    in
      pkgs.stdenv.mkDerivation {
        inherit jsonContent;
        name = "nixtoYaml";
        passAsFile = [ "jsonContent" ];
        phases = [ "buildPhase" ];
        buildPhase = "${pkgs.yq-go}/bin/yq -p json -o yaml $jsonContentPath > $out";
      };

  _docs = {
    functions = {
      keyValFromJsonResource = ''
        Generates a key value pair from a json file containing a single Kubernetes resource. They key is templated using '.metadata.name - .kind - .metadata.namespace', the value is the nix equivalent
        From a JSON file whose content is {"apiVersion":"v1", "kind": "Pod", "metadata": {"name": "test", "namespace": "somenamespace"}}
        An attribute set is generated like: { test-pod-somenamespace = { apiVersion = "v1"; kind = "Pod", metadata = { name = "test"; namespace = "somenamespace"; }; }; }
      '';
      keyValFromJsonResources = "Same as keyValFromJsonResource but for multiple paths";
      yamlToJsonFile = "Converts YAML content into a JSON file.";
      yamlToMultiJsonFiles = "Converts a multi object YAML content into multiple JSON files.";
      yamlToNix = "Converts YAML content into Nix equivalent.";
      yamlToJson = "Converts YAML content into JSON string";
      yamlToNixList = "Converts YAML content to a list of Nix attrsets.";
      yamlFileToMultiJsonFiles = "Same as yamlToMultiJsonFiles but accepts a file as a source.";
      yamlFileToNix = "Same as yamlToNix but accepts a file as a source.";
      yamlFileToNixList = "Same as yamlToNixList but accepts a file as a source.";
      nixToYaml = "Converts an attribute set to YAML";
    };
  };
}
