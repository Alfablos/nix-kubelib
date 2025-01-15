{ pkgs, lib, ... }:
with builtins;
let
  inherit (pkgs.callPackage ./helpers.nix { })
    readPathAndThen
    getGeneratedFiles
    wrapF
    handleResult
    ;
in
rec {

  helm = pkgs.callPackage ./helm.nix { inherit nixToYaml; };

  # Turns a Nix list into a generic Kubernetes Resource List
  toList = items: {
    apiVersion = "v1";
    kind = "List";
    inherit items;
  };

  keyValFromJsonManifest = args: wrapF args _keyValFromJsonManifest;
  # Takes a JSON kubernetes manifests and builds a key-value pair
  # from the manifest.
  # - The VALUE is the content of the file itself
  # - The KEY is the string interpolation of resource name, resource kind
  #   and resource namespace. In case of a non-namespaced resource, the kind is repeated
  _keyValFromJsonManifest =
    { source }:
    let
      nixData = fromJSON source;
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
    # handleResult pathList lib.attrsets.mergeAttrsList;
    lib.attrsets.mergeAttrsList (lib.lists.flatten pathList);

  yamlToJsonFile = args: wrapF args _yamlToJsonFile;

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
      name = "yaml2jsonfile.json";
      inherit source;
      passAsFile = [ "source" ];
      phases = [ "installPhase" ];
      installPhase = "${pkgs.yq-go}/bin/yq $sourcePath -p yaml -o json | ${jqCommand} > $out";
    };


  yamlToMultiJsonFiles = args: wrapF args _yamlToMultiJsonFiles;

  # Turns some YAML content describing ONE OR MORE Kubernetes resources
  # into as many JSON manifests as resources described. The RETURN VALUE is
  # the STORE PATH to the directory containing built files.
  # This function is useful for directly working with Kubernetes AddonManager.
  _yamlToMultiJsonFiles =
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
  # list of ABSOLUTE paths to JSON files.
  yamlToMultiJsonFilePaths =
    args:
    let process = as: getGeneratedFiles (wrapF as _yamlToMultiJsonFiles);
    in
    if isList args
    then lib.lists.flatten (map process args)
    else process args;

  # Converts YAML content to a Nix list forcing the output to be a list.
  # So even if a single object is passed the result will be a Nix list
  # with a single Attrset in it.
  yamlToNixList =
    args:
    lib.lists.flatten [ (yamlToNix args) ];

  # Converts YAML content to JSON.
  yamlToJson =
    args:
    let
      process = a: wrapF a _yamlToJsonFile;
    in
    if isList args
    then
      let paths = map process args;
      in map builtins.readFile paths    # No need to flatten, nested objects in a file remain in the generated file contents
    else readFile (wrapF args _yamlToJsonFile);

  # Converts YAML content (object or list) to Nix. Evaluates to a list anyway if the
  # input is a list of objects.
  yamlToNix =
    args:
    let
      json_s = yamlToJson args;
    in
      if isList json_s
      then lib.lists.flatten (map fromJSON json_s)
      else fromJSON json_s;

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

  # Turns JSON source into YAML string
  jsonToYaml =
    args:
    let
      result = wrapF args _jsonToYamlFile;
    in
    handleResult result readFile;

  jsonToYamlFile =
    args:
    handleResult (wrapF args _jsonToYamlFile) null;

  _jsonToYamlFile =
    {
      source,
      topLevelKey ? null,
    }:
    let
      jsonIsList = j: isList (fromJSON j);
    in
    pkgs.stdenv.mkDerivation rec {
      name = "json2yaml";
      inherit source topLevelKey;
      passAsFile = [ "source" ];
      phases = [ "installPhase" ];
      yqTransform =
        if topLevelKey != null && jsonIsList source then "--expression '{ \"${topLevelKey}\":. }'" else "";
      installPhase = "${pkgs.yq-go}/bin/yq $sourcePath -p json -o yaml ${yqTransform} > $out";
    };
}


