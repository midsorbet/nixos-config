{
  fetchCrate,
  lib,
  makeWrapper,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "pdf-inspector";
  version = "0.1.7";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-S6/NohXpIHIcpCUOGiO9hHwK5cxDYS83cf646i5AREQ=";
  };

  cargoHash = "sha256-/PTqpmL2JdnK/Ejo3IAK/DqTSVrA9zTmFnmRPoc4tLc=";

  # The published crate excludes tests/fixtures to stay under crates.io's size cap.
  checkFlags = [
    "--skip=structure_tree::tests::test_bare_name_struct_types"
    "--skip=structure_tree::tests::test_parse_real_tagged_pdf"
    "--skip=vector_grid_tests::"
  ];

  nativeBuildInputs = [makeWrapper];

  postInstall = ''
    mkdir -p "$out/share/pdf-inspector/bcmaps"
    cp -R external/bcmaps/. "$out/share/pdf-inspector/bcmaps/"

    for program in pdf2md detect-pdf dump_ops; do
      wrapProgram "$out/bin/$program" \
        --set-default PDF_INSPECTOR_BCMAPS_DIR "$out/share/pdf-inspector/bcmaps"
    done
  '';

  meta = {
    description = "Fast PDF classification and Markdown extraction";
    homepage = "https://github.com/firecrawl/pdf-inspector";
    license = lib.licenses.mit;
    mainProgram = "pdf2md";
    platforms = lib.platforms.unix;
  };
}
