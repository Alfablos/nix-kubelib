{ lib }:
with builtins;
rec {
  kallPackage =
    incomingArgs: f: overrides:
    let
      fArgs = functionArgs f;
      finalArgs = intersectAttrs fArgs incomingArgs // overrides; # Merge with overrides happens last
    in
    f finalArgs;

  readPathAndThen = path: f: f (readFile path);

  handleResult =
    result: f:
    let
      fOrNull = r: if isNull f then r else f r;
    in
    if isList result
    then lib.lists.flatten (map (r: fOrNull r) result)
    else fOrNull result;

  # Allows to call a function in two ways:
  # - f /some/path or f (builtins.readFile /some/path) or f (drv)
  # - f { arg1 = "val1"; arg2 = "val2"; ... }
  # The downstream function (wrapF) will only have to handle 3 cases:
  # - List
  # - Attrs { source = args; }
  # - Attrs { some = "thing"; something = "else"; }
  # 
  # -> resolveArgs [ ./deploy.yml ./deploys.yml ]
  # [
  #   /path/to/deploy.yml
  #   /path/to/deploys.yml
  # ]
  #
  # -> resolveArgs { a = 1; b = 2; }
  # { a = 1; b = 2; }
  #
  # -> resolveArgs "test"
  # { source = "test"; }
  resolveArgs = args:
    if isAttrs args then args
    else if isList args
      then lib.lists.flatten ( resolveArgs args )
    else { source = args; };


  # Caller calls a function with args. Args can be { source, this, that, ... },
  # a path/string or a list of elements.
  # If a list is detected, each element is processed as follows:
  #   If a path is detected, the content is read before calling the downstream function.
  #   If args is Attrset then proceed, if not turn it into an Attrset with defaults.
  # If no list is passed process happens normally.
  # This allows to mix argument sources:
  # - yamlToJsonFile [ ./tests/services.yml (builtins.readFile ./tests/server-cert.yml) ]
  # - yamlToJsonFile [ { source = ./tests/services.yml; } { source = (builtins.readFile ./tests/server-cert.yml); } ]
  wrapF =
    args: f:
    let
      processUnit = as:
        let
          finalArgs = resolveArgs as;
          sourceIsPath = isPath finalArgs.source;
        in
        if sourceIsPath then
        kallPackage finalArgs f { source = readFile finalArgs.source; }
        else
        kallPackage finalArgs f { };
    in
    if isList args
    then map processUnit args
    else processUnit args;


  getGeneratedFiles =
    with builtins;
    drv:
    let
      fileRelPaths = attrNames (readDir drv.outPath);
    in
    map (file: drv.outPath + "/" + file) fileRelPaths;

  jsonIsList = source: isList (fromJSON source);
}
