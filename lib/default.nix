{ pkgs, lib, ... }:
with builtins;
let
  kallPackage =
    incomingArgs: f: overrides:
    let
      fArgs = functionArgs f;
      finalArgs = intersectAttrs fArgs incomingArgs // overrides; # Merge with overrides happens last
    in
    f finalArgs;

  readPathAndThen = path: f: f (readFile path);

  # Allows to call a function in two ways:
  # - f /some/path or f (builtins.readFile /some/path) or f (drv)
  # - f { arg1 = "val1"; arg2 = "val2"; ... }
  # while calling the downstream function with a unified interface.
  resolveArgs = args: if isAttrs args then args else { source = args; };

  # Caller calls a function with { source, ... }@args
  # if a path is detected, the content is read before calling the downstream.
  # If args is Attrset then proceed, if not turn it into an Attrset with defaults
  wrapF =
    args: f:
    let
      finalArgs = resolveArgs args;
      sourceIsPath = isPath finalArgs.source;
    in
    if sourceIsPath then
      kallPackage finalArgs f { source = readFile finalArgs.source; }
    else
      kallPackage finalArgs f { };

  getGeneratedFiles =
    with builtins;
    drv:
    let
      fileRelPaths = attrNames (readDir drv.outPath);
    in
    map (file: drv.outPath + "/" + file) fileRelPaths;

  jsonIsList = source: isList (fromJSON source);

