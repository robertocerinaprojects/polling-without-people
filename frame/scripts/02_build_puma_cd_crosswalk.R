# Build a PUMA-to-congressional-district crosswalk for the 2026 election.
# Plain-language summary: frame/docs/02_build_puma_cd_crosswalk.md
# Run from repository root: Rscript frame/scripts/02_build_puma_cd_crosswalk.R


# Section 1: import and audit the national block-to-district assignments.
# Source documentation:
# https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html

library(dplyr)

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

# Pin the archive downloaded on 2026-10-30.
source_url <- paste0(
  "https://www2.census.gov/programs-surveys/decennial/rdo/",
  "mapping-files/2027/120-congressional-district-befs/cd120.zip"
)
zip_path <- here::here("frame", "data", "input", "cd120.zip")
# SHA-256 computed from our downloaded source_url archive.
expected_sha256 <- "bc9a4fc543b8b279ce3663642a5cc4e19e32a8ef84f12371e26f754e5b8cc8a5"

check(file.exists(zip_path), "Missing input: frame/data/input/cd120.zip")
check(
  digest::digest(zip_path, algo = "sha256", file = TRUE,
                 serialize = FALSE) == expected_sha256,
  "Archive checksum differs from the pinned snapshot."
)

member <- "NationalCD120.txt"
check(
  sum(unzip(zip_path, list = TRUE)$Name == member) == 1L,
  "Expected exactly one NationalCD120.txt in the archive."
)

# Extract only the national table into a temporary directory.
# Eager reading allows that temporary copy to be removed immediately.
read_national_bef <- function(zip_path, member) {
  temporary_dir <- tempfile("cd120_")
  dir.create(temporary_dir)
  on.exit(unlink(temporary_dir, recursive = TRUE), add = TRUE)

  extracted <- unzip(zip_path, files = member, exdir = temporary_dir)
  check(length(extracted) == 1L, "National table extraction failed.")
  check(file.exists(extracted), "Extracted national table is missing.")

  readr::read_csv(
    extracted,
    col_types = readr::cols(.default = readr::col_character()),
    trim_ws = FALSE,
    name_repair = "minimal",
    skip_empty_rows = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )
}

cat("Reading national block assignments...\n")
block_cd <- read_national_bef(zip_path, member)

expected_columns <- c(
  "GEOID", "STATEFP", "COUNTYFP", "TRACTCE", "BLOCKCE", "CDFP"
)
check(identical(names(block_cd), expected_columns), "Unexpected columns.")
check(nrow(block_cd) > 0L, "National table is empty.")
check(nrow(readr::problems(block_cd)) == 0L, "CSV parsing problems found.")
check(!anyNA(block_cd), "Missing values found in block assignments.")

# Validate digit-only geographic identifiers and their fixed widths.
# Identifier widths and concatenation: https://www.census.gov/programs-surveys/geography/guidance/geo-identifiers.html
widths <- c(GEOID = 15L, STATEFP = 2L, COUNTYFP = 3L,
            TRACTCE = 6L, BLOCKCE = 4L)

for (variable in names(widths)) {
  pattern <- sprintf("^[0-9]{%d}$", widths[[variable]])
  check(
    all(grepl(pattern, block_cd[[variable]])),
    paste("Malformed identifiers in", variable)
  )
}

check(
  all(block_cd$GEOID == paste0(
    block_cd$STATEFP, block_cd$COUNTYFP,
    block_cd$TRACTCE, block_cd$BLOCKCE
  )),
  "GEOID disagrees with its geographic components."
)
check(anyDuplicated(block_cd$GEOID) == 0L, "Duplicate block GEOIDs found.")

# Validate documented district-code forms; review state-specific sets next.
# Codes 01-53, 00, 98 and ZZ: BEF documentation above, notes 2-3.
allowed_cd_codes <- c(sprintf("%02d", 0:53), "98", "ZZ")
check(
  all(block_cd$CDFP %in% allowed_cd_codes),
  "Unexpected congressional district codes."
)

# Require all 50 states plus DC; retain and report any territories.
# Listed FIPS codes: https://www2.census.gov/geo/docs/reference/state.txt
target_states <- sprintf(
  "%02d", c(1, 2, 4, 5, 6, 8:13, 15:42, 44:51, 53:56)
)
allowed_states <- c(target_states, "60", "66", "69", "72", "78")

check(
  all(block_cd$STATEFP %in% allowed_states),
  "Unrecognized state or territory codes."
)
check(
  all(target_states %in% block_cd$STATEFP),
  "At least one required state or DC is missing."
)

coverage <- block_cd |>
  group_by(STATEFP) |>
  summarise(
    blocks = n(),
    assigned_districts = n_distinct(CDFP[CDFP != "ZZ"]),
    unassigned_blocks = sum(CDFP == "ZZ"),
    .groups = "drop"
  ) |>
  mutate(in_target = STATEFP %in% target_states)

cat("\nJurisdiction coverage:\n")
print(coverage, n = Inf, width = Inf)

cat("\nSpecial district codes:\n")
block_cd |>
  filter(CDFP %in% c("00", "98", "ZZ")) |>
  count(STATEFP, CDFP, name = "blocks") |>
  print(n = Inf, width = Inf)

cat("\nStructural checks passed.\n")
cat("Total block records:", nrow(block_cd), "\n")
cat(
  "Assigned districts across the 50 states plus DC:",
  sum(coverage$assigned_districts[coverage$in_target]), "\n"
)

# Section 2: validate district-code sets and apply geographic scope.
# Seat allocations: 2020 Census apportionment, Table 1.
# https://www.census.gov/data/tables/2020/dec/2020-apportionment-data.html
seats <- c(
  "01" = 7L,  "02" = 1L,  "04" = 9L,  "05" = 4L,  "06" = 52L,
  "08" = 8L,  "09" = 5L,  "10" = 1L,  "12" = 28L, "13" = 14L,
  "15" = 2L,  "16" = 2L,  "17" = 17L, "18" = 9L,  "19" = 4L,
  "20" = 4L,  "21" = 6L,  "22" = 6L,  "23" = 2L,  "24" = 8L,
  "25" = 9L,  "26" = 13L, "27" = 8L,  "28" = 4L,  "29" = 8L,
  "30" = 2L,  "31" = 3L,  "32" = 4L,  "33" = 2L,  "34" = 12L,
  "35" = 3L,  "36" = 26L, "37" = 14L, "38" = 1L,  "39" = 15L,
  "40" = 5L,  "41" = 6L,  "42" = 17L, "44" = 2L,  "45" = 7L,
  "46" = 1L,  "47" = 9L,  "48" = 38L, "49" = 4L,  "50" = 1L,
  "51" = 11L, "53" = 10L, "54" = 2L,  "55" = 8L,  "56" = 1L
)

check(sum(seats) == 435L, "Seat reference does not total 435.")
check(
  setequal(names(seats), setdiff(target_states, "11")),
  "Seat reference does not cover exactly the 50 states."
)

expected_codes <- lapply(seats, function(n) {
  if (n == 1L) "00" else sprintf("%02d", seq_len(n))
})
expected_codes[["11"]] <- "98"  # District of Columbia
expected_codes[["72"]] <- "98"  # Puerto Rico, audited before exclusion

check(
  setequal(names(expected_codes), unique(block_cd$STATEFP)),
  "Input jurisdictions differ from the district-code reference."
)

assigned_codes <- block_cd |>
  distinct(STATEFP, CDFP) |>
  filter(CDFP != "ZZ")

district_audit <- bind_rows(lapply(names(expected_codes), function(st) {
  observed <- assigned_codes$CDFP[assigned_codes$STATEFP == st]
  expected <- expected_codes[[st]]

  tibble(
    STATEFP = st,
    expected_districts = length(expected),
    observed_districts = length(observed),
    missing_codes = paste(setdiff(expected, observed), collapse = ","),
    unexpected_codes = paste(setdiff(observed, expected), collapse = ","),
    passed = setequal(expected, observed)
  )
})) |>
  arrange(STATEFP)

if (!all(district_audit$passed)) {
  print(filter(district_audit, !passed), n = Inf, width = Inf)
  stop("District-code validation failed.", call. = FALSE)
}

cat("\nExact district-code validation passed for all",
    nrow(district_audit), "jurisdictions.\n")

# Apply the same 50-state-plus-DC scope used in PUMS preparation.
excluded_jurisdictions <- coverage |>
  filter(!in_target)

rows_before_scope <- nrow(block_cd)
block_cd <- block_cd |>
  filter(STATEFP %in% target_states)

check(
  rows_before_scope ==
    nrow(block_cd) + sum(excluded_jurisdictions$blocks),
  "Block counts do not reconcile after applying geographic scope."
)
check(
  setequal(unique(block_cd$STATEFP), target_states),
  "Retained geography differs from the 50 states plus DC."
)

cat("\nExcluded jurisdictions:\n")
print(excluded_jurisdictions, n = Inf, width = Inf)
cat("Retained block records:", nrow(block_cd), "\n")
cat("Retained unassigned blocks:", sum(block_cd$CDFP == "ZZ"), "\n")

