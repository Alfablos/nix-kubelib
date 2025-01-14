{ # todo # }
{
  _return =
    d:
    let
      process =
        e:
        with lib.filesystem;
        if pathIsDirectory e then
          readDir (trace "Reading dir ${e}" e)
        else if pathIsRegularFile e then
          readFile (trace "Reading regular file ${e}" e)
        else if isPath e then
          readFile (trace "Reading file from store path: ${e}" e)
        else
          throw "Ma che cazzo è?!";
    in
    if isList d then map (x: process x) d else process d;

  _fTest =
    f: path: string:
    let
      supportedFunctionArgs = {
        outputType = [
          "array"
          "object"
        ];
        yqExpression = [
          null
          ".name"
        ];
      };
      fArgs = functionArgs f;
      intersection = lib.intersectAttrs fArgs supportedFunctionArgs;
      invocationAttrNames = attrNames intersection; # [ "outputType" ]
      getAttrsfromName =
        attrName: # from attrNames
        let
          attrvals = lib.lists.flatten (
            map (name: lib.attrsets.getAttrFromPath [ name ] intersection) invocationAttrNames
          ); # [ "array" "object" null ]
        in
        map (v: { ${attrName} = v; }) (attrvals); # [ { outputType = "array"; } { out = "object"; } { out = null; } ], only for outputType

      # returns possible mappings:
      # - { outputType = null; }
      # - { outputType = "array"; }
      # - { yqExpression = ".name"; }
      # - ...
      # But ONLY where approriate (uses functionArgs)
      defaultArgSets = lib.lists.flatten (map getAttrsfromName invocationAttrNames); # [ { outputType = "array"; } { out = "object"; } { out = null; } { otherforthatfunction1 = "..."; } ]

      invokeWithDefaultArgs =
        func: attrs:
        map (
          defaultSet:
          let
            final = attrs // defaultSet;
          in
          func final #  (trace final final)
        ) defaultArgSets;
    in
    {
      withAttrsStr = _return (invokeWithDefaultArgs f { source = string; });
      withAttrsPath = _return (invokeWithDefaultArgs f { source = path; });
    };

  _fWrapperTest = f: path: string: read: {
    withPath = _return (f path);
    withStr = _return (f string);
  };
}
