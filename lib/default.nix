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

  callWithYamlContent = args: f: kallPackage args f { yamlContent = readFile args.path; };

  getGeneratedFiles =
    with builtins;
    drv:
    let
      fileRelPaths = attrNames (readDir drv.outPath);
    in
    map (file: drv.outPath + "/" + file) fileRelPaths;
    
  jsonIsList = jsonContent:
    isList (fromJSON jsonContent);

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
      process = c:
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
      list = map (p: keyValFromJsonManifestFile p) paths;
    in
    lib.attrsets.mergeAttrsList list;

  # Turns some YAML content describing ONE OR MORE kubernetes resources
  # into a SINGLE JSON file in the store.
  # In case of more than one resource the default output is a JSON ARRAY (not an object).
  # Call the function with "object" as an outputType and an object with the following structure
  # will be returned: { "items": [ {...}, {...}, ... ] }
  yamlToJsonFile =
    {
      yamlContent,
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
      inherit yamlContent;
      passAsFile = [ "yamlContent" ];
      phases = [ "installPhase" ];
      installPhase = "${pkgs.yq-go}/bin/yq $yamlContentPath -p yaml -o json | ${jqCommand} > $out";
    };

  # Turns some YAML content describing ONE OR MORE Kubernetes resources
  # into as many JSON manifests as resources described. The RETURN VALUE is
  # the STORE PATH to the directory containing built files.
  # This function is useful for directly working with Kubernetes AddonManager.
  yamlToMultiJsonFiles =
    {
      yamlContent,
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
      inherit yamlContent;
      passAsFile = [ "yamlContent" ];
      phases = [ "buildPhase" ];
      buildPhase = ''
        mkdir $out
        cd $out
        ${pkgs.yq-go}/bin/yq -p yaml -o json -s '${yqExpr}' $yamlContentPath
      '';
    };

  # Same as yamlToMultiJsonFiles but the RETURN VALUE is a
  # NIX LIST (cannot be used with nix build and so on) of ABSOLUTE paths to JSON files.
  yamlToMultiJsonFilePaths =
    {
      yamlContent,
      yqExpression ? null,
    }@args:
    getGeneratedFiles (yamlToMultiJsonFiles {
      inherit yamlContent yqExpression;
    });

  # Converts YAML content to a Nix list forcing the output to be a list.
  # So even if a single object is passed the result will be a Nix list
  # with a single Attrset in it.
  yamlToNixList =
    yamlContent:
    let
      fileAbsPaths = yamlToMultiJsonFilePaths { inherit yamlContent; };
    in
    map (path: readPathAndThen path fromJSON) fileAbsPaths;

  # Converts YAML content to JSON.
  yamlToJson =
    {
      yamlContent,
      outputType ? "array",
    }@args:
    let
      f = kallPackage args yamlToJsonFile { };
    in
    readFile f;

  # Converts YAML content (object or list) to Nix. Evaluates to a list anyway if the
  # input is a list of objects.
  yamlToNix =
    yamlContent:
    fromJSON (yamlToJson {
      inherit yamlContent;
    });

  # Same as yamlToJson but for reading files directly.
  yamlFileToJson =
    {
      path,
      outputType ? "array",
    }@args:
    callWithYamlContent args yamlToJson;

  # Same as yamlToJsonFiles but for reading files directly.
  yamlFileToJsonFile =
    {
      path,
      outputType ? "array",
    }@args:
    callWithYamlContent args yamlToJsonFile;
  # Same as yyamlToMultiJsonFiles but for reading files directly.
  yamlFileToMultiJsonFiles =
    {
      path,
      yqExpression ? null,
    }@args:
    callWithYamlContent args yamlToMultiJsonFiles;

  # Same as yamlToNix but for reading files directly.
  yamlFileToNix = path: readPathAndThen path yamlToNix;

  # Sane as yyamlFileToNixList but for reading files directly.
  yamlFileToNixList = path: readPathAndThen path yamlToNixList;

  # Converts Nix to YAML.
  nixToYaml =
    attrs:
    let
      jsonContent = toJSON attrs;
    in
    pkgs.stdenv.mkDerivation {
      inherit jsonContent;
      name = "nixtoYaml";
      passAsFile = [ "jsonContent" ];
      phases = [ "buildPhase" ];
      buildPhase = "${pkgs.yq-go}/bin/yq -p json -o yaml $jsonContentPath > $out";
    };

  jsonToYaml =
    {
      jsonContent,
      topLevelKey ? null
    }@args:
    readFile ( kallPackage args jsonToYamlFile { } );

  jsonToYamlFile =
    {
      jsonContent,
      topLevelKey ? null,
    }:
    pkgs.stdenv.mkDerivation rec {
      name = "json2yaml";
      inherit jsonContent topLevelKey;
      passAsFile = [ "jsonContent" ];
      phases = [ "installPhase" ];
      yqTransform = if topLevelKey != null && jsonIsList jsonContent then "--expression '{ \"${topLevelKey}\":. }'" else "";
      installPhase = "${pkgs.yq-go}/bin/yq $jsonContentPath -p json -o yaml ${yqTransform} > $out";
    };

  jsonFileToYamlFile =
    { path, topLevelKey ? null }@args:
    kallPackage args jsonToYamlFile { jsonContent = builtins.readFile path; };
}