output_dir <- here::here("frame", "data", "output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

readr::write_csv(
  coverage, file.path(output_dir, "02_cd120_coverage.csv")
)
readr::write_csv(
  district_audit, file.path(output_dir, "02_cd120_district_codes.csv")
)
readr::write_csv(
  excluded_jurisdictions,
  file.path(output_dir, "02_cd120_excluded_jurisdictions.csv")
)

cat("District and geographic-scope audits saved.\n")

# Section 3: import the tract-to-PUMA lookup and audit block matches.
puma_source_url <- paste0(
  "https://www2.census.gov/geo/docs/maps-data/data/rel2020/",
  "2020_Census_Tract_to_2020_PUMA.txt"
)
puma_path <- here::here(
  "frame", "data", "input", "2020_Census_Tract_to_2020_PUMA.txt"
)
# SHA-256 computed from our downloaded puma_source_url file.
puma_sha256 <- "5262f460b2c8dbe86b00549e916317b1791fdc595c9af72ab18f6f6a67040531"

check(file.exists(puma_path), "Missing tract-to-PUMA input.")
check(
  digest::digest(puma_path, algo = "sha256", file = TRUE,
                 serialize = FALSE) == puma_sha256,
  "Tract-to-PUMA checksum differs from the pinned snapshot."
)

tract_puma <- readr::read_csv(
  puma_path,
  col_types = readr::cols(.default = readr::col_character()),
  trim_ws = FALSE,
  name_repair = "minimal",
  skip_empty_rows = FALSE,
  show_col_types = FALSE,
  lazy = FALSE
)

check(
  identical(names(tract_puma),
            c("STATEFP", "COUNTYFP", "TRACTCE", "PUMA5CE")),
  "Unexpected tract-to-PUMA columns."
)
check(nrow(tract_puma) > 0L, "Tract-to-PUMA table is empty.")
check(nrow(readr::problems(tract_puma)) == 0L, "Lookup parsing problems.")
check(!anyNA(tract_puma), "Missing values in the tract-to-PUMA lookup.")

# Widths: GEOID guidance above and PUMA coding guidelines below.
puma_widths <- c(STATEFP = 2L, COUNTYFP = 3L, TRACTCE = 6L, PUMA5CE = 5L)
for (variable in names(puma_widths)) {
  check(
    all(grepl(sprintf("^[0-9]{%d}$", puma_widths[[variable]]),
              tract_puma[[variable]])),
    paste("Malformed lookup identifiers in", variable)
  )
}

# Census 2020 PUMA coding guidelines specify 00100 through 99995.
# https://www2.census.gov/geo/pdfs/reference/puma2020/2020PUMA_CodingGuidelines.pdf
puma_numbers <- as.integer(tract_puma$PUMA5CE)
check(
  all(puma_numbers >= 100L & puma_numbers <= 99995L),
  "PUMA codes outside the documented range; review required."
)
check(
  all(tract_puma$STATEFP %in% allowed_states),
  "Unrecognized lookup jurisdiction codes."
)
check(
  all(target_states %in% tract_puma$STATEFP),
  "Lookup does not cover all 50 states plus DC."
)

tract_puma <- tract_puma |>
  mutate(tract_geoid = paste0(STATEFP, COUNTYFP, TRACTCE))

check(
  anyDuplicated(tract_puma$tract_geoid) == 0L,
  "Duplicate tract keys: each tract must have one lookup row."
)

puma_lookup_audit <- tract_puma |>
  group_by(STATEFP) |>
  summarise(
    tracts = n(),
    pumas = n_distinct(PUMA5CE),
    .groups = "drop"
  ) |>
  mutate(in_target = STATEFP %in% target_states)

tract_puma <- tract_puma |>
  filter(STATEFP %in% target_states)

# Join only the tract key and PUMA code, preserving all block rows.
rows_before_join <- nrow(block_cd)
block_ids_before <- block_cd$GEOID

block_cd <- block_cd |>
  # Tract key: first 11 digits = state 2 + county 3 + tract 6 (GEOID guidance).
  mutate(tract_geoid = substr(GEOID, 1L, 11L)) |>
  left_join(
    select(tract_puma, tract_geoid, PUMA5CE),
    by = "tract_geoid",
    relationship = "many-to-one",
    na_matches = "never"
  )

check(
  nrow(block_cd) == rows_before_join,
  "The tract-to-PUMA join changed the number of blocks."
)
check(
  identical(block_cd$GEOID, block_ids_before),
  "Block identifiers or their order changed during the join."
)
rm(block_ids_before)

puma_join_audit <- block_cd |>
  group_by(STATEFP) |>
  summarise(
    blocks = n(),
    matched_blocks = sum(!is.na(PUMA5CE)),
    unmatched_blocks = sum(is.na(PUMA5CE)),
    unmatched_tracts = n_distinct(tract_geoid[is.na(PUMA5CE)]),
    matched_pumas = n_distinct(PUMA5CE, na.rm = TRUE),
    .groups = "drop"
  )

# Each audit row below represents a tract-district combination.
unmatched_tract_districts <- block_cd |>
  filter(is.na(PUMA5CE)) |>
  count(STATEFP, tract_geoid, CDFP, name = "blocks") |>
  arrange(STATEFP, tract_geoid, CDFP)

check(
  sum(unmatched_tract_districts$blocks) == sum(is.na(block_cd$PUMA5CE)),
  "Unmatched-block audit does not reconcile."
)

readr::write_csv(
  puma_lookup_audit,
  file.path(output_dir, "02_puma_lookup_coverage.csv")
)
readr::write_csv(
  puma_join_audit,
  file.path(output_dir, "02_block_puma_join.csv")
)
readr::write_csv(
  unmatched_tract_districts,
  file.path(output_dir, "02_unmatched_tract_districts.csv")
)

cat("\nBlock-to-PUMA matching audit:\n")
print(puma_join_audit, n = Inf, width = Inf)

cat("\nUnmatched tract-district combinations (first 20):\n")
print(head(unmatched_tract_districts, 20L), n = 20, width = Inf)

cat("\nBlock count and identifier checks passed.\n")
cat("Unmatched blocks retained:", sum(is.na(block_cd$PUMA5CE)), "\n")
cat("Tract-to-PUMA audits saved.\n")

# Section 4: reusable reader for 2020 PL population counts.
# Field positions verified against the Census Bureau's official R import:
# https://www2.census.gov/programs-surveys/decennial/rdo/about/2020-census-program/Phase3/SupportMaterials/2020PL_R_import_scripts.zip
# Member: R Versions/pl_geohd_2020_dar.r

# Positions counted from colnames(header), lines 113-123 of the R source above.
# That source defines 97 columns; positions here start at 1.
pl_fields <- c(
  FILEID = 1L, STUSAB = 2L, SUMLEV = 3L, GEOVAR = 4L,
  GEOCOMP = 5L, CHARITER = 6L, CIFSN = 7L, LOGRECNO = 8L,
  STATE = 13L, COUNTY = 15L, TRACT = 33L, BLOCK = 35L,
  POP100 = 91L
)
pl_names <- sprintf("field_%02d", seq_len(97L))
pl_names[pl_fields] <- names(pl_fields)

read_pl_population <- function(path, abbreviation, state_fips, sha256) {
  check(file.exists(path), paste("Missing population archive:", path))
  check(
    digest::digest(path, algo = "sha256", file = TRUE,
                   serialize = FALSE) == sha256,
    paste("Population archive checksum mismatch:", abbreviation)
  )

  member <- paste0(tolower(abbreviation), "geo2020.pl")
  check(
    sum(unzip(path, list = TRUE)$Name == member) == 1L,
    paste("Missing or duplicated geography member:", member)
  )

  temporary_dir <- tempfile("pl2020_")
  dir.create(temporary_dir)
  on.exit(unlink(temporary_dir, recursive = TRUE), add = TRUE)
  extracted <- unzip(path, files = member, exdir = temporary_dir)

  geo <- readr::read_delim(
    extracted,
    delim = "|",
    quote = "",
    col_names = pl_names,
    col_select = all_of(names(pl_fields)),
    col_types = readr::cols(.default = readr::col_character()),
    trim_ws = FALSE,
    skip_empty_rows = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )

  check(nrow(readr::problems(geo)) == 0L, "PL geography parsing problems.")
  # PLST and record-code definitions: PL technical documentation, Chapter 6.
  # https://www2.census.gov/programs-surveys/decennial/2020/technical-documentation/complete-tech-docs/summary-file/2020Census_PL94_171Redistricting_StatesTechDoc_English.pdf
  check(
    all(geo$FILEID == "PLST" &
        geo$STUSAB == toupper(abbreviation) &
        geo$STATE == state_fips),
    "Population file identification or state codes are unexpected."
  )

  # Source: PL technical documentation, Figure 4-2.
  # 040 = state; 750 = census block.
  geo <- geo |>
    filter(SUMLEV %in% c("040", "750"))

  # Expected flags for this input; field definitions: PL documentation, Ch. 6.
  check(
    all(geo$GEOVAR == "00" & geo$GEOCOMP == "00" &
        geo$CHARITER == "000" & geo$CIFSN == "00"),
    "Unexpected geographic variant, component, iteration or file segment."
  )
  # PL Ch. 6 specifies maximum width 7; exact seven digits is our format check.
  check(
    !anyNA(geo$LOGRECNO) &&
      all(grepl("^[0-9]{7}$", geo$LOGRECNO)) &&
      anyDuplicated(geo$LOGRECNO) == 0L,
    "Invalid or duplicated PL record identifiers."
  )
  # POP100 population definition: PL documentation, Ch. 6, endnote 24.
  check(
    !anyNA(geo$POP100) && all(grepl("^[0-9]+$", geo$POP100)),
    "Missing or invalid population counts."
  )

  geo$POP100 <- as.numeric(geo$POP100)
  check(
    all(is.finite(geo$POP100) & geo$POP100 >= 0 &
        geo$POP100 == floor(geo$POP100)),
    "Population counts must be finite, nonnegative integers."
  )


  # Segment 2 schema: Census official R import archive cited above,
  # member R Versions/pl_part2_2020_dar.r, lines 168-170.
  # Five linking fields, 71 P3 cells, 73 P4 cells and 3 H1 cells.
  adult_names <- c(
    "FILEID", "STUSAB", "CHARITER", "CIFSN", "LOGRECNO",
    paste0("P00", c(30001:30071, 40001:40073)),
    paste0("H00", 10001:10003)
  )
  adult_fields <- c(
    "FILEID", "STUSAB", "CHARITER", "CIFSN", "LOGRECNO", "P0030001"
  )
  adult_member <- paste0(tolower(abbreviation), "000022020.pl")
  check(
    sum(unzip(path, list = TRUE)$Name == adult_member) == 1L,
    paste("Missing or duplicated segment-2 member:", adult_member)
  )
  adult_file <- unzip(path, files = adult_member, exdir = temporary_dir)

  adult <- readr::read_delim(
    adult_file,
    delim = "|",
    quote = "",
    col_names = adult_names,
    col_select = all_of(adult_fields),
    col_types = readr::cols(.default = readr::col_character()),
    trim_ws = FALSE,
    skip_empty_rows = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )
  check(
    nrow(readr::problems(adult)) == 0L && !anyNA(adult),
    paste(abbreviation, "segment 2 has parsing problems or missing fields.")
  )

  # Linking fields and segment code: PL technical documentation, p. 6-32.
  check(
    all(adult$FILEID == "PLST" &
        adult$STUSAB == toupper(abbreviation) &
        adult$CHARITER == "000" &
        adult$CIFSN == "02"),
    paste(abbreviation, "has unexpected segment-2 identification fields.")
  )
  check(
    all(grepl("^[0-9]{7}$", adult$LOGRECNO)) &&
      anyDuplicated(adult$LOGRECNO) == 0L,
    paste(abbreviation, "has invalid or duplicated segment-2 record IDs.")
  )
  check(
    all(grepl("^[0-9]+$", adult$P0030001)),
    paste(abbreviation, "has missing or invalid adult counts.")
  )

  # P0030001 = total population aged 18+, including noncitizens.
  # Definition: https://api.census.gov/data/2020/dec/pl/groups/P3.html
  # Match by record identifier within this state, never by row order.
  adult_index <- match(geo$LOGRECNO, adult$LOGRECNO)
  check(
    !anyNA(adult_index),
    paste(abbreviation, "has state or block records without adult counts.")
  )
  geo$vap20 <- as.numeric(adult$P0030001[adult_index])
  check(
    all(is.finite(geo$vap20) &
        geo$vap20 >= 0 &
        geo$vap20 == floor(geo$vap20) &
        geo$vap20 <= geo$POP100),
    paste(abbreviation, "has adult counts outside 0 to total population.")
  )

  state_record <- filter(geo, SUMLEV == "040")
  blocks <- filter(geo, SUMLEV == "750")
  check(nrow(state_record) == 1L, "Expected exactly one state-total record.")
  check(nrow(blocks) > 0L, "No block population records found.")

  # Component widths: Census GEOID guidance cited in Section 1.
  component_widths <- c(STATE = 2L, COUNTY = 3L, TRACT = 6L, BLOCK = 4L)
  for (variable in names(component_widths)) {
    check(
      !anyNA(blocks[[variable]]) &&
        all(grepl(sprintf("^[0-9]{%d}$", component_widths[[variable]]),
                  blocks[[variable]])),
      paste("Invalid population-file identifiers in", variable)
    )
  }

  blocks <- blocks |>
    transmute(
      GEOID = paste0(STATE, COUNTY, TRACT, BLOCK),
      LOGRECNO,
      pop20 = POP100,
      vap20
    )

  check(anyDuplicated(blocks$GEOID) == 0L, "Duplicate population block IDs.")
  check(
    sum(blocks$pop20) == state_record$POP100[[1]],
    "Block populations do not sum to the state total."
  )

  check(
    sum(blocks$vap20) == state_record$vap20[[1]],
    "Block adult populations do not sum to the state adult total."
  )

  list(
    blocks = blocks,
    state_total = state_record$POP100[[1]],
    state_vap = state_record$vap20[[1]]
  )
}

# Section 5: match population records for every jurisdiction in the manifest.
# Source URLs, file sizes and SHA-256 fingerprints were recorded on download.
population_sources <- readr::read_csv(
  here::here("frame", "docs", "02_pl_2020_sources.csv"),
  col_types = readr::cols(.default = readr::col_character()),
  name_repair = "minimal",
  trim_ws = FALSE,
  show_col_types = FALSE,
  lazy = FALSE
)

check(
  identical(names(population_sources),
            c("STATEFP", "STUSAB", "state_name", "path", "url", "bytes", "sha256")),
  "Unexpected population-manifest columns."
)
check(
  nrow(readr::problems(population_sources)) == 0L &&
    !anyNA(population_sources),
  "Population manifest has parsing problems or incomplete entries."
)
check(
  nrow(population_sources) == length(target_states) &&
    anyDuplicated(population_sources$STATEFP) == 0L &&
    anyDuplicated(population_sources$STUSAB) == 0L &&
    setequal(population_sources$STATEFP, target_states),
  "Population manifest must cover exactly the 50 states plus DC."
)
check(
  all(grepl("^[A-Z]{2}$", population_sources$STUSAB)) &&
    all(grepl("^[0-9a-f]{64}$", population_sources$sha256)) &&
    all(grepl("^[1-9][0-9]*$", population_sources$bytes)),
  "Invalid abbreviation, checksum or file size in population manifest."
)
check(
  all(population_sources$path == paste0(
    "frame/data/input/pl_2020/",
    tolower(population_sources$STUSAB), "2020.pl.zip"
  )),
  "Unexpected population-file paths."
)

population_sources <- arrange(population_sources, STATEFP)
state_audits <- vector("list", nrow(population_sources))
unassigned_audits <- vector("list", nrow(population_sources))
block_cd$pop20 <- rep(NA_real_, nrow(block_cd))
block_cd$vap20 <- rep(NA_real_, nrow(block_cd))

for (i in seq_len(nrow(population_sources))) {
  entry <- population_sources[i, ]
  st <- entry$STATEFP
  abbreviation <- entry$STUSAB
  archive_path <- here::here(entry$path)

  cat(sprintf("\nReading population %d/%d: %s\n",
              i, nrow(population_sources), abbreviation))

  check(
    file.exists(archive_path) &&
      file.info(archive_path)$size == as.numeric(entry$bytes),
    paste(abbreviation, "archive is missing or has an unexpected size.")
  )

  population <- read_pl_population(
    path = archive_path,
    abbreviation = abbreviation,
    state_fips = st,
    sha256 = entry$sha256
  )

  positions <- which(block_cd$STATEFP == st)
  district_ids <- block_cd$GEOID[positions]
  population_ids <- population$blocks$GEOID

  missing_ids <- sum(!district_ids %in% population_ids)
  extra_ids <- sum(!population_ids %in% district_ids)
  check(
    missing_ids == 0L && extra_ids == 0L &&
      length(district_ids) == length(population_ids),
    sprintf(
      "%s block identifiers differ: %d missing population records; %d extra.",
      abbreviation, missing_ids, extra_ids
    )
  )

  index <- match(district_ids, population_ids)
  check(!anyNA(index), paste(abbreviation, "has unmatched population records."))
  values <- population$blocks$pop20[index]
  adult_values <- population$blocks$vap20[index]

  check(
    !anyNA(adult_values) &&
      sum(adult_values) == population$state_vap,
    paste(abbreviation, "adult population changed during matching.")
  )

  check(
    !anyNA(values) && sum(values) == population$state_total,
    paste(abbreviation, "population total changed during matching.")
  )

  # Assign by row position, preserving the national block order.
  block_cd$pop20[positions] <- values
  block_cd$vap20[positions] <- adult_values
  unassigned_positions <- positions[block_cd$CDFP[positions] == "ZZ"]

  state_audits[[i]] <- tibble(
    STATEFP = st,
    STUSAB = abbreviation,
    blocks = length(positions),
    state_population = population$state_total,
    matched_population = sum(values),
    state_vap = population$state_vap,
    matched_vap = sum(adult_values),
    unassigned_blocks = length(unassigned_positions),
    unassigned_population = sum(block_cd$pop20[unassigned_positions]),
    unassigned_vap = sum(block_cd$vap20[unassigned_positions])
  )

  # Retain all unassigned blocks for review, including any populated blocks.
  unassigned_audits[[i]] <- block_cd[
    unassigned_positions,
    c("GEOID", "STATEFP", "CDFP", "PUMA5CE", "pop20", "vap20")
  ]

  rm(population, values, adult_values, index)
}

population_audit <- bind_rows(state_audits)
unassigned_population <- bind_rows(unassigned_audits)

check(
  !anyNA(block_cd$pop20) &&
    all(is.finite(block_cd$pop20)) &&
    all(block_cd$pop20 >= 0),
  "Missing or invalid population values after nationwide matching."
)
check(
  sum(population_audit$blocks) == nrow(block_cd) &&
    sum(population_audit$state_population) == sum(block_cd$pop20) &&
    nrow(unassigned_population) == sum(block_cd$CDFP == "ZZ"),
  "National population audit does not reconcile."
)

check(
  !anyNA(block_cd$vap20) &&
    all(is.finite(block_cd$vap20) &
        block_cd$vap20 >= 0 &
        block_cd$vap20 == floor(block_cd$vap20) &
        block_cd$vap20 <= block_cd$pop20) &&
    sum(population_audit$state_vap) == sum(block_cd$vap20),
  "National adult-population audit does not reconcile."
)

readr::write_csv(
  population_audit,
  file.path(output_dir, "02_population_by_state.csv")
)
readr::write_csv(
  unassigned_population,
  file.path(output_dir, "02_unassigned_block_population.csv")
)

cat("\nNational population audit:\n")
print(population_audit, n = Inf, width = Inf)

cat("\nUnassigned-block population audit:\n")
unassigned_population |>
  group_by(STATEFP) |>
  summarise(
    blocks = n(),
    population = sum(pop20),
    populated_blocks = sum(pop20 > 0),
    .groups = "drop"
  ) |>
  print(n = Inf, width = Inf)

cat("\nJurisdictions processed:", nrow(population_audit), "\n")
cat("Matched blocks:", nrow(block_cd), "\n")
cat("Total population:", sum(block_cd$pop20), "\n")
cat("Unassigned blocks retained:", nrow(unassigned_population), "\n")
cat("National population matching passed.\n")
cat("Total adult population:", sum(block_cd$vap20), "\n")
cat("Unassigned adult population:",
    sum(block_cd$vap20[block_cd$CDFP == "ZZ"]), "\n")
cat("National adult-population matching passed.\n")

# Section 6: compare missing New York CVAP geography with Census Errata 148.
# Source: https://www.census.gov/programs-surveys/acs/technical-documentation/errata/148.html
# This section audits coverage; treatment is documented in frame/docs/02_cvap_allocation_decisions.md.

cvap_path <- here::here(
  "frame", "data", "input", "CVAP_2020-2024_ACS_csv_files.zip"
)
errata_path <- here::here(
  "frame", "data", "input",
  "Errata148_Suppressed_Geographies_for_Wyandanch.xlsx"
)

# SHA-256 fingerprints recorded from the downloaded source files.
cvap_sha256 <- "0c67665c62de843de7a3521a8110de05b4aa158cdc2db304015380615941056c"
errata_sha256 <- "26975c7dbbcd738b4546416d8753ec0a59e4957b3959fbab29ab7d96f7024369"

check(file.exists(cvap_path), "Missing CVAP archive.")
check(file.exists(errata_path), "Missing Census suppression list.")
check(
  digest::digest(file = cvap_path, algo = "sha256") == cvap_sha256,
  "CVAP archive fingerprint differs."
)
check(
  digest::digest(file = errata_path, algo = "sha256") == errata_sha256,
  "Census suppression-list fingerprint differs."
)

cvap_records <- readr::read_csv(
  unz(cvap_path, "BlockGr.csv"),
  col_types = readr::cols_only(
    geoid = readr::col_character(),
    lnnumber = readr::col_integer()
  ),
  progress = FALSE
)

check(
  nrow(readr::problems(cvap_records)) == 0L &&
    !anyNA(cvap_records) &&
    all(grepl("^1500000US[0-9]{12}$", cvap_records$geoid)),
  "Invalid CVAP geography or category identifiers."
)

# CVAP technical documentation: line 1 = Total.
cvap_total_records <- filter(cvap_records, lnnumber == 1L)
check(
  anyDuplicated(cvap_total_records$geoid) == 0L &&
    setequal(cvap_records$geoid, cvap_total_records$geoid),
  "Expected exactly one Total record per CVAP block group."
)

cvap_keys <- cvap_total_records |>
  transmute(bg_geoid = sub("^1500000US", "", geoid))

# Header is on row 3 in the pinned workbook, as inspected during review.
errata_sheet <- "2020-2024 ACS 5yr"
check(
  errata_sheet %in% readxl::excel_sheets(errata_path),
  "Expected 2020-2024 worksheet is absent."
)

errata <- readxl::read_excel(
  errata_path,
  sheet = errata_sheet,
  skip = 2,
  col_types = "text"
)
check(
  all(c("GEOID", "NAME") %in% names(errata)),
  "Unexpected suppression-list column names."
)

# Census identifiers: 1500000US = block group; state FIPS 36 = New York.
suppressed_bg <- errata |>
  filter(grepl("^1500000US36[0-9]{10}$", GEOID)) |>
  transmute(
    bg_geoid = sub("^1500000US", "", GEOID),
    geography_name = NAME
  )

check(
  nrow(suppressed_bg) > 0L &&
    anyDuplicated(suppressed_bg$bg_geoid) == 0L,
  "Suppression list has no New York block groups or contains duplicate IDs."
)

ny_block_groups <- block_cd |>
  filter(STATEFP == "36") |>
  transmute(bg_geoid = substr(GEOID, 1L, 12L)) |>
  distinct()

ny_missing <- anti_join(ny_block_groups, cvap_keys, by = "bg_geoid")

suppression_audit <- full_join(
  mutate(ny_missing, missing_from_cvap = TRUE),
  mutate(suppressed_bg, listed_in_errata = TRUE),
  by = "bg_geoid",
  relationship = "one-to-one"
) |>
  mutate(
    missing_from_cvap = coalesce(missing_from_cvap, FALSE),
    listed_in_errata = coalesce(listed_in_errata, FALSE)
  ) |>
  arrange(bg_geoid)

exact_match <- setequal(ny_missing$bg_geoid, suppressed_bg$bg_geoid)

cat("\nNew York suppression-list comparison:\n")
print(tibble::tibble(
  missing_block_groups = nrow(ny_missing),
  officially_listed_block_groups = nrow(suppressed_bg),
  exact_identifier_match = exact_match
))

cat("\nIdentifiers that do not agree between the two lists:\n")
suppression_audit |>
  filter(missing_from_cvap != listed_in_errata) |>
  print(n = Inf, width = Inf)

audit_path <- here::here(
  "frame", "data", "output", "02_cvap_ny_suppression_audit.csv"
)
dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(suppression_audit, audit_path)

note_path <- here::here(
  "frame", "docs", "02_cvap_suppression_audit.md"
)
dir.create(dirname(note_path), recursive = TRUE, showWarnings = FALSE)

writeLines(c(
  "# New York CVAP suppression: source audit",
  "",
  "Generated by Section 6 of `02_build_puma_cd_crosswalk.R`.",
  "This file records verification results, not the allocation decision.",
  "",
  "## Sources",
  "",
  "- Census ACS Errata 148:",
  "  https://www.census.gov/programs-surveys/acs/technical-documentation/errata/148.html",
  "- CVAP release:",
  "  https://www.census.gov/programs-surveys/decennial-census/about/voting-rights/cvap/2020-2024-CVAP.html",
  "- Suppression workbook: `Errata148_Suppressed_Geographies_for_Wyandanch.xlsx`.",
  paste0("- Worksheet: `", errata_sheet, "`."),
  paste0("- Workbook SHA-256: `", errata_sha256, "`."),
  paste0("- CVAP archive SHA-256: `", cvap_sha256, "`."),
  "",
  "## Verification",
  "",
  "Compare New York block-group IDs present in the pinned CD120 block",
  "file but absent from CVAP Total records with the official suppression list.",
  "Compare identifiers in both directions, not merely their counts.",
  "",
  paste0("- Missing block groups: ", nrow(ny_missing), "."),
  paste0("- Officially listed block groups: ", nrow(suppressed_bg), "."),
  paste0("- Exact identifier-set match: ", exact_match, "."),
  "- Row-level audit: `../data/output/02_cvap_ny_suppression_audit.csv`.",
  "",
  "## Allocation decision",
  "",
  "**New York treatment: structural allocation. Section 11 constructs and checks the weights.** See [decision record](02_cvap_allocation_decisions.md). This audit does not replace missing estimates with zero,",
  "impute values, remove PUMS records, or calculate allocation weights.",
  "",
  "Errata 148 states that PUMS files are unaffected. It also cautions",
  "against affected 2016-2020, 2017-2021 and 2018-2022 ACS estimates;",
  "an older-period replacement therefore requires separate justification.",
  "",
  "The selected treatment, alternatives considered, affected population,",
  "validation and limitations are recorded in the Script 02",
  "allocation decision record linked above."
), note_path)

cat("Audit saved:", audit_path, "\n")
cat("Source note saved:", note_path, "\n")

check(
  exact_match,
  "Missing New York identifiers differ from the official suppression list."
)

# Section 7: measure the geographic extent of New York CVAP suppression.
# Population measure: 2020 PL POP100, already validated above.
# These totals describe coverage; they do not estimate missing CVAP.

ny_impact_blocks <- block_cd |>
  filter(STATEFP == "36") |>
  mutate(
    bg_geoid = substr(GEOID, 1L, 12L),
    cvap_suppressed = bg_geoid %in% ny_missing$bg_geoid
  )

check(
  setequal(
    ny_impact_blocks$bg_geoid[ny_impact_blocks$cvap_suppressed],
    ny_missing$bg_geoid
  ),
  "Some suppressed block groups are absent from the New York block map."
)
check(
  !anyNA(ny_impact_blocks$PUMA5CE) &&
    !anyNA(ny_impact_blocks$CDFP) &&
    !any(ny_impact_blocks$CDFP == "ZZ"),
  "Missing PUMA or unassigned district in the New York impact audit."
)

affected_ny_pumas <- ny_impact_blocks |>
  filter(cvap_suppressed) |>
  distinct(STATEFP, PUMA5CE)

# Retain ALL blocks of each affected PUMA, including zero-population blocks.
# This establishes whether the whole PUMA lies within one assigned district.
affected_ny_blocks <- semi_join(
  ny_impact_blocks,
  affected_ny_pumas,
  by = c("STATEFP", "PUMA5CE")
)

ny_intersection_impact <- affected_ny_blocks |>
  group_by(STATEFP, PUMA5CE, CDFP) |>
  summarise(
    blocks = n(),
    population_2020 = sum(pop20),
    suppressed_bg_blocks = sum(cvap_suppressed),
    suppressed_bg_population_2020 = sum(pop20[cvap_suppressed]),
    .groups = "drop"
  ) |>
  arrange(STATEFP, PUMA5CE, CDFP)

check(
  sum(ny_intersection_impact$blocks) == nrow(affected_ny_blocks) &&
    sum(ny_intersection_impact$population_2020) ==
      sum(affected_ny_blocks$pop20) &&
    sum(ny_intersection_impact$suppressed_bg_population_2020) ==
      sum(ny_impact_blocks$pop20[ny_impact_blocks$cvap_suppressed]),
  "Population or block counts changed during impact aggregation."
)

ny_puma_impact <- ny_intersection_impact |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    districts = paste(sort(CDFP), collapse = ", "),
    district_count = n(),
    population_2020 = sum(population_2020),
    suppressed_bg_population_2020 = sum(suppressed_bg_population_2020),
    .groups = "drop"
  )

