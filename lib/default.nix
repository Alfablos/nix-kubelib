{ pkgs, lib, ... }:
let
  helm = pkgs.callPackage ./helm.nix;

  readAndThen = path: f: f (builtins.readFile path);

  getGeneratedFiles = with builtins;
    drv:
    let
      fileRelPaths = attrNames (readDir drv.outPath);
    in
      map (file: drv.outPath + "/" + file) fileRelPaths;

in
rec {
  inherit helm;
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
    lib.pipe
    yamlContent
    [
      (yamlContent:
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
        })
      getGeneratedFiles
    ];

  yamlToNixList = with builtins;
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

  _docs = {
    functions = {
      yamlToJsonFile = "Converts YAML content into a JSON file.";
      yamlToMultiJsonFiles = "Converts a multi object YAML content into multiple JSON files.";
      yamlToNix = "Converts YAML content into Nix equivalent.";
      yamlToJson = "Converts YAML content into JSON string";
      yamlToNixList = "Converts YAML content to a list of Nix attrsets.";
      yamlFileToMultiJsonFiles = "Same as yamlToMultiJsonFiles but accepts a file as a source.";
      yamlFileToNix = "Same as yamlToNix but accepts a file as a source.";
      yamlFileToNixList = "Same as yamlToNixList but accepts a file as a source.";
    };
  };
}


