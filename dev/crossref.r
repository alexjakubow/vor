library(dplyr)
library(httr2)
library(cosr)


#' Create table of preprint DOIs and associated metadata from OSF.
get_preprint_doi <- function() {
  osf_preprints <- open_parquet(tbl = "osf_preprint") |>
    filter(is_public == TRUE, is.na(deleted), machine_state == "accepted") |>
    select(preprint_id = id, creator_id, title, article_doi, created)

  osf_users <- open_parquet(tbl = "osf_osfuser") |>
    select(creator_id = id, given_name, family_name)

  osf_identifier <- open_parquet(tbl = "osf_identifier") |>
    filter(content_type_id == 47, grepl("doi", category), is.na(deleted)) |>
    select(preprint_id = object_id, category, value)

  osf_preprints |>
    left_join(osf_users, by = "creator_id") |>
    left_join(osf_identifier, by = "preprint_id")
}


#' Check for any relations associated with a given DOI using the Crossref API.
check_doi_relations <- function(preprint_doi) {
  URL <- "https://api.crossref.org/works/"
  req <- request(URL) |>
    req_url_path_append(doi) |>
    req_headers(accept = "application/json")

  resp <- req |> req_perform()

  data <- resp |> resp_body_json()

  relations <- data$message$relation

  return(relations)
}


#' Search for an article using the Crossref API based on author name and title.
article_search_query <- function(given_name, family_name, title, after = NULL) {
  URL <- "https://api.crossref.org/v1/works"

  author_query <- glue::glue(
    "?filter=query.author={given_name}+{family_name}"
  )
  title_query <- glue::glue("query.title={title}")
  title_query <- gsub(" ", ",", title_query)

  if (!is.null(after)) {
    after_query <- glue::glue("from-pub-date:{after}")
    title_query <- paste(title_query, after_query, sep = ",")
  }

  query <- paste(author_query, title_query, sep = ",")

  req <- request(URL) |>
    req_url_path_append(author_query, title_query) |>
    req_headers(accept = "application/json")

  return(req)
}

title <- "Socioeconomic,status,correlates,with,measures,of,Language,ENvironment,Analysis,(LENA),system:,a,meta-analysis"
title_encoded <- utils::URLencode(title, reserved = TRUE)
after = "2020-01-01"

request("https://api.crossref.org/v1/works") |>
  req_url_query(
    `query.author` = "Leonardo Piot",
    `query.title` = title_encoded,
    filter = if (!is.null(after)) glue::glue("from-pub-date:{after}") else NULL
  )

#' Perform the article search and return parsed items.
get_response_data <- function(query) {
  response <- req_perform(query)
  data <- resp_body_json(response)
  items <- data$message$items

  if (length(items) == 0) {
    return(NULL)
  }

  return(items)
}


# parse_item <- function(item) {
#   # Extract relevant information from the first item
#   doi <- item$DOI
#   title <- item$title[[1]]
#   authors <- sapply(item$author, function(a) paste(a$given, a$family))
#   published_date <- paste(
#     unlist(item$published$`date-parts`[[1]]),
#     collapse = "-"
#   )

#   return(list(
#     doi = doi,
#     title = title,
#     authors = authors,
#     published_date = published_date
#   ))
# }

# # Randoom sample of preprint DOIs
# set.seed(8675309)
# preprint_dois <- get_preprint_doi() |>
#   collect() |>
#   sample_n(10)

# # Check DOI relations
# test_doi <- preprint_dois$value[1]
# relations <- check_doi_relations(test_doi)

# # article_search(
#   preprint_dois[1, "given_name"],
#   preprint_dois[1, "family_name"],
#   preprint_dois[1, "title"]
# )

article_search_query(
  given_name = preprint_dois[1, "given_name"],
  family_name = preprint_dois[1, "family_name"],
  title = preprint_dois[1, "title"],
  after = preprint_dois[1, "created"]
)