check(
  all(ny_puma_impact$population_2020 > 0),
  "An affected PUMA has no 2020 population."
)

ny_puma_impact <- ny_puma_impact |>
  mutate(
    suppressed_bg_population_pct =
      100 * suppressed_bg_population_2020 / population_2020,
    entirely_within_one_district = district_count == 1L
  )

cat("\nNew York suppression: geographic extent\n")
cat("Affected block groups:", nrow(ny_missing), "\n")
cat("Affected PUMAs:", nrow(ny_puma_impact), "\n")
cat(
  "2020 total population in suppressed block groups:",
  sum(ny_intersection_impact$suppressed_bg_population_2020), "\n"
)

cat("\nAll district intersections within affected PUMAs:\n")
print(ny_intersection_impact, n = Inf, width = Inf)

cat("\nSummary by affected PUMA:\n")
print(ny_puma_impact, n = Inf, width = Inf)

impact_path <- here::here(
  "frame", "data", "output", "02_cvap_ny_puma_district_impact.csv"
)
readr::write_csv(ny_intersection_impact, impact_path)

# Section 6 regenerates this source note on each full run.
# Add the verified geographic extent supporting the allocation decision.
impact_notes <- c(
  "",
  "## Geographic extent of suppression",
  "",
  "Population figures below are 2020 total population, including children",
  "and noncitizens. They measure geographic coverage, not missing CVAP",
  "or the size of an allocation error.",
  "",
  paste0("- Affected block groups: ", nrow(ny_missing), "."),
  paste0("- Affected PUMAs: ", nrow(ny_puma_impact), "."),
  paste0(
    "- Total population in affected block groups: ",
    sum(ny_intersection_impact$suppressed_bg_population_2020), "."
  ),
  "",
  sprintf(
    "- PUMA %s/%s: district(s) %s; %.0f of %.0f residents (%.2f%%) are in suppressed block groups.",
    ny_puma_impact$STATEFP,
    ny_puma_impact$PUMA5CE,
    ny_puma_impact$districts,
    ny_puma_impact$suppressed_bg_population_2020,
    ny_puma_impact$population_2020,
    ny_puma_impact$suppressed_bg_population_pct
  ),
  "",
  "District coverage uses every block of each affected PUMA, including",
  "zero-population blocks. A PUMA wholly within one assigned district",
  "can receive allocation weight 1 without estimating its missing CVAP.",
  "Its CVAP total would nevertheless remain unknown.",
  "",
  "Detailed audit: `../data/output/02_cvap_ny_puma_district_impact.csv`.",
  "",
  "**New York decision: apply the general containment rule in Section 11.** See [decision record](02_cvap_allocation_decisions.md)."
)

