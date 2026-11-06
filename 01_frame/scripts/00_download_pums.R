# Download the full IPUMS 2020-2024 ACS five-year person extract.
# Plain-language summary and recovery: 01_frame/docs/00_download_pums.md
# Run from repository root: Rscript 01_frame/scripts/00_download_pums.R
# Reuse a verified local download; --refresh requests a separate new snapshot.
# Outputs: 01_frame/data/input/ipums_pums/ (ignored source files and receipts).
# Script 01 checks this snapshot against 01_frame/docs/00_pums_source.json.

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  check(length(args) == 0L || identical(args, "--refresh"),
        "Usage: Rscript 01_frame/scripts/00_download_pums.R [--refresh]")
  refresh <- identical(args, "--refresh")
  root <- here::here()
  check(normalizePath(root) == normalizePath(getwd()),
        "Run this script from the repository root.")

  # API sample ID (different from the numeric SAMPLE column in the CSV):
  # https://usa.ipums.org/usa-action/samples/sample_ids
  # Variables reproduce the reviewed 24-column source schema; no case filters.
  variables <- c(
    "YEAR", "MULTYEAR", "SAMPLE", "SERIAL", "CBSERIAL", "HHWT", "CLUSTER",
    "STATEFIP", "PUMA", "CPUMA1020", "STRATA", "GQ", "HHINCOME", "PERNUM",
    "PERWT", "SEX", "AGE", "RACE", "RACED", "HISPAN", "HISPAND", "CITIZEN",
    "EDUC", "EDUCD"
  )
  # Person-rectangular CSV attaches household fields to each person record.
  # https://tech.popdata.org/ipumsr/reference/define_extract_micro.html
  definition <- ipumsr::define_extract_micro(
    collection = "usa",
    description = "polling-without-people: full 2020-2024 ACS five-year PUMS",
    samples = "us2024c",
    variables = variables,
    data_format = "csv",
    data_structure = "rectangular",
    rectangular_on = "P"
  )
  request_tmp <- tempfile(fileext = ".json")
  on.exit(unlink(request_tmp), add = TRUE)
  ipumsr::save_extract_as_json(definition, request_tmp)
  fingerprint <- function(path) digest::digest(file = path, algo = "sha256")
  request_sha256 <- fingerprint(request_tmp)

  store <- file.path(root, "01_frame", "data", "input", "ipums_pums")
  dir.create(store, recursive = TRUE, showWarnings = FALSE)
  pointer <- file.path(store, "current_snapshot.txt")
  if (refresh || !file.exists(pointer)) {
    check(nzchar(Sys.getenv("IPUMS_API_KEY")), "IPUMS_API_KEY is unavailable.")
    samples <- ipumsr::get_sample_info("usa")
    chosen <- samples[samples$name == "us2024c", , drop = FALSE]
    check(nrow(chosen) == 1L &&
            chosen$description[[1]] == "2020-2024, ACS 5-year",
          "The requested sample is unavailable or its description has changed.")
    snapshot <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"),
                       "_", Sys.getpid())
    run_dir <- file.path(store, snapshot)
    check(dir.create(run_dir), "Could not create a new snapshot directory.")
    check(file.copy(request_tmp, file.path(run_dir, "request.json")),
          "Could not save the requested extract definition.")
    # This pointer chooses a download snapshot, not an approved analysis input.
    pointer_tmp <- tempfile(tmpdir = store)
    writeLines(snapshot, pointer_tmp)
    check(file.rename(pointer_tmp, pointer), "Could not save the snapshot pointer.")
  }

  snapshot <- readLines(pointer, warn = FALSE)
  check(length(snapshot) == 1L && grepl("^[0-9]{8}T[0-9]{6}_[0-9]+$", snapshot),
        "Invalid local snapshot pointer; inspect it before proceeding.")
  run_dir <- file.path(store, snapshot)
  request_path <- file.path(run_dir, "request.json")
  check(file.exists(request_path) && fingerprint(request_path) == request_sha256,
        "The requested settings differ from this snapshot. Use --refresh for a new request.")
  manifest_path <- file.path(run_dir, "download_manifest.csv")
  files_dir <- file.path(run_dir, "files")
  dir.create(files_dir, showWarnings = FALSE)

  # A completed local receipt is authoritative for reuse, even after the
  # remote download expires. Never replace its fingerprints automatically.
  manifest <- NULL
  if (file.exists(manifest_path)) {
    manifest <- readr::read_csv(
      manifest_path, col_types = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE
    )
    required <- c("role", "file", "bytes", "sha256", "extract_number",
                  "sample", "request_sha256", "downloaded_utc")
    check(all(required %in% names(manifest)) && nrow(manifest) == 2L &&
            !anyNA(manifest) && !anyDuplicated(manifest$role) &&
            setequal(manifest$role, c("ddi_codebook", "data")) &&
            !anyDuplicated(manifest$file) &&
            all(grepl("^[A-Za-z0-9_.-]+$", manifest$file)) &&
            all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
            all(grepl("^[0-9]+$", manifest$extract_number)) &&
            length(unique(manifest$extract_number)) == 1L &&
            all(is.finite(as.numeric(manifest$bytes)) &
                  as.numeric(manifest$bytes) > 0) &&
            all(manifest$sample == "us2024c") &&
            all(manifest$request_sha256 == request_sha256),
          "Invalid local download manifest; inspect it before proceeding.")
    paths <- file.path(files_dir, manifest$file)
    present <- file.exists(paths)
    for (i in which(present)) {
      check(file.info(paths[i])$size == as.numeric(manifest$bytes[i]) &&
              fingerprint(paths[i]) == manifest$sha256[i],
            paste("Stored file differs from its receipt:", manifest$file[i],
                  "Inspect the change; --refresh creates a separate snapshot."))
    }
    if (all(present)) {
      cat("Verified and reused the stored IPUMS files; no API request made.\n")
      cat("Snapshot:", run_dir, "\n")
      cat("Script 01 verifies this snapshot against the reviewed source specification.\n")
      return(invisible(NULL))
    }
    cat("A stored source file is missing; recovering the same extract.\n")
  }

  check(nzchar(Sys.getenv("IPUMS_API_KEY")), "IPUMS_API_KEY is unavailable.")
  check(nzchar(Sys.which("gzip")), "The gzip command is required to check the download.")
  id_path <- file.path(run_dir, "extract_number.txt")
  started_path <- file.path(run_dir, "submission_started.txt")
  if (!file.exists(id_path)) {
    check(is.null(manifest), "Completed receipt exists but its extract number file is missing.")
    check(!file.exists(started_path), paste(
      "An earlier submission has no saved extract number.",
      "Inspect your IPUMS extract history before retrying; see the companion document."
    ))
    # A failed POST can still have been accepted remotely. This marker stops
    # a rerun from silently submitting it twice if the response was lost.
    writeLines(format(Sys.time(), tz = "UTC", usetz = TRUE), started_path)
    submitted <- ipumsr::submit_extract(definition)
    number <- as.character(submitted$number)
    check(length(number) == 1L && grepl("^[0-9]+$", number),
          "The API returned no usable extract number.")
    id_tmp <- tempfile(tmpdir = run_dir)
    writeLines(number, id_tmp)
    check(file.rename(id_tmp, id_path), "Could not save the submitted extract number.")
    saveRDS(submitted, file.path(run_dir, "submitted_extract.rds"))
    cat("Submitted IPUMS USA extract:", number, "\n")
  }

  number <- readLines(id_path, warn = FALSE)
  check(length(number) == 1L && grepl("^[0-9]+$", number),
        "Invalid saved extract number.")
  if (!is.null(manifest)) {
    check(all(manifest$extract_number == number), "Receipt and extract number disagree.")
  }
  cat("Checking IPUMS USA extract:", number, "\n")
  extract <- ipumsr::get_extract_info(paste0("usa:", number))
  # Store the returned specification separately: IPUMS can add defaults.
  returned_json <- tempfile(fileext = ".json")
  on.exit(unlink(returned_json), add = TRUE)
  ipumsr::save_extract_as_json(extract, returned_json)
  returned <- jsonlite::read_json(returned_json)
  check(file.copy(returned_json, file.path(run_dir, "returned_definition.json"),
                  overwrite = TRUE), "Could not save the returned definition.")
  # Default annotations such as 'preselected' do not change the data request.
  # Validate content and selection settings, not JSON field ordering.
  empty <- function(x) is.null(x) ||
    length(unlist(x, recursive = TRUE, use.names = FALSE)) == 0L
  false_or_empty <- function(x) empty(x) || identical(x, FALSE)
  # API definitions use base names; downloads also contain detailed columns.
  # General/detailed coding: https://usa.ipums.org/usa-action/faq
  # The exact 24-column CSV and DDI checks below remain required.
  api_variables <- setdiff(variables, c("RACED", "HISPAND", "EDUCD"))
  received_variables <- names(returned$variables)
  check(!anyDuplicated(received_variables) &&
          all(api_variables %in% received_variables) &&
          all(received_variables %in% variables),
        paste(
          "Returned API variable definitions differ. Missing base names:",
          paste(setdiff(api_variables, received_variables), collapse = ", "),
          "; unexpected names:",
          paste(setdiff(received_variables, variables), collapse = ", ")
        ))
  check(identical(returned$collection, "usa") &&
          identical(returned$dataFormat, "csv") &&
          identical(names(returned$dataStructure), "rectangular") &&
          identical(returned$dataStructure$rectangular$on, "P") &&
          setequal(names(returned$samples), "us2024c") &&
          length(returned$samples) == 1L &&
          false_or_empty(returned$dataQualityFlags),
        "Returned sample or layout differs; inspect returned_definition.json.")
  for (variable in returned$variables) {
    check(empty(variable$caseSelections) && empty(variable$attachedCharacteristics) &&
            false_or_empty(variable$adjustMonetaryValues) &&
            false_or_empty(variable$dataQualityFlags),
          "Returned definition includes a selection or variable transformation.")
  }

  check(extract$status %in% c("queued", "started", "produced", "completed"),
        paste("Extract status is", extract$status, "- inspect it on IPUMS."))
  if (extract$status != "completed") {
    # Local operational choices: check at most every 30 seconds, wait up to
    # 30 minutes. A timeout keeps the saved number so the next run can resume.
    extract <- ipumsr::wait_for_extract(
      extract, max_delay_seconds = 30, timeout_seconds = 1800
    )
  }
  links <- extract$download_links[c("ddi_codebook", "data")]
  usable <- vapply(links, function(x) {
    is.list(x) && is.character(x$url) && length(x$url) == 1L && nzchar(x$url)
  }, logical(1))
  check(length(usable) == 2L && all(usable), paste(
    "This extract has no usable download links, possibly because it expired.",
    "Use --refresh to request a separate new snapshot."
  ))
  filenames <- vapply(links, function(x) basename(x$url), character(1))
  check(!anyDuplicated(filenames) && all(grepl("^[A-Za-z0-9_.-]+$", filenames)),
        "Unexpected source filenames in the API response.")
  saveRDS(extract, file.path(run_dir, "download_metadata.rds"))

  # Download into staging: preserve verified surviving files during recovery.
  # A retry replaces only an incomplete attempt at this same saved request.
  stage_dir <- file.path(run_dir, "download_in_progress")
  dir.create(stage_dir, showWarnings = FALSE)
  ipumsr::download_extract(extract, download_dir = stage_dir, overwrite = TRUE)
  paths <- file.path(stage_dir, filenames)
  check(all(file.exists(paths)) && all(file.info(paths)$size > 0),
        "The codebook or microdata download is missing or empty.")
  hashes <- vapply(paths, fingerprint, character(1))
  sizes <- file.info(paths)$size
  provider_size_checked <- provider_sha256_checked <- rep(FALSE, length(links))
  for (i in seq_along(links)) {
    # Check provider metadata when supplied; local hashes are always recorded.
    if (!is.null(links[[i]]$bytes)) {
      check(sizes[i] == as.numeric(links[[i]]$bytes), "Downloaded byte count differs from IPUMS.")
      provider_size_checked[i] <- TRUE
    }
    if (!is.null(links[[i]]$sha256)) {
      check(tolower(links[[i]]$sha256) == hashes[i], "Downloaded SHA-256 differs from IPUMS.")
      provider_sha256_checked[i] <- TRUE
    }
  }
  if (!is.null(manifest)) {
    ix <- match(names(links), manifest$role)
    check(all(filenames == manifest$file[ix]) &&
            all(hashes == manifest$sha256[ix]) &&
            all(sizes == as.numeric(manifest$bytes[ix])),
          "Recovered files differ from the previous download receipt.")
  }

  data_path <- paths[names(links) == "data"]
  check(grepl("\\.gz$", data_path), "Expected compressed microdata.")
  gzip_result <- system2("gzip", c("-t", "--", shQuote(data_path)),
                         stdout = TRUE, stderr = TRUE)
  check(is.null(attr(gzip_result, "status")), "gzip integrity check failed.")
  ddi <- ipumsr::read_ipums_ddi(paths[names(links) == "ddi_codebook"])
  ddi_variables <- ipumsr::ipums_var_info(ddi)$var_name
  header <- names(readr::read_csv(
    data_path, n_max = 0L, name_repair = "minimal", show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  ))
  check(!anyDuplicated(header) && !anyDuplicated(ddi_variables) &&
          setequal(header, variables) && setequal(ddi_variables, variables),
        "CSV/codebook columns differ from the requested 24-variable schema.")
  destinations <- file.path(files_dir, filenames)
  for (i in seq_along(paths)) {
    if (!is.null(manifest) && file.exists(destinations[i])) {
      check(fingerprint(destinations[i]) == hashes[i],
            "A surviving source file changed during recovery.")
      unlink(paths[i])
    } else {
      check(file.rename(paths[i], destinations[i]), "Could not promote a checked download.")
    }
  }
  unlink(stage_dir, recursive = TRUE)
  if (is.null(manifest)) {
    manifest <- data.frame(
      role = names(links), file = unname(filenames), bytes = sizes,
      sha256 = unname(hashes), extract_number = number, sample = "us2024c",
      request_sha256 = request_sha256,
      downloaded_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      provider_size_checked = provider_size_checked,
      provider_sha256_checked = provider_sha256_checked
    )
    manifest_tmp <- tempfile(tmpdir = run_dir)
    readr::write_csv(manifest, manifest_tmp)
    check(file.rename(manifest_tmp, manifest_path), "Could not save the download receipt.")
  }
  cat("\nDownload, compression and 24-column schema checks passed.\n")
  cat("Snapshot:", run_dir, "\n")
  cat("Receipt:", manifest_path, "\n")
  print(manifest[, c("role", "file", "bytes", "sha256")], row.names = FALSE)
  cat("\nDownload complete; analysis outputs have not been changed.\n")
  cat("Next: Script 01 checks the selected snapshot against 00_pums_source.json.\n")
}

main()
