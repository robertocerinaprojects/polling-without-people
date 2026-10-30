# Build a PUMA-to-congressional-district crosswalk for the 2026 election.
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
      pop20 = POP100
    )

  check(anyDuplicated(blocks$GEOID) == 0L, "Duplicate population block IDs.")
  check(
    sum(blocks$pop20) == state_record$POP100[[1]],
    "Block populations do not sum to the state total."
  )

  list(blocks = blocks, state_total = state_record$POP100[[1]])
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

  check(
    !anyNA(values) && sum(values) == population$state_total,
    paste(abbreviation, "population total changed during matching.")
  )

  # Assign by row position, preserving the national block order.
  block_cd$pop20[positions] <- values
  unassigned_positions <- positions[block_cd$CDFP[positions] == "ZZ"]

  state_audits[[i]] <- tibble(
    STATEFP = st,
    STUSAB = abbreviation,
    blocks = length(positions),
    state_population = population$state_total,
    matched_population = sum(values),
    unassigned_blocks = length(unassigned_positions),
    unassigned_population = sum(block_cd$pop20[unassigned_positions])
  )

  # Retain all unassigned blocks for review, including any populated blocks.
  unassigned_audits[[i]] <- block_cd[
    unassigned_positions,
    c("GEOID", "STATEFP", "CDFP", "PUMA5CE", "pop20")
  ]

  rm(population, values, index)
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
  "**New York treatment: structural allocation. Crosswalk implementation pending.** See [decision record](02_cvap_allocation_decisions.md). This audit does not replace missing estimates with zero,",
  "impute values, remove PUMS records, or calculate allocation weights.",
  "",
  "Errata 148 states that PUMS files are unaffected. It also cautions",
  "against affected 2016-2020, 2017-2021 and 2018-2022 ACS estimates;",
  "an older-period replacement therefore requires separate justification.",
  "",
  "The selected treatment, alternatives considered, affected population,",
  "validation and limitations must be recorded in the main Script 02",
  "documentation before the allocation method is finalized."
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
# Add the verified geographic extent while keeping treatment pending.
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
  "**New York decision resolved; crosswalk implementation pending.** See [decision record](02_cvap_allocation_decisions.md)."
)

writeLines(c(readLines(note_path, warn = FALSE), impact_notes), note_path)

cat("Impact audit saved:", impact_path, "\n")
cat("Documentation updated:", note_path, "\n")