writeLines(c(readLines(note_path, warn = FALSE), impact_notes), note_path)

cat("Impact audit saved:", impact_path, "\n")
cat("Documentation updated:", note_path, "\n")

# Section 8: audit Connecticut identifier reconciliation candidates.
# Official relationship file:
# https://www2.census.gov/geo/docs/maps-data/data/rel2022/acs22_cousub22_blkgrp20_st09.txt

ct_lookup_path <- here::here(
  "frame", "data", "input", "acs22_cousub22_blkgrp20_st09.txt"
)

# SHA-256 recorded from our downloaded lookup.
ct_lookup_sha256 <- "06957a5e777dc96da4c678a79d27dce6617cfbd510c9611dbf7720c3cd16c5bd"

check(file.exists(ct_lookup_path), "Missing Connecticut relationship file.")
check(
  digest::digest(file = ct_lookup_path, algo = "sha256") == ct_lookup_sha256,
  "Connecticut relationship-file fingerprint differs."
)

ct_rel <- readr::read_delim(
  ct_lookup_path,
  delim = "|",
  col_types = readr::cols_only(
    GEOID_BLKGRP_20 = readr::col_character(),
    GEOID_COUSUB_22 = readr::col_character(),
    AREALAND_PART = readr::col_double(),
    AREAWATER_PART = readr::col_double()
  ),
  progress = FALSE
)

# Identifier widths and overlap-area definitions:
# https://www.census.gov/programs-surveys/geography/technical-documentation/records-layout/2022-connecticut-record-layout.html
check(
  nrow(readr::problems(ct_rel)) == 0L &&
    !anyNA(ct_rel) &&
    all(grepl("^09[0-9]{10}$", ct_rel$GEOID_BLKGRP_20)) &&
    all(grepl("^09[0-9]{8}$", ct_rel$GEOID_COUSUB_22)) &&
    all(is.finite(ct_rel$AREALAND_PART)) &&
    all(is.finite(ct_rel$AREAWATER_PART)) &&
    all(ct_rel$AREALAND_PART >= 0) &&
    all(ct_rel$AREAWATER_PART >= 0),
  "Invalid Connecticut identifiers or overlap areas."
)

