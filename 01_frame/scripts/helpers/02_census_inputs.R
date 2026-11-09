# Input readers for Step 02. The main script loads dplyr and defines check().

# Read the national Block Equivalency File (BEF) ----
# Eager reading lets us delete the extracted file before returning its table.

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

# Read 2020 Public Law 94-171 (PL) redistricting archives ----
# The state and block rows in each geography file share a record number
# (LOGRECNO) with their population rows in segment 2 of the same archive.
# Both tables are headerless and pipe-delimited. Reading fields as text
# preserves leading zeroes until the population counts have been validated.
read_pl_columns <- function(path, column_names, selected_columns) {
  readr::read_delim(
    path,
    delim = "|",
    quote = "",
    col_names = column_names,
    col_select = all_of(selected_columns),
    col_types = readr::cols(.default = readr::col_character()),
    trim_ws = FALSE,
    skip_empty_rows = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )
}

read_pl_geography <- function(path, abbreviation, state_fips) {
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
  geo <- read_pl_columns(path, pl_names, names(pl_fields))
  check(nrow(readr::problems(geo)) == 0L, "PL geography parsing problems.")
  # PLST and record-code definitions: PL technical documentation, Chapter 6.
  # https://www2.census.gov/programs-surveys/decennial/2020/technical-documentation/complete-tech-docs/summary-file/2020Census_PL94_171Redistricting_StatesTechDoc_English.pdf
  check(
    all(geo$FILEID == "PLST" &
        geo$STUSAB == toupper(abbreviation) &
        geo$STATE == state_fips),
    "Population file identification or state codes are unexpected."
  )

  # PL technical documentation, Figure 4-2.
  # 040 is a state, 750 a census block. Other summary levels are omitted.
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
  geo
}

read_pl_adults <- function(path, abbreviation) {
  # Segment 2 layout in the same official Census R import archive,
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
  adult <- read_pl_columns(path, adult_names, adult_fields)
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
  adult
}

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

  geo <- read_pl_geography(extracted, abbreviation, state_fips)

  adult_member <- paste0(tolower(abbreviation), "000022020.pl")
  check(
    sum(unzip(path, list = TRUE)$Name == adult_member) == 1L,
    paste("Missing or duplicated segment-2 member:", adult_member)
  )
  adult_file <- unzip(path, files = adult_member, exdir = temporary_dir)
  adult <- read_pl_adults(adult_file, abbreviation)

  # P0030001 counts all adults, including noncitizens.
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

  # Component widths: Census GEOID guidance cited in Section 1 of Step 02.
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
