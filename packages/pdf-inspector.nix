{
  fetchCrate,
  lib,
  makeWrapper,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "pdf-inspector";
  version = "1.14.0";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-uVnrgDwjz7wsn+OF7tHfpFlBBH7VYHPmQf4SljyuGfU=";
  };

  cargoHash = "sha256-oY3VoY/gbY54Jvy/RcAj4hVSLS3RZfudMx8yFEJAKO0=";

  # The published crate excludes tests/fixtures to stay under crates.io's size cap.
  checkFlags = [
    "--skip=structure_tree::tests::test_bare_name_struct_types"
    "--skip=structure_tree::tests::test_parse_real_tagged_pdf"
    "--skip=tests::items_json_uses_supplied_pdf_password"
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