# First five subdivision-ID characters identify state plus county-equivalent.
# Collapse multiple town relationships within the same planning region.
ct_pairs <- ct_rel |>
  mutate(
    bg_2020 = GEOID_BLKGRP_20,
    planning_region = substr(GEOID_COUSUB_22, 1L, 5L)
  ) |>
  group_by(bg_2020, planning_region) |>
  summarise(
    source_rows = n(),
    land_m2 = sum(AREALAND_PART),
    water_m2 = sum(AREAWATER_PART),
    .groups = "drop"
  )

ct_bg_population <- block_cd |>
  filter(STATEFP == "09") |>
  mutate(bg_2020 = substr(GEOID, 1L, 12L)) |>
  group_by(bg_2020) |>
  summarise(population_2020 = sum(pop20), .groups = "drop")

check(
  setequal(ct_pairs$bg_2020, ct_bg_population$bg_2020),
  "Lookup and district file contain different Connecticut block-group IDs."
)

ct_cvap_source <- readr::read_csv(
  unz(cvap_path, "BlockGr.csv"),
  col_types = readr::cols_only(
    geoid = readr::col_character(),
    lnnumber = readr::col_integer(),
    cvap_est = readr::col_double()
  ),
  progress = FALSE
)
check(
  nrow(readr::problems(ct_cvap_source)) == 0L,
  "CVAP parsing problems."
)

ct_cvap <- ct_cvap_source |>
  filter(lnnumber == 1L, startsWith(geoid, "1500000US09")) |>
  transmute(
    bg_cvap = sub("^1500000US", "", geoid),
    cvap_est
  )

check(
  nrow(ct_cvap) > 0L &&
    anyDuplicated(ct_cvap$bg_cvap) == 0L &&
    all(is.finite(ct_cvap$cvap_est)),
  "Invalid Connecticut CVAP Total records."
)
check(
  setequal(
    ct_pairs$planning_region,
    substr(ct_cvap$bg_cvap, 1L, 5L)
  ),
  "Lookup and CVAP file contain different planning-region codes."
)

ct_cardinality <- ct_pairs |>
  group_by(bg_2020) |>
  summarise(
    regions = n(),
    regions_with_overlap = sum(land_m2 + water_m2 > 0),
    regions_with_land = sum(land_m2 > 0),
    .groups = "drop"
  )

# Construct candidate identifiers for the reviewed checks below:
# replace the county prefix while retaining the tract and block-group suffix.
ct_candidate_audit <- ct_pairs |>
  mutate(
    bg_cvap = paste0(planning_region, substr(bg_2020, 6L, 12L))
  ) |>
  left_join(
    ct_bg_population, by = "bg_2020",
    relationship = "many-to-one"
  ) |>
  left_join(
    ct_cvap, by = "bg_cvap",
    relationship = "many-to-one"
  ) |>
  mutate(present_in_cvap = bg_cvap %in% ct_cvap$bg_cvap) |>
  arrange(bg_2020, bg_cvap)

ct_collisions <- ct_candidate_audit |>
  group_by(bg_cvap) |>
  summarise(old_block_groups = n_distinct(bg_2020), .groups = "drop") |>
  filter(old_block_groups > 1L)

ct_missing_candidates <- filter(ct_candidate_audit, !present_in_cvap)
ct_unmatched_cvap <- anti_join(
  ct_cvap, ct_candidate_audit, by = "bg_cvap"
)

cat("\nConnecticut identifier audit\n")
cat("Original block groups:", nrow(ct_bg_population), "\n")
cat("Distinct old-block-group / planning-region pairs:", nrow(ct_pairs), "\n")
cat("CVAP block groups:", nrow(ct_cvap), "\n")

cat("\nRelationship counts per original block group:\n")
ct_cardinality |>
  count(regions, regions_with_overlap, regions_with_land) |>
  print(n = Inf, width = Inf)

cat("\nBlock groups without exactly one region with positive overlap:\n")
ct_candidate_audit |>
  semi_join(
    filter(ct_cardinality, regions != 1L | regions_with_overlap != 1L),
    by = "bg_2020"
  ) |>
  print(n = Inf, width = Inf)

cat("\nPairs with zero land and water overlap:\n")
ct_candidate_audit |>
  filter(land_m2 + water_m2 == 0) |>
  print(n = Inf, width = Inf)

cat("\nCandidate IDs absent from CVAP:\n")
print(ct_missing_candidates, n = Inf, width = Inf)

cat("\nCVAP IDs absent from the candidates:\n")
print(ct_unmatched_cvap, n = Inf, width = Inf)

cat("\nCandidate IDs shared by multiple original block groups:\n")
print(ct_collisions, n = Inf, width = Inf)

ct_audit_path <- here::here(
  "frame", "data", "output", "02_ct_cvap_identifier_audit.csv"
)
readr::write_csv(ct_candidate_audit, ct_audit_path)

ct_note_path <- here::here(
  "frame", "docs", "02_ct_cvap_identifier_audit.md"
)
writeLines(c(
  "# Connecticut CVAP identifier audit",
  "",
  "Generated by Section 8 of `02_build_puma_cd_crosswalk.R`.",
  "",
  "## Source and method",
  "",
  "Official lookup:",
  "https://www2.census.gov/geo/docs/maps-data/data/rel2022/acs22_cousub22_blkgrp20_st09.txt",
  paste0("SHA-256: `", ct_lookup_sha256, "`."),
  "",
  "The lookup connects original block groups to newer county subdivisions.",
  "It is not itself a direct old-to-new block-group crosswalk.",
  "",
  "Repeated old-block-group/planning-region pairs are collapsed.",
  "Candidate IDs combine the planning-region prefix with the original",
  "tract and block-group suffix. Candidates are compared with the actual",
  "2020–2024 CVAP identifiers in both directions.",
  "",
  "Land and water overlaps are both retained. Exceptional relationships",
  "are reported alongside 2020 total population and published CVAP estimates.",
  "",
  "## Results",
  "",
  paste0("- Original block groups: ", nrow(ct_bg_population), "."),
  paste0("- Relationship pairs: ", nrow(ct_pairs), "."),
  paste0("- CVAP block groups: ", nrow(ct_cvap), "."),
  paste0("- Candidates absent from CVAP: ", nrow(ct_missing_candidates), "."),
  paste0("- CVAP IDs absent from candidates: ", nrow(ct_unmatched_cvap), "."),
  paste0("- Target-ID collisions: ", nrow(ct_collisions), "."),
  "",
  "Detailed audit: `../data/output/02_ct_cvap_identifier_audit.csv`.",
  "Selected treatments: [CVAP allocation decisions](02_cvap_allocation_decisions.md).",
  "",
  "Conversion choices are documented in the decision record.",
  "Later sections use these reviewed relationships to prepare allocation inputs."
), ct_note_path)

cat("Identifier audit saved:", ct_audit_path, "\n")
cat("Source note saved:", ct_note_path, "\n")

# Reviewed Connecticut exceptions; see docs/02_cvap_allocation_decisions.md.
# Fingerprint of the saved official 2024 catalogue response.
ct_catalog_path <- here::here(
  "frame", "data", "input", "ct_bg_2024_identifier_check.json"
)
ct_catalog_sha256 <- "a01ecdfb5bfe0fe4119a3aab71007408f458ebc5c0c580a04402fe102a51bb87"
ct_catalog_query_url <- "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/10/query?where=GEOID+IN+%28%27091403431011%27%2C%27091703431011%27%29&outFields=GEOID%2CNAME%2CSTATE%2CCOUNTY%2CTRACT%2CBLKGRP%2CAREALAND%2CAREAWATER&returnGeometry=false&orderByFields=GEOID&f=json"

check(file.exists(ct_catalog_path), "Missing 2024 Connecticut catalogue response.")
check(
  digest::digest(file = ct_catalog_path, algo = "sha256") == ct_catalog_sha256,
  "2024 Connecticut catalogue response fingerprint differs."
)

ct_catalog <- jsonlite::fromJSON(
  ct_catalog_path, simplifyVector = FALSE
)
check(
  is.null(ct_catalog$error) &&
    !isTRUE(ct_catalog$exceededTransferLimit) &&
    length(ct_catalog$features) == 1L,
  "Invalid or incomplete 2024 catalogue response."
)

# Expected identifier and areas come from the reviewed catalogue response.
ct_catalog_attributes <- ct_catalog$features[[1]]$attributes
check(
  identical(ct_catalog_attributes$GEOID, "091403431011") &&
    isTRUE(ct_catalog_attributes$AREALAND == 3606413) &&
    isTRUE(ct_catalog_attributes$AREAWATER == 0),
  "2024 catalogue geography differs from the reviewed case."
)

check(
  nrow(ct_unmatched_cvap) == 0L,
  "Some Connecticut CVAP identifiers have no candidate source geography."
)

# Exact exception identities are from the saved relationship/CVAP audits.
ct_pair_keys <- function(x) paste(x$bg_2020, x$bg_cvap, sep = "->")

check(
  identical(
    sort(ct_pair_keys(ct_missing_candidates)),
    "090093431011->091703431011"
  ),
  "An unreviewed Connecticut candidate is absent from CVAP."
)

ct_main_candidate <- ct_candidate_audit |>
  filter(bg_2020 == "090093431011", bg_cvap == "091403431011")

check(
  nrow(ct_main_candidate) == 1L &&
    isTRUE(ct_main_candidate$present_in_cvap[[1]]) &&
    ct_main_candidate$land_m2[[1]] == ct_catalog_attributes$AREALAND &&
    ct_missing_candidates$land_m2[[1]] == 160 &&
    ct_missing_candidates$water_m2[[1]] == 0,
  "The reviewed small-overlap case has changed."
)

ct_multiple_region_rows <- ct_candidate_audit |>
  semi_join(
    filter(ct_cardinality, regions > 1L),
    by = "bg_2020"
  )

ct_expected_multiple_pairs <- c(
  "090019900000->091209900000",
  "090019900000->091909900000",
  "090093431011->091403431011",
  "090093431011->091703431011",
  "090119901000->091309901000",
  "090119901000->091809901000"
)

check(
  identical(
    sort(ct_pair_keys(ct_multiple_region_rows)),
    sort(ct_expected_multiple_pairs)
  ),
  "An unreviewed multi-region Connecticut relationship was found."
)

ct_collision_rows <- ct_candidate_audit |>
  semi_join(ct_collisions, by = "bg_cvap")

check(
  identical(
    sort(ct_pair_keys(ct_collision_rows)),
    c(
      "090079901000->091309901000",
      "090119901000->091309901000"
    )
  ) &&
    all(ct_collision_rows$land_m2 == 0) &&
    all(ct_collision_rows$population_2020 == 0),
  "An unreviewed Connecticut target-ID collision was found."
)