in
rec {
  helm = pkgs.callPackage ./helm.nix { inherit nixToYaml; };

  # Turns a Nix list into a generic Kubernetes Resource List
  toList = items: {
    apiVersion = "v1";
    kind = "List";
    inherit items;
  };

  # Takes a JSON kubernetes manifests and builds a key-value pair
  # from the manifest.
  # - The VALUE is the content of the file itself
  # - The KEY is the string interpolation of resource name, resource kind
  #   and resource namespace. In case of a non-namespaced resource, the kind is repeated
  keyValFromJsonManifest =
    input:
    let
      nixData = fromJSON input;
      process =
        c:
        let
          name = c.metadata.name;
          kind = lib.strings.toLower c.kind;
          third = c.metadata.namespace or kind;
        in
        {
          "${name}-${kind}-${third}" = toJSON c;
        };

      f =
        nixContent: if isList nixContent then map (cont: process cont) nixContent else process nixContent;
    in
    f nixData;

  keyValFromJsonManifestFile = path: readPathAndThen path keyValFromJsonManifest;
  # Same as kkeyValFromJsonManifest but deals with list of resources

  keyValFromJsonManifestFiles =
    paths:
    let
      pathList = map (p: keyValFromJsonManifestFile p) paths;
    in
    lib.attrsets.mergeAttrsList (lib.lists.flatten pathList);

  # Turns some YAML content describing ONE OR MORE kubernetes resources
  # into a SINGLE JSON file in the store.
  # In case of more than one resource the default output is a JSON ARRAY (not an object).
  # Call the function with "object" as an outputType and an object with the following structure
  # will be returned: { "items": [ {...}, {...}, ... ] }
  _yamlToJsonFile =
    {
      source,
      outputType ? "array",
    }:
    let
      jqReturnValue =
        if outputType == "array" then
          "."
        else if outputType == "object" then
          "{ items:. }"
        else
          throw "Unknown output type ${outputType}";

      jqCommand = "${pkgs.jq}/bin/jq -n '[inputs] | if length == 1 then .[0] else ${jqReturnValue} end | .'";
    in
    pkgs.stdenv.mkDerivation {
      name = "yaml2jsonfile";
      inherit source;
      passAsFile = [ "source" ];
      phases = [ "installPhase" ];
      installPhase = "${pkgs.yq-go}/bin/yq $sourcePath -p yaml -o json | ${jqCommand} > $out";
    };

  yamlToJsonFile = args: wrapF args _yamlToJsonFile;

  # Turns some YAML content describing ONE OR MORE Kubernetes resources
  # into as many JSON manifests as resources described. The RETURN VALUE is
  # the STORE PATH to the directory containing built files.
  # This function is useful for directly working with Kubernetes AddonManager.
  yamlToMultiJsonFiles =
    {
      source,
      yqExpression ? null,
    }:
    let
      yqExpr =
        if yqExpression == null then
          ".metadata.name + \"-\" + (.kind | downcase) + \"-\" + (.metadata.namespace // (.kind | downcase))"
        else
          yqExpression;
    in
    pkgs.stdenv.mkDerivation {
      name = "yaml2multijsonfile";
      inherit source;
      passAsFile = [ "source" ];
      phases = [ "buildPhase" ];
      buildPhase = ''
        mkdir $out
        cd $out
        ${pkgs.yq-go}/bin/yq -p yaml -o json -s '${yqExpr}' $sourcePath
      '';
    };

  # Same as yamlToMultiJsonFiles but the RETURN VALUE is a
  # NIX LIST (cannot be used with nix build and so on) of ABSOLUTE paths to JSON files.
  yamlToMultiJsonFilePaths =
    {
      source,
      yqExpression ? null,
    }@args:
    getGeneratedFiles (yamlToMultiJsonFiles {
      inherit source yqExpression;
    });

  # Converts YAML content to a Nix list forcing the output to be a list.
  # So even if a single object is passed the result will be a Nix list
  # with a single Attrset in it.
  yamlToNixList =
    source:
    let
      fileAbsPaths = yamlToMultiJsonFilePaths { inherit source; };
    in
    map (path: readPathAndThen path fromJSON) fileAbsPaths;

  # Converts YAML content to JSON.
  yamlToJson =
    {
      source,
      outputType ? "array",
    }@args:
    let
      f = kallPackage args yamlToJsonFile { };
    in
    readFile f;

  # Converts YAML content (object or list) to Nix. Evaluates to a list anyway if the
  # input is a list of objects.
  yamlToNix =
    source:
    fromJSON (yamlToJson {
      inherit source;
    });

  # Converts Nix to YAML.
  nixToYaml =
    attrs:
    let
      j = toJSON attrs;
    in
    pkgs.stdenv.mkDerivation {
      inherit j;
      name = "nixtoYaml";
      passAsFile = [ "j" ];
      phases = [ "buildPhase" ];
      buildPhase = "${pkgs.yq-go}/bin/yq -p json -o yaml $jPath > $out";
    };

  jsonToYaml =
    {
      source,
      topLevelKey ? null,
    }@args:
    readFile (kallPackage args jsonToYamlFile { });

  jsonToYamlFile =
    {
      source,
      topLevelKey ? null,
    }:
    pkgs.stdenv.mkDerivation rec {
      name = "json2yaml";
      inherit source topLevelKey;
      passAsFile = [ "source" ];
      phases = [ "installPhase" ];
      yqTransform =
        if topLevelKey != null && jsonIsList source then "--expression '{ \"${topLevelKey}\":. }'" else "";
      installPhase = "${pkgs.yq-go}/bin/yq $sourcePath -p json -o yaml ${yqTransform} > $out";
    };

  # Same as yamlToJson but for reading files directly.
  yamlFileToJson =
    {
      source,
      outputType ? "array",
    }@args:
    wrapF args yamlToJson;

  # Same as yyamlToMultiJsonFiles but for reading files directly.
  yamlFileToMultiJsonFiles =
    {
      source,
      yqExpression ? null,
    }@args:
    wrapF args yamlToMultiJsonFiles;

  # Same as yamlToNix but for reading files directly.
  yamlFileToNix = path: readPathAndThen path yamlToNix;

  # Sane as yyamlFileToNixList but for reading files directly.
  yamlFileToNixList = path: readPathAndThen path yamlToNixList;

  jsonFileToYamlFile =
    {
      path,
      topLevelKey ? null,
    }@args:
    kallPackage args jsonToYamlFile { source = builtins.readFile path; };
}


