-- Load project flake dev-shell environment when one is present.
return {
  cmd = { 'metals' },
  filetypes = { 'scala', 'sbt' },
  root_markers = { 'build.sbt', 'build.sc', { 'build.gradle', 'build.gradle.kts' }, 'pom.xml', 'flake.nix', '.git' },
}