writeLines(c(
  readLines(ct_note_path, warn = FALSE),
  "",
  "## Reviewed exception checks",
  "",
  "The raw absent-candidate and collision counts are retained above.",
  "The script verified that their identities match the documented cases,",
  "and that no additional multi-region relationships were introduced.",
  "",
  paste0("2024 catalogue response SHA-256: `", ct_catalog_sha256, "`."),
  paste0("Exact source query: ", ct_catalog_query_url),
  "",
  "Known candidate exceptions are classified under documented rules.",
  "This note records identifier checks; Sections 9-11 prepare and validate the final allocation."
), ct_note_path)

cat("\nReviewed Connecticut identifier exception checks passed.\n")
cat("Catalogue SHA256:", ct_catalog_sha256, "\n")
cat("Continuing with national allocation inputs.\n")

# Section 9: prepare national CVAP allocation inputs.
# First preserve exact totals on the original 2020 block geography.
# A block-group ID is the first 12 block-GEOID characters:
# state 2 + county 3 + tract 6 + block-group digit 1.
bg_2020_cells <- block_cd |>
  mutate(bg_2020 = substr(GEOID, 1L, 12L)) |>
  group_by(STATEFP, bg_2020, PUMA5CE, CDFP) |>
  summarise(
    blocks = n(),
    pop20 = sum(pop20),
    vap20 = sum(vap20),
    .groups = "drop"
  )

check(
  !anyNA(bg_2020_cells) &&
    sum(bg_2020_cells$blocks) == nrow(block_cd) &&
    sum(bg_2020_cells$pop20) == sum(block_cd$pop20) &&
    sum(bg_2020_cells$vap20) == sum(block_cd$vap20),
  "Original block-group aggregation changed block or population totals."
)

bg_2020_totals <- bg_2020_cells |>
  group_by(STATEFP, bg_2020) |>
  summarise(
    pop20 = sum(pop20),
    vap20 = sum(vap20),
    .groups = "drop"
  )

# Apply the reviewed CT identifier rules.
# Section 8 verifies the exact absent candidate before we exclude its link.
# No original block or person record is removed.
ct_links <- ct_candidate_audit |>
  filter(present_in_cvap) |>
  transmute(STATEFP = "09", bg_2020, bg_cvap)

ct_source_counts <- count(ct_links, bg_2020, name = "targets")
ct_target_counts <- count(ct_links, bg_cvap, name = "sources")

ct_multiple_targets <- filter(ct_source_counts, targets > 1L)
ct_multiple_sources <- filter(ct_target_counts, sources > 1L)

# Ambiguous water relationships describe possible source coverage,
# not an exact partition of blocks between newer block groups.
ct_water_support <- ct_candidate_audit |>
  filter(
    present_in_cvap,
    bg_2020 %in% ct_multiple_targets$bg_2020 |
      bg_cvap %in% ct_multiple_sources$bg_cvap
  )

check(
  all(ct_water_support$land_m2 == 0) &&
    all(ct_water_support$population_2020 == 0),
  "Ambiguous CT correspondence includes land or recorded population."
)

ct_population_links <- bg_2020_totals |>
  filter(STATEFP == "09") |>
  left_join(
    ct_source_counts,
    by = "bg_2020",
    relationship = "one-to-one"
  )

check(
  !anyNA(ct_population_links$targets) &&
    all(ct_population_links$targets[ct_population_links$pop20 > 0] == 1L),
  "A populated CT source block group lacks one reviewed destination."
)

ct_links <- ct_links |>
  mutate(
    coverage_only =
      bg_2020 %in% ct_multiple_targets$bg_2020 |
      bg_cvap %in% ct_multiple_sources$bg_cvap
  )

bg_links <- bind_rows(
  bg_2020_totals |>
    filter(STATEFP != "09") |>
    transmute(
      STATEFP, bg_2020,
      bg_cvap = bg_2020,
      coverage_only = FALSE
    ),
  ct_links
)

check(
  !anyNA(bg_links) &&
    anyDuplicated(select(bg_links, STATEFP, bg_2020, bg_cvap)) == 0L &&
    setequal(bg_links$bg_2020, bg_2020_totals$bg_2020),
  "Block-group correspondence is incomplete or duplicated."
)

# Multiple coverage links are intentional only for reviewed water cases.
# CVAP estimates are deliberately absent from this intersection table.
bg_target_cells <- bg_2020_cells |>
  left_join(
    bg_links,
    by = c("STATEFP", "bg_2020"),
    relationship = "many-to-many"
  ) |>
  group_by(STATEFP, bg_cvap, PUMA5CE, CDFP) |>
  summarise(
    source_block_links = sum(blocks),
    pop20 = sum(pop20),
    vap20 = sum(vap20),
    coverage_only = any(coverage_only),
    .groups = "drop"
  )

check(
  !anyNA(bg_target_cells) &&
    sum(bg_target_cells$pop20) == sum(block_cd$pop20) &&
    sum(bg_target_cells$vap20) == sum(block_cd$vap20),
  "Identifier reconciliation changed recorded population totals."
)

# source_block_links can repeat zero-population water blocks across targets.
# Do not interpret their national sum as a unique-block count.

# Reuse the national CVAP table already read in Section 8.
# Keep exactly one published Total estimate per target block group.
cvap_totals <- ct_cvap_source |>
  filter(lnnumber == 1L) |>
  transmute(
    bg_cvap = sub("^1500000US", "", geoid),
    STATEFP = substr(bg_cvap, 1L, 2L),
    cvap_est
  ) |>
  filter(STATEFP %in% target_states)

check(
  !anyNA(cvap_totals) &&
    anyDuplicated(cvap_totals$bg_cvap) == 0L &&
    setequal(cvap_totals$STATEFP, target_states) &&
    all(is.finite(cvap_totals$cvap_est) & cvap_totals$cvap_est >= 0),
  "Invalid national CVAP Total estimates."
)

# Keep summary names distinct from input columns until all sums are computed.
bg_coverage <- bg_target_cells |>
  group_by(STATEFP, bg_cvap) |>
  summarise(
    intersections = n(),
    pumas = n_distinct(PUMA5CE),
    has_unassigned = any(CDFP == "ZZ"),
    wholly_unassigned = all(CDFP == "ZZ"),
    pop20_total = sum(pop20),
    vap20_total = sum(vap20),
    unassigned_vap20 = sum(vap20[CDFP == "ZZ"]),
    coverage_only = any(coverage_only),
    .groups = "drop"
  ) |>
  rename(
    pop20 = pop20_total,
    vap20 = vap20_total
  )

check(
  !anyNA(bg_coverage) &&
    all(is.finite(bg_coverage$vap20)) &&
    all(is.finite(bg_coverage$unassigned_vap20)) &&
    all(bg_coverage$vap20 >= 0 &
        bg_coverage$vap20 <= bg_coverage$pop20) &&
    all(bg_coverage$unassigned_vap20 >= 0 &
        bg_coverage$unassigned_vap20 <= bg_coverage$vap20) &&
    sum(bg_coverage$vap20) == sum(bg_target_cells$vap20) &&
    sum(bg_coverage$unassigned_vap20) ==
      sum(bg_target_cells$vap20[bg_target_cells$CDFP == "ZZ"]),
  "Block-group adult totals or unassigned subtotals do not reconcile."
)

allocation_readiness <- full_join(
  bg_coverage,
  cvap_totals,
  by = c("STATEFP", "bg_cvap"),
  relationship = "one-to-one"
) |>
  mutate(
    allocation_case = case_when(
      is.na(intersections) ~ "missing_geography",
      is.na(cvap_est) ~ "missing_cvap",
      cvap_est == 0 ~ "zero_cvap",
      wholly_unassigned ~ "exclude_unassigned",
      intersections == 1L & !has_unassigned ~ "direct_containment",
      vap20 > 0 & unassigned_vap20 == 0 ~ "adult_proportions",
      TRUE ~ "review_required"
    )
  ) |>
  arrange(STATEFP, bg_cvap)

# Reviewed structural-zero overrides: decision 2026-10-30.
# Project assumption, restricted to the five cases documented in:
# frame/docs/02_cvap_allocation_decisions.md
# Expected estimates and locations come from the reviewed source audits.
structural_zero_rules <- tibble::tribble(
  ~bg_cvap,       ~expected_cvap, ~expected_puma, ~expected_districts,
  "060379800031", 5,              "03772",        "23,27",
  "120219900000", 4,              "02102",        "19,22",
  "120719800001", 5,              "07105",        "17,19",
  "120869806001", 5,              "08623",        "27,28",
  "120999900000", 5,              "09902",        "21,23,25"
)

zero_locations <- bg_target_cells |>
  semi_join(structural_zero_rules, by = "bg_cvap") |>
  group_by(bg_cvap) |>
  summarise(
    observed_pumas = paste(sort(unique(PUMA5CE)), collapse = ","),
    observed_districts = paste(sort(unique(CDFP)), collapse = ","),
    .groups = "drop"
  )

reviewed_zero_inputs <- structural_zero_rules |>
  left_join(
    allocation_readiness,
    by = "bg_cvap",
    relationship = "one-to-one"
  ) |>
  left_join(
    zero_locations,
    by = "bg_cvap",
    relationship = "one-to-one"
  )

check(
  nrow(reviewed_zero_inputs) == 5L &&
    !anyNA(reviewed_zero_inputs) &&
    all(reviewed_zero_inputs$cvap_est ==
          reviewed_zero_inputs$expected_cvap) &&
    all(reviewed_zero_inputs$observed_pumas ==
          reviewed_zero_inputs$expected_puma) &&
    all(reviewed_zero_inputs$observed_districts ==
          reviewed_zero_inputs$expected_districts) &&
    all(reviewed_zero_inputs$pop20 == 0 &
          reviewed_zero_inputs$vap20 == 0 &
          reviewed_zero_inputs$pumas == 1L &
          reviewed_zero_inputs$intersections > 1L &
          !reviewed_zero_inputs$has_unassigned &
          !reviewed_zero_inputs$coverage_only) &&
    all(reviewed_zero_inputs$allocation_case == "review_required"),
  "The five structural-zero cases no longer match their reviewed evidence."
)

published_before_override <- allocation_readiness$cvap_est
cases_before_override <- allocation_readiness$allocation_case

allocation_readiness <- allocation_readiness |>
  mutate(
    structural_zero_override = bg_cvap %in% structural_zero_rules$bg_cvap,
    cvap_structural_zero_adjustment = if_else(
      structural_zero_override, cvap_est, 0
    ),
    # Keep the previously selected CT geographic exclusion separate.
    cvap_geographic_exclusion = if_else(
      allocation_case == "exclude_unassigned", cvap_est, 0
    ),
    cvap_for_allocation =
      cvap_est -
      cvap_structural_zero_adjustment -
      cvap_geographic_exclusion,
    allocation_case = if_else(
      structural_zero_override,
      "structural_zero_reviewed",
      allocation_case
    )
  )

