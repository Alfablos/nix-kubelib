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

  # Allows to call a function in two ways:
  # - f /some/path or f (builtins.readFile /some/path) or f (drv)
  # - f { arg1 = "val1"; arg2 = "val2"; ... }
  # while calling the downstream function with a unified interface.
  resolveArgs = args: if isAttrs args then args else { source = args; };

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
