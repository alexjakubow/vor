library(dplyr)
library(httr2)
library(cosr)

#' OpenAlex fields to retrieve for works.
OA_WORKS_FIELDS <- c(
  "doi",
  "id",
  "ids",
  "locations_count",
  "primary_location",
  "locations",
  "open_access"
)

#' Locations
DATA_DIR <- file.path("data", "doi_lookups")
LOG_PATH <- file.path("logs", "doi_lookup_status.csv")


# Functions --------------------------------------------------------------------
#' Create table of preprint DOIs and associated metadata from OSF.
get_preprint_doi <- function() {
  osf_preprints <- open_parquet(tbl = "osf_preprint") |>
    filter(
      is_public == TRUE,
      is.na(deleted),
      machine_state == "accepted",
      is_published == TRUE,
      is.na(article_doi)
    ) |>
    select(preprint_id = id, creator_id, title, created)

  osf_users <- open_parquet(tbl = "osf_osfuser") |>
    select(creator_id = id, given_name, family_name)

  osf_identifier <- open_parquet(tbl = "osf_identifier") |>
    filter(content_type_id == 47, grepl("doi", category), is.na(deleted)) |>
    select(preprint_id = object_id, doi = value) |>
    mutate(doi = paste0("https://doi.org/", doi))

  # Return subset of preprints with DOIs and associated metadata
  osf_preprints |>
    left_join(osf_users, by = "creator_id") |>
    inner_join(osf_identifier, by = "preprint_id")
}


#' Format a lookup request for a given DOI using the OpenAlex API
doi_lookup_request <- function(doi) {
  BASE_URL <- "https://api.openalex.org/works"

  request <- request(BASE_URL) |>
    req_url_path_append(doi) |>
    req_url_query(
      per_page = 200,
      select = paste(OA_WORKS_FIELDS, collapse = ",")
    ) |>
    req_headers(accept = "application/json") |>
    req_throttle(capacity = 100)

  return(request)
}


#' Perform a batch of DOI lookup requests in parallel and save responses to disk.
perform_doi_lookups <- function(
  dois,
  json_dir = DATA_DIR,
  log_file = LOG_PATH
) {
  # Format requests for all DOIs
  requests <- purrr::map(dois, doi_lookup_request)

  # Specify file paths for saving responses locally
  filepaths <- file.path(json_dir, paste0(basename(dois), ".json"))

  # Perform requests in parallel and save responses to disk
  responses <- req_perform_parallel(
    requests,
    paths = filepaths,
    progress = TRUE,
    on_error = "continue"
  )
  names(responses) <- dois

  # Extract status codes and success/failure information for logging
  successes <- resps_successes(responses)
  success_data <- tibble(
    guid = basename(names(successes)),
    doi = names(successes),
    status = as.character(purrr::map_int(successes, ~ .x$status_code)),
    success = purrr::map_lgl(successes, ~ .x$status_code == 200)
  )

  failures <- resps_failures(responses)
  failure_data <- tibble(
    guid = basename(names(failures)),
    doi = names(failures),
    status = purrr::map_chr(failures, ~ class(.x)[1]),
    success = FALSE
  ) |>
    filter(!is.na(guid))

  bind_rows(success_data, failure_data) |>
    readr::write_csv(log_file)

  return(responses)
}


#' Process DOI lookup results from JSON files
munge_doi_lookup_results <- function(
  json_dir = DATA_DIR,
  log_file = LOG_PATH
) {
  # Return successful DOI lookups from log file and extract DOIs for processing
  dois <- readr::read_csv(
    log_file,
    show_col_types = FALSE
  ) |>
    filter(status == "200") |>
    pull(doi)

  # Set file paths
  json_files <- file.path(json_dir, paste0(basename(dois), ".json"))

  # Read JSON files and extract relevant information into a table
  lookup_results <- purrr::map_dfr(
    json_files,
    ~ {
      data <- jsonlite::fromJSON(.x)
      tibble(
        doi = data$doi,
        open_access = list(data$open_access),
        locations_count = data$locations_count,
        locations = list(data$locations)
      )
    }
  )

  return(lookup_results)
}


#' Prepare directories for saving DOI lookup results and logs.
prep_directories <- function() {
  fs::dir_delete(DATA_DIR)
  fs::dir_create(DATA_DIR)

  fs::dir_delete("logs")
  fs::dir_create("logs")
}


export_results_csvs <- function(results) {
  # Save detailed results to CSV, excluding OSF locations
  tbl <- results |>
    tidyr::unnest_longer(locations) |>
    filter(!grepl("osf.io", tolower(locations$landing_page_url))) |>
    select(doi, location = locations) |>
    tidyr::unnest_wider(location) |>
    mutate(guid = basename(doi)) |>
    select(
      guid,
      doi,
      external_url = landing_page_url,
      is_oa,
      version,
      is_accepted,
      is_published,
      raw_type
    ) |>
    arrange(guid)
  readr::write_csv(tbl, file.path("data", "doi_lookup_results.csv"))

  # Create summary table
  summary_tbl <- tbl |>
    summarise(
      .by = doi,
      n_external_locations = n(),
      any_oa = any(is_oa, na.rm = TRUE)
    )

  summary_tbl <- full_join(
    summary_tbl,
    select(results, doi, n_locations = locations_count),
    by = "doi"
  ) |>
    mutate(
      n_external_locations = ifelse(
        is.na(n_external_locations),
        0L,
        n_external_locations
      ),
      any_external_oa = ifelse(is.na(any_oa), FALSE, any_oa),
      guid = basename(doi)
    ) |>
    select(
      guid,
      doi,
      n_locations,
      n_external_locations,
      any_external_oa
    )
  readr::write_csv(summary_tbl, file.path("data", "doi_lookup_summary.csv"))
}


#' Wrapper function to perform the entire DOI lookup process: prepare directories, get DOIs, perform lookups, and process results.
openalex_doi_search <- function(sample_size = NULL, seed = 8675309) {
  start_time <- Sys.time()
  message("Starting OpenAlex DOI lookup process...")
  message("Preparing directories for DOI lookup results and logs...")
  prep_directories()

  message("Collecting preprint DOIs from OSF...")
  dois <- get_preprint_doi() |>
    collect()
  if (!is.null(sample_size)) {
    set.seed(seed)
    dois <- dois |>
      sample_n(sample_size) |>
      pull(doi)
  } else {
    dois <- dois |>
      pull(doi)
  }

  message("Performing DOI lookups using OpenAlex API...")
  perform_doi_lookups(dois)

  message("Processing DOI lookup results...")
  result <- munge_doi_lookup_results()

  message("Exporting results to CSV files...")
  export_results_csvs(result)

  end_time <- Sys.time()
  message(
    "OpenAlex DOI lookup process completed in ",
    round(difftime(end_time, start_time, units = "mins"), 2),
    " minutes."
  )
}

# Lookup for preprint DOIs ------------------------------------------------------
# openalex_doi_search(sample_size = 10000)