observed_cvap <- allocation_readiness |>
  filter(!is.na(cvap_est))

check(
  identical(allocation_readiness$cvap_est, published_before_override) &&
    identical(
      is.na(allocation_readiness$cvap_for_allocation),
      is.na(allocation_readiness$cvap_est)
    ) &&
    all(
      allocation_readiness$allocation_case[
        !allocation_readiness$structural_zero_override
      ] ==
        cases_before_override[
          !allocation_readiness$structural_zero_override
        ]
    ) &&
    all(is.finite(observed_cvap$cvap_for_allocation) &
          observed_cvap$cvap_for_allocation >= 0) &&
    all(
      observed_cvap$cvap_est ==
        observed_cvap$cvap_for_allocation +
        observed_cvap$cvap_structural_zero_adjustment +
        observed_cvap$cvap_geographic_exclusion
    ) &&
    sum(observed_cvap$cvap_structural_zero_adjustment) == 24 &&
    sum(observed_cvap$cvap_geographic_exclusion) == 5 &&
    setequal(
      observed_cvap$bg_cvap[
        observed_cvap$cvap_geographic_exclusion > 0
      ],
      "091309901000"
    ),
  "Published CVAP, allocation inputs and adjustment amounts do not reconcile."
)

structural_zero_audit <- allocation_readiness |>
  filter(structural_zero_override) |>
  left_join(
    zero_locations,
    by = "bg_cvap",
    relationship = "one-to-one"
  )

readr::write_csv(
  structural_zero_audit,
  file.path(output_dir, "02_cvap_structural_zero_audit.csv")
)

cat("\nStructural-zero override audit:\n")
structural_zero_audit |>
  select(
    bg_cvap, observed_pumas, observed_districts,
    cvap_est, cvap_for_allocation, cvap_structural_zero_adjustment
  ) |>
  print(n = Inf, width = Inf)

# Subsequent allocation calculations must use cvap_for_allocation.
# cvap_est remains the published source value, including missing values.

# Write the evidence before stopping on any newly discovered problem.
readr::write_csv(
  bg_links,
  file.path(output_dir, "02_bg_identifier_links.csv")
)
readr::write_csv(
  bg_target_cells,
  file.path(output_dir, "02_bg_district_support.csv")
)
readr::write_csv(
  allocation_readiness,
  file.path(output_dir, "02_cvap_allocation_readiness.csv")
)

case_summary <- allocation_readiness |>
  group_by(allocation_case) |>
  summarise(
    block_groups = n(),
    missing_estimates = sum(is.na(cvap_est)),
    published_cvap = if (all(is.na(cvap_est))) {
      NA_real_
    } else {
      sum(cvap_est, na.rm = TRUE)
    },
    allocation_cvap = if (all(is.na(cvap_for_allocation))) {
      NA_real_
    } else {
      sum(cvap_for_allocation, na.rm = TRUE)
    },
    structural_zero_adjustment = sum(cvap_structural_zero_adjustment),
    geographic_exclusion = sum(cvap_geographic_exclusion),
    .groups = "drop"
  )

readr::write_csv(
  case_summary,
  file.path(output_dir, "02_cvap_allocation_case_summary.csv")
)

cat("\nNational CVAP allocation cases:\n")
print(case_summary, n = Inf, width = Inf)

cat("\nPositive CVAP with zero recorded adult population (first 20):\n")
allocation_readiness |>
  filter(cvap_est > 0, vap20 == 0) |>
  head(20L) |>
  print(n = 20, width = Inf)

review_cases <- allocation_readiness |>
  filter(allocation_case %in% c("missing_geography", "review_required"))

cat("\nCases requiring further review (first 20):\n")
print(head(review_cases, 20L), n = 20, width = Inf)

# Missing values must remain exactly the previously verified NY omissions.
missing_cvap_ids <- allocation_readiness$bg_cvap[
  allocation_readiness$allocation_case == "missing_cvap"
]
check(
  setequal(missing_cvap_ids, ny_missing$bg_geoid),
  "Missing CVAP does not match the reviewed New York suppression list."
)

# Reproduce the location conclusions previously checked separately for CT.
# These identifiers and expected locations come from the decision record.
ct_land_support <- filter(
  bg_target_cells, bg_cvap == "091902114003"
)
ct_water_locations <- filter(
  bg_target_cells, bg_cvap == "091309901000"
)

check(
  nrow(ct_land_support) == 1L &&
    ct_land_support$PUMA5CE[[1]] == "20904" &&
    ct_land_support$CDFP[[1]] == "05",
  "The reviewed CT land case is no longer contained in PUMA 20904 / CT-05."
)
check(
  nrow(ct_water_locations) > 0L &&
    all(ct_water_locations$CDFP == "ZZ") &&
    setequal(ct_water_locations$PUMA5CE, c("20401", "20500")),
  "The reviewed CT water case has unexpected district or PUMA coverage."
)

check(
  nrow(review_cases) == 0L,
  paste(
    "Further allocation decisions are needed.",
    "See frame/data/output/02_cvap_allocation_readiness.csv."
  )
)

cat("\nNational allocation-input checks passed.\n")
cat("Continuing with block-group CVAP contributions.\n")

# Section 10: calculate block-group CVAP contributions.
# Method and assumptions: frame/docs/02_build_puma_cd_crosswalk.md.
# Sum block adult counts within each PUMA-district portion before splitting
# CVAP. This gives the same contributions as allocating to blocks first.

# Numerical tolerance for floating-point arithmetic, not statistical error.
cvap_close <- function(actual, expected) {
  is.finite(actual) & is.finite(expected) &
    abs(actual - expected) <= 1e-8 + 1e-12 * abs(expected)
}

# A total containing unknown contributions must remain unknown.
sum_cvap_or_na <- function(x) {
  if (anyNA(x)) NA_real_ else sum(x)
}

contribution_methods <- c(
  "adult_proportions", "direct_containment",
  "exclude_unassigned", "missing_cvap",
  "structural_zero_reviewed", "zero_cvap"
)

contribution_work <- bg_target_cells |>
  left_join(
    allocation_readiness |>
      select(
        STATEFP, bg_cvap, allocation_case,
        bg_allocation_cvap = cvap_for_allocation,
        bg_adults_2020 = vap20
      ),
    by = c("STATEFP", "bg_cvap"),
    relationship = "many-to-one"
  )

check(
  nrow(contribution_work) == nrow(bg_target_cells) &&
    anyDuplicated(select(
      contribution_work, STATEFP, bg_cvap, PUMA5CE, CDFP
    )) == 0L &&
    !anyNA(contribution_work$allocation_case) &&
    all(contribution_work$allocation_case %in% contribution_methods) &&
    !anyNA(contribution_work$bg_adults_2020),
  "Contribution inputs have missing methods, duplicated cells or unmatched rows."
)

zero_case <- contribution_work$allocation_case %in% c(
  "zero_cvap", "structural_zero_reviewed", "exclude_unassigned"
)
direct_case <- contribution_work$allocation_case == "direct_containment"
adult_case <- contribution_work$allocation_case == "adult_proportions"
missing_case <- contribution_work$allocation_case == "missing_cvap"

direct_counts <- contribution_work |>
  filter(allocation_case == "direct_containment") |>
  count(STATEFP, bg_cvap, name = "target_cells")

check(
  all(direct_counts$target_cells == 1L) &&
    all(contribution_work$CDFP[direct_case] != "ZZ") &&
    all(contribution_work$bg_allocation_cvap[zero_case] == 0) &&
    all(contribution_work$bg_adults_2020[adult_case] > 0),
  "Direct allocation, zero allocation or adult denominators are inconsistent."
)

# Use indexed assignments so division is evaluated only for valid denominators.
contribution_work$cvap_contribution <- NA_real_
contribution_work$cvap_contribution[zero_case] <- 0

contribution_work$cvap_contribution[direct_case] <-
  contribution_work$bg_allocation_cvap[direct_case]

contribution_work$cvap_contribution[adult_case] <-
  contribution_work$bg_allocation_cvap[adult_case] *
  contribution_work$vap20[adult_case] /
  contribution_work$bg_adults_2020[adult_case]

# Missing CVAP remains NA, including when the geographic destination is known.
# Do not export repeated block-group CVAP totals in the intersection table.
bg_cvap_contributions <- contribution_work |>
  select(
    STATEFP, bg_cvap, PUMA5CE, CDFP,
    source_block_links, pop20, vap20, coverage_only,
    allocation_case, cvap_contribution
  )

known_cell <- !is.na(bg_cvap_contributions$cvap_contribution)

check(
  identical(
    is.na(bg_cvap_contributions$cvap_contribution),
    missing_case
  ) &&
    setequal(
      bg_cvap_contributions$bg_cvap[missing_case],
      ny_missing$bg_geoid
    ) &&
    all(
      is.finite(bg_cvap_contributions$cvap_contribution[known_cell]) &
        bg_cvap_contributions$cvap_contribution[known_cell] >= 0
    ) &&
    all(
      bg_cvap_contributions$cvap_contribution[
        bg_cvap_contributions$CDFP == "ZZ"
      ] == 0
    ),
  "Contributions contain unexpected missing, invalid or unassigned amounts."
)

# Reconcile once per block group, never by summing repeated source estimates.
bg_contribution_audit <- bg_cvap_contributions |>
  group_by(STATEFP, bg_cvap) |>
  summarise(
    cell_rows = n(),
    cell_adults = sum(vap20),
    unknown_cells = sum(is.na(cvap_contribution)),
    contributed_cvap = sum_cvap_or_na(cvap_contribution),
    .groups = "drop"
  ) |>
  left_join(
    allocation_readiness,
    by = c("STATEFP", "bg_cvap"),
    relationship = "one-to-one"
  ) |>
  mutate(
    cvap_difference = contributed_cvap - cvap_for_allocation,
    allocation_check_passed = if_else(
      is.na(cvap_for_allocation),
      is.na(contributed_cvap) & unknown_cells == cell_rows,
      unknown_cells == 0L &
        cvap_close(contributed_cvap, cvap_for_allocation)
    )
  )

# Save detailed evidence before checking the reconciliation results.
readr::write_csv(
  bg_cvap_contributions,
  file.path(output_dir, "02_bg_cvap_contributions.csv")
)
readr::write_csv(
  bg_contribution_audit,
  file.path(output_dir, "02_bg_cvap_conservation.csv")
)

check(
  nrow(bg_contribution_audit) == nrow(allocation_readiness) &&
    setequal(bg_contribution_audit$bg_cvap, allocation_readiness$bg_cvap) &&
    all(bg_contribution_audit$cell_rows ==
          bg_contribution_audit$intersections) &&
    all(bg_contribution_audit$cell_adults ==
          bg_contribution_audit$vap20) &&
    all(bg_contribution_audit$allocation_check_passed),
  "Block-group contribution checks failed; inspect 02_bg_cvap_conservation.csv."
)

