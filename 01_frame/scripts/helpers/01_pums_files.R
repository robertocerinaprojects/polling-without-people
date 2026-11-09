# File checks and output publication for 01_prepare_pums.R.

# Check the downloaded files against the receipt in their snapshot folder ----
verify_snapshot_receipt <- function(snapshot_dir, expected_sample) {
  receipt_path <- file.path(snapshot_dir, "download_manifest.csv")
  if (!file.exists(receipt_path)) {
    stop("This download is incomplete. Resume 00_download_pums.R first.")
  }
  receipt <- readr::read_csv(
    receipt_path, col_types = readr::cols(.default = readr::col_character())
  )

  required_fields <- c("role", "file", "bytes", "sha256", "sample", "request_sha256")
  stopifnot(
    all(required_fields %in% names(receipt)),
    nrow(receipt) == 2L,
    !anyNA(receipt[required_fields]),
    !anyDuplicated(receipt$role),
    !anyDuplicated(receipt$file),
    setequal(receipt$role, c("ddi_codebook", "data")),
    all(grepl("^[A-Za-z0-9_.-]+$", receipt$file)),
    all(grepl("^[a-f0-9]{64}$", receipt$sha256)),
    all(receipt$sample == expected_sample)
  )

  # Account-specific filenames can differ. Use the role to identify the CSV and codebook.
  paths <- file.path(snapshot_dir, "files", receipt$file)
  names(paths) <- receipt$role
  stopifnot(
    all(file.exists(paths)),
    all(file.info(paths)$size == as.numeric(receipt$bytes)),
    all(unname(vapply(paths, file_sha256, character(1))) == receipt$sha256)
  )

  request_path <- file.path(snapshot_dir, "request.json")
  stopifnot(
    file.exists(request_path),
    length(unique(receipt$request_sha256)) == 1L,
    all(grepl("^[a-f0-9]{64}$", receipt$request_sha256)),
    file_sha256(request_path) == receipt$request_sha256[[1]]
  )
  paths
}

file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

# Hash the variable definitions exactly as recorded in 00_pums_source.json ----
variable_metadata_sha256 <- function(variable_info) {
  # ipums_var_info_json_v1 uses the complete table, in its original row and field
  # order. Administrative XML fields such as the extract date are outside this table.
  # https://tech.popdata.org/ipumsr/reference/ipums_var_info.html
  metadata_json <- jsonlite::toJSON(
    variable_info, dataframe = "rows", auto_unbox = TRUE,
    na = "null", null = "null", digits = NA, pretty = FALSE
  )
  digest::digest(enc2utf8(as.character(metadata_json)), algo = "sha256", serialize = FALSE)
}

# Check the selected download against the source approved for this study ----
open_approved_pums <- function(snapshot_store, specification_path) {
  spec <- jsonlite::read_json(specification_path, simplifyVector = TRUE)
  stopifnot(
    spec$schema_version == 1L,
    spec$collection == "usa",
    spec$sample == "us2024c",
    spec$data_format == "csv",
    spec$variable_info_encoding == "ipums_var_info_json_v1"
  )

  current_snapshot_path <- file.path(snapshot_store, "current_snapshot.txt")
  if (!file.exists(current_snapshot_path)) {
    stop("Run 00_download_pums.R first to acquire the PUMS source.")
  }
  snapshot_id <- readLines(current_snapshot_path, warn = FALSE)
  stopifnot(length(snapshot_id) == 1L, grepl("^[0-9]{8}T[0-9]{6}_[0-9]+$", snapshot_id))
  files <- verify_snapshot_receipt(file.path(snapshot_store, snapshot_id), spec$sample)
  data_path <- files[["data"]]

  # A newer extract can match its own receipt while containing different data.
  if (file_sha256(data_path) != spec$data_sha256 ||
      file.info(data_path)$size != spec$data_bytes) {
    stop("Downloaded PUMS data differ from the reviewed source. Review before updating 00_pums_source.json.")
  }
  codebook <- ipumsr::read_ipums_ddi(files[["ddi_codebook"]])
  variable_info <- ipumsr::ipums_var_info(codebook)
  if (variable_metadata_sha256(variable_info) != spec$variable_info_sha256) {
    stop("IPUMS variable definitions differ from the reviewed source. Review before updating 00_pums_source.json.")
  }
  stopifnot(identical(variable_info$var_name, spec$required_columns))
  cat("Verified approved IPUMS source:", snapshot_id, "\n")
  list(data_path = data_path, codebook = codebook, raw_columns = variable_info$var_name)
}

# Stage all five files, then publish the audit CSVs followed by the person RDS ----
save_outputs <- function(people, audits, destination, audit_dir) {
  audit_paths <- file.path(audit_dir, paste0("01_pums_", names(audits), ".csv"))
  temporary_audits <- tempfile(paste0("01-", names(audits), "-"), tmpdir = audit_dir)
  temporary_people <- tempfile("01-people-", tmpdir = dirname(destination))
  on.exit(unlink(c(temporary_audits, temporary_people)), add = TRUE)

  saveRDS(people, temporary_people, compress = "gzip")
  for (i in seq_along(audits)) {
    readr::write_csv(audits[[i]], temporary_audits[i])
  }
  for (i in seq_along(audit_paths)) {
    if (!file.rename(temporary_audits[i], audit_paths[i])) {
      stop("Could not publish the completed audit: ", audit_paths[i])
    }
  }
  if (!file.rename(temporary_people, destination)) {
    stop("Could not publish the completed RDS: ", destination)
  }
}
