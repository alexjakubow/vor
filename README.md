# OSF Preprints: External Version of Record Analysis

This repository analyzes the extent to which preprints hosted on the Open Science Framework (OSF) link to external versions of record (VOR). The goal is to understand how many OSF preprints point to external versions that live somewhere other than OSF, including copies on other preprint servers or versions eventually published in academic journals.

## 📊 View the Report

**[View the full analysis report here](https://alexjakubow.github.io/vor/osf_preprint_vor_analysis.html)**

The report is automatically rendered and published via GitHub Actions whenever changes are pushed to the main branch.

## Overview

Using the OpenAlex API, this project:
- Extracts preprint DOIs from the OSF database
- Queries OpenAlex for location and version information
- Identifies external versions of record (non-OSF locations)
- Analyzes open access availability of external versions

## Key Findings

From a sample of 10,000 OSF preprints:
- **99.4%** successfully looked up in OpenAlex
- **3.7%** have at least one external location (non-OSF)
- **47.5%** of those with external locations have open access versions
- **1.7%** of all preprints have an external open access version

## Repository Structure

```
.
├── openalex.r                      # Main analysis script
├── osf_preprint_vor_analysis.qmd   # Quarto report with full methodology and results
├── data/
│   ├── doi_lookup_summary.csv      # Summary statistics per preprint
│   └── doi_lookup_results.csv      # Detailed external location data
├── logs/
│   └── doi_lookup_status.csv       # API request success/failure log
└── .github/
    └── workflows/
        └── render-quarto.yml       # GitHub Actions workflow for automatic rendering
```

## Requirements

### R Packages
- `dplyr` - Data manipulation
- `httr2` - HTTP requests
- `cosr` - OSF database access (internal)
- `jsonlite` - JSON parsing
- `readr` - CSV file I/O
- `tidyr` - Data tidying
- `purrr` - Functional programming

### Data Access
- Access to OSF database (via `cosr` package and local files)
- Internet connection for OpenAlex API queries

## Usage

### Running the Analysis

```r
# Source the main script
source("openalex.r")

# Run with default sample size (10,000)
openalex_doi_search(sample_size = 10000)

# Run on full dataset (this may take considerable time)
openalex_doi_search(sample_size = NULL)
```

### Generating the Report Locally

```r
# In R
quarto::quarto_render("osf_preprint_vor_analysis.qmd")
```

Or from the command line:
```bash
quarto render osf_preprint_vor_analysis.qmd
```

### Automated Report Publishing

The repository is configured with GitHub Actions to automatically:
1. Render the Quarto document whenever changes are pushed to `main`
2. Publish the HTML output to GitHub Pages

To enable this for your fork:
1. Go to your repository's **Settings** → **Pages**
2. Under "Source", select **GitHub Actions**
3. Push changes to the `main` branch to trigger the workflow

## Methodology

### Data Selection Criteria

The analysis focuses on OSF preprints that are:
- Public and not deleted
- In "accepted" machine state
- Published
- **Without** an existing `article_doi` field (to find potential external VORs)

### API Query Process

1. Extract preprint DOIs from OSF database
2. Make parallel API requests to OpenAlex (throttled to 100/min)
3. Save JSON responses and log success/failure
4. Parse location data from successful responses
5. Filter out locations pointing back to OSF
6. Generate summary and detailed CSV files

### Output Files

- **`doi_lookup_summary.csv`**: One row per preprint with counts of total and external locations, plus OA status
- **`doi_lookup_results.csv`**: One row per external location with detailed metadata (version, access status, URL)
- **`doi_lookup_status.csv`**: Log of all API requests (success/failure, status codes)

With adequate permissions, these files can be accessed on Google Drive for further exploration.  Please contact for access.