# These sums cover observed estimates only; missing New York CVAP is unknown.
expected_observed_cvap <- sum(
  allocation_readiness$cvap_for_allocation, na.rm = TRUE
)
contributed_observed_cvap <- sum(
  bg_cvap_contributions$cvap_contribution, na.rm = TRUE
)

check(
  cvap_close(contributed_observed_cvap, expected_observed_cvap),
  "National contributions do not sum to the observed adjusted CVAP inputs."
)

ct_land_contribution <- bg_cvap_contributions |>
  filter(bg_cvap == "091902114003")

check(
  nrow(ct_land_contribution) == 1L &&
    ct_land_contribution$PUMA5CE[[1]] == "20904" &&
    ct_land_contribution$CDFP[[1]] == "05" &&
    ct_land_contribution$cvap_contribution[[1]] == 5,
  "The reviewed Connecticut land estimate was not allocated exactly once."
)

contribution_summary <- bg_contribution_audit |>
  group_by(allocation_case) |>
  summarise(
    block_groups = n(),
    expected_cvap_total = sum_cvap_or_na(cvap_for_allocation),
    contributed_cvap_total = sum_cvap_or_na(contributed_cvap),
    .groups = "drop"
  )

cat("\nBlock-group CVAP contribution audit:\n")
print(contribution_summary, n = Inf, width = Inf)

cat("\nContribution checks passed for every block group.\n")
cat("Contributed CVAP from observed estimates:",
    format(contributed_observed_cvap, scientific = FALSE, trim = TRUE), "\n")
cat("Block groups with unknown CVAP:",
    sum(is.na(bg_contribution_audit$cvap_for_allocation)), "\n")
cat("Largest absolute block-group balance error:",
    max(abs(bg_contribution_audit$cvap_difference), na.rm = TRUE), "\n")
cat("Continuing with PUMA-to-district weight construction.\n")

# Section 11: construct PUMA-to-district allocation weights.
# Containment uses ALL original blocks, including zero-population blocks.
# CT candidate correspondence links must not determine PUMA containment.
puma_geography <- bg_2020_cells |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    source_blocks = sum(blocks),
    unassigned_blocks = sum(blocks[CDFP == "ZZ"]),
    assigned_districts = n_distinct(CDFP[CDFP != "ZZ"]),
    .groups = "drop"
  ) |>
  mutate(
    structural_containment =
      assigned_districts == 1L & unassigned_blocks == 0L
  )

# Preserve every original assigned PUMA-district intersection.
puma_cd_backbone <- bg_2020_cells |>
  filter(CDFP != "ZZ") |>
  distinct(STATEFP, PUMA5CE, CDFP) |>
  arrange(STATEFP, PUMA5CE, CDFP)

puma_cd_cvap <- bg_cvap_contributions |>
  filter(CDFP != "ZZ") |>
  group_by(STATEFP, PUMA5CE, CDFP) |>
  summarise(
    known_cvap_subtotal = sum(cvap_contribution, na.rm = TRUE),
    district_cvap = sum_cvap_or_na(cvap_contribution),
    .groups = "drop"
  )

check(
  nrow(anti_join(
    puma_cd_backbone, puma_cd_cvap,
    by = c("STATEFP", "PUMA5CE", "CDFP")
  )) == 0L &&
    nrow(anti_join(
      puma_cd_cvap, puma_cd_backbone,
      by = c("STATEFP", "PUMA5CE", "CDFP")
    )) == 0L &&
    cvap_close(
      sum(puma_cd_cvap$known_cvap_subtotal),
      contributed_observed_cvap
    ),
  "PUMA-district aggregation changed geographic coverage or known CVAP."
)

puma_cvap_totals <- puma_cd_cvap |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    known_puma_cvap_subtotal = sum(known_cvap_subtotal),
    puma_cvap = sum_cvap_or_na(district_cvap),
    .groups = "drop"
  )

puma_missing_counts <- bg_cvap_contributions |>
  filter(CDFP != "ZZ") |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    missing_block_groups = n_distinct(
      bg_cvap[is.na(cvap_contribution)]
    ),
    .groups = "drop"
  )

puma_allocation_audit <- puma_geography |>
  left_join(
    puma_cvap_totals,
    by = c("STATEFP", "PUMA5CE"),
    relationship = "one-to-one"
  ) |>
  left_join(
    puma_missing_counts,
    by = c("STATEFP", "PUMA5CE"),
    relationship = "one-to-one"
  ) |>
  mutate(
    weight_method = case_when(
      structural_containment ~ "structural_single_district",
      missing_block_groups == 0L &
        is.finite(puma_cvap) & puma_cvap > 0 ~ "cvap_share",
      TRUE ~ "review_required"
    )
  )

readr::write_csv(
  puma_allocation_audit,
  file.path(output_dir, "02_puma_allocation_audit.csv")
)

blocked_pumas <- puma_allocation_audit |>
  filter(weight_method == "review_required" | is.na(missing_block_groups))

if (nrow(blocked_pumas) > 0L) {
  print(blocked_pumas, n = Inf, width = Inf)
}
check(
  nrow(blocked_pumas) == 0L,
  "Some PUMAs lack usable allocation inputs; inspect 02_puma_allocation_audit.csv."
)

weight_work <- puma_cd_backbone |>
  left_join(
    puma_cd_cvap,
    by = c("STATEFP", "PUMA5CE", "CDFP"),
    relationship = "one-to-one"
  ) |>
  left_join(
    puma_allocation_audit |>
      select(STATEFP, PUMA5CE, puma_cvap, weight_method),
    by = c("STATEFP", "PUMA5CE"),
    relationship = "many-to-one"
  )

contained_puma <-
  weight_work$weight_method == "structural_single_district"
proportional_puma <- weight_work$weight_method == "cvap_share"

# Evaluate division only where the complete denominator is positive.
weight_work$allocation_weight <- NA_real_
weight_work$allocation_weight[contained_puma] <- 1
weight_work$allocation_weight[proportional_puma] <-
  weight_work$district_cvap[proportional_puma] /
  weight_work$puma_cvap[proportional_puma]

puma_cd_crosswalk <- weight_work |>
  select(
    STATEFP, PUMA5CE, CDFP,
    allocation_weight, weight_method
  ) |>
  arrange(STATEFP, PUMA5CE, CDFP)

check(
  !anyNA(puma_cd_crosswalk) &&
    nrow(puma_cd_crosswalk) == nrow(puma_cd_backbone) &&
    anyDuplicated(select(
      puma_cd_crosswalk, STATEFP, PUMA5CE, CDFP
    )) == 0L &&
    all(is.finite(puma_cd_crosswalk$allocation_weight)) &&
    all(puma_cd_crosswalk$allocation_weight >= 0 &
          puma_cd_crosswalk$allocation_weight <= 1) &&
    all(puma_cd_crosswalk$CDFP != "ZZ") &&
    setequal(puma_cd_crosswalk$STATEFP, target_states),
  "Crosswalk identifiers or allocation weights are invalid."
)

weight_sums <- puma_cd_crosswalk |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    weight_rows = n(),
    weight_sum = sum(allocation_weight),
    zero_weight_rows = sum(allocation_weight == 0),
    .groups = "drop"
  )

puma_allocation_audit <- puma_allocation_audit |>
  left_join(
    weight_sums,
    by = c("STATEFP", "PUMA5CE"),
    relationship = "one-to-one"
  )

# Numerical tolerance for dimensionless weights, not statistical uncertainty.
check(
  !anyNA(puma_allocation_audit$weight_sum) &&
    nrow(weight_sums) == nrow(puma_geography) &&
    all(puma_allocation_audit$weight_rows ==
          puma_allocation_audit$assigned_districts) &&
    all(abs(puma_allocation_audit$weight_sum - 1) <= 1e-12),
  "Crosswalk coverage or within-PUMA weight sums failed."
)

expected_districts <- puma_cd_backbone |>
  distinct(STATEFP, CDFP)

positive_districts <- puma_cd_crosswalk |>
  filter(allocation_weight > 0) |>
  distinct(STATEFP, CDFP)

check(
  nrow(anti_join(
    expected_districts, positive_districts,
    by = c("STATEFP", "CDFP")
  )) == 0L,
  "An assigned district has no positive allocation weight."
)

# Exact reviewed NY cases: see 02_cvap_allocation_decisions.md.
ny_weights <- puma_cd_crosswalk |>
  filter(STATEFP == "36", PUMA5CE %in% c("03310", "03313"))

ny_puma_audit <- puma_allocation_audit |>
  filter(STATEFP == "36", PUMA5CE %in% c("03310", "03313"))

check(
  nrow(ny_weights) == 2L &&
    setequal(ny_weights$PUMA5CE, c("03310", "03313")) &&
    all(ny_weights$CDFP == "02") &&
    all(ny_weights$allocation_weight == 1) &&
    all(ny_weights$weight_method == "structural_single_district") &&
    nrow(ny_puma_audit) == 2L &&
    all(is.na(ny_puma_audit$puma_cvap)) &&
    sum(ny_puma_audit$missing_block_groups) == 39L,
  "NY containment weights or preservation of unknown CVAP failed."
)

# Save outputs only after the crosswalk checks pass.
readr::write_csv(
  puma_cd_cvap,
  file.path(output_dir, "02_puma_cd_cvap.csv")
)
readr::write_csv(
  puma_allocation_audit,
  file.path(output_dir, "02_puma_allocation_audit.csv")
)
readr::write_csv(
  puma_cd_crosswalk,
  file.path(output_dir, "02_puma_cd_weights.csv")
)

intermediate_dir <- here::here("frame", "data", "intermediate")
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)

crosswalk_path <- file.path(intermediate_dir, "puma_cd_crosswalk.rds")
temporary_crosswalk <- tempfile(
  pattern = "puma_cd_crosswalk_",
  tmpdir = intermediate_dir,
  fileext = ".rds"
)
saveRDS(puma_cd_crosswalk, temporary_crosswalk, compress = "gzip")
check(
  file.rename(temporary_crosswalk, crosswalk_path),
  "Could not move the completed crosswalk to its final filename."
)

cat("\nPUMA allocation methods:\n")
puma_allocation_audit |>
  count(weight_method, name = "pumas") |>
  print(n = Inf, width = Inf)

cat("\nReviewed New York weights:\n")
print(ny_weights, n = Inf, width = Inf)

cat("\nCrosswalk validation passed.\n")
cat("PUMAs:", nrow(puma_allocation_audit), "\n")
cat("Assigned districts including DC:", nrow(expected_districts), "\n")
cat("PUMA-district rows:", nrow(puma_cd_crosswalk), "\n")
cat("Zero-weight rows:",
    sum(puma_cd_crosswalk$allocation_weight == 0), "\n")
cat("Largest within-PUMA weight-sum error:",
    max(abs(puma_allocation_audit$weight_sum - 1)), "\n")
cat("Saved:", crosswalk_path, "\n")
cat("PUMS coverage and application will be checked in the next stage.\n")
