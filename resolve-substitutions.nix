template: substitutions:
let
  keys = builtins.attrNames substitutions;
  wrappedKeys = map (k: "@${k}@") keys;
  values = builtins.attrValues substitutions;
in
  builtins.replaceStrings wrappedKeys values template
